# LiveCoding: учебные карточки

Набор для коротких ежедневных занятий с телефона на уровне middle/middle+. В карточках с задачей сначала дано условие, затем в `answer` — шаги решения и сложность, а в `code` — реализация. Кодовый блок в приложении прокручивается: строки можно добавлять ради понятности, без искусственного ограничения длины; большие самостоятельные программы в карточку не помещаем. Примеры Java ориентированы на Java 21+, стандартные импорты опущены; фрагменты предполагают окружающий класс и объявленные в условии типы. `draft` означает статус контента до импорта.

| Подтема | Карточек | Файлы |
|---|---:|---|
| Подход к задаче и сложность | 24 | [YAML](01-problem-solving-complexity/01-01-problem-solving-complexity-draft.yaml) |
| Паттерны решения задач | 25 | [YAML](02-solution-patterns/01-02-solution-patterns-draft.yaml) |
| Популярные алгоритмические задачи | 20 | [основной набор](03-common-algorithm-tasks/01-03-common-algorithm-tasks-draft.yaml) · [дополнения](03-common-algorithm-tasks/02-03-common-algorithm-tasks-essential-additions-draft.yaml) |
| Java и Collections: практические задачи | 19 | [основной набор](04-java-collections-tasks/01-04-java-collections-tasks-draft.yaml) · [дополнения](04-java-collections-tasks/02-04-java-collections-tasks-essential-additions-draft.yaml) |
| Stream API: практические задачи | 18 | [YAML](05-stream-api-tasks/01-05-stream-api-tasks-draft.yaml) |
| SQL-задачи PostgreSQL | 20 | [YAML](06-sql-tasks/01-06-sql-tasks-draft.yaml) |
| Многопоточность: задачи по коду | 17 | [YAML](07-concurrency-code/01-07-concurrency-code-draft.yaml) |
| Чтение кода и debugging | 21 | [основной набор](08-code-reading-debugging/01-08-code-reading-debugging-draft.yaml) · [дополнения](08-code-reading-debugging/02-08-code-reading-debugging-essential-additions-draft.yaml) |
| Рефакторинг и code review | 20 | [YAML](09-refactoring-code-review/01-09-refactoring-code-review-draft.yaml) |

**Итого:** 184 карточки. В каждой подтеме не более 40; короткие ответы важнее заполнения квоты.

Для выбора формата и проверки фактов использованы [описание алгоритмических интервью Яндекса](https://habr.com/ru/companies/yandex/articles/449890/), [Java Stream API](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/stream/package-summary.html) и [документация PostgreSQL по оконным функциям](https://www.postgresql.org/docs/current/tutorial-window.html).

