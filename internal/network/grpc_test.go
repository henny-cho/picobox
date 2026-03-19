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

// mockAgentServer implements the AgentService for testing purposes.
type mockAgentServer struct {
	pb.UnimplementedAgentServiceServer
}

func (s *mockAgentServer) ControlChannel(stream pb.AgentService_ControlChannelServer) error {
	for {
		msg, err := stream.Recv()
		if err != nil {
			return err
		}

		if req := msg.GetDeployResponse(); req != nil {
			// Ack deploy response
			continue
		} else if metrics := msg.GetMetrics(); metrics != nil {
			// Acknowledge heartbeat
			err := stream.Send(&pb.MasterMessage{
				Payload: &pb.MasterMessage_HeartbeatAck{
					HeartbeatAck: &pb.HeartbeatResponse{Acknowledged: true},
				},
			})
			if err != nil {
				return err
			}
			return nil // exit after one for the test
		}
	}
}

func init() {
	lis = bufconn.Listen(bufSize)
	s := grpc.NewServer()

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

func TestControlChannelRPC(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	//nolint:staticcheck // DialContext needed for bufconn in tests
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

	stream, err := client.ControlChannel(ctx)
	if err != nil {
		t.Fatalf("Failed to open ControlChannel stream: %v", err)
	}

	metrics := &pb.NodeMetrics{
		Hostname:         "mock-edge-01",
		CpuUsagePercent:  45.5,
		MemoryUsedBytes:  1024 * 1024 * 512,  // 512 MB
		MemoryTotalBytes: 1024 * 1024 * 2048, // 2 GB
		DiskIoWait:       0.1,
	}

	// Send an initial heartbeat
	if err := stream.Send(&pb.AgentMessage{
		Payload: &pb.AgentMessage_Metrics{
			Metrics: metrics,
		},
	}); err != nil {
		t.Fatalf("Failed to send metrics: %v", err)
	}

	// Wait for response from mock server
	res, err := stream.Recv()
	if err != nil {
		t.Fatalf("Failed to receive stream: %v", err)
	}
	ack := res.GetHeartbeatAck()
	if ack == nil || !ack.Acknowledged {
		t.Errorf("Expected server to acknowledge heartbeat")
	}
}
