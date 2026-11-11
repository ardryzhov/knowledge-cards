import { expect, type Page } from '@playwright/test'

const owner = {
  id: '11000000-0000-4000-8000-000000000001',
  aud: 'authenticated',
  role: 'authenticated',
  email: 'owner@example.test',
  app_metadata: { provider: 'email', providers: ['email'] },
  user_metadata: {},
  created_at: '2026-11-08T00:00:00.000Z',
}

function accessToken() {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url')
  return `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: owner.id, role: 'authenticated', exp: Math.floor(Date.now() / 1000) + 3600 })}.test-signature`
}

type ContentOptions = { topics?: typeof sampleTopics; cards?: MockCard[]; failTopics?: boolean; failCards?: boolean }

export async function mockOwnerSignIn(page: Page, content: ContentOptions = {}) {
  await mockContent(page, content)
  await page.route('**/auth/v1/**', route => {
    const pathname = new URL(route.request().url()).pathname
    if (pathname.endsWith('/token')) return route.fulfill({ json: { access_token: accessToken(), token_type: 'bearer', expires_in: 3600, refresh_token: 'test-refresh-token', user: owner } })
    if (pathname.endsWith('/user')) return route.fulfill({ json: owner })
    if (pathname.endsWith('/logout')) return route.fulfill({ status: 204 })
    return route.fulfill({ status: 404 })
  })
  await page.goto('/#dashboard')
  await page.getByLabel('Email').fill(owner.email)
  await page.getByLabel('Пароль').fill('test-password')
  await page.getByRole('button', { name: 'Войти' }).click()
  if (content.failTopics) await expect(page.getByRole('alert')).toContainText('Не удалось загрузить темы и карточки')
  else await expect(page.getByRole('heading', { name: /Что повторить сегодня/ })).toBeVisible()
}

export const topicId = '22000000-0000-4000-8000-000000000001'
export const cardId = '33000000-0000-4000-8000-000000000001'

export const sampleTopics = [
  { id: topicId, title: 'Разработка', description: 'JavaScript и TypeScript', color: 'green', icon: 'development', sort_order: 1, created_at: '2026-11-08T00:00:00Z', updated_at: '2026-11-08T00:00:00Z', deleted_at: null },
]
export const sampleCards = [
  { id: cardId, topic_id: topicId, section: null, category: 'TypeScript', question: 'Что такое unknown?', context: 'Сравните с any.', answer: 'Тип с обязательным сужением.', hint_1: 'Нужна проверка типа.', hint_2: 'Используйте typeof.', difficulty: 'medium', code: 'typeof value === "string"', created_at: '2026-11-08T00:00:00Z', updated_at: '2026-11-08T00:00:00Z', deleted_at: null },
]
export type MockCard = Omit<(typeof sampleCards)[number], 'section' | 'category' | 'difficulty' | 'deleted_at'> & {
  section: string | null
  category: string | null
  difficulty: 'easy' | 'medium' | 'hard'
  deleted_at: string | null
}

export async function mockContent(page: Page, options: ContentOptions = {}) {
  await page.route('**/rest/v1/**', route => {
    const url = new URL(route.request().url())
    if (url.pathname.endsWith('/rpc/get_training_stats')) {
      const ids = options.topics?.filter(item => !item.deleted_at).map(item => item.id) ?? []
      const due = (options.cards ?? []).filter(item => !item.deleted_at && ids.includes(item.topic_id)).length
      return route.fulfill({ json: { answers: 0, correct: 0, incorrect: 0, learning: 0, mastered: 0, due } })
    }
    if (url.pathname.endsWith('/topics')) {
      if (options.failTopics) return route.abort('failed')
      const items = (options.topics ?? []).filter(item => !item.deleted_at)
      return route.fulfill({ json: items })
    }
    if (url.pathname.endsWith('/cards')) {
      if (options.failCards && url.searchParams.get('select') !== 'id,topic_id') return route.abort('failed')
      const ids = options.topics?.filter(item => !item.deleted_at).map(item => item.id) ?? []
      const items = (options.cards ?? []).filter(item => !item.deleted_at && ids.includes(item.topic_id))
      return route.fulfill({ json: url.searchParams.get('select') === 'id,topic_id' ? items.map(({ id, topic_id }) => ({ id, topic_id })) : items })
    }
    return route.fulfill({ status: 404 })
  })
}
