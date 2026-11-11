import { expect, test } from '@playwright/test'
import { mockOwnerSignIn, sampleCards, sampleTopics, topicId, type MockCard } from './mock-owner'
import { mockTrainingApi } from './mock-training'

function card(id: string, category: string | null, difficulty: MockCard['difficulty'], question: string, section: string | null = null): MockCard {
  return { ...sampleCards[0]!, id, section, category, difficulty, question }
}

test('раздел, группа и сложность выбираются последовательно и фильтруют spaced на сервере', async ({ page }) => {
  const cards: MockCard[] = [
    ...sampleCards,
    card('33000000-0000-4000-8000-000000000061', 'Многопоточность', 'hard', 'Hard thread?', '04-concurrency'),
    card('33000000-0000-4000-8000-000000000062', 'Многопоточность', 'easy', 'Easy thread?', '04-concurrency'),
    card('33000000-0000-4000-8000-000000000063', null, 'hard', 'No category?'),
    card('33000000-0000-4000-8000-000000000064', '   ', 'medium', 'Blank category?'),
    card('33000000-0000-4000-8000-000000000065', 'C++ / JVM & Kafka', 'hard', 'Special?', '03-stream-api-functional'),
  ]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  const server = await mockTrainingApi(page, cards)
  await page.goto(`/#topics/${topicId}`)
  await expect(page.getByRole('button', { name: 'Concurrency 2' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Без раздела 3' })).toBeVisible()
  const sectionButtons = page.getByLabel('Разделы').getByRole('button')
  await expect(sectionButtons.nth(1)).toContainText('Stream Api Functional')
  await expect(sectionButtons.nth(2)).toContainText('Concurrency')
  await expect(sectionButtons.nth(3)).toContainText('Без раздела')
  await page.getByRole('button', { name: 'Concurrency 2' }).click()
  await expect(page.getByRole('button', { name: 'Многопоточность 2' })).toBeVisible()
  await page.getByRole('button', { name: 'Многопоточность 2' }).click()
  await page.getByLabel('Сложность').selectOption('hard')
  await expect(page.getByText('Карточки · 1')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Hard thread?' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Easy thread?' })).toHaveCount(0)
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await expect(page.getByText('Concurrency · Многопоточность · Сложно')).toBeVisible()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await expect(page.getByRole('heading', { name: 'Hard thread?' })).toBeVisible()
  expect(server.sessions[0]?.attempts.map(item => item.card.question)).toEqual(['Hard thread?'])
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Hard thread?' })).toBeVisible()
  expect(server.sessions).toHaveLength(1)
  await page.getByRole('button', { name: 'Показать ответ' }).click()
  await page.getByRole('button', { name: 'Знал', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Тренировка завершена' })).toBeVisible()
  await page.getByRole('link', { name: 'К выбору раздела' }).last().click()
  await expect(page.getByLabel('Сложность')).toHaveValue('hard')
  await expect(page.getByRole('button', { name: 'Concurrency 2' })).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByRole('button', { name: 'Многопоточность 2' })).toHaveAttribute('aria-pressed', 'true')
  await page.setViewportSize({ width: 320, height: 844 })
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320)
})

test('смена фильтров предлагает продолжить текущую сессию или завершить её', async ({ page }) => {
  const cards: MockCard[] = [
    card('33000000-0000-4000-8000-000000000066', 'Многопоточность', 'hard', 'Hard?', '01-java-core'),
    card('33000000-0000-4000-8000-000000000067', 'Многопоточность', 'easy', 'Easy?', '02-collections-generics'),
  ]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  const server = await mockTrainingApi(page, cards)
  await page.goto(`/#topics/${topicId}`)
  await page.getByRole('button', { name: 'Java Core 1' }).click()
  await page.getByRole('button', { name: 'Многопоточность 1' }).click()
  await page.getByLabel('Сложность').selectOption('hard')
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await page.getByRole('radio', { name: 'Свободная практика' }).check()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await expect(page.getByRole('heading', { name: 'Hard?' })).toBeVisible()
  await page.getByRole('link', { name: 'К выбору раздела' }).click()
  await page.getByRole('button', { name: 'Collections Generics 1' }).click()
  await page.getByRole('button', { name: 'Многопоточность 1' }).click()
  await page.getByLabel('Сложность').selectOption('easy')
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await page.getByRole('radio', { name: 'Свободная практика' }).check()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await expect(page.getByRole('heading', { name: 'Уже есть активная тренировка' })).toBeVisible()
  await expect(page.getByText('Текущие фильтры: Java Core · Многопоточность · Сложно.')).toBeVisible()
  await page.getByRole('button', { name: 'Продолжить текущую' }).click()
  await expect(page.getByRole('heading', { name: 'Hard?' })).toBeVisible()
  expect(server.sessions).toHaveLength(1)
  await page.getByRole('link', { name: 'К выбору раздела' }).click()
  await page.getByRole('button', { name: 'Collections Generics 1' }).click()
  await page.getByRole('button', { name: 'Многопоточность 1' }).click()
  await page.getByLabel('Сложность').selectOption('easy')
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await page.getByRole('radio', { name: 'Свободная практика' }).check()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await page.getByRole('button', { name: 'Завершить и начать новую' }).click()
  await expect(page.getByRole('heading', { name: 'Easy?' })).toBeVisible()
  expect(server.sessions).toHaveLength(2)
  expect(server.sessions[0]?.status).toBe('abandoned')
})

test('карточки без раздела и группы и пустой фильтр видны на мобильном экране', async ({ page }, testInfo) => {
  const cards: MockCard[] = [card('33000000-0000-4000-8000-000000000068', null, 'easy', 'No category?')]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  await mockTrainingApi(page, cards)
  await page.goto(`/#topics/${topicId}`)
  await page.getByRole('button', { name: 'Без раздела 1' }).click()
  await page.getByRole('button', { name: 'Без группы 1' }).click()
  await page.getByLabel('Сложность').selectOption('hard')
  await expect(page.getByText('Нет карточек с выбранными фильтрами')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Нет карточек для тренировки' })).toBeDisabled()
  await page.getByLabel('Сложность').selectOption('easy')
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await expect(page.getByRole('heading', { name: 'No category?' })).toBeVisible()
  if (testInfo.project.name === 'iphone-webkit') {
    const width = await page.locator('.training-screen').evaluate(element => element.getBoundingClientRect().width)
    expect(width).toBeLessThanOrEqual(page.viewportSize()!.width)
  }
})

test('фильтры действуют в infinite и mistakes без изменения интервального прогресса', async ({ page }) => {
  const cards: MockCard[] = [
    card('33000000-0000-4000-8000-000000000069', 'Типы и ссылки', 'hard', 'Java hard?', '01-java-core'),
    card('33000000-0000-4000-8000-000000000070', 'Типы и ссылки', 'easy', 'Java easy?', '01-java-core'),
    card('33000000-0000-4000-8000-000000000071', 'Типы и ссылки', 'hard', 'JVM hard?', '05-jvm-performance'),
  ]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  const server = await mockTrainingApi(page, cards)
  await page.goto(`/#training?topic=${topicId}&mode=spaced&section_mode=named&section=01-java-core&category_mode=named&category=${encodeURIComponent('Типы и ссылки')}&difficulty=hard`)
  await expect(page.getByRole('heading', { name: 'Java hard?' })).toBeVisible()
  await page.getByRole('button', { name: 'Показать ответ' }).click()
  await page.getByRole('button', { name: 'Не знал' }).click()
  await expect(page.getByRole('heading', { name: 'Тренировка завершена' })).toBeVisible()
  expect(server.progress.get(cards[0]!.id)?.incorrect).toBe(1)

  await page.goto(`/#training?topic=${topicId}&mode=mistakes&section_mode=named&section=01-java-core&category_mode=named&category=${encodeURIComponent('Типы и ссылки')}&difficulty=hard`)
  await expect(page.getByRole('heading', { name: 'Java hard?' })).toBeVisible()
  await page.getByRole('button', { name: 'Показать ответ' }).click()
  await page.getByRole('button', { name: 'Знал', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Тренировка завершена' })).toBeVisible()
  expect(server.progress.get(cards[0]!.id)?.incorrect).toBe(1)

  await page.goto(`/#training?topic=${topicId}&mode=infinite&section_mode=named&section=01-java-core&category_mode=named&category=${encodeURIComponent('Типы и ссылки')}&difficulty=easy`)
  await expect(page.getByRole('heading', { name: 'Java easy?' })).toBeVisible()
  await page.getByRole('button', { name: 'Показать ответ' }).click()
  await page.getByRole('button', { name: 'Знал', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Java easy?' })).toBeVisible()
  expect(server.progress.has(cards[1]!.id)).toBe(false)
  expect(server.sessions.map(item => item.attempts[0]?.card.question)).toEqual(['Java hard?', 'Java hard?', 'Java easy?'])
})

test('тренировка всего направления включает разные разделы и старые карточки без раздела', async ({ page }) => {
  const cards: MockCard[] = [
    card('33000000-0000-4000-8000-000000000072', 'Типы', 'easy', 'Java?', '01-java-core'),
    card('33000000-0000-4000-8000-000000000073', 'Типы', 'medium', 'Collections?', '02-collections-generics'),
    card('33000000-0000-4000-8000-000000000074', null, 'hard', 'Legacy?'),
  ]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  const server = await mockTrainingApi(page, cards)
  await page.goto(`/#training?topic=${topicId}&mode=spaced`)
  await expect(page.getByText('Оценено: 0 / 3')).toBeVisible()
  expect(server.sessions[0]?.attempts.map(item => item.card.question)).toEqual(['Java?', 'Collections?', 'Legacy?'])
  await expect(page.getByText('Все разделы · Все группы · Все сложности')).toBeVisible()
})

test('изменение раздела выданной карточки не записывает ответ и позволяет продолжить', async ({ page }) => {
  const cards: MockCard[] = [
    card('33000000-0000-4000-8000-000000000075', 'Типы', 'easy', 'Moved?', '01-java-core'),
    card('33000000-0000-4000-8000-000000000076', 'Типы', 'easy', 'Next?', '01-java-core'),
  ]
  await mockOwnerSignIn(page, { topics: sampleTopics, cards })
  const server = await mockTrainingApi(page, cards)
  await page.goto(`/#training?topic=${topicId}&mode=spaced&section_mode=named&section=01-java-core`)
  await expect(page.getByRole('heading', { name: 'Moved?' })).toBeVisible()
  await page.getByRole('button', { name: 'Показать ответ' }).click()
  cards[0]!.section = '02-collections-generics'
  await page.getByRole('button', { name: 'Знал', exact: true }).click()
  await expect(page.getByRole('alert')).toContainText('Карточка изменилась')
  expect(server.history).toHaveLength(0)
  await page.getByRole('button', { name: 'Повторить' }).click()
  await expect(page.getByRole('heading', { name: 'Next?' })).toBeVisible()
})
