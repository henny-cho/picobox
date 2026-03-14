package main

import (
	"context"
	"fmt"
	"log"
	"time"

	pb "github.com/henny-cho/picobox/api/gen/go"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	fmt.Println("[PicoBox-Daemon] Starting agent...")

	// Connect to Master Server via grpc.NewClient (non-blocking)
	conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer func() {
		if err := conn.Close(); err != nil {
			log.Printf("Failed to close connection: %v", err)
		}
	}()

	client := pb.NewAgentServiceClient(conn)

	// Open a streaming RPC
	stream, err := client.Heartbeat(context.Background())
	if err != nil {
		log.Fatalf("Error opening stream: %v", err)
	}

	fmt.Println("[PicoBox-Daemon] Connected to master. Sending heartbeats...")

	// Simulate periodic heartbeats
	cpuUsage := 10.5
	memUsed := uint64(1024 * 1024 * 512)

	for i := 0; i < 60; i++ {
		metrics := &pb.NodeMetrics{
			Hostname:         "pico-worker-1",
			CpuUsagePercent:  float32(cpuUsage),
			MemoryUsedBytes:  memUsed,
			MemoryTotalBytes: 1024 * 1024 * 4096,
			DiskIoWait:       0.05,
		}

		if err := stream.Send(metrics); err != nil {
			log.Fatalf("Failed to send a note: %v", err)
		}

		fmt.Printf("Sent heartbeat: CPU %.1f%%, Mem %dMB\n", cpuUsage, memUsed/(1024*1024))

		cpuUsage += 1.2
		if cpuUsage > 90.0 {
			cpuUsage = 10.5
		}
		memUsed += 1024 * 1024 * 50 // +50MB per tick

		time.Sleep(2 * time.Second)
	}

	// Wait for response and close
	res, err := stream.CloseAndRecv()
	if err != nil {
		log.Fatalf("Error receiving response: %v", err)
	}
	fmt.Printf("[PicoBox-Daemon] Finished. Master acknowledged: %v\n", res.Acknowledged)
}
