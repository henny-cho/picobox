import React from 'react'

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

const NodeCard: React.FC<NodeCardProps> = ({ node }) => {
  const memUsagePercent = (node.memory_used_bytes / node.memory_total_bytes) * 100

  return (
    <div className="bg-gray-800 border border-gray-700 p-4 rounded-lg shadow-lg hover:border-cyan-500 transition-colors">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-xl font-bold text-white tracking-wider">{node.hostname}</h3>
        <span className="w-3 h-3 bg-green-500 rounded-full animate-pulse shadow-[0_0_10px_#22c55e]"></span>
      </div>
      
      <div className="space-y-3">
        {/* CPU Bar */}
        <div>
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>CPU</span>
            <span>{node.cpu_usage_percent.toFixed(1)}%</span>
          </div>
          <div className="w-full bg-gray-700 h-2 rounded-full overflow-hidden">
            <div 
              className="bg-cyan-500 h-full rounded-full transition-all duration-500"
              style={{ width: `${node.cpu_usage_percent}%` }}
            ></div>
          </div>
        </div>

        {/* Memory Bar */}
        <div>
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>RAM</span>
            <span>{memUsagePercent.toFixed(1)}%</span>
          </div>
          <div className="w-full bg-gray-700 h-2 rounded-full overflow-hidden">
            <div 
              className={`h-full rounded-full transition-all duration-500 ${memUsagePercent > 80 ? 'bg-red-500' : 'bg-green-500'}`}
              style={{ width: `${memUsagePercent}%` }}
            ></div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default NodeCard
