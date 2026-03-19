package main

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
)

const bufSize = 1024 * 1024

var lis *bufconn.Listener

func initBufferConn() {
	lis = bufconn.Listen(bufSize)
	s := grpc.NewServer()

	server := &PicoMasterServer{
		nodes: make(map[string]*pb.NodeMetrics),
	}

	pb.RegisterAgentServiceServer(s, server)

	go func() {
		if err := s.Serve(lis); err != nil {
			panic(err)
		}
	}()
}

func bufDialer(context.Context, string) (net.Conn, error) {
	return lis.Dial()
}

// TestAPIRoutes validates the Fiber REST API returns expected nodes list (TDD)
func TestAPIRoutes(t *testing.T) {
	app := setupFiberApp()

	// Inject fake data into the master's memory for testing the REST endpoint
	globalNodeState["test-node-01"] = &pb.NodeMetrics{
		Hostname:         "test-node-01",
		CpuUsagePercent:  12.5,
		MemoryUsedBytes:  512000,
		MemoryTotalBytes: 1024000,
	}

	req := httptest.NewRequest(http.MethodGet, "/api/nodes", nil)
	resp, err := app.Test(req, -1)
	if err != nil {
		t.Fatalf("Failed to execute request: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status code 200, got %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var nodes map[string]*pb.NodeMetrics
	if err := json.Unmarshal(body, &nodes); err != nil {
		t.Fatalf("Failed to parse JSON response: %v", err)
	}

	if node, exists := nodes["test-node-01"]; !exists {
		t.Errorf("Expected test-node-01 in response, got %v", nodes)
	} else if node.CpuUsagePercent != 12.5 {
		t.Errorf("Expected CPU usage 12.5, got %f", node.CpuUsagePercent)
	}
}

// TestGRPCHeartbeat integrates the gRPC server and tests that the data maps back to our structures.
func TestGRPCHeartbeat(t *testing.T) {
	initBufferConn()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	//nolint:staticcheck // DialContext needed for bufconn in tests; NewClient doesn't support bufconn resolver directly.
	conn, err := grpc.DialContext(ctx, "bufnet",
		grpc.WithContextDialer(bufDialer),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("Failed to dial bufnet: %v", err)
	}
	defer func() {
		if err := conn.Close(); err != nil {
			t.Logf("conn.Close error: %v", err)
		}
	}()

	client := pb.NewAgentServiceClient(conn)

	stream, err := client.ControlChannel(ctx)
	if err != nil {
		t.Fatalf("Failed to open ControlChannel stream: %v", err)
	}

	metrics := &pb.NodeMetrics{
		Hostname:         "integration-node-02",
		CpuUsagePercent:  88.8,
		MemoryUsedBytes:  1000,
		MemoryTotalBytes: 2000,
	}

	// Send an initial heartbeat to our in-memory gRPC server
	if err := stream.Send(&pb.AgentMessage{
		Payload: &pb.AgentMessage_Metrics{
			Metrics: metrics,
		},
	}); err != nil {
		t.Fatalf("Failed to send metrics: %v", err)
	}

	// Wait for response
	res, err := stream.Recv()
	if err != nil {
		t.Fatalf("Failed to receive stream: %v", err)
	}
	ack := res.GetHeartbeatAck()
	if ack == nil || !ack.Acknowledged {
		t.Errorf("Expected server to acknowledge heartbeat")
	}
}
