package main

import (
	"context"
	"fmt"
	"log"
	"time"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	"github.com/henny-cho/picobox/internal/isolation"
	"github.com/henny-cho/picobox/internal/storage"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"os"
	"os/exec"
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

	// Open a bi-directional streaming RPC
	stream, err := client.ControlChannel(context.Background())
	if err != nil {
		log.Fatalf("Error opening stream: %v", err)
	}

	fmt.Println("[PicoBox-Daemon] Connected to master. Starting ControlChannel...")

	// Goroutine to receive commands from Master
	go func() {
		for {
			msg, err := stream.Recv()
			if err != nil {
				log.Fatalf("Stream closed or error receiving from master: %v", err)
			}
			if ack := msg.GetHeartbeatAck(); ack != nil {
				// Master acknowledged heartbeat
			} else if req := msg.GetDeployRequest(); req != nil {
				fmt.Printf("[PicoBox-Daemon] Received DeployRequest for container %s\n", req.ContainerId)
				
				go func(containerId, rootfs, command string) {
					// 1. Storage setup
					storageDir := os.Getenv("PICOBOX_STORAGE_DIR")
					storeMgr := storage.NewStorageManager(storageDir)
					lower, upper, work, merged, err := storeMgr.PrepareOverlayDirs(containerId)
					
					success := true
					errMsg := ""
					
					if err == nil {
						// Simple E2E Hack: If rootfs is provided, copy it to lower
						if rootfs != "" {
							fmt.Printf("[PicoBox-Daemon] Populating lower layer from %s\n", rootfs)
							_ = exec.Command("cp", "-r", rootfs+"/.", lower).Run()
						}

						// Note: MountOverlayFS requires root. In tests we mock or ignore errors if not root.
						err = storeMgr.MountOverlayFS(lower, upper, work, merged)
						if err != nil {
							fmt.Printf("Warning: MountOverlayFS failed (needs root): %v\n", err)
							// Proceeding anyway for the sake of the daemon loop in non-root dev environments
						}
					}

					// 2. Isolation process spawn
					if command == "" {
						command = "/bin/sleep"
					}
					fmt.Printf("[PicoBox-Daemon] Spawning process: %s\n", command)
					cmd := isolation.NewContainerProcess(context.Background(), command, "10")
					if errStart := cmd.Start(); errStart != nil {
						success = false
						errMsg = errStart.Error()
					}

					// 3. Send response
					_ = stream.Send(&pb.AgentMessage{
						Payload: &pb.AgentMessage_DeployResponse{
							DeployResponse: &pb.DeployResponse{
								ContainerId:  containerId,
								Success:      success,
								ErrorMessage: errMsg,
							},
						},
					})
				}(req.ContainerId, req.RootfsImageUrl, req.Command)
			}
		}
	}()

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

		if err := stream.Send(&pb.AgentMessage{
			Payload: &pb.AgentMessage_Metrics{
				Metrics: metrics,
			},
		}); err != nil {
			log.Fatalf("Failed to send metrics: %v", err)
		}

		fmt.Printf("Sent heartbeat: CPU %.1f%%, Mem %dMB\n", cpuUsage, memUsed/(1024*1024))

		cpuUsage += 1.2
		if cpuUsage > 90.0 {
			cpuUsage = 10.5
		}
		memUsed += 1024 * 1024 * 50 // +50MB per tick

		time.Sleep(2 * time.Second)
	}

	fmt.Printf("[PicoBox-Daemon] Finished simulated run.\n")
}
