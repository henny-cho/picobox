package isolation

import (
	"context"
	"os"
	"os/exec"
	"syscall"
)

// NewContainerProcess generates a background command configured to run in isolated Linux namespaces.
// It leverages standard library `syscall` to configure process attributes.
func NewContainerProcess(ctx context.Context, command string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, command, args...)

	// Basic I/O streams can be inherited or redirected later
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	// Configure namespace isolation flags via SysProcAttr
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags: syscall.CLONE_NEWPID | syscall.CLONE_NEWUTS | syscall.CLONE_NEWNS | syscall.CLONE_NEWIPC | syscall.CLONE_NEWNET,
		// Unshare flags can also be set here if necessary
	}

	return cmd
}
