import { readFileSync } from 'node:fs'
import { expect, test } from '@playwright/test'
import { parse } from 'yaml'
import { mockOwnerSignIn, sampleCards, sampleTopics, topicId, type MockCard } from './mock-owner'
import { mockTrainingApi } from './mock-training'

type SourceCard = Pick<MockCard, 'id' | 'question' | 'answer' | 'category' | 'context' | 'hint_1' | 'hint_2' | 'difficulty' | 'code'>
const source = parse(readFileSync('cards/Backend/01-java-core.yaml', 'utf8')) as { cards: SourceCard[] }
const originalCards = source.cards.slice(0, 20)
const cards: MockCard[] = originalCards.map(card => ({
  ...sampleCards[0]!, ...card, section: '01-java-core', topic_id: topicId,
}))
const topics = [{ ...sampleTopics[0]!, title: 'Backend', description: 'Вопросы по backend-разработке' }]

test('первый раздел Java Core виден с реальными группами, сложностью, ответами и подсказками', async ({ page }) => {
  await mockOwnerSignIn(page, { topics, cards })
  const server = await mockTrainingApi(page, cards)
  await expect(page.getByRole('link', { name: /Backend/ })).toBeVisible()
  await page.goto(`/#topics/${topicId}`)
  await page.getByRole('button', { name: 'Java Core 20' }).click()
  await expect(page.getByRole('button', { name: 'Все группы 20' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Полиморфизм 3' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Объектная модель 3' })).toBeVisible()
  await page.getByRole('button', { name: 'Объектная модель 3' }).click()
  await expect(page.getByRole('heading', { name: originalCards[2]!.question })).toBeVisible()
  await page.getByText('Показать ответ и подсказки').first().click()
  await expect(page.getByText(originalCards[2]!.hint_1!)).toBeVisible()
  await expect(page.getByText(originalCards[2]!.hint_2!)).toBeVisible()
  await expect(page.getByText(originalCards[2]!.answer)).toBeVisible()

  await page.getByRole('button', { name: 'Полиморфизм 3' }).click()
  await page.getByLabel('Сложность').selectOption('hard')
  await expect(page.getByText('Карточки · 1')).toBeVisible()
  await expect(page.getByRole('heading', { name: originalCards[6]!.question })).toBeVisible()
  await page.getByRole('link', { name: 'Тренироваться' }).click()
  await page.getByRole('button', { name: 'Продолжить' }).click()
  await expect(page.getByRole('heading', { name: originalCards[6]!.question })).toBeVisible()
  expect(server.sessions[0]?.attempts.map(item => item.card.id)).toEqual([originalCards[6]!.id])
  await page.reload()
  await expect(page.getByRole('heading', { name: originalCards[6]!.question })).toBeVisible()
  expect(server.sessions).toHaveLength(1)
  await page.getByRole('link', { name: 'К выбору раздела' }).click()
  await page.getByLabel('Сложность').selectOption('easy')
  await expect(page.getByText('Нет карточек с выбранными фильтрами')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Нет карточек для тренировки' })).toBeDisabled()
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(page.viewportSize()!.width)
})
