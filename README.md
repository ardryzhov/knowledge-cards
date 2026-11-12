# Knowledge Cards

Персональное приложение для изучения карточек и интервальных повторений. Интерфейс написан на React, TypeScript и Vite; авторизация, контент и прогресс хранятся в Supabase. Учебные материалы добавляются SQL-миграциями, без редактора в приложении.

## Локальный запуск

Нужны Node.js 22 и npm. Создайте `.env.local` по образцу `.env.example` с URL проекта и publishable key Supabase. Не используйте во фронтенде `service_role` или secret key.

```sh
npm ci
npm run dev
```

## Проверки

```sh
npm run typecheck
npm run lint
npx supabase db start
npx supabase test db
npx playwright install chromium webkit
npm run test:e2e
```

E2E собирает приложение с тестовыми параметрами Supabase и не обращается к рабочей базе. Для сборки под GitHub Pages используйте **отдельную** команду `npm run build:pages` с рабочими `VITE_SUPABASE_URL` и `VITE_SUPABASE_PUBLISHABLE_KEY`.

## Публикация на GitHub Pages

Репозиторий `ardryzhov/knowledge-cards` публикуется по адресу `https://ardryzhov.github.io/knowledge-cards/`. Команда `npm run build:pages` задаёт Vite путь `/knowledge-cards/`; менять его потребуется, если изменится имя репозитория или появится собственный домен.

1. Сделайте репозиторий публичным. На бесплатном плане GitHub Pages не публикует приватный репозиторий. Исходные YAML-файлы в публичном репозитории также станут доступны всем.
2. В GitHub откройте **Settings → Secrets and variables → Actions → Repository secrets** и добавьте `VITE_SUPABASE_URL` и `VITE_SUPABASE_PUBLISHABLE_KEY`. Это параметры клиентской сборки: после публикации они видны в браузере. Доступ к данным защищает Supabase Auth и RLS.
3. В **Settings → Pages → Build and deployment → Source** выберите **GitHub Actions**.
4. В Supabase Dashboard откройте **Authentication → URL Configuration**: задайте **Site URL** `https://ardryzhov.github.io/knowledge-cards/` и добавьте этот адрес в **Redirect URLs** для будущих ссылок авторизации. Локальный URL можно оставить среди дополнительных адресов.
5. Добавьте workflow из `.github/workflows/pages.yml` в ветку `main`, затем создайте от актуального `main` ветку вида `release/1.0.0` и отправьте её в GitHub. Push запускает проверки TypeScript, ESLint, SQL/RLS и Playwright, но **не публикует** сайт.
6. После успешных проверок откройте **Actions → Check and deploy Pages → Run workflow**, в выпадающем списке **Branch** выберите нужную ветку `release/x.y.z` и нажмите **Run workflow**. Ручной запуск повторяет проверки для этого коммита, собирает сайт с рабочим Supabase и публикует его только после их успеха. Файл workflow должен присутствовать в `main`, чтобы GitHub показывал кнопку ручного запуска; сам запуск выполняется на выбранной release-ветке.

Workflow проверяет точный формат имени release-ветки и закрепляет SHA коммита между проверками и сборкой. Приложение использует hash-навигацию, поэтому GitHub Pages не нужны правила перенаправления внутренних маршрутов.

После публикации откройте сайт на телефоне, проверьте вход, список направлений, тренировку и восстановление сессии после обновления страницы. Сайт доступен по HTTPS; офлайн-режим и полноценная установка PWA пока не реализованы.
