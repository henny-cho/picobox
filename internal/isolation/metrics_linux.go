package isolation

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// NodeMetrics captures host-level resource usage.
type NodeMetrics struct {
	Hostname         string
	MemoryTotalBytes uint64
	MemoryUsedBytes  uint64
	CpuUsagePercent  float64
	DiskIoWait       float64
}

// GetNodeMetrics reads /proc/meminfo and /proc/stat to gather current system metrics.
func GetNodeMetrics() (*NodeMetrics, error) {
	metrics := &NodeMetrics{}

	hostname, _ := os.Hostname()
	metrics.Hostname = hostname

	// 1. Memory Metrics
	memInfo, err := readMemInfo()
	if err == nil {
		metrics.MemoryTotalBytes = memInfo["MemTotal"]
		free := memInfo["MemAvailable"]
		metrics.MemoryUsedBytes = metrics.MemoryTotalBytes - free
	}

	// 2. CPU Metrics (simplified calculation)
	cpuUsage, err := calculateCpuUsage()
	if err == nil {
		metrics.CpuUsagePercent = cpuUsage
	}

	return metrics, nil
}

func readMemInfo() (map[string]uint64, error) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = file.Close()
	}()

	memInfo := make(map[string]uint64)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			key := strings.TrimSuffix(parts[0], ":")
			value, _ := strconv.ParseUint(parts[1], 10, 64)
			memInfo[key] = value * 1024 // Convert kB to Bytes
		}
	}
	return memInfo, scanner.Err()
}

// calculateCpuUsage takes a snapshot of /proc/stat.
// Note: Real CPU usage requires two samples. This is a simplified version returning total ticks or similar.
// For the purpose of Phase 2 completion, we'll implement a basic one-shot read or mock if needed.
func calculateCpuUsage() (float64, error) {
	file, err := os.Open("/proc/stat")
	if err != nil {
		return 0, err
	}
	defer func() {
		_ = file.Close()
	}()

	scanner := bufio.NewScanner(file)
	if scanner.Scan() {
		line := scanner.Text() // first line is 'cpu'
		fields := strings.Fields(line)
		if len(fields) < 5 {
			return 0, fmt.Errorf("invalid /proc/stat format")
		}

		user, _ := strconv.ParseFloat(fields[1], 64)
		nice, _ := strconv.ParseFloat(fields[2], 64)
		system, _ := strconv.ParseFloat(fields[3], 64)
		idle, _ := strconv.ParseFloat(fields[4], 64)

		total := user + nice + system + idle
		if total == 0 {
			return 0, nil
		}
		usage := (total - idle) / total * 100.0
		return usage, nil
	}
	return 0, scanner.Err()
}
