'use client'
import React from 'react'
import { motion } from 'framer-motion'
import { Cpu, Database, Server, Terminal, Square, Play, Settings } from 'lucide-react'

export interface NodeMetrics {
  hostname: string
  cpu_usage_percent: number
  memory_used_bytes: number
  memory_total_bytes: number
  disk_io_wait: number
}

export interface ContainerInfo {
  deploy_response: {
    container_id: string
    success: boolean
    error_message: string
  }
  status: string
  hostname: string
}

interface NodeCardProps {
  node: NodeMetrics
  containers: ContainerInfo[]
  onStop?: (hostname: string, containerId: string) => void
  onStart?: (hostname: string, containerId: string) => void
  onEdit?: (container: ContainerInfo) => void
}

export default function NodeCard({ node, containers, onStop, onStart, onEdit }: NodeCardProps) {
  const memUsedGB = (node.memory_used_bytes / (1024 * 1024 * 1024)).toFixed(1)
  const memTotalGB = (node.memory_total_bytes / (1024 * 1024 * 1024)).toFixed(1)
  const memPercent = (node.memory_used_bytes / node.memory_total_bytes) * 100

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="glass p-8 rounded-[3rem] border border-white/5 hover:border-cyan-500/30 transition-all group relative overflow-hidden"
    >
      {/* Background Glow */}
      <div className="absolute -right-20 -top-20 w-64 h-64 bg-cyan-500/5 blur-[80px] group-hover:bg-cyan-500/10 transition-colors" />

      <div className="flex justify-between items-start mb-8 relative z-10">
        <div>
          <h3 className="text-2xl font-black text-white tracking-tighter flex items-center gap-2">
            <Server className="w-6 h-6 text-cyan-500" />
            {node.hostname}
          </h3>
          <div className="flex items-center gap-2 mt-1">
            <span className="flex h-2 w-2 rounded-full bg-green-500 animate-pulse" />
            <span className="text-[10px] font-bold text-slate-500 uppercase tracking-widest">Active Node</span>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-6 mb-8 relative z-10">
        <div className="space-y-3">
          <div className="flex justify-between items-end">
            <div className="flex items-center gap-2 text-slate-400">
              <Cpu className="w-4 h-4" />
              <span className="text-[10px] font-bold uppercase tracking-widest">CPU Load</span>
            </div>
            <span className="text-xl font-black text-white">{node.cpu_usage_percent.toFixed(1)}%</span>
          </div>
          <div className="h-1.5 w-full bg-slate-800/50 rounded-full overflow-hidden">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${node.cpu_usage_percent}%` }}
              className="h-full bg-gradient-to-r from-cyan-500 to-blue-500 shadow-[0_0_10px_rgba(6,182,212,0.5)]"
            />
          </div>
        </div>

        <div className="space-y-3">
          <div className="flex justify-between items-end">
            <div className="flex items-center gap-2 text-slate-400">
              <Database className="w-4 h-4" />
              <span className="text-[10px] font-bold uppercase tracking-widest">Memory</span>
            </div>
            <span className="text-xl font-black text-white">{memUsedGB}G / {memTotalGB}G</span>
          </div>
          <div className="h-1.5 w-full bg-slate-800/50 rounded-full overflow-hidden">
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${memPercent}%` }}
              className="h-full bg-gradient-to-r from-blue-500 to-indigo-500 shadow-[0_0_10px_rgba(59,130,246,0.5)]"
            />
          </div>
        </div>
      </div>

      <div className="relative z-10">
        <div className="flex items-center justify-between mb-4">
          <h4 className="text-[10px] font-black text-slate-500 uppercase tracking-[0.2em]">Active Workloads ({containers.length})</h4>
        </div>

        <div className="space-y-2 max-h-40 overflow-y-auto pr-1 custom-scrollbar">
          {containers.map(c => {
            const info = c.deploy_response
            const isRunning = c.status === 'Running'
            const isPending = c.status === 'Pending'
            const isStopped = c.status === 'Stopped'
            const isError = c.status === 'Error' || c.status === 'Stop Failed'

            let dotColor = 'bg-slate-500' // Default / Unknown
            if (isRunning) dotColor = 'bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]'
            if (isPending) dotColor = 'bg-yellow-500 animate-pulse'
            if (isStopped) dotColor = 'bg-slate-600'
            if (isError) dotColor = 'bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.5)]'

            return (
              <div key={info.container_id} className="flex items-center justify-between p-3 bg-slate-900/50 rounded-2xl border border-slate-800/50 group/item hover:bg-slate-800/80 transition-all">
                <div className="flex items-center gap-3">
                  <div className={`w-2 h-2 rounded-full ${dotColor}`} />
                  <div className="flex flex-col">
                    <span className="text-xs font-bold text-slate-300 font-mono">{info.container_id}</span>
                    <span className={`text-[8px] font-black uppercase tracking-widest ${isError ? 'text-red-400' : 'text-slate-500'}`}>
                      {c.status} {(!info.success && info.error_message) ? `- ${info.error_message}` : ''}
                    </span>
                  </div>
                </div>
                <div className="flex items-center gap-1 opacity-0 group-hover/item:opacity-100 transition-opacity">
                  {!isStopped && (
                    <>
                      <button
                        onClick={() => window.location.href = `/terminal?container_id=${info.container_id}&hostname=${node.hostname}`}
                        className="p-1.5 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-cyan-400 transition-all"
                        title="Shell"
                      >
                        <Terminal className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => onEdit?.(c)}
                        className="p-1.5 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-blue-400 transition-all"
                        title="Settings"
                      >
                        <Settings className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => onStop?.(node.hostname, info.container_id)}
                        className="p-1.5 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-red-400 transition-all"
                        title="Stop"
                      >
                        <Square className="w-3.5 h-3.5 fill-current" />
                      </button>
                    </>
                  )}
                  {isStopped && (
                    <>
                      <button
                        onClick={() => onEdit?.(c)}
                        className="p-1.5 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-blue-400 transition-all"
                        title="Settings"
                      >
                        <Settings className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => onStart?.(node.hostname, info.container_id)}
                        className="p-1.5 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-green-400 transition-all"
                        title="Start"
                      >
                        <Play className="w-3.5 h-3.5 fill-current" />
                      </button>
                    </>
                  )}
                </div>
              </div>
            )
          })}

          {containers.length === 0 && (
            <div className="py-4 text-center border border-dashed border-slate-800 rounded-2xl">
              <span className="text-[10px] font-bold text-slate-600 uppercase tracking-widest italic">No workloads active</span>
            </div>
          )}
        </div>
      </div>
    </motion.div>
  )
}
