'use client'

import React from 'react'
import { HardDrive, Layers, Download, Plus, Search, Archive, Package, Play } from 'lucide-react'

export default function StoragePage() {
  const images = [
    { name: 'busybox', size: '1.2 MB', containers: 1, created: '2 days ago' },
    { name: 'alpine-base', size: '5.6 MB', containers: 0, created: '1 week ago' },
    { name: 'nginx-lite', size: '12.4 MB', containers: 0, created: '3 weeks ago' },
  ]

  return (
    <div className="space-y-10">
      <div className="flex justify-between items-end">
        <div>
          <h1 className="text-4xl font-black text-white tracking-tighter">Image & Storage</h1>
          <p className="text-slate-500 mt-2 font-medium">Manage your lightweight RootFS images and container storage layers.</p>
        </div>
        <button className="flex items-center gap-2 px-6 py-3 bg-gradient-to-r from-cyan-500 to-blue-600 text-white rounded-2xl font-black glow-cyan transition-all active:scale-95">
          <Download className="w-5 h-5" />
          Pull Image
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        <div className="lg:col-span-3 space-y-6">
           <div className="glass rounded-[2rem] overflow-hidden">
              <div className="p-6 border-b border-slate-800 bg-slate-950/30 flex items-center justify-between">
                 <h2 className="font-black text-white uppercase text-xs tracking-widest flex items-center gap-2">
                    <Layers className="w-4 h-4 text-cyan-400" /> Image Repository
                 </h2>
                 <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-500" />
                    <input type="text" placeholder="Search images..." className="pl-9 pr-4 py-1.5 bg-slate-900 border border-slate-800 rounded-lg text-xs outline-none focus:ring-1 focus:ring-cyan-500/50" />
                 </div>
              </div>
              <div className="divide-y divide-slate-800/50">
                 {images.map(img => (
                    <div key={img.name} className="p-6 flex items-center justify-between hover:bg-slate-900/30 transition-colors group">
                       <div className="flex items-center gap-5">
                          <div className="w-12 h-12 bg-slate-900 rounded-2xl flex items-center justify-center text-slate-500 group-hover:text-cyan-400 transition-colors">
                             <Package className="w-6 h-6" />
                          </div>
                          <div>
                             <p className="font-bold text-white text-lg">{img.name}</p>
                             <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest mt-0.5">{img.size} • {img.containers} containers active</p>
                          </div>
                       </div>
                       <div className="flex gap-2">
                          <button className="p-2.5 bg-slate-900 border border-slate-800 rounded-xl text-slate-400 hover:text-white transition-colors">
                             <Play className="w-4 h-4" />
                          </button>
                          <button className="p-2.5 bg-slate-900 border border-slate-800 rounded-xl text-slate-400 hover:text-red-400 transition-colors">
                             <Archive className="w-4 h-4" />
                          </button>
                       </div>
                    </div>
                 ))}
              </div>
           </div>
        </div>

        <div className="space-y-6">
           <div className="glass p-8 rounded-[2rem] border-cyan-500/10">
              <HardDrive className="w-10 h-10 text-cyan-500 mb-6" />
              <h3 className="font-black text-white text-xl uppercase tracking-tighter">Disk Usage</h3>
              <p className="text-slate-500 text-sm mt-2 font-medium">OverlayFS pools across the cluster.</p>

              <div className="mt-8 space-y-4">
                 <div className="space-y-2">
                    <div className="flex justify-between text-[10px] font-black uppercase text-slate-500 tracking-widest">
                       <span>Upper Layers</span>
                       <span>2.4 GB</span>
                    </div>
                    <div className="h-2 bg-slate-900 rounded-full overflow-hidden">
                       <div className="h-full bg-cyan-500 w-[15%]" />
                    </div>
                 </div>
                 <div className="space-y-2">
                    <div className="flex justify-between text-[10px] font-black uppercase text-slate-500 tracking-widest">
                       <span>Image Cache</span>
                       <span>12.8 GB</span>
                    </div>
                    <div className="h-2 bg-slate-900 rounded-full overflow-hidden">
                       <div className="h-full bg-blue-500 w-[45%]" />
                    </div>
                 </div>
              </div>
           </div>

           <button className="w-full py-4 glass rounded-[2rem] border-dashed border-slate-800 text-slate-500 font-bold text-sm flex items-center justify-center gap-2 hover:border-slate-700 hover:text-slate-400 transition-all">
              <Plus className="w-4 h-4" /> Add Storage Backend
           </button>
        </div>
      </div>
    </div>
  )
}
