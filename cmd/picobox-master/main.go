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
	nodes map[string]*pb.NodeMetrics
	mu    sync.RWMutex
}

// Heartbeat receives periodic streaming metrics from agents and updates the central registry.
func (s *PicoMasterServer) Heartbeat(stream pb.AgentService_HeartbeatServer) error {
	for {
		metrics, err := stream.Recv()
		if err == io.EOF {
			return stream.SendAndClose(&pb.HeartbeatResponse{Acknowledged: true})
		}
		if err != nil {
			return err
		}

		// Update both local and global state
		s.mu.Lock()
		s.nodes[metrics.Hostname] = metrics
		s.mu.Unlock()

		stateMutex.Lock()
		globalNodeState[metrics.Hostname] = metrics
		stateMutex.Unlock()

		fmt.Printf("[Master] Received heartbeat from %s (CPU: %.1f%%)\n", metrics.Hostname, metrics.CpuUsagePercent)
	}
}

// setupFiberApp configures the web routing and middleware
func setupFiberApp() *fiber.App {
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

	return app
}

// startGRPC runs the gRPC listener to handle daemon traffic.
func startGRPC(port string) {
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("Failed to listen on gRPC port %s: %v", port, err)
	}

	grpcServer := grpc.NewServer()
	serverImpl := &PicoMasterServer{
		nodes: make(map[string]*pb.NodeMetrics),
	}

	pb.RegisterAgentServiceServer(grpcServer, serverImpl)
	fmt.Printf("[PicoBox-Master] gRPC Daemon listener started on %s\n", port)

	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve gRPC: %v", err)
	}
}

func main() {
	// 1. Boot up the gRPC interface on 50051 for PicoBox Daemons
	go startGRPC(":50051")

	// 2. Boot up the Fiber REST interface on 3000 for Web/Mobile Clients
	app := setupFiberApp()
	fmt.Printf("[PicoBox-Master] REST API started on :3000\n")
	log.Fatal(app.Listen(":3000"))
}
