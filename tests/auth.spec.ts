import { expect, test } from '@playwright/test'
import { mockOwnerSignIn } from './mock-owner'

test('неавторизованный посетитель видит только экран входа', async ({ page }) => {
  await page.goto('/#dashboard')
  await expect(page.getByRole('heading', { name: 'Вход в приложение' })).toBeVisible()
  await expect(page.getByLabel('Email')).toBeVisible()
  await expect(page.getByLabel('Пароль')).toHaveAttribute('type', 'password')
  await expect(page.getByRole('button', { name: 'Войти' })).toBeVisible()
  await expect(page.getByRole('heading', { name: /Что повторить сегодня/ })).toHaveCount(0)
  await expect(page.getByRole('link', { name: /регистрация/i })).toHaveCount(0)

  await page.reload()
  await expect(page.getByRole('heading', { name: 'Вход в приложение' })).toBeVisible()
  await page.goto('/#training')
  await expect(page.getByRole('heading', { name: 'Вход в приложение' })).toBeVisible()
  await expect(page.locator('.training-card')).toHaveCount(0)
})

test('вход, восстановление сессии и выход', async ({ page }) => {
  await mockOwnerSignIn(page)

  await page.reload()
  await expect(page.getByRole('heading', { name: /Что повторить сегодня/ })).toBeVisible()
  await page.getByRole('button', { name: 'Выйти из аккаунта' }).click()
  await expect(page.getByRole('heading', { name: 'Вход в приложение' })).toBeVisible()
})
