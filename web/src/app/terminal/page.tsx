'use client'

import React, { useEffect, useRef, Suspense, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { Terminal as TerminalIcon, ShieldAlert, Cpu, Database, Server, Info, ArrowLeft } from 'lucide-react'
import Link from 'next/link'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'

function TerminalContent() {
  const searchParams = useSearchParams()
  const containerId = searchParams.get('container_id') || 'Global-Session'
  const hostname = searchParams.get('hostname') || ''

  const terminalRef = useRef<HTMLDivElement>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    if (!terminalRef.current) return

    const term = new Terminal({
      cursorBlink: true,
      theme: {
        background: '#0f172a', // slate-900 like
        foreground: '#cbd5e1', // slate-300
        cursor: '#22d3ee',     // cyan-400
      },
      fontFamily: 'monospace',
      fontSize: 14,
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.open(terminalRef.current)

    // Timeout for font loading calculation
    setTimeout(() => {
      fitAddon.fit()
    }, 50)

    const handleResize = () => fitAddon.fit()
    window.addEventListener('resize', handleResize)

    term.writeln(`\x1b[1;36mPicoBox Edge Shell v1.0.4 [Target: ${containerId}]\x1b[0m`)
    term.writeln(`Connecting to cluster...`)

    const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost'
    const wsProt = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const token = process.env.NEXT_PUBLIC_API_TOKEN || 'dev-secret-token'

    const ws = new WebSocket(`${wsProt}//${host}:3000/ws/terminal?container_id=${containerId}&token=${token}`)

    ws.onopen = () => {
      setIsConnected(true)
      term.writeln(`\x1b[1;32mWebSocket Connected.\x1b[0m`)
      term.write('\r\n$ ')
    }

    ws.onmessage = (event) => {
      term.write(event.data)
      term.write('$ ')
    }

    ws.onclose = () => {
      setIsConnected(false)
      term.writeln(`\x1b[1;31m\r\nConnection Closed.\x1b[0m`)
    }

    let currentInput = ''
    term.onData(data => {
      if (ws.readyState !== WebSocket.OPEN) return

      const code = data.charCodeAt(0)
      if (code === 13) { // Enter
        term.write('\r\n')
        const cmd = currentInput.trim()
        if (cmd.toLowerCase() === 'clear') {
            term.clear()
            term.write('$ ')
        } else if (cmd) {
            ws.send(cmd)
        } else {
            term.write('$ ')
        }
        currentInput = ''
      } else if (code === 127) { // Backspace
        if (currentInput.length > 0) {
          term.write('\b \b')
          currentInput = currentInput.slice(0, -1)
        }
      } else if (code < 32 && code !== 9) {
          // Ignore control characters
      } else {
        term.write(data)
        currentInput += data
      }
    })

    return () => {
      window.removeEventListener('resize', handleResize)
      ws.close()
      term.dispose()
    }
  }, [containerId])

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
           {hostname && (
             <div className="px-4 py-2 bg-slate-900 border border-slate-800 rounded-xl flex items-center gap-2 text-[10px] font-black uppercase text-slate-400 tracking-widest">
                <Server className="w-3.5 h-3.5" /> Node: {hostname}
             </div>
           )}
           <div className={`px-4 py-2 rounded-xl flex items-center gap-2 text-[10px] font-black uppercase tracking-widest ${isConnected ? 'bg-green-500/10 border border-green-500/20 text-green-400' : 'bg-red-500/10 border border-red-500/20 text-red-500'}`}>
              <span className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`} />
              {isConnected ? 'Connected' : 'Disconnected'}
           </div>
        </div>
      </div>

      <div className="flex-1 glass rounded-[2.5rem] bg-slate-950/80 border border-slate-800/50 p-6 flex flex-col relative group overflow-hidden">
        <div className="absolute top-4 right-6 flex gap-2 opacity-30 group-hover:opacity-100 transition-opacity z-10">
           <div className="w-3 h-3 rounded-full bg-red-500/50" />
           <div className="w-3 h-3 rounded-full bg-yellow-500/50" />
           <div className="w-3 h-3 rounded-full bg-green-500/50" />
        </div>
        <div ref={terminalRef} className="w-full h-full" />
      </div>

      <div className="flex gap-6">
         <div className="flex-1 glass p-6 rounded-[2rem] flex items-center gap-4 border-cyan-500/10">
            <ShieldAlert className="w-8 h-8 text-yellow-500 shrink-0" />
            <div>
               <p className="text-[10px] font-black text-slate-500 uppercase tracking-widest">Isolation Context</p>
               <p className="text-xs text-slate-400 mt-1 font-medium italic">Command executed via <span className="text-cyan-400">nsenter</span> in target container namespaces.</p>
            </div>
         </div>
         <div className="px-8 flex items-center gap-10 bg-slate-900 rounded-[2rem]">
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
