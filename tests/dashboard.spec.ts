import { expect, test } from '@playwright/test'
import { cardId, mockOwnerSignIn, sampleCards, sampleTopics, topicId } from './mock-owner'

test('реальные темы, карточки, поля и сортировка отображаются без демоданных', async ({ page }) => {
  const queries: string[] = []
  page.on('request', request => { if (request.url().includes('/rest/v1/')) queries.push(request.url()) })
  await mockOwnerSignIn(page, { topics: sampleTopics, cards: sampleCards })
  await expect(page.getByRole('heading', { name: /Что повторить сегодня/ })).toBeVisible()
  await expect(page.locator('.topic-row')).toHaveCount(1)
  await expect(page.locator('.topic-row')).toContainText('Разработка')
  await expect(page.locator('.topic-row')).toContainText('1 карточка')
  await expect(page.locator('.db-review-count strong')).toHaveText('1')
  await expect(page.getByText('LVL 12')).toHaveCount(0)
  await expect(page.getByText('7 дней')).toHaveCount(0)
  await expect(page.getByText('Первый шаг')).toHaveCount(0)
  await expect(page.getByRole('button', { name: /создать.*тему/i })).toHaveCount(0)

  await page.locator('.topic-row').click()
  await expect(page).toHaveURL(new RegExp(`#topics/${topicId}$`))
  await expect(page.getByRole('heading', { name: 'Что такое unknown?' })).toBeVisible()
  await expect(page.getByText('Без раздела · TypeScript · Средне')).toBeVisible()
  await expect(page.getByText('Сравните с any.')).toBeVisible()
  await page.getByText('Показать ответ и подсказки').click()
  await expect(page.getByText('Нужна проверка типа.')).toBeVisible()
  await expect(page.getByText('Используйте typeof.')).toBeVisible()
  await expect(page.getByText('Тип с обязательным сужением.')).toBeVisible()
  await expect(page.locator('pre code')).toHaveText('typeof value === "string"')
  expect(queries.some(url => url.includes('topics?') && url.includes('deleted_at=is.null') && url.includes('sort_order.asc'))).toBeTruthy()
  expect(queries.some(url => url.includes('cards?') && url.includes('deleted_at=is.null') && url.includes(`topic_id=eq.${topicId}`))).toBeTruthy()
  expect(cardId).toBeTruthy()
})

test('пустая база не подменяется демонстрационными темами', async ({ page }) => {
  await mockOwnerSignIn(page)
  await expect(page.getByText('Пока нет направлений')).toBeVisible()
  await expect(page.locator('.topic-row')).toHaveCount(0)
  await expect(page.locator('.db-review-count strong')).toHaveText('0')
  await page.goto('/#topics')
  await expect(page.getByText('Пока нет направлений')).toBeVisible()
  await expect(page.getByText('Разработка')).toHaveCount(0)
  await expect(page.getByRole('button', { name: /создать/i })).toHaveCount(0)
})

test('ошибку загрузки можно повторить без показа устаревших данных', async ({ page }) => {
  await mockOwnerSignIn(page, { failTopics: true })
  await expect(page.getByRole('alert')).toContainText('Не удалось загрузить темы и карточки')
  await expect(page.locator('.topic-row')).toHaveCount(0)
  await page.getByRole('button', { name: 'Повторить загрузку' }).click()
  await expect(page.getByRole('alert')).toContainText('Не удалось загрузить темы и карточки')
})

test('ошибка загрузки карточек отображается внутри темы', async ({ page }) => {
  await mockOwnerSignIn(page, { topics: sampleTopics, failCards: true })
  await page.locator('.topic-row').click()
  await expect(page.getByRole('alert')).toContainText('Не удалось загрузить карточки')
  await expect(page.getByText('Что такое unknown?')).toHaveCount(0)
})

test('статистика показывает только учебные показатели', async ({ page }) => {
  await mockOwnerSignIn(page, { topics: sampleTopics, cards: sampleCards })
  await page.goto('/#statistics')
  await expect(page.getByText('Всего ответов')).toBeVisible()
  await expect(page.locator('.metric').filter({ hasText: 'Активных карточек' }).locator('.metric-value')).toHaveText('1')
  await expect(page.locator('.metric').filter({ hasText: 'Новые' }).locator('.metric-value')).toHaveText('1')
  await expect(page.locator('.metric').filter({ hasText: 'Всего ответов' }).locator('.metric-value')).toHaveText('0')
  await expect(page.locator('.metric').filter({ hasText: 'Процент правильных ответов' }).locator('.metric-value')).toHaveText('—')
  await page.goto('/#achievements')
  await expect(page.getByRole('heading', { name: /Что повторить сегодня/ })).toBeVisible()
  await expect(page.getByText('Достижения пока недоступны')).toHaveCount(0)
  await expect(page.getByText('XP')).toHaveCount(0)
})
