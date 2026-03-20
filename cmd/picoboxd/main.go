package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	"github.com/henny-cho/picobox/internal/isolation"
	"github.com/henny-cho/picobox/internal/storage"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var containerRegistry sync.Map // map[string]*exec.Cmd

func getRealMetrics() (float32, uint64, uint64) {
	// 1. CPU Usage (/proc/stat)
	data, err := os.ReadFile("/proc/stat")
	var cpuUsage float32 = 0.0
	if err == nil {
		var user, nice, system, idle, iowait, irq, softirq, steal uint64
		_, _ = fmt.Sscanf(string(data), "cpu  %d %d %d %d %d %d %d %d", &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal)
		total := user + nice + system + idle + iowait + irq + softirq + steal
		active := total - idle - iowait
		if total > 0 {
			cpuUsage = float32(active) * 100 / float32(total)
		}
	}

	// 2. Memory Usage (/proc/meminfo)
	var memTotal, memAvailable uint64
	memData, err := os.ReadFile("/proc/meminfo")
	if err == nil {
		content := string(memData)
		for _, line := range strings.Split(content, "\n") {
			if strings.HasPrefix(line, "MemTotal:") {
				_, _ = fmt.Sscanf(line, "MemTotal: %d kB", &memTotal)
			}
			if strings.HasPrefix(line, "MemAvailable:") {
				_, _ = fmt.Sscanf(line, "MemAvailable: %d kB", &memAvailable)
			}
		}
		memTotal *= 1024
		memAvailable *= 1024
	}

	memUsed := memTotal - memAvailable
	if memTotal == 0 {
		memTotal = 1024 * 1024 * 4096 // Default fallback
	}

	return cpuUsage, memUsed, memTotal
}

func main() {
	fmt.Println("[PicoBox-Agent] Starting...")

	// Connect to Master Server
	conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer func() {
		_ = conn.Close()
	}()

	client := pb.NewAgentServiceClient(conn)
	stream, err := client.ControlChannel(context.Background())
	if err != nil {
		log.Fatalf("Error opening stream: %v", err)
	}

	fmt.Println("[PicoBox-Agent] Connected to Master. Starting ControlChannel...")

	// Receive Loop
	go func() {
		for {
			msg, err := stream.Recv()
			if err != nil {
				log.Fatalf("Stream closed or error: %v", err)
			}

			if req := msg.GetDeployRequest(); req != nil {
				fmt.Printf("[PicoBox-Agent] Received DeployRequest: %s\n", req.ContainerId)
				go handleDeploy(stream, req)
			} else if req := msg.GetStopRequest(); req != nil {
				fmt.Printf("[PicoBox-Agent] Received StopRequest: %s\n", req.ContainerId)
				handleStop(stream, req)
			} else if req := msg.GetExecRequest(); req != nil {
				fmt.Printf("[PicoBox-Agent] Received ExecRequest for %s: %s\n", req.ContainerId, req.Command)
				handleExec(stream, req)
			}
		}
	}()

	// Heartbeat Loop (Real Metrics)
	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "pico-agent"
	}

	for {
		cpu, used, total := getRealMetrics()
		metrics := &pb.NodeMetrics{
			Hostname:         hostname,
			CpuUsagePercent:  cpu,
			MemoryUsedBytes:  used,
			MemoryTotalBytes: total,
			DiskIoWait:       0.0,
		}

		err := stream.Send(&pb.AgentMessage{
			Payload: &pb.AgentMessage_Metrics{
				Metrics: metrics,
			},
		})
		if err != nil {
			log.Printf("Failed to send metrics: %v", err)
			break
		}

		fmt.Printf("[PicoBox-Agent] Heartbeat: CPU %.1f%%, Mem %d/%d MB\n", cpu, used/(1024*1024), total/(1024*1024))
		time.Sleep(5 * time.Second)
	}
}

func handleDeploy(stream pb.AgentService_ControlChannelClient, req *pb.ContainerSpec) {
	containerId := req.ContainerId
	rootfs := req.RootfsImageUrl
	command := req.Command

	// 1. Storage setup
	storageDir := os.Getenv("PICOBOX_STORAGE_DIR")
	storeMgr := storage.NewStorageManager(storageDir)
	lower, upper, work, merged, _ := storeMgr.PrepareOverlayDirs(containerId)

	success := true
	errMsg := ""

	if rootfs != "" {
		_ = exec.Command("cp", "-r", rootfs+"/.", lower).Run()
	}
	// Note: Overlay mount requires root.
	_ = storeMgr.MountOverlayFS(lower, upper, work, merged)

	// Isolation process spawn
	// Using sh -c to allow complex shell scripts from UI
	if command == "" {
		command = "while true; do date; sleep 5; done"
	} // TODO: fix this process is not killed when the container is stopped
	cmd := isolation.NewContainerProcess(context.Background(), "/bin/sh", "-c", command)
	containerRegistry.Store(containerId, cmd)

	if errStart := cmd.Start(); errStart != nil {
		success = false
		errMsg = errStart.Error()
		containerRegistry.Delete(containerId)
	} else {
		fmt.Printf("[PicoBox-Agent] Container %s started (PID: %d)\n", containerId, cmd.Process.Pid)
		go func() {
			_ = cmd.Wait()
			containerRegistry.Delete(containerId)
			fmt.Printf("[PicoBox-Agent] Container %s exited\n", containerId)
		}()
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
}

func handleStop(stream pb.AgentService_ControlChannelClient, req *pb.StopRequest) {
	success := false
	errMsg := ""

	if val, ok := containerRegistry.Load(req.ContainerId); ok {
		cmd := val.(*exec.Cmd)
		if cmd.Process != nil {
			fmt.Printf("[PicoBox-Agent] Terminating container %s\n", req.ContainerId)
			var err error
			if req.Force {
				err = cmd.Process.Kill()
			} else {
				err = cmd.Process.Signal(os.Interrupt)
			}

			if err == nil {
				success = true
			} else {
				errMsg = err.Error()
			}
		} else {
			errMsg = "process not started"
		}
	} else {
		errMsg = "container not found"
	}

	_ = stream.Send(&pb.AgentMessage{
		Payload: &pb.AgentMessage_StopResponse{
			StopResponse: &pb.StopResponse{
				ContainerId:  req.ContainerId,
				Success:      success,
				ErrorMessage: errMsg,
			},
		},
	})
}

func handleExec(stream pb.AgentService_ControlChannelClient, req *pb.ExecRequest) {
	containerId := req.ContainerId
	command := req.Command

	success := false
	output := ""
	errMsg := ""

	if val, ok := containerRegistry.Load(containerId); ok {
		cmd := val.(*exec.Cmd)
		if cmd.Process != nil {
			pid := cmd.Process.Pid
			// Use nsenter to run command in the container's namespaces
			// Note: This requires the agent to have sufficient privileges or be in the right namespace itself.
			// Since we are using unprivileged user namespaces, we might need to handle this carefully.
			// For now, we use sh -c as a fallback or nsenter if available.

			// We try nsenter first
			nsCmd := exec.Command("nsenter", "-t", fmt.Sprintf("%d", pid), "-m", "-u", "-i", "-n", "-p", "sh", "-c", command)
			out, err := nsCmd.CombinedOutput()
			if err == nil {
				success = true
				output = string(out)
			} else {
				// Fallback to simple exec if nsenter fails (might happen in some restricted environments)
				errMsg = fmt.Sprintf("nsenter failed: %v. Output: %s", err, string(out))

				// Optional: Just run it if it's a simple process-based "container"
				// but for real isolation, nsenter is required.
			}
		} else {
			errMsg = "container process not found"
		}
	} else {
		errMsg = "container not tracked in registry"
	}

	_ = stream.Send(&pb.AgentMessage{
		Payload: &pb.AgentMessage_ExecResponse{
			ExecResponse: &pb.ExecResponse{
				ContainerId:  containerId,
				Success:      success,
				Output:       output,
				ErrorMessage: errMsg,
			},
		},
	})
}
