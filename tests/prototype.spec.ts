import { expect, test } from '@playwright/test'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { MarkdownAnswer } from '../src/features/training/MarkdownAnswer'
import { mockOwnerSignIn, sampleCards, sampleTopics } from './mock-owner'

test('основные экраны сохраняют мобильную адаптацию', async ({ page }) => {
  await mockOwnerSignIn(page, { topics: sampleTopics, cards: sampleCards })
  for (const hash of ['dashboard', 'topics', 'statistics', 'training']) {
    await page.goto(`/#${hash}`)
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 844 })
      expect(await page.evaluate(() => document.documentElement.scrollWidth), `${hash} at ${width}px`).toBeLessThanOrEqual(width)
    }
  }
})

test('Markdown ответа сохраняет безопасное форматирование', () => {
  const answer = '# Ответ\n\n**Важное** и `inlineCode`.\n\n[Небезопасная ссылка](javascript:alert(1))\n\n<script>alert(1)</script>'
  const html = renderToStaticMarkup(createElement(MarkdownAnswer, { answer }))
  expect(html).toContain('<h1>Ответ</h1>')
  expect(html).toContain('<strong>Важное</strong>')
  expect(html).not.toContain('href="javascript:')
  expect(html).not.toContain('<script')
})
