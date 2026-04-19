// Minimal HEALTHCHECK binary embedded in the distroless master image.
// Exits 0 if the master's /healthz endpoint responds 200 within the timeout,
// non-zero otherwise.
package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	url := os.Getenv("PICOBOX_HEALTHCHECK_URL")
	if url == "" {
		url = "http://127.0.0.1:3000/healthz"
	}

	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck: %v\n", err)
		os.Exit(1)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "healthcheck: status %d\n", resp.StatusCode)
		os.Exit(1)
	}
}
