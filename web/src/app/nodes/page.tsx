'use client'

import React, { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Activity, Database, Server, Cpu, HardDrive, Shield, MoreVertical, RefreshCw } from 'lucide-react'
import { NodeMetrics } from '@/components/NodeCard'

export default function NodesPage() {
  const [nodes, setNodes] = useState<Record<string, NodeMetrics>>({})
  const [loading, setLoading] = useState(true)

  const getApiUrl = (path: string) => {
    const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost'
    return `http://${host}:3000${path}`
  }

  const fetchData = async () => {
    try {
      const res = await fetch(getApiUrl('/api/nodes'))
      if (res.ok) setNodes(await res.json())
    } catch (err) {
      console.warn("Backend not reachable", err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 3000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="space-y-10">
      <div className="flex justify-between items-end">
        <div>
          <h1 className="text-4xl font-black text-white tracking-tighter">Node Fleet</h1>
          <p className="text-slate-500 mt-2 font-medium">Detailed configuration and real-time health of your infrastructure.</p>
        </div>
        <button
          onClick={() => { setLoading(true); fetchData(); }}
          className="flex items-center gap-2 px-5 py-2.5 bg-slate-900 border border-slate-800 rounded-xl text-slate-300 font-bold hover:text-white hover:bg-slate-800 transition-all active:scale-95"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          Refresh Fleet
        </button>
      </div>

      <div className="glass rounded-[2.5rem] overflow-hidden border border-slate-800/50">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-slate-950/50 border-b border-slate-800">
              <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Node Name</th>
              <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Status</th>
              <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">CPU Usage</th>
              <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest">Memory Utilization</th>
              <th className="px-8 py-5 text-[10px] font-black text-slate-500 uppercase tracking-widest text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/50">
            {Object.values(nodes).map(node => (
              <motion.tr
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                key={node.hostname}
                className="hover:bg-cyan-500/5 transition-colors group"
              >
                <td className="px-8 py-6">
                  <div className="flex items-center gap-4">
                    <div className="w-10 h-10 bg-slate-800 rounded-xl flex items-center justify-center text-cyan-400 group-hover:scale-110 transition-transform">
                      <Server className="w-5 h-5" />
                    </div>
                    <div>
                      <p className="font-bold text-white text-lg tracking-tight">{node.hostname}</p>
                      <p className="text-[10px] text-slate-500 font-black uppercase tracking-widest">Edge Agent v1.0</p>
                    </div>
                  </div>
                </td>
                <td className="px-8 py-6">
                  <span className="inline-flex items-center gap-2 px-3 py-1 bg-green-500/10 text-green-400 text-[10px] font-black uppercase tracking-widest rounded-full border border-green-500/20">
                    <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
                    Operational
                  </span>
                </td>
                <td className="px-8 py-6 font-mono text-cyan-400 font-bold">
                  {node.cpu_usage_percent.toFixed(1)}%
                  <div className="w-24 h-1 bg-slate-800 rounded-full mt-2 overflow-hidden">
                    <motion.div
                      className="h-full bg-cyan-500"
                      initial={{ width: 0 }}
                      animate={{ width: `${node.cpu_usage_percent}%` }}
                    />
                  </div>
                </td>
                <td className="px-8 py-6 font-mono text-blue-400 font-bold">
                  {(node.memory_used_bytes / (1024 * 1024)).toFixed(0)} MB
                  <p className="text-[10px] text-slate-500 font-bold mt-1">Total: { (node.memory_total_bytes / (1024 * 1024)).toFixed(0) } MB</p>
                </td>
                <td className="px-8 py-6 text-right">
                  <button className="p-2 text-slate-600 hover:text-white transition-colors">
                    <MoreVertical className="w-5 h-5" />
                  </button>
                </td>
              </motion.tr>
            ))}
            {Object.keys(nodes).length === 0 && !loading && (
              <tr>
                <td colSpan={5} className="px-8 py-20 text-center text-slate-500 font-bold italic">
                  No edge nodes detected. Start 'picoboxd' on your target machines.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
