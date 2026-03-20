package isolation

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

// DefaultCgroupMount is the standard v2 mount point in modern Linux distributions.
const DefaultCgroupMount = "/sys/fs/cgroup"
const PicoBoxCgroupPrefix = "picobox"

// CgroupsManager handles interacting with the Linux cgroups v2 filesystem.
type CgroupsManager struct {
	basePath string
}

// NewCgroupsManager returns a configured CgroupsManager.
// If basePath is empty, it uses the standard /sys/fs/cgroup.
func NewCgroupsManager(baseMount string) *CgroupsManager {
	if baseMount == "" {
		baseMount = DefaultCgroupMount
	}
	return &CgroupsManager{
		basePath: baseMount,
	}
}

// CreateCgroup provisions a new cgroup directory for a specific container ID under the picobox hierarchy.
func (c *CgroupsManager) CreateCgroup(containerID string) error {
	cgPath := filepath.Join(c.basePath, PicoBoxCgroupPrefix, containerID)

	// Creates the directory structure (e.g. /sys/fs/cgroup/picobox/{container_id})
	if err := os.MkdirAll(cgPath, 0755); err != nil {
		return fmt.Errorf("failed to create cgroup hierarchy at %s: %w", cgPath, err)
	}

	return nil
}

// AddProcess assigns a process (by its PID) to the specified container's cgroup.
// The OS kernel immediately applies all resource constraints configured in that cgroup to the process.
func (c *CgroupsManager) AddProcess(containerID string, pid int) error {
	procFilePath := filepath.Join(c.basePath, PicoBoxCgroupPrefix, containerID, "cgroup.procs")

	pidStr := strconv.Itoa(pid)

	if err := os.WriteFile(procFilePath, []byte(pidStr), 0644); err != nil {
		return fmt.Errorf("failed to write pid %s to %s: %w", pidStr, procFilePath, err)
	}

	return nil
}

// SetMemoryLimit configures the maximum memory (bytes) limit (memory.max) for a cgroup.
// When processes within this cgroup exceed the limit, the OOM killer is triggered by the kernel.
func (c *CgroupsManager) SetMemoryLimit(containerID string, maxBytes uint64) error {
	memMaxPath := filepath.Join(c.basePath, PicoBoxCgroupPrefix, containerID, "memory.max")

	limitStr := strconv.FormatUint(maxBytes, 10)

	if err := os.WriteFile(memMaxPath, []byte(limitStr), 0644); err != nil {
		return fmt.Errorf("failed to write memory limit to %s: %w", memMaxPath, err)
	}

	return nil
}
