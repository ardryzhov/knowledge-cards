import { useEffect, useRef, type ReactNode } from 'react'
import { ArrowUpRight, BookOpen, ChartNoAxesCombined, ChevronRight, Command, House, LayoutDashboard, Layers3, LogOut, MoveUpRight } from 'lucide-react'
import type { Screen } from '@/types/navigation'

const links = [
  { id: 'dashboard', title: 'Обзор', icon: LayoutDashboard, number: '01' },
  { id: 'topics', title: 'Направления', icon: BookOpen, number: '02' },
  { id: 'training', title: 'Тренировка', icon: Layers3, number: '03' },
  { id: 'statistics', title: 'Статистика', icon: ChartNoAxesCombined, number: '04' },
] as const

const mobileLinks = [
  { id: 'dashboard', title: 'Главная', icon: House },
  { id: 'topics', title: 'Карточки', icon: Layers3 },
] as const

export function Layout({ screen, children, onSignOut }: { screen: Screen; children: ReactNode; onSignOut?: () => void }) {
  const contentRef = useRef<HTMLDivElement>(null)
  useEffect(() => { contentRef.current?.scrollTo({ top: 0 }) }, [screen])

  if (screen === 'training') {
    return <main id="main-content" className="training-stage" tabIndex={-1}>{children}</main>
  }

  return <div className={`app-shell ${screen === 'dashboard' ? 'dashboard-shell' : ''}`}>
    <aside className="sidebar">
      <a href="#dashboard" className="brand" aria-label="Knowledge Cards — обзор"><span className="brand-mark"><Command size={23} strokeWidth={2.3} /></span><span>knowledge<span className="brand-sub">CARDS /</span></span></a>
      <div className="workspace-label">ЛИЧНОЕ ПРОСТРАНСТВО <span className="status-dot" /></div>
      <nav className="side-nav" aria-label="Основная навигация">{links.map(({ id, title, icon: Icon, number }) => <a key={id} href={`#${id}`} className={`nav-link ${screen === id ? 'active' : ''}`} aria-current={screen === id ? 'page' : undefined}><Icon size={19} /><span>{title}</span><small>{number}</small></a>)}</nav>
      <div className="sidebar-bottom"><div className="prototype-label"><span className="status-dot" />Личное пространство</div><div className="profile"><span className="avatar">KC</span><div><strong>Владелец</strong><small>Персональный аккаунт</small></div></div></div>
    </aside>
    <div className="main-shell" ref={contentRef}>
      <header className="topbar"><div className="breadcrumbs"><span className="desktop-label">Рабочее пространство</span><ChevronRight size={13} className="desktop-label" /><span>{links.find(item => item.id === screen)?.title}</span></div><div className="topbar-right"><span className="avatar avatar-small">KC</span>{onSignOut && <button className="signout-button" onClick={onSignOut} type="button" aria-label="Выйти из аккаунта" title="Выйти"><LogOut size={17} /></button>}</div></header>
      <main id="main-content" tabIndex={-1}>{children}<footer className="page-footer"><span>Личная база знаний</span><span>KNOWLEDGE CARDS <MoveUpRight size={12} /></span></footer></main>
    </div>
    <nav className="mobile-nav" aria-label="Мобильная навигация">{mobileLinks.map(({ id, title, icon: Icon }) => <a href={`#${id}`} key={id} className={screen === id ? 'active' : ''} aria-current={screen === id ? 'page' : undefined}><Icon size={23} /><span>{title}</span></a>)}</nav>
  </div>
}

export function SectionHeading({ eyebrow, title, description, action }: { eyebrow: string; title: string; description: string; action?: ReactNode }) {
  return <div className="page-heading"><div><div className="eyebrow"><span className="status-dot" />{eyebrow}</div><h1>{title}<span className="heading-dot">.</span></h1><p>{description}</p></div>{action}</div>
}

export function TextLink({ href, children }: { href: string; children: ReactNode }) {
  return <a className="text-link" href={href}>{children}<ArrowUpRight size={15} /></a>
}
