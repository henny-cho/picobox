'use client'

import React, { useState, useEffect, useRef, Suspense } from 'react'
import { useSearchParams } from 'next/navigation'
import { Terminal as TerminalIcon, ShieldAlert, Cpu, Database, Server, Info, ArrowLeft } from 'lucide-react'
import Link from 'next/link'

function TerminalContent() {
  const searchParams = useSearchParams()
  	const containerId = searchParams.get('container_id') || 'Global-Session'
	const hostname = searchParams.get('hostname') || ''

  const [history, setHistory] = useState<string[]>([
    `PicoBox Edge Shell v1.0.4 [Target: ${containerId}]`,
    'Connected to cluster 192.168.219.100',
    'Type "help" for local commands or any shell command for the container.',
    ''
  ])
  	const [input, setInput] = useState('')
	const [isExecuting, setIsExecuting] = useState(false)
	const [cmdHistory, setCmdHistory] = useState<string[]>([])
	const [historyIdx, setHistoryIdx] = useState(-1)
	const scrollRef = useRef<HTMLDivElement>(null)

  const getApiUrl = (path: string) => {
    const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost'
    return `http://${host}:3000${path}`
  }

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [history])

  const handleCommand = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || isExecuting) return

    const rawInput = input.trim()
    const cmd = rawInput.toLowerCase()
    setHistory(prev => [...prev, `$ ${rawInput}`])
    setInput('')
    setIsExecuting(true)

    if (cmd === 'clear') {
      setHistory([])
      setIsExecuting(false)
      return
    }

    if (cmd === 'help') {
      setHistory(prev => [...prev, 'Available commands:', '  clear    - Clear terminal history', '  ls/ps/etc - Executed within container', ''])
      setIsExecuting(false)
      return
    }

    // Call /api/exec
    try {
      setCmdHistory(prev => [rawInput, ...prev])
      setHistoryIdx(-1)

      const res = await fetch(getApiUrl('/api/exec'), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          container_id: containerId,
          hostname: hostname,
          command: rawInput
        })
      })

      if (res.ok) {
        const data = await res.json()
        if (data.success) {
          const lines = data.output.split('\n')
          setHistory(prev => [...prev, ...lines, ''])
        } else {
          setHistory(prev => [...prev, `Error: ${data.error_message}`, ''])
        }
      } else {
        const err = await res.json()
        setHistory(prev => [...prev, `System Error: ${err.error}`, ''])
      }
    } catch (err) {
      setHistory(prev => [...prev, 'Failed to reach PicoBox Master.', ''])
    } finally {
      setIsExecuting(false)
    }
  }

  return (
    <div className="h-[calc(100vh-160px)] flex flex-col gap-6">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-4">
          <Link href="/" className="p-2 hover:bg-slate-900 rounded-xl text-slate-500 hover:text-white transition-all">
            <ArrowLeft className="w-6 h-6" />
          </Link>
          <h1 className="text-4xl font-black text-white tracking-tighter flex items-center gap-4">
            <TerminalIcon className="w-10 h-10 text-cyan-400" />
            Shell: <span className="text-slate-500">{containerId}</span>
          </h1>
        </div>
        <div className="flex gap-4">
           <div className="px-4 py-2 bg-slate-900 border border-slate-800 rounded-xl flex items-center gap-2 text-[10px] font-black uppercase text-slate-400 tracking-widest">
              <Server className="w-3.5 h-3.5" /> Edge-Agent
           </div>
           <div className="px-4 py-2 bg-green-500/10 border border-green-500/20 rounded-xl flex items-center gap-2 text-[10px] font-black uppercase text-green-400 tracking-widest">
              <span className="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse" />
              Connected
           </div>
        </div>
      </div>

      <div className="flex-1 glass rounded-[2.5rem] bg-slate-950/80 border border-slate-800/50 p-6 font-mono text-sm overflow-hidden flex flex-col relative group">
        <div className="absolute top-4 right-6 flex gap-2 opacity-30 group-hover:opacity-100 transition-opacity">
           <div className="w-3 h-3 rounded-full bg-red-500/50" />
           <div className="w-3 h-3 rounded-full bg-yellow-500/50" />
           <div className="w-3 h-3 rounded-full bg-green-500/50" />
        </div>

        <div ref={scrollRef} className="flex-1 overflow-y-auto space-y-1 scrollbar-hide mb-4">
          {history.map((line, i) => (
            <div key={i} className={line.startsWith('$') ? 'text-white font-bold' : 'text-slate-400 min-h-[1.2em]'}>
              {line}
            </div>
          ))}
          {isExecuting && (
            <div className="text-cyan-500 animate-pulse font-bold tracking-widest text-[10px] uppercase">
              Executing request...
            </div>
          )}
        </div>

        <form onSubmit={handleCommand} className="flex gap-3 items-center bg-slate-900/50 p-4 rounded-2xl border border-slate-800 focus-within:border-cyan-500/50 transition-all">
          <span className="text-cyan-400 font-bold shrink-0">$</span>
          <input
            autoFocus
            disabled={isExecuting}
            type="text"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => {
              if (e.key === 'ArrowUp') {
                e.preventDefault()
                const newIdx = Math.min(historyIdx + 1, cmdHistory.length - 1)
                if (newIdx >= 0) {
                  setHistoryIdx(newIdx)
                  setInput(cmdHistory[newIdx])
                }
              } else if (e.key === 'ArrowDown') {
                e.preventDefault()
                const newIdx = Math.max(historyIdx - 1, -1)
                setHistoryIdx(newIdx)
                setInput(newIdx === -1 ? '' : cmdHistory[newIdx])
              }
            }}
            className="flex-1 bg-transparent border-none outline-none text-white font-mono placeholder-slate-700 disabled:opacity-50"
            placeholder={isExecuting ? 'Waiting for agent output...' : 'Enter command...'}
          />
        </form>
      </div>

      <div className="flex gap-6">
         <div className="flex-1 glass p-6 rounded-[2rem] flex items-center gap-4 border-cyan-500/10">
            <ShieldAlert className="w-8 h-8 text-yellow-500 shrink-0" />
            <div>
               <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest">Isolation Context</p>
               <p className="text-xs text-slate-400 mt-1 font-medium italic">Command executed via <span className="text-cyan-400">nsenter</span> in target container namespaces.</p>
            </div>
         </div>
         <div className="px-8 flex items-center gap-10">
            <div className="flex items-center gap-3">
               <Cpu className="w-4 h-4 text-slate-600" />
               <span className="text-xs font-bold text-slate-400 tracking-tight">Status: Active</span>
            </div>
            <div className="flex items-center gap-3">
               <Database className="w-4 h-4 text-slate-600" />
               <span className="text-xs font-bold text-slate-400 tracking-tight">PicoBox v1.0</span>
            </div>
         </div>
      </div>
    </div>
  )
}

export default function TerminalPage() {
  return (
    <Suspense fallback={<div className="text-white p-10 font-bold">Resonance link established...</div>}>
      <TerminalContent />
    </Suspense>
  )
}
