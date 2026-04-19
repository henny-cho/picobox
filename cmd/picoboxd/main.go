package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	"github.com/henny-cho/picobox/internal/isolation"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
)

// Injected at build time via -ldflags "-X main.Version=... -X main.Commit=... -X main.BuildDate=..."
var (
	Version   = "dev"
	Commit    = "unknown"
	BuildDate = "unknown"
)

var (
	sandboxRegistry sync.Map // map[string]*isolation.Sandbox
	streamMu        sync.Mutex
)

// safeSend sends a message over the gRPC stream in a thread-safe manner.
func safeSend(stream pb.AgentService_ControlChannelClient, msg *pb.AgentMessage) error {
	streamMu.Lock()
	defer streamMu.Unlock()
	return stream.Send(msg)
}

func getRealMetrics() *pb.NodeMetrics {
	m, err := isolation.GetNodeMetrics()
	if err != nil {
		log.Printf("[PicoBox-Agent] Error getting node metrics: %v", err)
		return &pb.NodeMetrics{
			Hostname: "pico-agent-error",
		}
	}
	return &pb.NodeMetrics{
		Hostname:         m.Hostname,
		CpuUsagePercent:  float32(m.CpuUsagePercent),
		MemoryUsedBytes:  m.MemoryUsedBytes,
		MemoryTotalBytes: m.MemoryTotalBytes,
		DiskIoWait:       float32(m.DiskIoWait),
	}
}

func cleanupOrphans() {
	storageDir := os.Getenv("PICOBOX_STORAGE_DIR")
	if storageDir == "" {
		storageDir = "storage"
	}
	// 1. Unmount all picobox overlay mounts
	fmt.Println("[PicoBox-Agent] Cleaning up orphan mounts...")
	data, err := os.ReadFile("/proc/mounts")
	if err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			if strings.Contains(line, "/"+storageDir+"/containers/") && strings.Contains(line, "merged") {
				fields := strings.Fields(line)
				if len(fields) > 1 {
					mountPoint := fields[1]
					fmt.Printf("[PicoBox-Agent] Unmounting orphan: %s\n", mountPoint)
					_ = syscall.Unmount(mountPoint, 0)
				}
			}
		}
	}

	// 2. Cleanup cgroups (picobox sub-hierarchy)
	fmt.Println("[PicoBox-Agent] Cleaning up orphan cgroups...")
	cgroupPath := "/sys/fs/cgroup/picobox"
	_ = filepath.Walk(cgroupPath, func(path string, info os.FileInfo, err error) error {
		if err == nil && info.IsDir() && path != cgroupPath {
			// Try to remove leaf cgroups first
			_ = os.Remove(path)
		}
		return nil
	})

	// 3. Clear container storage state (optional, but keeps it clean)
	// We might want to keep images but clear 'containers' working dirs
	contDir := filepath.Join(storageDir, "containers")
	entries, err := os.ReadDir(contDir)
	if err == nil {
		for _, entry := range entries {
			if entry.IsDir() {
				fmt.Printf("[PicoBox-Agent] Removing orphan container dir: %s\n", entry.Name())
				_ = os.RemoveAll(filepath.Join(contDir, entry.Name()))
			}
		}
	}
}

func main() {
	showVersion := flag.Bool("version", false, "Print version information and exit")
	flag.Parse()
	if *showVersion {
		fmt.Printf("picoboxd %s (commit %s, built %s)\n", Version, Commit, BuildDate)
		return
	}

	fmt.Printf("[PicoBox-Agent] Starting (version=%s, commit=%s)...\n", Version, Commit)

	// 0. Robustness: Cleanup Orphans
	cleanupOrphans()

	for {
		err := runAgent()
		if err != nil {
			log.Printf("[PicoBox-Agent] Error: %v. Reconnecting in 5s...", err)
			time.Sleep(5 * time.Second)
		}
	}
}

func runAgent() error {
	// Connect to Master Server
	conn, err := grpc.NewClient("localhost:50051", grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return fmt.Errorf("did not connect: %w", err)
	}
	defer func() {
		_ = conn.Close()
	}()

	client := pb.NewAgentServiceClient(conn)

	token := os.Getenv("PICOBOX_API_TOKEN")
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	if token != "" {
		md := metadata.Pairs("x-api-token", token)
		ctx = metadata.NewOutgoingContext(ctx, md)
	}

	stream, err := client.ControlChannel(ctx)
	if err != nil {
		return fmt.Errorf("error opening stream: %w", err)
	}

	fmt.Println("[PicoBox-Agent] Connected to Master. Starting ControlChannel...")

	// Receive Loop
	stopChan := make(chan struct{})
	go func() {
		for {
			msg, err := stream.Recv()
			if err != nil {
				log.Printf("[PicoBox-Agent] Stream recv error: %v", err)
				close(stopChan)
				return
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

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-stopChan:
			return fmt.Errorf("control channel closed")
		case <-ticker.C:
			metrics := getRealMetrics()
			if metrics.Hostname == "pico-agent-error" || metrics.Hostname == "" {
				metrics.Hostname = hostname
			}

			err := safeSend(stream, &pb.AgentMessage{
				Payload: &pb.AgentMessage_Metrics{
					Metrics: metrics,
				},
			})
			if err != nil {
				return fmt.Errorf("failed to send metrics: %w", err)
			}
			fmt.Printf("[PicoBox-Agent] Heartbeat sent. CPU %.1f%%\n", metrics.CpuUsagePercent)
		}
	}
}

func handleDeploy(stream pb.AgentService_ControlChannelClient, req *pb.ContainerSpec) {
	containerId := req.ContainerId

	storageDir := os.Getenv("PICOBOX_STORAGE_DIR")
	if storageDir == "" {
		storageDir = "storage"
	}

	// Prepare Sandbox Configuration
	config := isolation.SandboxConfig{
		ID:             containerId,
		RootfsImageUrl: req.RootfsImageUrl,
		Command:        req.Command,
		MemoryMaxBytes: req.MemoryMaxBytes,
		CpuMaxQuota:    int(req.CpuMaxQuota),
		StorageDir:     storageDir,
	}

	sb := isolation.NewSandbox(config)

	success := true
	errMsg := ""

	// 1. Initial Start (including storage/cgroups setup)
	fmt.Printf("[PicoBox-Agent] Initiating Sandbox for %s...\n", containerId)
	if err := sb.Start(context.Background()); err != nil {
		success = false
		errMsg = "Sandbox start failed: " + err.Error()
		fmt.Printf("[PicoBox-Agent] Deploy failed: %s\n", errMsg)

		// 2. Rollback (Cleanup on failure)
		_ = sb.Stop()
	} else {
		fmt.Printf("[PicoBox-Agent] Sandbox %s active.\n", containerId)
		sandboxRegistry.Store(containerId, sb)

		// 3. Log Streaming
		stdout, errPipe := sb.GetStdout()
		if errPipe != nil {
			log.Printf("Warning: Failed to get stdout for %s: %v", containerId, errPipe)
		}
		stderr, errPipe := sb.GetStderr()
		if errPipe != nil {
			log.Printf("Warning: Failed to get stderr for %s: %v", containerId, errPipe)
		}

		streamLogs := func(r io.Reader, isStderr bool) {
			if r == nil { return }
			scanner := bufio.NewScanner(r)
			for scanner.Scan() {
				_ = safeSend(stream, &pb.AgentMessage{
					Payload: &pb.AgentMessage_ContainerLog{
						ContainerLog: &pb.ContainerLog{
							ContainerId: containerId,
							LogLine:     scanner.Text(),
							IsStderr:    isStderr,
						},
					},
				})
			}
		}

		go streamLogs(stdout, false)
		go streamLogs(stderr, true)

		// Wait for exit
		go func() {
			err := sb.Wait()
			sandboxRegistry.Delete(containerId)
			fmt.Printf("[PicoBox-Agent] Sandbox %s exited. Info: %v\n", containerId, err)

			// Optional: Auto-cleanup on exit
			_ = sb.Stop()
		}()
	}

	// 4. Send response to Master
	_ = safeSend(stream, &pb.AgentMessage{
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

	if val, ok := sandboxRegistry.Load(req.ContainerId); ok {
		sb := val.(*isolation.Sandbox)
		fmt.Printf("[PicoBox-Agent] Stopping sandbox %s (Force: %v)\n", req.ContainerId, req.Force)

		// currently sb.Stop() handles unmounting and cgroup cleanup
		if err := sb.Stop(); err == nil {
			success = true
		} else {
			errMsg = err.Error()
		}
	} else {
		errMsg = "sandbox not found in registry"
	}

	_ = safeSend(stream, &pb.AgentMessage{
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

	if val, ok := sandboxRegistry.Load(containerId); ok {
		sb := val.(*isolation.Sandbox)
		// Run in sandbox namespaces
		out, err := sb.Exec(command)
		if err == nil {
			success = true
			output = out
		} else {
			errMsg = err.Error()
		}
	} else {
		errMsg = "sandbox not tracked in registry"
	}

	_ = safeSend(stream, &pb.AgentMessage{
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
