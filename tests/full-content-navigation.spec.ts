import { readFileSync } from 'node:fs'
import { expect, test } from '@playwright/test'
import { parse } from 'yaml'
import { mockOwnerSignIn, sampleCards, sampleTopics, type MockCard } from './mock-owner'

const directions = [
  ['Backend', '02-collections-generics'],
  ['Analysis', '01-requirements-elicitation'],
  ['Testing', '01-testing-strategy-levels'],
  ['DevOps', '01-linux-processes-files'],
  ['LiveCoding', '01-problem-solving-complexity'],
  ['ProductEngineering', '01-end-to-end-delivery'],
] as const

test('шесть направлений из новой структуры доступны по разделам и группам', async ({ page }) => {
  const topics = directions.map(([name], index) => ({
    ...sampleTopics[0]!, id: `22000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
    title: name, description: null, sort_order: index + 1,
  }))
  const cards: MockCard[] = directions.map(([name, section], index) => {
    const source = parse(readFileSync(`cards/${name}/${section}.yaml`, 'utf8')) as { cards: MockCard[] }
    return { ...sampleCards[0]!, ...source.cards[0]!, topic_id: topics[index]!.id, section }
  })
  await mockOwnerSignIn(page, { topics, cards })
  for (const topic of topics) await expect(page.getByRole('link', { name: new RegExp(topic.title) })).toBeVisible()
  const product = topics.at(-1)!
  await page.goto(`/#topics/${product.id}`)
  await page.getByRole('button', { name: /End To End Delivery 1/ }).click()
  await expect(page.getByRole('heading', { name: cards.at(-1)!.question })).toBeVisible()
  await expect(page.getByRole('button', { name: `${cards.at(-1)!.category} 1` })).toBeVisible()
})
