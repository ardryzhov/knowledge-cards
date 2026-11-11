import { useState, type FormEvent } from 'react'
import { Command, LockKeyhole, LogIn } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { signIn } from '@/lib/supabase/auth'
import './auth.css'

export function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (pending) return
    setPending(true)
    setError('')
    try { await signIn(email.trim(), password) }
    catch { setError('Не удалось войти. Проверьте email, пароль и подключение к сети.') }
    finally { setPending(false) }
  }

  return <main className="auth-screen">
    <div className="auth-card panel">
      <div className="auth-brand"><span className="brand-mark"><Command size={23} strokeWidth={2.3} /></span><span>knowledge<small>CARDS /</small></span></div>
      <div className="auth-heading"><span className="eyebrow"><span className="status-dot" />ЛИЧНОЕ ПРОСТРАНСТВО</span><h1>Вход в приложение<span className="heading-dot">.</span></h1><p>Введите данные учётной записи владельца.</p></div>
      <form onSubmit={submit} className="auth-form">
        <label htmlFor="auth-email">Email</label>
        <input id="auth-email" type="email" autoComplete="username" inputMode="email" required value={email} onChange={event => setEmail(event.target.value)} disabled={pending} />
        <label htmlFor="auth-password">Пароль</label>
        <input id="auth-password" type="password" autoComplete="current-password" required value={password} onChange={event => setPassword(event.target.value)} disabled={pending} />
        {error && <p className="auth-error" role="alert">{error}</p>}
        <Button type="submit" disabled={pending}><LogIn size={17} />{pending ? 'Входим…' : 'Войти'}</Button>
      </form>
      <p className="auth-foot"><LockKeyhole size={13} />Доступ только для владельца</p>
    </div>
  </main>
}
