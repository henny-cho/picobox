'use client'

import React, { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Activity, Database, Cpu, HardDrive, TrendingUp, BarChart3, PieChart, Info } from 'lucide-react'
import { NodeMetrics } from '@/components/NodeCard'

export default function MetricsPage() {
  const [nodes, setNodes] = useState<Record<string, NodeMetrics>>({})

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
    }
  }

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 3000)
    return () => clearInterval(interval)
  }, [])

  const totalCpu = Object.values(nodes).reduce((acc, n) => acc + n.cpu_usage_percent, 0) / (Object.keys(nodes).length || 1)
  const totalMemUsed = Object.values(nodes).reduce((acc, n) => acc + n.memory_used_bytes, 0)
  const totalMemMax = Object.values(nodes).reduce((acc, n) => acc + n.memory_total_bytes, 0)

  return (
    <div className="space-y-10">
      <div>
        <h1 className="text-4xl font-black text-white tracking-tighter">Cluster Metrics</h1>
        <p className="text-slate-500 mt-2 font-medium">Real-time resource utilization and performance analytics across all agents.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        {/* CPU Chart Placeholder */}
        <div className="glass p-8 rounded-[2.5rem] space-y-6">
          <div className="flex justify-between items-center">
             <div className="w-12 h-12 bg-cyan-500/10 rounded-2xl flex items-center justify-center text-cyan-400">
                <Cpu className="w-6 h-6" />
             </div>
             <TrendingUp className="w-5 h-5 text-green-400" />
          </div>
          <div>
            <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest">Avg CPU Load</p>
            <p className="text-4xl font-black text-white">{totalCpu.toFixed(1)}%</p>
          </div>
          <div className="h-24 flex items-end gap-1 px-1">
             {[...Array(20)].map((_, i) => (
                <motion.div
                  key={i}
                  initial={{ height: 0 }}
                  animate={{ height: `${Math.random() * 80 + 20}%` }}
                  className="flex-1 bg-cyan-500/20 rounded-t-sm"
                />
             ))}
          </div>
        </div>

        {/* Memory Chart Placeholder */}
        <div className="glass p-8 rounded-[2.5rem] space-y-6">
          <div className="flex justify-between items-center">
             <div className="w-12 h-12 bg-blue-500/10 rounded-2xl flex items-center justify-center text-blue-400">
                <Database className="w-6 h-6" />
             </div>
             <PieChart className="w-5 h-5 text-blue-400" />
          </div>
          <div>
            <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest">Memory Used</p>
            <p className="text-4xl font-black text-white">{(totalMemUsed / (1024 * 1024 * 1024)).toFixed(1)} GB</p>
            <p className="text-xs text-slate-500 mt-1">of {(totalMemMax / (1024 * 1024 * 1024)).toFixed(1)} GB available</p>
          </div>
          <div className="w-full h-4 bg-slate-800 rounded-full overflow-hidden">
             <motion.div
               className="h-full bg-blue-500 shadow-[0_0_20px_rgba(59,130,246,0.5)]"
               initial={{ width: 0 }}
               animate={{ width: `${(totalMemUsed / (totalMemMax || 1)) * 100}%` }}
             />
          </div>
        </div>

        {/* Disk IO Placeholder */}
        <div className="glass p-8 rounded-[2.5rem] space-y-6">
          <div className="flex justify-between items-center">
             <div className="w-12 h-12 bg-purple-500/10 rounded-2xl flex items-center justify-center text-purple-400">
                <HardDrive className="w-6 h-6" />
             </div>
             <BarChart3 className="w-5 h-5 text-purple-400" />
          </div>
          <div>
            <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest">Avg Disk I/O Wait</p>
            <p className="text-4xl font-black text-white">0.05ms</p>
          </div>
          <div className="flex gap-4">
             <div className="flex-1 p-4 bg-slate-950/50 rounded-2xl border border-slate-800">
                <p className="text-[8px] font-black text-slate-500 uppercase mb-1">Read</p>
                <p className="text-lg font-black text-white">12.4 MB/s</p>
             </div>
             <div className="flex-1 p-4 bg-slate-950/50 rounded-2xl border border-slate-800">
                <p className="text-[8px] font-black text-slate-500 uppercase mb-1">Write</p>
                <p className="text-lg font-black text-white">4.1 MB/s</p>
             </div>
          </div>
        </div>
      </div>

      <div className="glass p-10 rounded-[3rem] border border-cyan-500/10 bg-gradient-to-br from-slate-900 to-slate-950">
         <div className="flex items-start gap-6">
            <div className="w-14 h-14 bg-cyan-500/20 rounded-2xl flex items-center justify-center text-cyan-400 shrink-0">
               <Info className="w-8 h-8" />
            </div>
            <div>
               <h3 className="text-2xl font-black text-white">Metric Insights</h3>
               <p className="text-slate-400 mt-2 leading-relaxed">
                 Cluster health is currently stable. Overall resource contention is minimal across all {Object.keys(nodes).length} detected nodes.
                 Consider scaling up if average CPU load exceeds 80% for more than 5 minutes.
               </p>
            </div>
         </div>
      </div>
    </div>
  )
}
