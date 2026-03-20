'use client'

import React from 'react'
import {
  LayoutDashboard,
  Box,
  Activity,
  Settings,
  Terminal,
  HardDrive,
  ShieldCheck,
  Zap
} from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

const Sidebar = () => {
  const pathname = usePathname()

  const menuItems = [
    { icon: LayoutDashboard, label: 'Dashboard', href: '/' },
    { icon: Box, label: 'Nodes', href: '/nodes' },
    { icon: Activity, label: 'Metrics', href: '/metrics' },
    { icon: Terminal, label: 'Terminal', href: '/terminal' },
    { icon: HardDrive, label: 'Storage', href: '/storage' },
  ]

  const bottomItems = [
    { icon: ShieldCheck, label: 'Security', href: '/security' },
    { icon: Settings, label: 'Settings', href: '/settings' },
  ]

  return (
    <aside className="w-64 glass h-screen fixed left-0 top-0 flex flex-col border-r border-slate-800/50 z-50">
      <div className="p-6">
        <div className="flex items-center gap-3 mb-8">
          <div className="w-10 h-10 bg-gradient-to-br from-cyan-500 to-blue-600 rounded-lg flex items-center justify-center glow-cyan">
            <Zap className="text-white w-6 h-6 fill-white" />
          </div>
          <span className="text-2xl font-black tracking-tighter text-white">PicoBox</span>
        </div>

        <nav className="space-y-1">
          {menuItems.map((item) => {
            const isActive = pathname === item.href
            return (
              <Link
                key={item.label}
                href={item.href}
                className={cn(
                  "flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200 group",
                  isActive
                    ? "bg-cyan-500/10 text-cyan-400 border border-cyan-500/20 shadow-[inset_0_0_10px_rgba(34,211,238,0.1)]"
                    : "text-slate-400 hover:text-white hover:bg-slate-800/50"
                )}
              >
                <item.icon className={cn(
                  "w-5 h-5 transition-colors",
                  isActive ? "text-cyan-400" : "text-slate-500 group-hover:text-slate-300"
                )} />
                <span className="font-medium">{item.label}</span>
              </Link>
            )
          })}
        </nav>
      </div>

      <div className="mt-auto p-6 border-t border-slate-800/50">
        <div className="space-y-1">
          {bottomItems.map((item) => (
            <Link
              key={item.label}
              href={item.href}
              className="flex items-center gap-3 px-4 py-3 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800/50 transition-all duration-200 group"
            >
              <item.icon className="w-5 h-5 text-slate-500 group-hover:text-slate-300" />
              <span className="font-medium">{item.label}</span>
            </Link>
          ))}
        </div>

        <div className="mt-6 flex items-center gap-3 p-3 rounded-2xl bg-slate-900/50 border border-slate-800">
          <div className="w-8 h-8 rounded-full bg-slate-700 flex items-center justify-center">
            <span className="text-xs font-bold text-slate-400">AD</span>
          </div>
          <div className="flex flex-col overflow-hidden">
            <span className="text-xs font-semibold text-slate-200 truncate">Admin User</span>
            <span className="text-[10px] text-slate-500 truncate">master@picobox.dev</span>
          </div>
        </div>
      </div>
    </aside>
  )
}

export default Sidebar
