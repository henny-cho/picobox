'use client'

import React, { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Activity, Bell, Search, Filter, Plus, Box as BoxIcon, Database } from 'lucide-react'
import NodeCard, { NodeMetrics, ContainerInfo } from '@/components/NodeCard'
import DeployModal from '@/components/DeployModal'

export interface ContainerState {
  deploy_response: {
    container_id: string
    success: boolean
    error_message: string
  }
  hostname: string
  status: string
  spec?: {
    container_id: string
    rootfs_image_url: string
    command: string
    memory_max_bytes: number
    cpu_max_quota: number
  }
}

export default function Dashboard() {
  const [nodes, setNodes] = useState<Record<string, NodeMetrics>>({})
  const [containers, setContainers] = useState<Record<string, ContainerState>>({})
  const [loading, setLoading] = useState(true)
  const [isDeployModalOpen, setIsDeployModalOpen] = useState(false)
  const [editingContainer, setEditingContainer] = useState<ContainerState | null>(null)

  const getApiUrl = (path: string) => {
    const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost'
    return `http://${host}:3000${path}`
  }

  const fetchData = async () => {
    try {
      const [nodesRes, containersRes] = await Promise.all([
        fetch(getApiUrl('/api/nodes')),
        fetch(getApiUrl('/api/containers'))
      ])

      if (nodesRes.ok) setNodes(await nodesRes.json())
      if (containersRes.ok) setContainers(await containersRes.json())
    } catch (err) {
      console.warn("Backend not reachable. Displaying empty states.", err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 3000)
    return () => clearInterval(interval)
  }, [])

  const handleDeploy = async (data: any) => {
    const endpoint = editingContainer ? '/api/update' : '/api/deploy'
    const res = await fetch(getApiUrl(endpoint), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    })
    if (!res.ok) {
      const err = await res.json()
      throw new Error(err.error || 'Failed to deploy')
    }
    fetchData()
  }

  const handleStop = async (hostname: string, containerId: string) => {
    try {
      const res = await fetch(getApiUrl('/api/stop'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ hostname, container_id: containerId })
      })
      if (!res.ok) {
        const err = await res.json()
        console.error('Failed to stop:', err.error)
      }
      fetchData()
    } catch (err) {
      console.error('Error stopping container:', err)
    }
  }

  const handleStart = async (hostname: string, containerId: string) => {
    try {
      const res = await fetch(getApiUrl('/api/start'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ hostname, container_id: containerId })
      })
      if (!res.ok) {
        const err = await res.json()
        console.error('Failed to start:', err.error)
      }
      fetchData()
    } catch (err) {
      console.error('Error starting container:', err)
    }
  }

  const activeNodesCount = Object.keys(nodes).length
  const activeContainersCount = Object.keys(containers).filter(id => containers[id].status === 'Running').length

  	return (
		<motion.div
			initial={{ opacity: 0 }}
			animate={{ opacity: 1 }}
			className="max-w-7xl mx-auto space-y-10 pb-20"
		>
      {/* Upper Dashboard Actions */}
      <section className="flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div>
          <h1 className="text-5xl font-black text-white tracking-tighter">Cluster Control</h1>
          <p className="text-slate-500 mt-2 font-medium">Manage ultra-lightweight containers across your edge nodes.</p>
        </div>

        <div className="flex items-center gap-3">
          <div className="relative group">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 group-focus-within:text-cyan-400 transition-colors" />
            <input
              type="text"
              placeholder="Search nodes or containers..."
              className="pl-10 pr-4 py-3 bg-slate-900/50 border border-slate-800 rounded-2xl focus:outline-none focus:ring-2 focus:ring-cyan-500/50 transition-all text-sm w-72 text-white"
            />
          </div>
          <button
            onClick={() => setIsDeployModalOpen(true)}
            className="px-6 py-3 bg-gradient-to-r from-cyan-500 to-blue-600 text-white rounded-2xl font-black flex items-center gap-2 glow-cyan hover:brightness-110 transition-all active:scale-95"
          >
            <Plus className="w-5 h-5 stroke-[3]" />
            Provision
          </button>
        </div>
      </section>

      {/* Stats Quick View */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        {[
          				{ icon: Activity, label: 'CPU Load', value: '12.4%', color: 'text-cyan-400', bg: 'bg-cyan-500/10' },
				{ icon: Database, label: 'Memory', value: '4.2 GB', color: 'text-blue-400', bg: 'bg-blue-500/10' },
				{ icon: BoxIcon, label: 'Containers', value: activeContainersCount.toString(), color: 'text-purple-400', bg: 'bg-purple-500/10' },
				{ icon: Plus, label: 'Nodes', value: `${activeNodesCount}/${activeNodesCount}`, color: 'text-green-400', bg: 'bg-green-500/10' },
			].map((stat, i) => (
				<motion.div
					key={i}
					initial={{ opacity: 0, scale: 0.9 }}
					animate={{ opacity: 1, scale: 1 }}
					transition={{ delay: i * 0.1 }}
					className="glass p-6 rounded-[2rem] flex items-center gap-5 transition-transform hover:scale-[1.02]"
				>
					 <div className={`w-14 h-14 ${stat.bg} rounded-2xl flex items-center justify-center`}>
							<stat.icon className={`w-7 h-7 ${stat.color}`} />
					 </div>
					 <div>
							<p className="text-[10px] font-bold text-slate-500 uppercase tracking-[0.2em]">{stat.label}</p>
							<p className="text-3xl font-black text-white tracking-tight">{stat.value}</p>
					 </div>
				</motion.div>
			))}
      </div>

      {/* Node Grid */}
      <section className="space-y-6">
        <div className="flex items-center justify-between">
          <h2 className="text-2xl font-black text-white flex items-center gap-3">
            Active Infrastructure
            <span className="flex items-center gap-1.5 px-3 py-1 bg-green-500/10 text-green-400 text-[10px] font-black uppercase tracking-widest rounded-full border border-green-500/20 shadow-[0_0_15px_rgba(34,197,94,0.1)]">
              <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
              Live Sync
            </span>
          </h2>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center h-80 glass rounded-[3rem] gap-4">
             <div className="relative w-16 h-16">
               <div className="absolute inset-0 border-4 border-cyan-500/10 rounded-full" />
               <div className="absolute inset-0 border-4 border-t-cyan-500 rounded-full animate-spin" />
             </div>
             <p className="text-slate-500 font-bold tracking-widest uppercase text-xs animate-pulse">Establishing Neural Link...</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            <AnimatePresence mode="popLayout">
              {Object.values(nodes).map(node => (
                <NodeCard
                  key={node.hostname}
                  node={node}
                  containers={Object.values(containers).filter(c => c.hostname === node.hostname)}
                  onStop={handleStop}
                  onStart={handleStart}
                  onEdit={(c) => {
                    setEditingContainer(c)
                    setIsDeployModalOpen(true)
                  }}
                />
              ))}
            </AnimatePresence>

            {Object.keys(nodes).length === 0 && (
              <div className="col-span-full py-32 text-center glass rounded-[3rem] border-2 border-dashed border-slate-800/50">
                <BoxIcon className="w-16 h-16 text-slate-800 mx-auto mb-4" />
                <p className="text-slate-500 font-black text-xl uppercase tracking-tighter">No Active Nodes Found</p>
                <p className="text-slate-600 font-medium text-sm mt-1">Ensure pico-daemon is running and connected to master.</p>
              </div>
            )}
          </div>
        )}
      </section>

      <DeployModal
        isOpen={isDeployModalOpen}
        onClose={() => {
          setIsDeployModalOpen(false)
          setEditingContainer(null)
        }}
        nodes={Object.keys(nodes)}
        onDeploy={handleDeploy}
        editData={editingContainer}
      />
    </motion.div>
  )
}
