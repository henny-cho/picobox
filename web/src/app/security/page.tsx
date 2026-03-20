'use client'

import React from 'react'
import { ShieldCheck, ShieldAlert, Key, Lock, Eye, CheckCircle2, AlertCircle, Shield } from 'lucide-react'

export default function SecurityPage() {
  return (
    <div className="space-y-10">
      <div className="flex justify-between items-end">
        <div>
          <h1 className="text-4xl font-black text-white tracking-tighter">Cluster Security</h1>
          <p className="text-slate-500 mt-2 font-medium">Manage encryption, access control, and container isolation policies.</p>
        </div>
        <div className="flex items-center gap-2 px-4 py-2 bg-green-500/10 text-green-400 text-[10px] font-black uppercase tracking-widest rounded-xl border border-green-500/20">
          <ShieldCheck className="w-4 h-4" />
          Hardened
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <section className="glass p-8 rounded-[3rem] space-y-6">
           <div className="w-14 h-14 bg-cyan-500/10 rounded-2xl flex items-center justify-center text-cyan-400">
              <Lock className="w-7 h-7" />
           </div>
           <h3 className="text-2xl font-black text-white">Access Control</h3>
           <p className="text-slate-500 text-sm font-medium">RBAC policies and API tokens for authentication between master and agents.</p>

           <div className="space-y-3 pt-4">
              {[
                { label: 'Admin Access', user: 'master@picobox.dev', status: 'Active' },
                { label: 'Edge Token #12', user: 'ub-server-lxc', status: 'Expiring in 4 days' },
              ].map((item, i) => (
                <div key={i} className="flex justify-between items-center bg-slate-950/50 p-4 rounded-2xl border border-slate-800">
                   <div>
                      <p className="font-bold text-white text-sm">{item.label}</p>
                      <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">{item.user}</p>
                   </div>
                   <span className="text-[10px] font-black text-cyan-400 uppercase tracking-widest">{item.status}</span>
                </div>
              ))}
           </div>
        </section>

        <section className="glass p-8 rounded-[3rem] space-y-6">
           <div className="w-14 h-14 bg-purple-500/10 rounded-2xl flex items-center justify-center text-purple-400">
              <Eye className="w-7 h-7" />
           </div>
           <h3 className="text-2xl font-black text-white">Audit Logs</h3>
           <p className="text-slate-500 text-sm font-medium">Recent security-related events and container execution logs.</p>

           <div className="space-y-3 pt-4">
              {[
                { event: 'Namespace Escalate', node: 'pico-worker-1', type: 'Warning' },
                { event: 'RootFS Integrity Check', node: 'ub-server-lxc', type: 'Success' },
              ].map((item, i) => (
                <div key={i} className="flex gap-4 items-center bg-slate-950/50 p-4 rounded-2xl border border-slate-800">
                   {item.type === 'Warning' ? <AlertCircle className="w-5 h-5 text-yellow-500" /> : <CheckCircle2 className="w-5 h-5 text-green-500" />}
                   <div>
                      <p className="font-bold text-white text-sm">{item.event}</p>
                      <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">{item.node} • Just now</p>
                   </div>
                </div>
              ))}
           </div>
        </section>
      </div>

      <div className="glass p-10 rounded-[3rem] border border-cyan-500/10 bg-gradient-to-br from-slate-900 to-slate-950 flex items-center justify-between">
         <div className="flex items-center gap-6">
            <div className="w-16 h-16 bg-blue-600/20 rounded-[1.5rem] flex items-center justify-center text-blue-400 shadow-[0_0_30px_rgba(37,99,235,0.1)]">
               <Shield className="w-10 h-10" />
            </div>
            <div>
               <h3 className="text-2xl font-black text-white">Kernel Lockdown Status</h3>
               <p className="text-slate-400 mt-2 font-medium">All containers are running with `no-new-privileges` and Seccomp filtering active.</p>
            </div>
         </div>
         <button className="px-8 py-3 bg-slate-800 text-white rounded-2xl font-black hover:bg-slate-700 transition-all">Configure Policies</button>
      </div>
    </div>
  )
}
