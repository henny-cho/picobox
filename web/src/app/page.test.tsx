import { render, screen, waitFor, act } from '@testing-library/react'
import Dashboard from '@/app/page'

// Mock the global fetch API to simulate our Go Backend
global.fetch = jest.fn((url: string) => {
  if (url.includes('/api/nodes')) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        'pico-master': {
          hostname: 'pico-master',
          cpu_usage_percent: 20.0,
          memory_used_bytes: 1024,
          memory_total_bytes: 2048,
          disk_io_wait: 0.0
        }
      })
    })
  }
  if (url.includes('/api/containers')) {
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({
        'test-c1': {
          deploy_response: { container_id: 'test-c1', success: true, error_message: '' },
          hostname: 'pico-master',
          status: 'Running'
        }
      })
    })
  }
  return Promise.resolve({ ok: true, json: () => Promise.resolve({}) })
}) as jest.Mock

describe('Dashboard Page', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders dashboard title and system status', async () => {
    await act(async () => {
      render(<Dashboard />)
    })
    expect(screen.getByText('Cluster Control')).toBeInTheDocument()
  })

  it('fetches nodes and displays cards', async () => {
    await act(async () => {
      render(<Dashboard />)
    })

    // Wait for the mock fetch to resolve and the UI to update
    await waitFor(() => {
      expect(screen.getByText('pico-master')).toBeInTheDocument()
    })
    expect(global.fetch).toHaveBeenCalledTimes(2)
  })
})
