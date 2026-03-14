import { render, screen } from '@testing-library/react'
import NodeCard from '@/components/NodeCard'

describe('NodeCard Component', () => {
  const mockNode = {
    hostname: 'test-node-01',
    cpu_usage_percent: 45.5,
    memory_used_bytes: 536870912, // 512 MB
    memory_total_bytes: 2147483648, // 2 GB
    disk_io_wait: 0.1,
  }

  it('renders node hostname correctly', () => {
    render(<NodeCard node={mockNode} />)
    const hostnameTitle = screen.getByText('test-node-01')
    expect(hostnameTitle).toBeInTheDocument()
  })

  it('calculates and displays memory usage correctly', () => {
    render(<NodeCard node={mockNode} />)
    // 512 MB / 2048 MB = 25%
    const memUsageText = screen.getByText(/25.0%/)
    expect(memUsageText).toBeInTheDocument()
  })

  it('displays CPU usage properly formatted', () => {
    render(<NodeCard node={mockNode} />)
    const cpuUsageText = screen.getByText(/45.5%/)
    expect(cpuUsageText).toBeInTheDocument()
  })
})
