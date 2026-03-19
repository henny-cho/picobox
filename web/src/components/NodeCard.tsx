'use client'

import React from 'react'
import { motion } from 'framer-motion'
import { Server, Cpu, Layers, HardDrive, ArrowUpRight, Activity } from 'lucide-react'
import { 
  AreaChart, 
  Area, 
  XAxis, 
  YAxis, 
  ResponsiveContainer 
} from 'recharts'

export interface NodeMetrics {
  hostname: string
  cpu_usage_percent: number
  memory_used_bytes: number
  memory_total_bytes: number
  disk_io_wait: number
}

interface NodeCardProps {
  node: NodeMetrics
}

// Mock history for chart visualization
const generateMockHistory = () => {
  return Array.from({ length: 10 }, (_, i) => ({
    time: i,
    val: Math.floor(Math.random() * 40) + 20
  }))
}

const NodeCard: React.FC<NodeCardProps> = ({ node }) => {
  const memUsagePercent = (node.memory_used_bytes / node.memory_total_bytes) * 100
  const history = React.useMemo(() => generateMockHistory(), [])

  const getStatusColor = () => {
    if (node.cpu_usage_percent > 80 || memUsagePercent > 80) return 'text-red-400'
    if (node.cpu_usage_percent > 60 || memUsagePercent > 60) return 'text-amber-400'
    return 'text-cyan-400'
  }

  const getStatusBg = () => {
    if (node.cpu_usage_percent > 80 || memUsagePercent > 80) return 'bg-red-500/20'
    if (node.cpu_usage_percent > 60 || memUsagePercent > 60) return 'bg-amber-500/20'
    return 'bg-cyan-500/20'
  }

  return (
    <motion.div 
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -5 }}
      className="glass rounded-3xl p-6 relative overflow-hidden group transition-all duration-300 hover:border-cyan-500/50 hover:shadow-[0_20px_50px_rgba(8,112,184,0.2)]"
    >
      <div className="flex justify-between items-start mb-6">
        <div className="flex items-center gap-3">
          <div className={`p-2 rounded-xl ${getStatusBg()}`}>
            <Server className={`w-5 h-5 ${getStatusColor()}`} />
          </div>
          <div>
            <h3 className="text-lg font-bold text-white tracking-tight">{node.hostname}</h3>
            <div className="flex items-center gap-2">
              <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse shadow-[0_0_8px_#22c55e]"></span>
              <span className="text-[10px] text-slate-400 font-mono uppercase tracking-widest">Active</span>
            </div>
          </div>
        </div>
        <button className="text-slate-500 hover:text-white transition-colors">
          <ArrowUpRight className="w-5 h-5" />
        </button>
      </div>

      <div className="space-y-5 relative z-10">
        {/* CPU Section */}
        <div className="space-y-2">
          <div className="flex justify-between items-end">
            <div className="flex items-center gap-2 text-slate-400">
              <Cpu className="w-3.5 h-3.5" />
              <span className="text-xs font-medium uppercase tracking-wider">CPU usage</span>
            </div>
            <span className="text-sm font-bold text-white font-mono">{node.cpu_usage_percent.toFixed(1)}%</span>
          </div>
          <div className="h-1.5 w-full bg-slate-800 rounded-full overflow-hidden">
            <motion.div 
              initial={{ width: 0 }}
              animate={{ width: `${node.cpu_usage_percent}%` }}
              className="h-full bg-gradient-to-r from-cyan-500 to-blue-500 rounded-full"
            />
          </div>
        </div>

        {/* RAM Section */}
        <div className="space-y-2">
          <div className="flex justify-between items-end">
            <div className="flex items-center gap-2 text-slate-400">
              <Layers className="w-3.5 h-3.5" />
              <span className="text-xs font-medium uppercase tracking-wider">Memory usage</span>
            </div>
            <span className="text-sm font-bold text-white font-mono">{memUsagePercent.toFixed(1)}%</span>
          </div>
          <div className="h-1.5 w-full bg-slate-800 rounded-full overflow-hidden">
            <motion.div 
              initial={{ width: 0 }}
              animate={{ width: `${memUsagePercent}%` }}
              className={`h-full rounded-full ${memUsagePercent > 80 ? 'bg-red-500' : 'bg-cyan-500'}`}
            />
          </div>
        </div>

        {/* Disk I/O or History Chart */}
        <div className="pt-2">
           <div className="flex items-center gap-2 text-slate-400 mb-2">
              <Activity className="w-3.5 h-3.5" />
              <span className="text-xs font-medium uppercase tracking-wider">Load Trend</span>
            </div>
            <div className="h-16 w-full -mx-2">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={history}>
                  <defs>
                    <linearGradient id="colorVal" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#22d3ee" stopOpacity={0.3}/>
                      <stop offset="95%" stopColor="#22d3ee" stopOpacity={0}/>
                    </linearGradient>
                  </defs>
                  <Area 
                    type="monotone" 
                    dataKey="val" 
                    stroke="#22d3ee" 
                    fillOpacity={1} 
                    fill="url(#colorVal)" 
                    strokeWidth={2}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
        </div>
      </div>

      {/* Decorative background logo */}
      <Server className="absolute -right-6 -bottom-6 w-32 h-32 text-white/5 rotate-12 group-hover:rotate-0 transition-transform duration-500" />
    </motion.div>
  )
}

export default NodeCard
