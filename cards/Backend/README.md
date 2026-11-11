# Backend: учебные карточки

Каждый YAML-файл содержит карточки одной подтемы. `draft` означает, что содержание ещё обсуждается и не считается окончательно одобренным.

| Подтема | Карточек | Файлы |
|---|---:|---|
| Java Core | 40 | [основной набор](01-java-core/01-java-core-draft.yaml) · [дополнения](01-java-core/02-java-core-middle-plus-draft.yaml) |
| Collections и Generics | 32 | [основной набор](02-collections-generics/01-collections-generics-draft.yaml) · [дополнения](02-collections-generics/02-collections-generics-essential-additions-draft.yaml) |
| Stream API и функциональный стиль | 26 | [основной набор](03-stream-api-functional/01-03-stream-api-functional-draft.yaml) · [дополнения](03-stream-api-functional/02-03-stream-api-functional-essential-additions-draft.yaml) |
| Многопоточность | 31 | [основной набор](04-concurrency/01-04-concurrency-draft.yaml) · [дополнения](04-concurrency/02-04-concurrency-essential-additions-draft.yaml) |
| JVM и производительность | 28 | [основной набор](05-jvm-performance/01-05-jvm-performance-draft.yaml) · [дополнения](05-jvm-performance/02-05-jvm-performance-essential-additions-draft.yaml) |
| Spring Core и Spring Boot | 27 | [основной набор](06-spring-core-boot/01-06-spring-core-boot-draft.yaml) · [дополнения](06-spring-core-boot/02-06-spring-core-boot-essential-additions-draft.yaml) |
| Spring Web и API | 27 | [основной набор](07-spring-web-api/01-07-spring-web-api-draft.yaml) · [дополнения](07-spring-web-api/02-07-spring-web-api-essential-additions-draft.yaml) |
| Spring Data и JPA | 28 | [основной набор](08-spring-data/01-08-spring-data-draft.yaml) · [дополнения](08-spring-data/02-08-spring-data-essential-additions-draft.yaml) |
| SQL и PostgreSQL | 28 | [основной набор](09-sql-postgresql/01-09-sql-postgresql-draft.yaml) · [дополнения](09-sql-postgresql/02-09-sql-postgresql-essential-additions-draft.yaml) |
| Транзакции и согласованность | 25 | [основной набор](10-transactions-consistency/01-10-transactions-consistency-draft.yaml) · [дополнения](10-transactions-consistency/02-10-transactions-consistency-essential-additions-draft.yaml) |
| Kafka | 26 | [основной набор](11-kafka/01-11-kafka-draft.yaml) · [дополнения](11-kafka/02-11-kafka-essential-additions-draft.yaml) |
| ArtemisMQ и JMS | 25 | [основной набор](12-artemismq-jms/01-12-artemismq-jms-draft.yaml) · [дополнения](12-artemismq-jms/02-12-artemismq-jms-essential-additions-draft.yaml) |
| Архитектура и проектирование | 24 | [основной набор](13-architecture-design/01-13-architecture-design-draft.yaml) · [дополнения](13-architecture-design/02-13-architecture-design-essential-additions-draft.yaml) |
| Паттерны интеграции и надёжности | 26 | [основной набор](14-integration-reliability-patterns/01-14-integration-reliability-patterns-draft.yaml) · [дополнения](14-integration-reliability-patterns/02-14-integration-reliability-patterns-essential-additions-draft.yaml) |
| Безопасность backend | 26 | [основной набор](15-backend-security/01-15-backend-security-draft.yaml) · [дополнения](15-backend-security/02-15-backend-security-essential-additions-draft.yaml) |

**Итого:** 419 карточек. Расширенный черновик Java Core на 248 карточек сохранён в [архиве](../../docs/content-archive/java-core-expanded-248-draft.yaml); он не входит в текущие 419 карточек.

Текущий скрипт импорта приложения читает только `01-java-core/01-java-core-draft.yaml`. Остальные карточки находятся в YAML и ещё не импортированы в приложение.
