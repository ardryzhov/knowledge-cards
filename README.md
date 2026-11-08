# Knowledge Cards

Персональный тренажёр знаний. Реализован **этап 0 — визуальный прототип** по [AGENT_PLAN.md](./AGENT_PLAN.md).

Три адаптивных экрана: Dashboard, Training и Statistics. Все показатели и карточки — **DEMO**. Учебные ответы хранятся только в памяти и сбрасываются при обновлении страницы или уходе с экрана тренировки.

## Локальный запуск

Нужен Node.js 22.12+ и npm. Проверено на Node.js 26.13.0.

```sh
npm ci
npm run dev
```

Открой адрес из терминала (обычно `http://127.0.0.1:5173`).

- `/#dashboard` — обзор, XP, уровень, streak, темы, активность и достижения.
- `/#training` — подсказки, таймер, переворот карточки, оценка и итог демо-сессии.
- `/#statistics` — метрики, графики и фильтры периода/режима.

Из карточек направлений можно перейти к демо-тренировке по конкретной теме. В тренировке сначала открой ответ, затем оцени его кнопками или горизонтальным свайпом. Длинный ответ прокручивается внутри карточки. Таймер не ставит автоматическую ошибку.

## Проверки

```sh
npm run typecheck
npm run build
npx playwright install chromium webkit
npm run test:e2e
```

`test:e2e` собирает приложение и запускает проверки production-сборки в Chromium и WebKit с профилем iPhone 13. Тесты проверяют экраны на ширинах 320, 375, 390, 430, 768, 1024 и 1440 px, навигацию, подсказки, оценку, таймер, фильтры и reduced motion. Проверка жеста в мобильном WebKit использует синтетические Pointer Events; физический iPhone всё ещё нужен для ручной проверки нативных жестов.

Посмотреть production-сборку:

```sh
npm run build
npm run preview
```

## Стек и структура

React, TypeScript strict, Vite, Tailwind CSS, компоненты shadcn/ui с исходниками в проекте, Geist Mono/Geist, Lucide, Recharts и Motion.

```text
src/
  app/                  # Компоновка приложения и hash-переходы прототипа
  components/
    ui/                 # Button, Card
    layout/             # Sidebar, мобильная навигация, заголовки
    charts/             # Графики Recharts
  features/
    dashboard/          # Экран обзора
    training/           # Интерактивная демо-сессия
    statistics/         # Демонстрационная аналитика
  data/demo.ts          # Только демонстрационные данные
  lib/utils.ts          # Объединение CSS-классов для shadcn/ui
  styles/
    tokens.css          # Палитра из ТЗ
    globals.css         # Tailwind, оформление, адаптивность
tests/                  # Браузерные проверки
docs/screenshots/       # Скриншоты трёх экранов: desktop и mobile
```

Шрифты поставляются локально через Fontsource; внешние сервисы для их загрузки не нужны. Графики и Motion вынесены в отдельные сборочные файлы.

## Скриншоты

| Экран | Desktop | Mobile |
| --- | --- | --- |
| Dashboard | [Посмотреть](docs/screenshots/dashboard-desktop.png) | [Посмотреть](docs/screenshots/dashboard-mobile.png) |
| Training | [Посмотреть](docs/screenshots/training-desktop.png) | [Посмотреть](docs/screenshots/training-mobile.png) |
| Statistics | [Посмотреть](docs/screenshots/statistics-desktop.png) | [Посмотреть](docs/screenshots/statistics-mobile.png) |

## Границы этапа 0

Supabase, авторизация, хранение прогресса, реальный XP, интервальные алгоритмы, полноценный бесконечный режим и PWA пока не реализованы. Переключение режимов демонстрирует интерфейс, оба режима используют короткий список карточек. Показатели Dashboard и Statistics не меняются от демо-ответов; пример XP на экране завершения явно помечен как DEMO.

Hash-переходы нужны только для трёх экранов прототипа. React Router и инфраструктура состояния относятся к этапу 1. Публикация на GitHub Pages относится к этапу 9.

Для продолжения требуется согласование внешнего вида и подтверждение перехода к этапу 1.
# knowledge-cards
