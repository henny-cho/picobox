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
	"time"
)

// globalNodeState holds the real-time status of all active PicoBox daemons.
type ContainerInfo struct {
	DeployResponse *pb.DeployResponse `json:"deploy_response"`
	Hostname       string             `json:"hostname"`
	Status         string             `json:"status"` // "Pending", "Running", "Stopped", "Error"
	Spec           *pb.ContainerSpec  `json:"spec"`   // Persist spec for restarts
}

var (
	globalNodeState      = make(map[string]*pb.NodeMetrics)
	globalContainerState = make(map[string]*ContainerInfo)
	execChannels         sync.Map // map[string]chan *pb.ExecResponse
	stateMutex           sync.RWMutex
	globalStore          *Store
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
			if globalStore != nil {
				_ = globalStore.SaveNode(metrics)
			}
			stateMutex.Unlock()

			fmt.Printf("[Master] Received metrics from %s (CPU: %.1f%%)\n", metrics.Hostname, metrics.CpuUsagePercent)

			// Optionally send an ACK
			_ = stream.Send(&pb.MasterMessage{
				Payload: &pb.MasterMessage_HeartbeatAck{
					HeartbeatAck: &pb.HeartbeatResponse{Acknowledged: true},
				},
			})
		} else if resp := msg.GetStopResponse(); resp != nil {
			fmt.Printf("[Master] Received StopResponse from Agent: Container %s Success: %v\n", resp.ContainerId, resp.Success)
			stateMutex.Lock()
			if info, ok := globalContainerState[resp.ContainerId]; ok {
				if resp.Success {
					info.Status = "Stopped"
				} else {
					info.Status = "Stop Failed"
				}
			}
			stateMutex.Unlock()
		} else if resp := msg.GetDeployResponse(); resp != nil {
			fmt.Printf("[Master] Received DeployResponse from Agent: Container %s Success: %v\n", resp.ContainerId, resp.Success)
			stateMutex.Lock()
			if info, ok := globalContainerState[resp.ContainerId]; ok {
				info.DeployResponse = resp
				if resp.Success {
					info.Status = "Running"
				} else {
					info.Status = "Error"
				}
			} else {
				status := "Error"
				if resp.Success { status = "Running" }
				globalContainerState[resp.ContainerId] = &ContainerInfo{
					DeployResponse: resp,
					Hostname:       hostname,
					Status:         status,
				}
			}
			if globalStore != nil {
				_ = globalStore.SaveContainer(resp.ContainerId, globalContainerState[resp.ContainerId])
			}
			stateMutex.Unlock()
		} else if resp := msg.GetExecResponse(); resp != nil {
			if ch, ok := execChannels.Load(resp.ContainerId); ok {
				ch.(chan *pb.ExecResponse) <- resp
			}
		}
	}
}

type StopRequest struct {
	Hostname    string `json:"hostname"`
	ContainerId string `json:"container_id"`
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

	// GET /api/containers returns all deployed containers and their status.
	api.Get("/containers", func(c *fiber.Ctx) error {
		stateMutex.RLock()
		defer stateMutex.RUnlock()
		return c.JSON(globalContainerState)
	})

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

		// Pre-register container info with hostname so we can track where it went
		stateMutex.Lock()
		spec := &pb.ContainerSpec{
			ContainerId:    req.ContainerId,
			RootfsImageUrl: req.RootfsImageUrl,
			Command:        req.Command,
			MemoryMaxBytes: req.MemoryMaxBytes,
			CpuMaxQuota:    req.CpuMaxQuota,
		}
		globalContainerState[req.ContainerId] = &ContainerInfo{
			DeployResponse: &pb.DeployResponse{
				ContainerId: req.ContainerId,
				Success:     false,
				ErrorMessage: "Deploying...",
			},
			Hostname: req.Hostname,
			Spec:     spec,
		}
		if globalStore != nil {
			_ = globalStore.SaveContainer(req.ContainerId, globalContainerState[req.ContainerId])
		}
		stateMutex.Unlock()

		err := stream.Send(&pb.MasterMessage{
			Payload: &pb.MasterMessage_DeployRequest{
				DeployRequest: spec,
			},
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(fiber.Map{"status": "Deploy request sent to " + req.Hostname})
	})

	// POST /api/stop triggers a container termination.
	api.Post("/stop", func(c *fiber.Ctx) error {
		var req StopRequest
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
			Payload: &pb.MasterMessage_StopRequest{
				StopRequest: &pb.StopRequest{
					ContainerId: req.ContainerId,
					Force:       true,
				},
			},
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(fiber.Map{"status": "Stop request sent to " + req.Hostname})
	})

	// POST /api/start re-deploys a stopped container with its existing spec.
	api.Post("/start", func(c *fiber.Ctx) error {
		var req struct {
			Hostname    string `json:"hostname"`
			ContainerId string `json:"container_id"`
		}
		if err := c.BodyParser(&req); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
		}

		stateMutex.Lock()
		info, exists := globalContainerState[req.ContainerId]
		if exists && info.Status != "Running" {
			info.Status = "Pending"
		}
		stateMutex.Unlock()

		if !exists || info.Spec == nil {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "container spec not found"})
		}

		master.mu.RLock()
		stream, ok := master.streams[req.Hostname]
		master.mu.RUnlock()

		if !ok {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "target agent not found"})
		}

		err := stream.Send(&pb.MasterMessage{
			Payload: &pb.MasterMessage_DeployRequest{
				DeployRequest: info.Spec,
			},
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(fiber.Map{"status": "Start request sent to " + req.Hostname})
	})

	// POST /api/update updates the container specification for future starts.
	api.Post("/update", func(c *fiber.Ctx) error {
		var req DeployRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
		}

		stateMutex.Lock()
		defer stateMutex.Unlock()

		if info, ok := globalContainerState[req.ContainerId]; ok {
			info.Spec = &pb.ContainerSpec{
				ContainerId:    req.ContainerId,
				RootfsImageUrl: req.RootfsImageUrl,
				Command:        req.Command,
				MemoryMaxBytes: req.MemoryMaxBytes,
				CpuMaxQuota:    req.CpuMaxQuota,
			}
			if globalStore != nil {
				_ = globalStore.SaveContainer(req.ContainerId, info)
			}
			return c.JSON(fiber.Map{"success": true, "message": "Container spec updated"})
		}

		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "container not found"})
	})

	// POST /api/exec executes a command in a running container and returns the output.
	api.Post("/exec", func(c *fiber.Ctx) error {
		var req struct {
			Hostname    string `json:"hostname" shadow:"true"`
			ContainerId string `json:"container_id"`
			Command     string `json:"command"`
		}
		if err := c.BodyParser(&req); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"error": "invalid request body"})
		}

		stateMutex.RLock()
		info, exists := globalContainerState[req.ContainerId]
		stateMutex.RUnlock()

		if !exists {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "container not found"})
		}

		master.mu.RLock()
		stream, ok := master.streams[info.Hostname]
		master.mu.RUnlock()

		if !ok {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"error": "agent offline"})
		}

		// Create a response channel
		respCh := make(chan *pb.ExecResponse, 1)
		execChannels.Store(req.ContainerId, respCh)
		defer execChannels.Delete(req.ContainerId)

		err := stream.Send(&pb.MasterMessage{
			Payload: &pb.MasterMessage_ExecRequest{
				ExecRequest: &pb.ExecRequest{
					ContainerId: req.ContainerId,
					Command:     req.Command,
				},
			},
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "failed to send exec request"})
		}

		// Wait for response with timeout
		select {
		case resp := <-respCh:
			return c.JSON(resp)
		case <-time.After(10 * time.Second):
			return c.Status(fiber.StatusGatewayTimeout).JSON(fiber.Map{"error": "exec timed out"})
		}
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
	var err error
	storageDir := "storage"
	globalStore, err = NewStore(storageDir + "/picobox.db")
	if err != nil {
		log.Printf("Warning: Failed to initialize SQLite store: %v. Running in-memory only.", err)
	} else {
		fmt.Println("[PicoBox-Master] Persistence layer initialized.")
		// Load initial state
		if nodes, err := globalStore.LoadNodes(); err == nil {
			stateMutex.Lock()
			globalNodeState = nodes
			stateMutex.Unlock()
		}
		if containers, err := globalStore.LoadContainers(); err == nil {
			stateMutex.Lock()
			globalContainerState = containers
			stateMutex.Unlock()
		}
	}

	// 1. Boot up the gRPC interface on 50051 for PicoBox Daemons
	master := startGRPC(":50051")

	// 2. Boot up the Fiber REST interface on 3000 for Web/Mobile Clients
	app := setupFiberApp(master)
	fmt.Printf("[PicoBox-Master] REST API started on :3000\n")
	log.Fatal(app.Listen(":3000"))
}
