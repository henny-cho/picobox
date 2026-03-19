'use client'

import React, { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Activity, Bell, Search, Filter, Plus } from 'lucide-react'
import NodeCard, { NodeMetrics } from '@/components/NodeCard'

export default function Dashboard() {
  const [nodes, setNodes] = useState<Record<string, NodeMetrics>>({})
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchNodes = async () => {
      try {
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
             cpu_usage_percent: 42.5,
             memory_used_bytes: 1024 * 1024 * 1200,
             memory_total_bytes: 1024 * 1024 * 4096,
             disk_io_wait: 0.1
          },
          'pico-worker-2': {
             hostname: 'pico-worker-2',
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
    <div className="max-w-7xl mx-auto space-y-10">
      {/* Upper Dashboard Actions */}
      <section className="flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div>
          <h1 className="text-4xl font-black text-white tracking-tight">System Overview</h1>
          <p className="text-slate-400 mt-1">Real-time cluster status and resource distribution.</p>
        </div>
        
        <div className="flex items-center gap-3">
          <div className="relative group">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 group-focus-within:text-cyan-400 transition-colors" />
            <input 
              type="text" 
              placeholder="Search nodes..." 
              className="pl-10 pr-4 py-2 bg-slate-900/50 border border-slate-800 rounded-xl focus:outline-none focus:ring-2 focus:ring-cyan-500/50 transition-all text-sm w-64"
            />
          </div>
          <button className="p-2 bg-slate-900/50 border border-slate-800 rounded-xl text-slate-400 hover:text-white transition-all hover:bg-slate-800">
            <Filter className="w-5 h-5" />
          </button>
          <button className="px-4 py-2 bg-gradient-to-r from-cyan-500 to-blue-600 text-white rounded-xl font-bold flex items-center gap-2 glow-cyan hover:brightness-110 transition-all">
            <Plus className="w-4 h-4" />
            Deploy
          </button>
        </div>
      </section>

      {/* Stats Quick View */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {[
          { icon: Activity, label: 'Cluster Load', value: '42%', color: 'text-cyan-400' },
          { icon: Bell, label: 'Active Alerts', value: '2', color: 'text-amber-400' },
          { icon: Plus, label: 'Nodes Up', value: '3/3', color: 'text-green-400' },
        ].map((stat, i) => (
          <div key={i} className="glass p-5 rounded-3xl flex items-center gap-4">
             <div className="w-12 h-12 bg-slate-800/50 rounded-2xl flex items-center justify-center">
                <stat.icon className={`w-6 h-6 ${stat.color}`} />
             </div>
             <div>
                <p className="text-xs font-semibold text-slate-500 uppercase tracking-widest">{stat.label}</p>
                <p className="text-2xl font-black text-white">{stat.value}</p>
             </div>
          </div>
        ))}
      </div>

      {/* Node Grid */}
      <section className="space-y-6">
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            Live Cluster Nodes
            <span className="px-2 py-0.5 bg-cyan-500/10 text-cyan-400 text-[10px] rounded-full border border-cyan-500/20">Real-time</span>
          </h2>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center h-64 glass rounded-3xl gap-4">
             <div className="w-12 h-12 border-4 border-cyan-500/20 border-t-cyan-500 rounded-full animate-spin"></div>
             <p className="text-slate-400 font-medium animate-pulse">Syncing cluster state...</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <AnimatePresence>
              {Object.values(nodes).map(node => (
                <NodeCard key={node.hostname} node={node} />
              ))}
            </AnimatePresence>
            
            {Object.keys(nodes).length === 0 && (
              <div className="col-span-full py-24 text-center glass rounded-3xl border-2 border-dashed border-slate-800">
                <p className="text-slate-500 font-medium">No active nodes connected to the control plane.</p>
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  )
}
