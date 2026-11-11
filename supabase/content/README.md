# Миграции учебного контента

Темы и карточки добавляются только новыми SQL-файлами в `supabase/migrations/`. В браузере у роли `authenticated` остаётся только чтение этих таблиц после применения `20261109000100_content_read_only.sql`. Существующие миграции не редактируются.

## Первый набор Java Core

Источник: `cards/Backend/01-java-core/01-java-core-draft.yaml`. Каждая из 20 карточек имеет постоянный `id` прямо в YAML. Направление хранится в `topics` как `Backend`, раздел — в `cards.section` как `01-java-core`, исходная группа — в `cards.category`. Вопрос, ответ, контекст, обе подсказки, сложность и код переносятся без изменения текста. Отсутствующие необязательные поля сохраняются как SQL `NULL`.

Миграция `20261112000100_java_core_content.sql` содержит зафиксированный снимок этих данных и UUID владельца, переданный владельцем проекта. Она использует существующий активный `Backend` того же владельца либо создаёт его с постоянным UUID. При отсутствии всех учётных записей в чистой локальной базе импорт пропускается; SQL-тест создаёт нужную запись внутри откатываемой транзакции и вызывает закрытую процедуру импорта. Если в базе есть пользователи, но переданный UUID не найден, миграция прерывается. В облаке перед применением проверьте, что нужная учётная запись существует. Если нет, остановитесь и сначала создайте её через Supabase Dashboard.

После изменения YAML **не перезаписывайте уже применённую миграцию**. Создайте следующую версионированную миграцию с теми же UUID карточек и `INSERT ... ON CONFLICT (id) DO UPDATE`, ограниченным `user_id` и `topic_id`. `deleted_at` не сбрасывайте автоматически. Прогресс и историю ответов не пересоздавайте.

До применения этой миграции можно проверить снимок командой `node scripts/generate-java-core-import.mjs --check`. Команда без `--check` перезаписывает файл миграции и предназначена только для подготовки ещё не применённой версии.

## Перед подготовкой миграции

1. В Supabase Dashboard откройте Authentication → Users и возьмите UUID владельца. Не используйте email как ключ для изменений.
2. Выдайте каждой логической теме и карточке отдельный UUID один раз. Храните этот UUID в последующих миграциях для той же записи. Название вопроса не служит идентификатором: его можно менять без потери `card_progress` и `answer_history`.
3. Проверьте список существующих UUID в миграциях. Новые UUID создавайте один раз, например `crypto.randomUUID()` в локальном Node, и записывайте литералом в SQL. Для 4–5 тем это удобнее отдельного столбца `content_key`; изменение схемы не требуется.
4. Проверьте SQL локально. Применяйте к удалённому проекту вручную после просмотра изменений.

## Шаблон новой миграции

Замените UUID-заглушки на реальные значения. Для каждой карточки используйте её постоянный UUID. Ниже показана одна тема и одна карточка; дополнительные строки добавляются по тому же образцу.

```sql
begin;

do $content$
declare
  v_owner uuid := '00000000-0000-4000-8000-000000000001';
  v_topic uuid := '00000000-0000-4000-8000-000000000002';
  v_card uuid := '00000000-0000-4000-8000-000000000003';
begin
  if not exists (select 1 from auth.users where id = v_owner) then
    raise exception 'Owner account not found';
  end if;

  -- Повышенные права обходят RLS, поэтому проверяем владельца явно.
  if exists (select 1 from public.topics where id = v_topic and user_id <> v_owner)
    or exists (select 1 from public.cards where id = v_card and user_id <> v_owner) then
    raise exception 'Content UUID belongs to another owner';
  end if;

  insert into public.topics (id, user_id, title, description, color, icon, sort_order)
  values (v_topic, v_owner, 'Название', 'Описание', 'green', 'development', 10)
  on conflict (id) do update
    set title = excluded.title,
        description = excluded.description,
        color = excluded.color,
        icon = excluded.icon,
        sort_order = excluded.sort_order
    where public.topics.user_id = v_owner;

  insert into public.cards
    (id, user_id, topic_id, category, question, context, answer, hint_1, hint_2, difficulty, code)
  values
    (v_card, v_owner, v_topic, 'Категория', 'Вопрос?', null, 'Ответ', null, null, 'medium', null)
  on conflict (id) do update
    set topic_id = excluded.topic_id,
        category = excluded.category,
        question = excluded.question,
        context = excluded.context,
        answer = excluded.answer,
        hint_1 = excluded.hint_1,
        hint_2 = excluded.hint_2,
        difficulty = excluded.difficulty,
        code = excluded.code
    where public.cards.user_id = v_owner;
end
$content$;

commit;
```

Повторный запуск такого SQL обновляет те же строки и сохраняет их UUID. `deleted_at` не меняется автоматически: восстановление удалённой записи требует отдельной осознанной миграции. Не используйте `DELETE`, `TRUNCATE`, массовые `UPDATE` без `user_id = v_owner` и смену UUID существующей карточки.

Данные контента для этого этапа не добавлены. Когда будут готовы вопросы, агент создаст конкретную миграцию по этому шаблону.
