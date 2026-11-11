import { supabase } from './client'

export async function signIn(email: string, password: string) {
  if (!supabase) throw new Error('Supabase не настроен.')
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
}

export async function signOut() {
  if (!supabase) return
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}
