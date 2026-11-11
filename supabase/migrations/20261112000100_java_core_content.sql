-- Java Core content snapshot. Source: cards/Backend/01-java-core/01-java-core-draft.yaml
-- Owner UUID was supplied for this migration. Never change this file after applying it.
-- On a clean local database without this auth user, installation is a no-op;
-- local SQL tests create the user and call the private import routine explicitly.
begin;

create or replace function app_private.import_java_core_v1(p_owner uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $import$
declare
  v_topic uuid;
  v_topic_count integer;
  v_changed integer;
  v_cards jsonb := $java_core_cards$[
  {
    "id": "a21911e3-7526-4d8a-9a90-7d7cd2e31796",
    "question": "Почему метод может изменить состояние переданного ему объекта, но не может заменить объект в переменной вызывающего кода?",
    "answer": "Java передаёт аргументы по значению. Для объекта значением служит ссылка: метод получает её копию и может через неё изменить доступный объект. Присваивание этой копии другой ссылки не меняет переменную вызывающего кода.",
    "category": "Типы и ссылки",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "7a237206-f045-4ac2-80de-b42d2afa1924",
    "question": "Чем сравнение ссылок через == отличается от вызова equals()?",
    "answer": "Для ссылок == проверяет, указывают ли они на один объект. equals() проверяет равенство по правилам, заданным классом; реализация Object по умолчанию также сравнивает идентичность. Поэтому для сравнения значений нужно понимать реализацию equals() у конкретного типа.",
    "category": "Типы и ссылки",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "18c71a00-5eeb-4933-a175-8efbec615fb9",
    "question": "Какое обязательное правило связывает equals() и hashCode() при переопределении этих методов?",
    "answer": "Если два объекта равны согласно equals(), их hashCode() должны совпадать. Обратное неверно: одинаковый хеш не означает равенства. Нарушение правила приводит, в частности, к некорректному поведению хеш-коллекций.",
    "category": "Объектная модель",
    "context": null,
    "hint_1": "Представь, как HashSet сначала ищет место для объекта.",
    "hint_2": "Равные объекты должны попадать в одну область поиска.",
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "4466c34a-5a09-484c-80b4-2bbca3e576b8",
    "question": "Почему изменяемое поле, участвующее в equals() и hashCode(), опасно менять после добавления объекта в HashSet?",
    "answer": "После изменения поля может измениться хеш объекта. Коллекция оставит объект там, куда поместила его при добавлении, а поиск будет использовать уже новый хеш. В результате contains() или remove() могут не найти объект. Это практическое следствие выбора изменяемых данных для идентичности объекта.",
    "category": "Объектная модель",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "bc4012b4-65e6-47d8-802e-9d327ccc97e1",
    "question": "Как Java выбирает метод при перегрузке и при переопределении?",
    "answer": "Подходящая перегрузка выбирается при компиляции с учётом объявленных типов аргументов. Для переопределённого экземплярного метода конкретная реализация выбирается во время выполнения по фактическому классу объекта. Поэтому объявленный тип переменной и фактический тип объекта могут влиять на разные этапы выбора.",
    "category": "Полиморфизм",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "ca424ad6-6782-422f-bd36-886d0a0451cf",
    "question": "Переопределяются ли в Java static-методы и поля так же, как экземплярные методы?",
    "answer": "Нет. Метод экземпляра может быть переопределён и выбран по фактическому типу объекта. Одноимённый static-метод в подклассе скрывает метод родителя, а обращение к полю определяется типом ссылки или явно указанным классом. Поэтому для них не работает тот же динамический полиморфизм.",
    "category": "Полиморфизм",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "3925522e-b319-4203-b6a2-00d017ea7bd0",
    "question": "Что должен сделать класс, если два реализуемых интерфейса объявляют несовместимые default-реализации метода с одной сигнатурой?",
    "answer": "Класс должен явно переопределить метод и разрешить конфликт. В реализации он может написать собственное поведение или вызвать нужную реализацию через ИмяИнтерфейса.super.метод(). Компилятор не выбирает один из конфликтующих методов произвольно.",
    "category": "Полиморфизм",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "hard",
    "code": null
  },
  {
    "id": "e93d6186-458e-426e-9199-00ca8f490dc0",
    "question": "Что именно запрещает final для переменной, метода и класса?",
    "answer": "final-переменной нельзя повторно присвоить значение после инициализации; если она хранит ссылку, состояние самого объекта всё ещё может меняться. final-метод нельзя переопределить в подклассе. От final-класса нельзя наследоваться.",
    "category": "Объектная модель",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "df0fb578-3ec8-4d9a-9272-f22912b1dacd",
    "question": "Почему одного объявления всех полей final недостаточно, чтобы сделать класс неизменяемым?",
    "answer": "Поле final сохраняет ссылку, но не замораживает объект по этой ссылке. Если класс принимает или возвращает изменяемые объекты, его наблюдаемое состояние может измениться извне. Для неизменяемости нужны контроль над изменяемыми данными и, где требуется, защитные копии.",
    "category": "Неизменяемость",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "cc3c74c1-c980-42d8-904e-f425db3153c1",
    "question": "Почему результат String.replace() нужно сохранить, если требуется изменить текст?",
    "answer": "String неизменяем. replace() возвращает строку с результатом замены и не меняет исходный объект. Если результат не использовать, значение переменной останется прежним.",
    "category": "Строки",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "50369e44-2669-4187-b6e7-5e451b249d86",
    "question": "Почему сравнение двух строк через == иногда возвращает true, хотя строки были созданы в разных местах кода?",
    "answer": "Две ссылки могут указывать на один объект строки, например при использовании строковых литералов из пула строк. Но это свойство размещения объектов, а не проверка равенства текста. Для сравнения содержимого используют equals().",
    "category": "Строки",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "35ec3842-dd18-4be2-b72b-29ce8eb92952",
    "question": "Как различаются checked и unchecked exceptions с точки зрения компилятора и контракта метода?",
    "answer": "Checked exception нужно обработать или объявить в throws; компилятор проверяет это требование. RuntimeException и его наследники относятся к unchecked exceptions, поэтому такого требования нет. Выбор типа исключения должен отражать смысл ошибки и способ реакции вызывающего кода, а не только удобство компиляции.",
    "category": "Исключения",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "004caa4b-21a4-4f34-9d8e-690785a01ddd",
    "question": "Что происходит, если при выполнении try-with-resources исключение возникло и в основном блоке, и при закрытии ресурса?",
    "answer": "Основным остаётся исключение из блока try. Исключение, возникшее при закрытии ресурса, добавляется к нему как suppressed exception; его можно получить через getSuppressed(). Это позволяет сохранить обе причины ошибки.",
    "category": "Исключения",
    "context": null,
    "hint_1": "Механизм старается не потерять первоначальную ошибку.",
    "hint_2": "Вспомни дополнительные исключения, прикреплённые к основному.",
    "difficulty": "hard",
    "code": null
  },
  {
    "id": "a09b498f-6d7b-4f18-b392-fcd25eae67f6",
    "question": "Чем orElse() отличается от orElseGet() с точки зрения вычисления запасного значения?",
    "answer": "Аргумент orElse() вычисляется до вызова метода, даже если значение внутри Optional присутствует. orElseGet() принимает поставщик и вызывает его только тогда, когда значение отсутствует. Разница важна, если получение запасного значения дорогое или имеет побочный эффект.",
    "category": "Optional",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "eca0f736-52bf-455f-b8b9-5bb8d5d0462d",
    "question": "Какой результат даёт Optional.map(), если переданная функция возвращает null?",
    "answer": "Результатом будет пустой Optional. map() оборачивает результат функции с учётом возможного null. Если функция уже возвращает Optional, обычно нужен flatMap(), чтобы не получить вложенный Optional<Optional<T>>.",
    "category": "Optional",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "c8df32a2-efea-4035-81cb-57c6f4fddd0f",
    "question": "Гарантирует ли record глубокую неизменяемость объекта?",
    "answer": "Нет. Компоненты record хранятся в final-полях, но сами значения могут ссылаться на изменяемые объекты. Например, список внутри record можно изменить, если не контролировать его при создании и выдаче. record сокращает шаблонный код для носителя данных, но не делает весь граф объектов неизменяемым.",
    "category": "Современная Java",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "906383e7-05dd-42fa-9f34-d75427af440a",
    "question": "Какую задачу решает sealed-класс или интерфейс?",
    "answer": "Он ограничивает набор классов, которым разрешено наследование или реализация. Это позволяет явно описать допустимые варианты модели и помогает проверять полноту обработки этих вариантов. Разрешённые наследники должны продолжить иерархию согласно правилам final, sealed или non-sealed.",
    "category": "Современная Java",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "95b30765-431c-4906-9d07-2cc79f2ee8f4",
    "question": "Почему локальная переменная, объявленная через var, не становится динамически типизированной?",
    "answer": "Компилятор выводит её конкретный статический тип из инициализатора. После этого действуют обычные проверки типов Java. var сокращает запись объявления, но не позволяет переменной произвольно менять тип.",
    "category": "Современная Java",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "506a1cb6-ce9f-4fec-ab7f-d9efa50c1519",
    "question": "Чем switch-выражение отличается от обычного switch-оператора?",
    "answer": "switch-выражение вычисляет значение, поэтому его ветви должны определять результат, а набор ветвей должен быть исчерпывающим. В ветви с блоком результат передают через yield. Форма со стрелкой также исключает случайный переход в следующую ветвь.",
    "category": "Современная Java",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  },
  {
    "id": "ce596f5d-798d-40b9-9ae6-766886c6ebb5",
    "question": "Почему LocalDateTime нельзя без дополнительного контекста считать однозначным моментом времени?",
    "answer": "LocalDateTime содержит дату и время без часового пояса или смещения UTC. Одинаковые локальные значения могут соответствовать разным моментам в разных зонах, а при переходе на летнее время некоторые локальные значения бывают неоднозначны или не существуют. Для конкретного момента времени используют Instant либо задают правила интерпретации через зону или смещение.",
    "category": "Date/Time API",
    "context": null,
    "hint_1": null,
    "hint_2": null,
    "difficulty": "medium",
    "code": null
  }
]$java_core_cards$::jsonb;
begin
  if p_owner is distinct from '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'::uuid then
    raise exception 'Unexpected content owner' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_owner) then
    raise exception 'Content owner account not found' using errcode = '22023';
  end if;

  -- Elevated migration rights bypass RLS. Every lookup and mutation below is owner scoped.
  select count(*) into v_topic_count
    from public.topics where user_id = p_owner and title = 'Backend';
  if v_topic_count > 1 then
    raise exception 'Multiple Backend topics for content owner' using errcode = '23505';
  elsif v_topic_count = 1 then
    select id into v_topic from public.topics
      where user_id = p_owner and title = 'Backend';
    if exists (select 1 from public.topics where id = v_topic and deleted_at is not null) then
      raise exception 'Backend topic is soft deleted; restore it separately' using errcode = '22023';
    end if;
  else
    v_topic := '4535e892-4d68-41c2-a5a8-87935d2f5134'::uuid;
    if exists (select 1 from public.topics where id = v_topic) then
      raise exception 'Reserved Backend UUID is already in use' using errcode = '23505';
    end if;
    insert into public.topics (id, user_id, title, description, color, icon, sort_order)
      values (v_topic, p_owner, 'Backend', 'Вопросы по backend-разработке', 'green', 'development', 10);
  end if;

  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards)
      as source(id uuid, question text) on source.id = c.id
    where c.user_id <> p_owner or c.topic_id <> v_topic or c.deleted_at is not null
  ) then
    raise exception 'Imported card UUID belongs to another scope or is soft deleted' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.cards c
    join jsonb_to_recordset(v_cards)
      as source(id uuid, question text) on source.question = c.question and source.id <> c.id
    where c.user_id = p_owner and c.topic_id = v_topic and c.section = '01-java-core'
      and c.deleted_at is null
  ) then
    raise exception 'A Java Core question already exists with another UUID' using errcode = '23505';
  end if;

  insert into public.cards
    (id, user_id, topic_id, section, category, question, answer, context,
     hint_1, hint_2, difficulty, code)
  select source.id, p_owner, v_topic, '01-java-core', source.category,
         source.question, source.answer, source.context, source.hint_1,
         source.hint_2, source.difficulty, source.code
    from jsonb_to_recordset(v_cards)
      as source(id uuid, question text, answer text, category text, context text,
                hint_1 text, hint_2 text, difficulty text, code text)
  on conflict (id) do update set
    section = excluded.section,
    category = excluded.category,
    question = excluded.question,
    answer = excluded.answer,
    context = excluded.context,
    hint_1 = excluded.hint_1,
    hint_2 = excluded.hint_2,
    difficulty = excluded.difficulty,
    code = excluded.code
  where public.cards.user_id = p_owner and public.cards.topic_id = v_topic
    and public.cards.deleted_at is null;
  get diagnostics v_changed = row_count;
  if v_changed <> 20 then
    raise exception 'Java Core import affected % cards, expected 20', v_changed;
  end if;
end;
$import$;
revoke all on function app_private.import_java_core_v1(uuid) from public, anon, authenticated;

do $install$
begin
  if exists (select 1 from auth.users where id = '7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'::uuid) then
    perform app_private.import_java_core_v1('7d53c0ee-fd2b-401a-ae4d-e6c0caa32a70'::uuid);
  elsif exists (select 1 from auth.users) then
    raise exception 'Configured content owner not found; import cancelled' using errcode = '22023';
  else
    raise notice 'Java Core import skipped: owner account is absent in this database';
  end if;
end;
$install$;
commit;
