'use client'

import React, { useEffect, useState } from 'react'
import NodeCard, { NodeMetrics } from '@/components/NodeCard'

export default function Dashboard() {
  const [nodes, setNodes] = useState<Record<string, NodeMetrics>>({})
  const [loading, setLoading] = useState(true)

  // Real implementation will fetch from Next.js server actions or proxy to Go backend
  // For UI tests and Phase 6 mockup, we use a mock state or simple fetch.
  useEffect(() => {
    const fetchNodes = async () => {
      try {
        // Polling loop targeting the Go Backend REST Endpoint
        const res = await fetch('http://localhost:3000/api/nodes')
        if (res.ok) {
          const data = await res.json()
          setNodes(data)
        }
      } catch (err) {
        console.warn("Backend not reachable. Displaying mock data for UI testing.", err)
        setNodes({
          'pico-master': {
            hostname: 'pico-master',
            cpu_usage_percent: 15.2,
            memory_used_bytes: 1024 * 1024 * 500,
            memory_total_bytes: 1024 * 1024 * 2048,
            disk_io_wait: 0.05
          },
          'pico-worker-1': {
             hostname: 'pico-worker-1',
             cpu_usage_percent: 88.5,
             memory_used_bytes: 1024 * 1024 * 3800,
             memory_total_bytes: 1024 * 1024 * 4096,
             disk_io_wait: 0.2
          }
        })
      } finally {
        setLoading(false)
      }
    }

    fetchNodes()
    const interval = setInterval(fetchNodes, 3000)
    return () => clearInterval(interval)
  }, [])

  return (
    <main className="min-h-screen bg-gray-900 p-8">
      <header className="mb-10 flex justify-between items-center border-b border-gray-800 pb-4">
        <div>
          <h1 className="text-4xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-blue-600 tracking-tight">
             PicoBox
          </h1>
          <p className="text-gray-400 text-sm mt-1 uppercase tracking-widest font-semibold">Cluster Control Plane</p>
        </div>
        <div className="flex items-center gap-3 bg-gray-800 px-4 py-2 rounded-full border border-gray-700">
           <span className="relative flex h-3 w-3">
             <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
             <span className="relative inline-flex rounded-full h-3 w-3 bg-cyan-500"></span>
           </span>
           <span className="text-sm text-cyan-400 font-medium">System Online</span>
        </div>
      </header>

      {loading ? (
        <div className="flex justify-center items-center h-64">
           <div className="w-12 h-12 border-4 border-cyan-500 border-t-transparent rounded-full animate-spin"></div>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6" data-testid="node-grid">
          {Object.values(nodes).map(node => (
            <NodeCard key={node.hostname} node={node} />
          ))}
          {Object.keys(nodes).length === 0 && (
            <div className="col-span-full text-center py-20 text-gray-500 border-2 border-dashed border-gray-800 rounded-xl">
               No active nodes connected to the control plane.
            </div>
          )}
        </div>
      )}
    </main>
  )
}
