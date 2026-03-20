'use client'
import React, { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { X, Cpu, MoveRight, Layers, Box, Terminal, AlertCircle, CheckCircle2 } from 'lucide-react'

interface DeployModalProps {
  isOpen: boolean
  onClose: () => void
  nodes: string[]
  onDeploy: (data: any) => Promise<void>
  editData?: any
}

export default function DeployModal({ isOpen, onClose, nodes, onDeploy, editData }: DeployModalProps) {
  const [formData, setFormData] = useState({
    hostname: nodes[0] || '',
    container_id: 'test-box',
    rootfs_image_url: '/home/hyun/works/picobox/storage/rootfs/busybox',
    command: 'sh -c "while true; do date; sleep 5; done"',
    memory_max_bytes: 536870912,
    cpu_max_quota: 100000
  })

  React.useEffect(() => {
    if (editData) {
      setFormData({
        hostname: editData.hostname || '',
        container_id: editData.deploy_response.container_id,
        rootfs_image_url: editData.spec?.rootfs_image_url || '/home/hyun/works/picobox/storage/rootfs/busybox',
        command: editData.spec?.command || 'sh -c "while true; do date; sleep 5; done"',
        memory_max_bytes: editData.spec?.memory_max_bytes || 536870912,
        cpu_max_quota: editData.spec?.cpu_max_quota || 100000
      })
    } else if (!formData.hostname && nodes.length > 0) {
      setFormData(prev => ({ ...prev, hostname: nodes[0] }))
    }
  }, [nodes, editData])

  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle')
  const [error, setError] = useState('')

  const validate = () => {
    if (!/^[a-z0-9-]+$/.test(formData.container_id)) {
      throw new Error('Container ID must be lowercase alphanumeric or hyphens')
    }
    if (!formData.rootfs_image_url) {
      throw new Error('RootFS path is required')
    }
    if (formData.memory_max_bytes < 4194304) {
      throw new Error('Memory limit must be at least 4MB')
    }
    if (formData.cpu_max_quota < 1000) {
      throw new Error('CPU quota must be at least 1000')
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setStatus('loading')
    try {
      validate()
      await onDeploy(formData)
      setStatus('success')
      setTimeout(() => {
        onClose()
        setStatus('idle')
      }, 2000)
    } catch (err: any) {
      setStatus('error')
      setError(err.message || 'Deployment failed')
    }
  }

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="absolute inset-0 bg-slate-950/80 backdrop-blur-md"
          />

          <motion.div
            initial={{ opacity: 0, scale: 0.95, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 20 }}
            className="relative w-full max-w-xl bg-slate-900 border border-slate-800 rounded-[2.5rem] shadow-2xl overflow-hidden"
          >
            {/* Header */}
            <div className="p-8 border-b border-slate-800 flex justify-between items-center bg-gradient-to-br from-slate-900 to-slate-950">
              <div>
                <h2 className="text-2xl font-black text-white flex items-center gap-3">
                  <Box className="w-8 h-8 text-cyan-500" />
                  {editData ? 'Update Container' : 'Deploy Container'}
                </h2>
                <p className="text-slate-500 text-sm mt-1 font-medium">
                  {editData ? `Editing ${editData.deploy_response.container_id}` : 'Provision a new isolated environment instantly.'}
                </p>
              </div>
              <button
                onClick={onClose}
                className="p-2 hover:bg-slate-800 rounded-full text-slate-500 hover:text-white transition-all"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            <form onSubmit={handleSubmit} className="p-8 space-y-6">
              <div className="grid grid-cols-2 gap-6">
                {/* Node Selection */}
                <div className="space-y-2">
                  <label className="text-xs font-bold text-slate-500 uppercase tracking-widest flex items-center gap-2">
                    Target Node
                  </label>
                  <select
                    value={formData.hostname}
                    onChange={e => setFormData({...formData, hostname: e.target.value})}
                    className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500/50 outline-none transition-all appearance-none"
                  >
                    {nodes.map(n => <option key={n} value={n}>{n}</option>)}
                    {nodes.length === 0 && <option disabled>No nodes available</option>}
                  </select>
                </div>

                {/* Container ID */}
                <div className="space-y-2">
                  <label className="text-xs font-bold text-slate-500 uppercase tracking-widest">
                    Container identifier
                  </label>
                  <input
                    type="text"
                    value={formData.container_id}
                    onChange={e => setFormData({...formData, container_id: e.target.value})}
                    placeholder="e.g. web-app-01"
                    className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white focus:ring-2 focus:ring-cyan-500/50 outline-none transition-all"
                  />
                  <p className="text-[9px] text-slate-600 font-bold uppercase tracking-tighter">Only lowercase, numbers, and hyphens.</p>
                </div>
              </div>

              {/* RootFS Path */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-slate-500 uppercase tracking-widest flex items-center gap-2">
                  <Layers className="w-3.5 h-3.5" /> RootFS path / URL
                </label>
                  <input
                    type="text"
                    value={formData.rootfs_image_url}
                    onChange={e => setFormData({...formData, rootfs_image_url: e.target.value})}
                    className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white font-mono text-sm focus:ring-2 focus:ring-cyan-500/50 outline-none transition-all"
                    placeholder="/path/to/rootfs or .tar.gz"
                  />
                  <p className="text-[9px] text-slate-600 font-bold uppercase tracking-tighter">Supports directories or .tar.gz images.</p>
              </div>

              {/* Command */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-slate-500 uppercase tracking-widest flex items-center gap-2">
                  <Terminal className="w-3.5 h-3.5" /> Init Command
                </label>
                <input
                  type="text"
                  value={formData.command}
                  onChange={e => setFormData({...formData, command: e.target.value})}
                  className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white font-mono text-sm focus:ring-2 focus:ring-cyan-500/50 outline-none transition-all"
                  placeholder="/bin/sh"
                />
              </div>

              <div className="grid grid-cols-2 gap-6">
                {/* Resources */}
                <div className="space-y-2">
                  <label className="text-xs font-bold text-slate-500 uppercase tracking-widest flex items-center gap-2">
                    Memory limit (Bytes)
                  </label>
                  <input
                    type="number"
                    value={formData.memory_max_bytes}
                    onChange={e => setFormData({...formData, memory_max_bytes: parseInt(e.target.value)})}
                    className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white focus:ring-2 focus:ring-cyan-500/50 outline-none transition-all"
                  />
                </div>
                <div className="space-y-2">
                  <label className="text-xs font-bold text-slate-500 uppercase tracking-widest flex items-center gap-2">
                    CPU Quota (μs)
                  </label>
                  <input
                    type="number"
                    value={formData.cpu_max_quota}
                    onChange={e => setFormData({...formData, cpu_max_quota: parseInt(e.target.value)})}
                    className="w-full bg-slate-950 border border-slate-800 rounded-2xl px-4 py-3 text-white focus:ring-2 focus:ring-cyan-500/50 outline-none transition-all"
                  />
                </div>
              </div>

              {/* Feedback Overlay */}
              <AnimatePresence mode="wait">
                {status !== 'idle' && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.9 }}
                    animate={{ opacity: 1, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.9 }}
                    className="absolute inset-0 bg-slate-900/95 flex flex-col items-center justify-center p-8 text-center"
                  >
                    {status === 'loading' && (
                      <>
                        <div className="w-16 h-16 border-4 border-cyan-500/20 border-t-cyan-500 rounded-full animate-spin mb-4" />
                        <h3 className="text-xl font-bold text-white">Deploying...</h3>
                        <p className="text-slate-400 mt-1">Negotiating with kernel namespaces</p>
                      </>
                    )}
                    {status === 'success' && (
                      <>
                        <CheckCircle2 className="w-20 h-20 text-green-400 mb-4 animate-[bounce_1s_ease-in-out_infinite]" />
                        <h3 className="text-2xl font-black text-white uppercase tracking-tight">Provisioned!</h3>
                        <p className="text-slate-400 mt-1">Container is now active on {formData.hostname}</p>
                      </>
                    )}
                    {status === 'error' && (
                      <>
                        <AlertCircle className="w-16 h-16 text-red-500 mb-4" />
                        <h3 className="text-xl font-bold text-white">Oops! Provision failed</h3>
                        <p className="text-red-400/80 mt-1">{error}</p>
                        <button
                          onClick={() => setStatus('idle')}
                          className="mt-6 px-6 py-2 bg-slate-800 text-white rounded-xl font-bold hover:bg-slate-700 transition-all"
                        >
                          Try Again
                        </button>
                      </>
                    )}
                  </motion.div>
                )}
              </AnimatePresence>

              {/* Action */}
              <button
                type="submit"
                disabled={status === 'loading' || nodes.length === 0}
                className="w-full py-4 bg-gradient-to-r from-cyan-500 to-blue-600 text-white rounded-2xl font-black text-lg group overflow-hidden relative glow-cyan disabled:grayscale disabled:opacity-50 transition-all"
              >
                <div className="relative z-10 flex items-center justify-center gap-3">
                  {editData ? 'Update Configuration' : 'Initiate Deployment'}
                  <MoveRight className="w-6 h-6 group-hover:translate-x-2 transition-transform" />
                </div>
              </button>
            </form>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  )
}
