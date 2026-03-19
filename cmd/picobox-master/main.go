package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"sync"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	pb "github.com/henny-cho/picobox/internal/api/pb"
	"google.golang.org/grpc"
)

// globalNodeState holds the real-time status of all active PicoBox daemons.
var (
	globalNodeState = make(map[string]*pb.NodeMetrics)
	stateMutex      sync.RWMutex
)

// PicoMasterServer implements the gRPC AgentService
type PicoMasterServer struct {
	pb.UnimplementedAgentServiceServer
	nodes   map[string]*pb.NodeMetrics
	streams map[string]pb.AgentService_ControlChannelServer
	mu      sync.RWMutex
}

// ControlChannel receives messages from agents (like metrics or deployment responses) and can send commands.
func (s *PicoMasterServer) ControlChannel(stream pb.AgentService_ControlChannelServer) error {
	var hostname string

	defer func() {
		if hostname != "" {
			s.mu.Lock()
			delete(s.streams, hostname)
			s.mu.Unlock()
			fmt.Printf("[Master] Agent %s disconnected.\n", hostname)
		}
	}()

	for {
		msg, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}

		if metrics := msg.GetMetrics(); metrics != nil {
			if hostname == "" {
				hostname = metrics.Hostname
				s.mu.Lock()
				s.streams[hostname] = stream
				s.mu.Unlock()
			}

			// Update both local and global state
			s.mu.Lock()
			s.nodes[metrics.Hostname] = metrics
			s.mu.Unlock()

			stateMutex.Lock()
			globalNodeState[metrics.Hostname] = metrics
			stateMutex.Unlock()

			fmt.Printf("[Master] Received metrics from %s (CPU: %.1f%%)\n", metrics.Hostname, metrics.CpuUsagePercent)

			// Optionally send an ACK
			_ = stream.Send(&pb.MasterMessage{
				Payload: &pb.MasterMessage_HeartbeatAck{
					HeartbeatAck: &pb.HeartbeatResponse{Acknowledged: true},
				},
			})
		} else if resp := msg.GetDeployResponse(); resp != nil {
			fmt.Printf("[Master] Received DeployResponse from Agent: Container %s Success: %v\n", resp.ContainerId, resp.Success)
		}
	}
}

type DeployRequest struct {
	Hostname       string `json:"hostname"`
	ContainerId    string `json:"container_id"`
	MemoryMaxBytes uint64 `json:"memory_max_bytes"`
	CpuMaxQuota    uint32 `json:"cpu_max_quota"`
	RootfsImageUrl string `json:"rootfs_image_url"`
	Command        string `json:"command"`
}

// setupFiberApp configures the web routing and middleware
func setupFiberApp(master *PicoMasterServer) *fiber.App {
	app := fiber.New()

	// Allow cross-origin requests from the web dashboard
	app.Use(cors.New())

	api := app.Group("/api")

	// GET /api/nodes returns the current state of all connected nodes.
	api.Get("/nodes", func(c *fiber.Ctx) error {
		stateMutex.RLock()
		defer stateMutex.RUnlock()

		return c.JSON(globalNodeState)
	})

	// POST /api/deploy triggers a container deployment on the specified node.
	api.Post("/deploy", func(c *fiber.Ctx) error {
		var req DeployRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
		}

		master.mu.RLock()
		stream, ok := master.streams[req.Hostname]
		master.mu.RUnlock()

		if !ok {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "target agent not found or offline"})
		}

		err := stream.Send(&pb.MasterMessage{
			Payload: &pb.MasterMessage_DeployRequest{
				DeployRequest: &pb.ContainerSpec{
					ContainerId:    req.ContainerId,
					MemoryMaxBytes: req.MemoryMaxBytes,
					CpuMaxQuota:    req.CpuMaxQuota,
					RootfsImageUrl: req.RootfsImageUrl,
					Command:        req.Command,
				},
			},
		})

		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to send deploy command"})
		}

		return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"message": "deploy command sent"})
	})

	return app
}

// startGRPC runs the gRPC listener to handle daemon traffic.
func startGRPC(port string) *PicoMasterServer {
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("Failed to listen on gRPC port %s: %v", port, err)
	}

	grpcServer := grpc.NewServer()
	serverImpl := &PicoMasterServer{
		nodes:   make(map[string]*pb.NodeMetrics),
		streams: make(map[string]pb.AgentService_ControlChannelServer),
	}

	pb.RegisterAgentServiceServer(grpcServer, serverImpl)
	fmt.Printf("[PicoBox-Master] gRPC Daemon listener started on %s\n", port)

	go func() {
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("Failed to serve gRPC: %v", err)
		}
	}()

	return serverImpl
}

func main() {
	// 1. Boot up the gRPC interface on 50051 for PicoBox Daemons
	master := startGRPC(":50051")

	// 2. Boot up the Fiber REST interface on 3000 for Web/Mobile Clients
	app := setupFiberApp(master)
	fmt.Printf("[PicoBox-Master] REST API started on :3000\n")
	log.Fatal(app.Listen(":3000"))
}
