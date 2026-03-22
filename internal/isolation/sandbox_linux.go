package isolation

import (
	"context"
	"fmt"
	"os/exec"

	"github.com/henny-cho/picobox/internal/storage"
)

// SandboxConfig holds the specification for a container run.
type SandboxConfig struct {
	ID         string
	Command    string
	Args       []string
	MemoryLimit uint64
	CpuQuota    int
	ImageID    string
}

// Sandbox represents a managed container lifecycle.
type Sandbox struct {
	Config   SandboxConfig
	storage  *storage.StorageManager
	cgroups  *CgroupsManager
	cmd      *exec.Cmd
}

// NewSandbox initializes a container facade.
func NewSandbox(cfg SandboxConfig) *Sandbox {
	return &Sandbox{
		Config:  cfg,
		storage: storage.NewStorageManager(""),
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

	// Note: In Phase 2, we assume images are already unpacked in 'lower'.
	// Phase 4 will formalize Image Management.
	if err := s.storage.MountOverlayFS(lower, upper, work, merged); err != nil {
		return fmt.Errorf("mount overlay failed: %w", err)
	}

	// 2. Prepare Namespaces
	s.cmd = NewContainerProcess(ctx, s.Config.Command, s.Config.Args...)
	s.cmd.Dir = "/" // After pivot_root, it should be /

	// Setup Pipe for the child to wait until Cgroups are ready (standard OCI-like sync)
	// For simplification in Phase 2, we start the command and then apply cgroups.

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
	if s.Config.MemoryLimit > 0 {
		if err := s.cgroups.SetMemoryLimit(s.Config.ID, s.Config.MemoryLimit); err != nil {
			return err
		}
	}
	if s.Config.CpuQuota > 0 {
		if err := s.cgroups.SetCpuLimit(s.Config.ID, s.Config.CpuQuota); err != nil {
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

// Note: PivotRoot call must be injected into the child process.
// In a follow-up, we will implement a 're-exec' pattern where the child calls PivotRoot.
// For now, this facade manages the host-side orchestration.
