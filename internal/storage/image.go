package storage

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ExtractTarball takes a source .tar.gz file and extracts it into the target directory.
func ExtractTarball(src, target string) error {
	f, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("failed to open tarball: %w", err)
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to read tar header: %w", err)
		}

		// Security: Prevent ZipSlip by cleaning the path
		targetPath := filepath.Join(target, header.Name)
		if !strings.HasPrefix(targetPath, filepath.Clean(target)+string(os.PathSeparator)) && targetPath != filepath.Clean(target) {
			return fmt.Errorf("tarball contains invalid path: %s", header.Name)
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				return fmt.Errorf("failed to create directory %s: %w", targetPath, err)
			}
		case tar.TypeReg:
			// Ensure parent directory exists
			if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
				return err
			}
			f, err := os.OpenFile(targetPath, os.O_CREATE|os.O_RDWR, os.FileMode(header.Mode))
			if err != nil {
				return fmt.Errorf("failed to create file %s: %w", targetPath, err)
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return fmt.Errorf("failed to copy file content to %s: %w", targetPath, err)
			}
			f.Close()
		case tar.TypeLink, tar.TypeSymlink:
			// Handle symlinks if necessary, for now we skip or log
			fmt.Printf("[Image] Skipping symlink: %s\n", header.Name)
		}
	}

	return nil
}
