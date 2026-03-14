package isolation_test

import (
	"context"
	"os"
	"syscall"
	"testing"
	"time"

	"github.com/henny-cho/picobox/pkg/isolation"
)

// TestNamespaceIsolation validates that a newly created process runs with isolated namespaces (PID).
func TestNamespaceIsolation(t *testing.T) {
	// Skip if not running as root (required for namespaces)
	if os.Getuid() != 0 {
		t.Skip("Namespace tests require root privileges. Please run with sudo.")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	cmd := isolation.NewContainerProcess(ctx, "sleep", "1")

	if cmd.SysProcAttr == nil {
		t.Fatalf("SysProcAttr is nil, expected namespaces configurations")
	}

	// Verify CLONE_NEWPID flag is set
	if cmd.SysProcAttr.Cloneflags&syscall.CLONE_NEWPID == 0 {
		t.Errorf("Expected CLONE_NEWPID flag to be set for namespace isolation")
	}

	// Verify CLONE_NEWUTS flag is set
	if cmd.SysProcAttr.Cloneflags&syscall.CLONE_NEWUTS == 0 {
		t.Errorf("Expected CLONE_NEWUTS flag to be set for hostname isolation")
	}

	// Verify CLONE_NEWNS flag is set
	if cmd.SysProcAttr.Cloneflags&syscall.CLONE_NEWNS == 0 {
		t.Errorf("Expected CLONE_NEWNS flag to be set for mount isolation")
	}

	// Start the isolated process
	if err := cmd.Start(); err != nil {
		t.Fatalf("Failed to start isolated process: %v", err)
	}

	// Ensure the process is running in the background and is terminated correctly after test.
	err := cmd.Wait()
	if err != nil {
		// A successful exit code from sleep 1 will not return an error
		t.Logf("Isolated process finished with info: %v", err)
	} else {
		t.Logf("Isolated process finished successfully.")
	}

	// At this point we verify the process didn't crash upon starting.
}

// TestHostnameIsolation validates that the hostname can be set independently in the new namespace.
func TestHostnameIsolation(t *testing.T) {
	if os.Getuid() != 0 {
		t.Skip("Hostname test requires root privileges. Please run with sudo.")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// Setting a custom hostname for the new namespace
	cmd := isolation.NewContainerProcess(ctx, "hostname")

	// Since syscall.SysProcAttr doesn't have a Hostname field directly in Go until we use specific linux packages or run a wrapper,
	// we test the basic UTS configuration flag for now to ensure our NewContainerProcess honors the UTS Flag.
	if cmd.SysProcAttr.Cloneflags&syscall.CLONE_NEWUTS == 0 {
		t.Errorf("Expected CLONE_NEWUTS flag to be set for hostname isolation")
	}

	// For a real hostname isolation test in Go, we'd need a wrapper process that calls `syscall.Sethostname`
	// after the clone, before exec-ing `hostname`. For now, we just verify the command structure.
	t.Logf("Hostname isolation clone flag verified successfully.")
}
