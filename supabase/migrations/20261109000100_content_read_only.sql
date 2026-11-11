-- Stage 2: educational content is maintained only by reviewed SQL migrations.
-- Keep owner-scoped SELECT policies and RLS enabled.
begin;

revoke insert, update, delete on table public.topics, public.cards from authenticated;
revoke update (title, description, color, icon, sort_order) on table public.topics from authenticated;
revoke update (topic_id, category, question, context, answer, hint_1, hint_2, difficulty, code) on table public.cards from authenticated;
drop policy if exists topics_insert_owner on public.topics;
drop policy if exists topics_update_owner on public.topics;
drop policy if exists cards_insert_owner on public.cards;
drop policy if exists cards_update_owner on public.cards;

-- These owner-checked content mutation RPCs belonged to the earlier CRUD plan.
-- Remove browser EXECUTE; the functions remain available to elevated SQL migrations.
revoke execute on function public.soft_delete_topic(uuid), public.restore_topic(uuid),
  public.soft_delete_card(uuid), public.restore_card(uuid) from authenticated;

commit;
