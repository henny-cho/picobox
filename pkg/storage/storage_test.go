package storage_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/henny-cho/picobox/pkg/storage"
)

// TestOverlayFSMount validates the creation of the underlying directory structures
// required for an OverlayFS mount without actually invoking the privileged mount syscall.
func TestOverlayFSMount(t *testing.T) {
	mockBase := t.TempDir()

	layerID := "picobox-overlay-test-01"
	overlayBase := filepath.Join(mockBase, "picobox", "overlay", layerID)

	manager := storage.NewStorageManager(filepath.Join(mockBase, "picobox"))

	// Create OverlayFS structure
	lowerDir, upperDir, workDir, mergedDir, err := manager.PrepareOverlayDirs(layerID)
	if err != nil {
		t.Fatalf("PrepareOverlayDirs failed: %v", err)
	}

	// Verify the paths are returned logically
	if lowerDir != filepath.Join(overlayBase, "lower") {
		t.Errorf("Unexpected lowerDir: %s", lowerDir)
	}
	if mergedDir != filepath.Join(overlayBase, "merged") {
		t.Errorf("Unexpected mergedDir: %s", mergedDir)
	}

	// Verify directories were physically created
	dirs := []string{lowerDir, upperDir, workDir, mergedDir}
	for _, dir := range dirs {
		info, err := os.Stat(dir)
		if os.IsNotExist(err) {
			t.Errorf("Expected directory %s to be created, but it does not exist", dir)
		}
		if err == nil && !info.IsDir() {
			t.Errorf("Expected %s to be a directory", dir)
		}
	}
}
