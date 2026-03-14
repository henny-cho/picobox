package storage

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// DefaultPicoBoxLib is the main directory where images, overlays, and cgroups references are stored.
const DefaultPicoBoxLib = "/var/lib/picobox"

// StorageManager orchestrates local filesystem setup.
type StorageManager struct {
	baseDir string
}

func NewStorageManager(baseDir string) *StorageManager {
	if baseDir == "" {
		baseDir = DefaultPicoBoxLib
	}
	return &StorageManager{
		baseDir: baseDir,
	}
}

// PrepareOverlayDirs sets up the 4 main directories required to mount an OverlayFS.
// Returns (lowerDir, upperDir, workDir, mergedDir, error).
func (s *StorageManager) PrepareOverlayDirs(layerID string) (string, string, string, string, error) {
	overlayBase := filepath.Join(s.baseDir, "overlay", layerID)

	lowerDir := filepath.Join(overlayBase, "lower")
	upperDir := filepath.Join(overlayBase, "upper")
	workDir := filepath.Join(overlayBase, "work")
	mergedDir := filepath.Join(overlayBase, "merged")

	dirs := []string{lowerDir, upperDir, workDir, mergedDir}

	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return "", "", "", "", fmt.Errorf("failed to create overlay struct dev at %s: %w", dir, err)
		}
	}

	return lowerDir, upperDir, workDir, mergedDir, nil
}

// MountOverlayFS calls the Linux Mount syscall to layer the upperDir on top of the read-only lowerDir
// using OverlayFS, and projects the union into mergedDir.
func (s *StorageManager) MountOverlayFS(lowerDir, upperDir, workDir, mergedDir string) error {
	opts := fmt.Sprintf("lowerdir=%s,upperdir=%s,workdir=%s", lowerDir, upperDir, workDir)
	
	err := syscall.Mount("overlay", mergedDir, "overlay", 0, opts)
	if err != nil {
		return fmt.Errorf("failed to syscall mount OverlayFS: %w", err)
	}

	return nil
}

// PivotRoot isolates the filesystem view of the container process to `newRoot`.
// Note: This must be called from within the isolated namespace of the child process.
func PivotRoot(newRoot string) error {
	putold := filepath.Join(newRoot, ".pivot_root")
	
	// Ensure the putold directory exists
	if err := os.MkdirAll(putold, 0700); err != nil {
		return fmt.Errorf("failed to setup putold directory: %w", err)
	}
	
	// Bind mount the newRoot over itself to meet pivot_root syscall constraints
	if err := syscall.Mount(newRoot, newRoot, "bind", syscall.MS_BIND|syscall.MS_REC, ""); err != nil {
		return fmt.Errorf("failed to bind mount newRoot against itself: %w", err)
	}

	if err := syscall.PivotRoot(newRoot, putold); err != nil {
		return fmt.Errorf("syscall PivotRoot failed: %w", err)
	}

	// Change current working directory to the new root
	if err := os.Chdir("/"); err != nil {
		return fmt.Errorf("failed to chdir to / after pivot_root: %w", err)
	}

	// Unmount the old root, which is now at /.pivot_root
	putoldPivot := "/.pivot_root"
	if err := syscall.Unmount(putoldPivot, syscall.MNT_DETACH); err != nil {
		return fmt.Errorf("failed to unmount old root: %w", err)
	}

	// Clean up the temporary folder
	if err := os.Remove(putoldPivot); err != nil {
		return fmt.Errorf("failed to remove %s: %w", putoldPivot, err)
	}

	return nil
}
