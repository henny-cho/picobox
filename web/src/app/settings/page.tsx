'use client'

import React from 'react'
import { Settings, User, Bell, Shield, Globe, Cpu, Save, Trash2, Info } from 'lucide-react'

export default function SettingsPage() {
  return (
    <div className="max-w-4xl space-y-10">
      <div>
        <h1 className="text-4xl font-black text-white tracking-tighter">System Settings</h1>
        <p className="text-slate-500 mt-2 font-medium">Configure your cluster control plane and orchestration parameters.</p>
      </div>

      <div className="space-y-8">
        <section className="glass p-8 rounded-[2.5rem] space-y-8">
           <div className="flex items-center gap-4 pb-6 border-b border-slate-800">
              <div className="w-10 h-10 bg-slate-900 rounded-xl flex items-center justify-center text-slate-400">
                 <Globe className="w-5 h-5" />
              </div>
              <h3 className="font-black text-white uppercase text-xs tracking-widest">Master API Configuration</h3>
           </div>

           <div className="grid grid-cols-2 gap-8">
              <div className="space-y-2">
                 <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest">REST Listen Port</label>
                 <input type="text" value="3000" readOnly className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-white font-mono text-sm outline-none" />
              </div>
              <div className="space-y-2">
                 <label className="text-[10px] font-black text-slate-500 uppercase tracking-widest">gRPC Control Port</label>
                 <input type="text" value="50051" readOnly className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-white font-mono text-sm outline-none" />
              </div>
           </div>
        </section>

        <section className="glass p-8 rounded-[2.5rem] space-y-8">
           <div className="flex items-center gap-4 pb-6 border-b border-slate-800">
              <div className="w-10 h-10 bg-slate-900 rounded-xl flex items-center justify-center text-slate-400">
                 <Cpu className="w-5 h-5" />
              </div>
              <h3 className="font-black text-white uppercase text-xs tracking-widest">Resource Scheduling</h3>
           </div>

           <div className="space-y-6">
              <div className="flex justify-between items-center bg-slate-950/50 p-6 rounded-2xl border border-slate-800">
                 <div>
                    <p className="font-bold text-white uppercase text-xs tracking-widest">Auto-Scale Nodes</p>
                    <p className="text-xs text-slate-500 mt-1">Automatically provision new agents when cluster load exceeds 80%.</p>
                 </div>
                 <div className="w-12 h-6 bg-slate-800 rounded-full relative cursor-pointer opacity-50">
                    <div className="absolute left-1 top-1 w-4 h-4 bg-slate-600 rounded-full" />
                 </div>
              </div>
           </div>
        </section>

        <div className="flex justify-end gap-4">
           <button className="px-8 py-3 bg-slate-900 text-slate-400 rounded-2xl font-black hover:text-white transition-all">Cancel</button>
           <button className="px-8 py-3 bg-gradient-to-r from-cyan-500 to-blue-600 text-white rounded-2xl font-black glow-cyan transition-all">
              Save Changes
           </button>
        </div>
      </div>
    </div>
  )
}
