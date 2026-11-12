# ProductEngineering: план учебного контента

Эта страница сохраняет согласованную структуру между сессиями. Рабочее имя темы — `ProductEngineering`; предложенное пользователем неформальное отображаемое название — «Восьми-рукий семи-х#й». Уровень карточек — middle/middle+; повторение материала Backend, Analysis, Testing и DevOps сводим к сквозным сценариям.

| № | Подтема | Содержание | Статус |
|---|---|---|---|
| 01 | Сквозное ведение задачи | От запроса до релиза и проверки результата | [карточки](01-end-to-end-delivery.yaml) |
| 02 | Продуктовая ценность и метрики | Цель, основная и ограничивающие метрики, эффект изменения | [карточки](02-product-value-and-metrics.yaml) |
| 03 | Основы работы с ИИ | Возможности, ограничения, постановка задач и итерации | [карточки](03-ai-fundamentals.yaml) |
| 04 | Контекст и агентное окружение | Правила проекта, источники контекста, skills, версии инструкций | [карточки](04-context-and-agent-environment.yaml) |
| 05 | MCP и инструменты | Клиенты, серверы, tools/resources/prompts, подключение и права | [карточки](05-mcp-and-tools.yaml) |
| 06 | Агенты и организация работы | Делегирование, sub-agents, workflows, hooks, сборка результатов | [карточки](06-agents-and-workflows.yaml) |
| 07 | Проверка работы ИИ | Ревью, тесты, фактическая проверка, quality gates | [карточки](07-ai-verification.yaml) |
| 08 | Данные, безопасность и автономность | Секреты, персональные данные, prompt injection, границы действий | [карточки](08-data-safety-autonomy.yaml) |
| 09 | Решения и компромиссы | Архитектурные варианты, проверка предположений, ADR | [карточки](09-decisions-and-tradeoffs.yaml) |
| 10 | Релиз и сопровождение с ИИ | Деплой, диагностика, откат, инциденты | [карточки](10-ai-release-and-operations.yaml) |
| 11 | Оценка пользы ИИ-процесса | Качество, время, стоимость и улучшение агентного процесса | [карточки](11-ai-process-value.yaml) |

Источник требований к роли: [матрица Product Engineer](../../../product-engineer-seniority-matrix/README.md), в особенности [AMPE](../../../product-engineer-seniority-matrix/common-skills/AMPE.md), [BRPE](../../../product-engineer-seniority-matrix/common-skills/BRPE.md), [QAPE](../../../product-engineer-seniority-matrix/common-skills/QAPE.md), [IDPE](../../../product-engineer-seniority-matrix/common-skills/IDPE.md), [SUPE](../../../product-engineer-seniority-matrix/common-skills/SUPE.md) и [MMPE](../../../product-engineer-seniority-matrix/common-skills/MMPE.md).

Технические ориентиры для карточек 05–11: [архитектура MCP](https://modelcontextprotocol.io/docs/learn/architecture), [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [MCP resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources), [MCP prompts](https://modelcontextprotocol.io/specification/2025-11-25/server/prompts), [оценка агентных сценариев](https://developers.openai.com/api/docs/guides/agent-evals), [контроль действий агента](https://developers.openai.com/api/docs/guides/agents/guardrails-approvals), [риски prompt injection](https://genai.owasp.org/llmrisk/llm01-prompt-injection/) и [чрезмерной автономности](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/).

