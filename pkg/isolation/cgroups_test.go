package isolation_test

import (
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/henny-cho/picobox/pkg/isolation"
)

// TestCgroupMemoryLimit creates a mock cgroup directory structure
// and validates that memory limit writing functions correctly.
func TestCgroupMemoryLimit(t *testing.T) {
	// 1. Setup mock cgroup v2 mount point
	mockCgroupBase := filepath.Join(t.TempDir(), "sys", "fs", "cgroup")
	err := os.MkdirAll(mockCgroupBase, 0755)
	if err != nil {
		t.Fatalf("Failed to create mock cgroup base dir: %v", err)
	}

	// Make our CgroupsManager use the mock path
	cgManager := isolation.NewCgroupsManager(mockCgroupBase)
	testContainerID := "picobox-test-cg-01"

	// 2. Validate creation
	err = cgManager.CreateCgroup(testContainerID)
	if err != nil {
		t.Fatalf("CreateCgroup failed: %v", err)
	}

	containerCgPath := filepath.Join(mockCgroupBase, "picobox", testContainerID)
	if _, err := os.Stat(containerCgPath); os.IsNotExist(err) {
		t.Errorf("Cgroup directory was not created at %s", containerCgPath)
	}

	// 3. Create mock 'memory.max' to simulate real cgroupfs behavior
	memMaxPath := filepath.Join(containerCgPath, "memory.max")
	if err := os.WriteFile(memMaxPath, []byte("max\n"), 0644); err != nil {
		t.Fatalf("Failed to create mock memory.max: %v", err)
	}

	var testLimit uint64 = 1024 * 1024 * 256 // 256MB limit

	// 4. Validate setting limits
	err = cgManager.SetMemoryLimit(testContainerID, testLimit)
	if err != nil {
		t.Fatalf("SetMemoryLimit failed: %v", err)
	}

	// Read back to verify
	readMax, err := os.ReadFile(memMaxPath)
	if err != nil {
		t.Fatalf("Failed to read back memory.max file: %v", err)
	}

	// We expect the limit mapped to string, checking against ReadFile which includes potentially a newline
	writtenLimitStr := string(readMax)
	expectedLimitStr := strconv.FormatUint(testLimit, 10)

	if writtenLimitStr != expectedLimitStr && writtenLimitStr != expectedLimitStr+"\n" {
		t.Errorf("Expected memory limit %s, but read %s", expectedLimitStr, writtenLimitStr)
	}
}

// TestCgroupProcAdd validates that a PID can be written to cgroup.procs
func TestCgroupProcAdd(t *testing.T) {
	mockCgroupBase := filepath.Join(t.TempDir(), "sys", "fs", "cgroup")
	cgManager := isolation.NewCgroupsManager(mockCgroupBase)
	testContainerID := "picobox-test-proc-01"

	// Create mock hierarchy
	if err := cgManager.CreateCgroup(testContainerID); err != nil {
		t.Fatalf("CreateCgroup failed: %v", err)
	}
	containerCgPath := filepath.Join(mockCgroupBase, "picobox", testContainerID)

	// Pre-create cgroup.procs for the test to write to
	procPath := filepath.Join(containerCgPath, "cgroup.procs")
	if err := os.WriteFile(procPath, []byte(""), 0644); err != nil {
		t.Fatalf("Failed to create mock cgroup.procs file: %v", err)
	}

	// Since we are mocking, we can just use our own PID to add.
	myPID := os.Getpid()

	err := cgManager.AddProcess(testContainerID, myPID)
	if err != nil {
		t.Fatalf("AddProcess failed: %v", err)
	}

	readProc, err := os.ReadFile(procPath)
	if err != nil {
		t.Fatalf("Failed to read back cgroup.procs file: %v", err)
	}

	writtenPIDStr := string(readProc)
	expectedPIDStr := strconv.Itoa(myPID)

	if writtenPIDStr != expectedPIDStr && writtenPIDStr != expectedPIDStr+"\n" {
		t.Errorf("Expected PID %s in procs, but read %s", expectedPIDStr, writtenPIDStr)
	}
}
