package main

import (
	"database/sql"
	"encoding/json"
	"fmt"

	pb "github.com/henny-cho/picobox/internal/api/pb"
	_ "modernc.org/sqlite"
)

type Store struct {
	db *sql.DB
}

func NewStore(dbPath string) (*Store, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open sqlite: %w", err)
	}

	s := &Store{db: db}
	if err := s.initSchema(); err != nil {
		return nil, err
	}

	return s, nil
}

func (s *Store) initSchema() error {
	queries := []string{
		`CREATE TABLE IF NOT EXISTS nodes (
			hostname TEXT PRIMARY KEY,
			cpu_usage REAL,
			mem_used INTEGER,
			mem_total INTEGER,
			io_wait REAL,
			last_seen DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS containers (
			container_id TEXT PRIMARY KEY,
			hostname TEXT,
			status TEXT,
			spec_json TEXT,
			error_message TEXT,
			last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
		)`,
	}

	for _, q := range queries {
		if _, err := s.db.Exec(q); err != nil {
			return fmt.Errorf("failed to init schema: %w", err)
		}
	}
	return nil
}

func (s *Store) SaveNode(metrics *pb.NodeMetrics) error {
	query := `INSERT OR REPLACE INTO nodes (hostname, cpu_usage, mem_used, mem_total, io_wait, last_seen)
	          VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
	_, err := s.db.Exec(query, metrics.Hostname, metrics.CpuUsagePercent, metrics.MemoryUsedBytes, metrics.MemoryTotalBytes, metrics.DiskIoWait)
	return err
}

func (s *Store) SaveContainer(id string, info *ContainerInfo) error {
	specRaw, _ := json.Marshal(info.Spec)
	errMsg := ""
	if info.DeployResponse != nil {
		errMsg = info.DeployResponse.ErrorMessage
	}

	query := `INSERT OR REPLACE INTO containers (container_id, hostname, status, spec_json, error_message, last_updated)
	          VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
	_, err := s.db.Exec(query, id, info.Hostname, info.Status, string(specRaw), errMsg)
	return err
}

func (s *Store) LoadNodes() (map[string]*pb.NodeMetrics, error) {
	rows, err := s.db.Query("SELECT hostname, cpu_usage, mem_used, mem_total, io_wait FROM nodes")
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()

	nodes := make(map[string]*pb.NodeMetrics)
	for rows.Next() {
		var m pb.NodeMetrics
		if err := rows.Scan(&m.Hostname, &m.CpuUsagePercent, &m.MemoryUsedBytes, &m.MemoryTotalBytes, &m.DiskIoWait); err != nil {
			return nil, err
		}
		nodes[m.Hostname] = &m
	}
	return nodes, nil
}

func (s *Store) LoadContainers() (map[string]*ContainerInfo, error) {
	rows, err := s.db.Query("SELECT container_id, hostname, status, spec_json, error_message FROM containers")
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()

	containers := make(map[string]*ContainerInfo)
	for rows.Next() {
		var id, hostname, status, specJSON, errMsg string
		if err := rows.Scan(&id, &hostname, &status, &specJSON, &errMsg); err != nil {
			return nil, err
		}

		var spec pb.ContainerSpec
		_ = json.Unmarshal([]byte(specJSON), &spec)

		containers[id] = &ContainerInfo{
			Hostname: hostname,
			Status:   status,
			Spec:     &spec,
			DeployResponse: &pb.DeployResponse{
				ContainerId:  id,
				Success:      status == "Running",
				ErrorMessage: errMsg,
			},
		}
	}
	return containers, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}
