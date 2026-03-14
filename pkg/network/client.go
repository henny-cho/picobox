package network

import (
	"fmt"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// GRPCClient is a common wrapper for gRPC connections with built-in resilience.
type GRPCClient struct {
	Conn *grpc.ClientConn
}

// NewGRPCClient establishes a secure-by-default (insecure for now) connection.
func NewGRPCClient(address string) (*GRPCClient, error) {
	// Connect with insecure credentials for local development/edge nodes.
	// In production, this should be replaced with mTLS.
	// Establish connection using grpc.NewClient (latest gRPC practice).
	// Note: grpc.NewClient is non-blocking and does not take a context for connection establishment.
	conn, err := grpc.NewClient(address,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create gRPC client: %v", err)
	}

	return &GRPCClient{Conn: conn}, nil
}

// Close gracefully shuts down the gRPC connection.
func (c *GRPCClient) Close() error {
	if c.Conn != nil {
		return c.Conn.Close()
	}
	return nil
}
