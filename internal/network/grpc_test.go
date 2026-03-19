package network_test

import (
	"context"
	"net"
	"testing"
	"time"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"
)

const bufSize = 1024 * 1024

var lis *bufconn.Listener

// mockMasterServer implements the MasterService for testing purposes.
type mockMasterServer struct {
	pb.UnimplementedMasterServiceServer
}

func (s *mockMasterServer) DeployContainer(ctx context.Context, req *pb.ContainerSpec) (*pb.DeployResponse, error) {
	// Simple validation for the mock logic
	if req.ContainerId == "" {
		return &pb.DeployResponse{Success: false, ErrorMessage: "empty container id"}, nil
	}
	return &pb.DeployResponse{Success: true, ErrorMessage: ""}, nil
}

// mockAgentServer implements the AgentService for testing purposes.
type mockAgentServer struct {
	pb.UnimplementedAgentServiceServer
}

func (s *mockAgentServer) Heartbeat(stream pb.AgentService_HeartbeatServer) error {
	// Receive a single metrics payload and acknowledge
	if _, err := stream.Recv(); err != nil {
		return err
	}
	return stream.SendAndClose(&pb.HeartbeatResponse{Acknowledged: true})
}

func init() {
	lis = bufconn.Listen(bufSize)
	s := grpc.NewServer()

	pb.RegisterMasterServiceServer(s, &mockMasterServer{})
	pb.RegisterAgentServiceServer(s, &mockAgentServer{})

	go func() {
		if err := s.Serve(lis); err != nil {
			panic(err)
		}
	}()
}

func bufDialer(context.Context, string) (net.Conn, error) {
	return lis.Dial()
}

func TestDeployContainerRPC(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	//nolint:staticcheck // DialContext needed for bufconn in tests; NewClient doesn't support bufconn resolver directly.
	conn, err := grpc.DialContext(ctx, "bufnet", grpc.WithContextDialer(bufDialer), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatalf("Failed to dial bufnet: %v", err)
	}
	defer func() {
		if err := conn.Close(); err != nil {
			t.Logf("conn.Close error: %v", err)
		}
	}()

	client := pb.NewMasterServiceClient(conn)

	// Test 1: Valid container spec
	spec := &pb.ContainerSpec{
		ContainerId:    "test-container-01",
		MemoryMaxBytes: 1024 * 1024 * 128, // 128 MB
		CpuMaxQuota:    100000,            // 1 Core
		RootfsImageUrl: "/tmp/mock/rootfs.tar.gz",
	}

	res, err := client.DeployContainer(ctx, spec)
	if err != nil {
		t.Fatalf("DeployContainer failed: %v", err)
	}
	if !res.Success {
		t.Errorf("Expected success to be true, got %v with error: %s", res.Success, res.ErrorMessage)
	}

	// Test 2: Invalid container spec (empty ID)
	specInvalid := &pb.ContainerSpec{
		ContainerId: "", // Will fail our mock check
	}

	resInvalid, err := client.DeployContainer(ctx, specInvalid)
	if err != nil {
		t.Fatalf("DeployContainer failed: %v", err)
	}
	if resInvalid.Success {
		t.Errorf("Expected success to be false for empty ID, but got true")
	}
}

func TestHeartbeatRPC(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	//nolint:staticcheck // DialContext needed for bufconn in tests; NewClient doesn't support bufconn resolver directly.
	conn, err := grpc.DialContext(ctx, "bufnet", grpc.WithContextDialer(bufDialer), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatalf("Failed to dial bufnet: %v", err)
	}
	defer func() {
		if err := conn.Close(); err != nil {
			t.Logf("conn.Close error: %v", err)
		}
	}()

	client := pb.NewAgentServiceClient(conn)

	stream, err := client.Heartbeat(ctx)
	if err != nil {
		t.Fatalf("Failed to open Heartbeat stream: %v", err)
	}

	metrics := &pb.NodeMetrics{
		Hostname:         "mock-edge-01",
		CpuUsagePercent:  45.5,
		MemoryUsedBytes:  1024 * 1024 * 512,  // 512 MB
		MemoryTotalBytes: 1024 * 1024 * 2048, // 2 GB
		DiskIoWait:       0.1,
	}

	// Send an initial heartbeat
	if err := stream.Send(metrics); err != nil {
		t.Fatalf("Failed to send metrics: %v", err)
	}

	// Wait for response and close
	res, err := stream.CloseAndRecv()
	if err != nil {
		t.Fatalf("Failed to close/receive stream: %v", err)
	}
	if !res.Acknowledged {
		t.Errorf("Expected server to acknowledge heartbeat")
	}
}
