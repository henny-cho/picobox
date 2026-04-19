package isolation

import (
	"context"
	"fmt"
	"io"
	"os/exec"

	"github.com/henny-cho/picobox/internal/storage"
)

// SandboxConfig holds the specification for a container run.
type SandboxConfig struct {
	ID             string
	Command        string
	Args           []string
	MemoryMaxBytes uint64
	CpuMaxQuota    int
	RootfsImageUrl string
	StorageDir     string
}

// Sandbox represents a managed container lifecycle.
type Sandbox struct {
	Config  SandboxConfig
	storage *storage.StorageManager
	cgroups *CgroupsManager
	cmd     *exec.Cmd
	stdout  io.ReadCloser
	stderr  io.ReadCloser
}

// NewSandbox initializes a container facade.
func NewSandbox(cfg SandboxConfig) *Sandbox {
	return &Sandbox{
		Config:  cfg,
		storage: storage.NewStorageManager(cfg.StorageDir),
		cgroups: NewCgroupsManager(""),
	}
}

// Start orchestrates the full isolation sequence: storage -> cgroups -> namespaces -> pivot_root.
func (s *Sandbox) Start(ctx context.Context) error {
	// 1. Prepare Storage (OverlayFS)
	lower, upper, work, merged, err := s.storage.PrepareOverlayDirs(s.Config.ID)
	if err != nil {
		return fmt.Errorf("storage prep failed: %w", err)
	}

	// For Phase 3 integration, we use the RootfsImageUrl as the source to copy into 'lower'
	if s.Config.RootfsImageUrl != "" {
		// Simplified copy for integration
		cp := exec.Command("cp", "-a", s.Config.RootfsImageUrl+"/.", lower)
		if err := cp.Run(); err != nil {
			return fmt.Errorf("failed to copy rootfs: %w", err)
		}
	}

	if err := s.storage.MountOverlayFS(lower, upper, work, merged); err != nil {
		return fmt.Errorf("mount overlay failed: %w", err)
	}

	// 2. Prepare Namespaces
	// To support complex command strings (like shell loops), we wrap in sh -c
	s.cmd = NewContainerProcess(ctx, "/bin/sh", "-c", s.Config.Command)
	s.cmd.Dir = "/" // After pivot_root, it should be /

	// Setup Pipes BEFORE Start
	s.stdout, _ = s.cmd.StdoutPipe()
	s.stderr, _ = s.cmd.StderrPipe()

	if err := s.cmd.Start(); err != nil {
		return fmt.Errorf("process start failed: %w", err)
	}

	// 3. Apply Resource Limits
	if err := s.cgroups.CreateCgroup(s.Config.ID); err != nil {
		return err
	}
	if err := s.cgroups.AddProcess(s.Config.ID, s.cmd.Process.Pid); err != nil {
		return err
	}
	if s.Config.MemoryMaxBytes > 0 {
		if err := s.cgroups.SetMemoryLimit(s.Config.ID, s.Config.MemoryMaxBytes); err != nil {
			return err
		}
	}
	if s.Config.CpuMaxQuota > 0 {
		if err := s.cgroups.SetCpuLimit(s.Config.ID, s.Config.CpuMaxQuota); err != nil {
			return err
		}
	}

	return nil
}

// Wait blocks until the container process exits.
func (s *Sandbox) Wait() error {
	if s.cmd == nil {
		return fmt.Errorf("sandbox not started")
	}
	return s.cmd.Wait()
}

// Stop tears down the sandbox resources.
func (s *Sandbox) Stop() error {
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
	// 1. Unmount storage
	_ = s.storage.UnmountOverlayFS(s.Config.ID)
	// 2. Remove cgroups
	_ = s.cgroups.RemoveCgroup(s.Config.ID)
	return nil
}

// GetStdout returns the stdout pipe of the container process.
func (s *Sandbox) GetStdout() (io.ReadCloser, error) {
	if s.stdout == nil {
		return nil, fmt.Errorf("stdout not available (check if started)")
	}
	return s.stdout, nil
}

// GetStderr returns the stderr pipe of the container process.
func (s *Sandbox) GetStderr() (io.ReadCloser, error) {
	if s.stderr == nil {
		return nil, fmt.Errorf("stderr not available (check if started)")
	}
	return s.stderr, nil
}

// Exec runs a command inside the existing sandbox namespaces.
func (s *Sandbox) Exec(command string) (string, error) {
	if s.cmd == nil || s.cmd.Process == nil {
		return "", fmt.Errorf("sandbox not running")
	}
	pid := s.cmd.Process.Pid
	nsCmd := exec.Command("nsenter", "-t", fmt.Sprintf("%d", pid), "-m", "-u", "-i", "-n", "-p", "sh", "-c", command)
	out, err := nsCmd.CombinedOutput()
	return string(out), err
}
