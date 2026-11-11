import { useEffect, useState } from 'react'
import { loadTrainingStats, type TrainingStats } from '@/lib/supabase/training'

export function useTrainingStats() {
  const [data, setData] = useState<TrainingStats | null>(null)
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading')
  const [retryKey, setRetryKey] = useState(0)

  useEffect(() => {
    let active = true
    loadTrainingStats().then(stats => {
      if (!active) return
      setData(stats)
      setState('ready')
    }).catch(() => {
      if (!active) return
      setState('error')
    })
    return () => { active = false }
  }, [retryKey])

  return {
    data,
    state,
    retry: () => { setState('loading'); setRetryKey(value => value + 1) },
  }
}
