# Backend: учебные карточки

Каждый YAML-файл содержит полный набор карточек одной подтемы для передачи агенту, который занимается импортом.

| Подтема | Карточек | Файлы |
|---|---:|---|
| Java Core | 40 | [карточки](01-java-core.yaml) |
| Collections и Generics | 33 | [карточки](02-collections-generics.yaml) |
| Stream API и функциональный стиль | 26 | [карточки](03-stream-api-functional.yaml) |
| Многопоточность | 32 | [карточки](04-concurrency.yaml) |
| JVM и производительность | 29 | [карточки](05-jvm-performance.yaml) |
| Spring Core и Spring Boot | 28 | [карточки](06-spring-core-boot.yaml) |
| Spring Web и API | 27 | [карточки](07-spring-web-api.yaml) |
| Spring Data и JPA | 28 | [карточки](08-spring-data.yaml) |
| SQL и PostgreSQL | 28 | [карточки](09-sql-postgresql.yaml) |
| Транзакции и согласованность | 25 | [карточки](10-transactions-consistency.yaml) |
| Kafka | 26 | [карточки](11-kafka.yaml) |
| ArtemisMQ и JMS | 25 | [карточки](12-artemismq-jms.yaml) |
| Архитектура и проектирование | 26 | [карточки](13-architecture-design.yaml) |
| Паттерны интеграции и надёжности | 26 | [карточки](14-integration-reliability-patterns.yaml) |
| Безопасность backend | 26 | [карточки](15-backend-security.yaml) |

**Итого:** 425 карточек. Расширенный черновик Java Core на 248 карточек сохранён в [архиве](../../docs/content-archive/java-core-expanded-248-draft.yaml); он не входит в текущие 425 карточек.

Полный набор Backend включён в `supabase/migrations/20261112000200_backend_content.sql`. Проверка соответствия YAML: `node scripts/generate-content-migrations.mjs --check`. Прежняя миграция первых 20 Java Core остаётся неизменной; новый импорт расширяет раздел с теми же UUID первых карточек.
