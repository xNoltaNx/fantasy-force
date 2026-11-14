-- Fantasy Force: the Discord bot's part of the database. Paste all of this into Supabase's SQL Editor once
-- (SQL Editor > New query > paste > Run). Safe to run again. schema.sql holds the same section, for new projects.

-- ---------- Discord bot ----------
-- Each event gets one post in a Discord channel with sign-up buttons, kept up to date, and a reminder
-- reply before it starts. Each kill-on-sight mark made on the site is broadcast too. The Edge Functions in
-- supabase/functions talk to Discord; the triggers and the cron job below tell them when, through pg_net.
-- Until discord_state.functions_url is set nothing calls out, and nothing here can stop a save on the site.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

alter table public.events add column if not exists discord_message_id text; -- the event's post in the channel
alter table public.events add column if not exists discord_reminded_at timestamptz; -- when its reminder went out

-- The bot's settings (one row). No row rules: only the functions' service key and the SQL Editor read it.
create table if not exists public.discord_state (
  id int primary key default 1 check (id = 1),
  functions_url text, -- 'https://<project>.supabase.co/functions/v1'; empty: Discord is off
  hook_secret text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''), -- the trigger's password
  reminder_minutes int not null default 60 check (reminder_minutes between 5 and 1440), -- how long before the start
  refresh_gap_seconds int not null default 5 check (refresh_gap_seconds between 1 and 60) -- at most one edit per event this often
);
insert into public.discord_state (id) values (1) on conflict do nothing;

-- Per event: when its post was last brought up to date, and whether a refresh waits its turn (discord_claim_sync).
create table if not exists public.discord_sync (
  event_id uuid primary key references public.events on delete cascade,
  synced_at timestamptz,
  busy_until timestamptz,
  pending_since timestamptz,
  pending_post boolean not null default false
);

alter table public.discord_state enable row level security;
alter table public.discord_sync enable row level security;
revoke all on public.discord_state, public.discord_sync from anon, authenticated;

-- Calls the discord-announce function, after this change is saved (pg_net sends once the transaction commits).
create or replace function public.discord_call(payload jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s public.discord_state;
begin
  select * into s from public.discord_state where id = 1;
  if coalesce(s.functions_url, '') = '' then return; end if;
  perform net.http_post(
    url := rtrim(s.functions_url, '/') || '/discord-announce',
    body := payload,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', s.hook_secret),
    timeout_milliseconds := 10000);
exception when others then
  raise warning 'Discord call failed: %', sqlerrm; -- Discord never stops a save
end $$;

-- An event posted, edited (what the post shows) or deleted on the site.
create or replace function public.discord_on_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.discord_message_id is not null then
      perform public.discord_call(jsonb_build_object('kind', 'delete', 'message_id', old.discord_message_id));
    end if;
    return old;
  end if;
  perform public.discord_call(jsonb_build_object('kind', 'event', 'event_id', new.id));
  return new;
end $$;
drop trigger if exists discord_event_posted_or_deleted on public.events;
create trigger discord_event_posted_or_deleted after insert or delete on public.events
  for each row execute function public.discord_on_event();
drop trigger if exists discord_event_edited on public.events;
create trigger discord_event_edited after update on public.events for each row
  when ((old.title, old.starts_at, old.duration_minutes, old.description, old.need_tank, old.need_healer, old.need_dps)
        is distinct from (new.title, new.starts_at, new.duration_minutes, new.description, new.need_tank, new.need_healer, new.need_dps))
  execute function public.discord_on_event();

-- A new start time earns a new reminder.
create or replace function public.discord_event_moved() returns trigger language plpgsql as $$
begin
  if new.starts_at is distinct from old.starts_at then new.discord_reminded_at := null; end if;
  return new;
end $$;
drop trigger if exists discord_event_moved on public.events;
create trigger discord_event_moved before update on public.events for each row execute function public.discord_event_moved();

-- A sign-up changed (on the site or by a button): refresh the post's counts, if it has a post.
create or replace function public.discord_on_signup() returns trigger
language plpgsql security definer set search_path = public as $$
declare eid uuid;
begin
  if tg_op = 'DELETE' then eid := old.event_id; else eid := new.event_id; end if;
  if exists (select 1 from public.events where id = eid and discord_message_id is not null) then
    perform public.discord_call(jsonb_build_object('kind', 'counts', 'event_id', eid));
  end if;
  return null;
end $$;
drop trigger if exists discord_signup_changed on public.signups;
create trigger discord_signup_changed after insert or update or delete on public.signups
  for each row execute function public.discord_on_signup();

-- ----- Kill on sight -----
-- The guild's kill-on-sight list on the site (the addon keeps its own in game; each post says how to add the
-- mark there). Members mark enemy players and anyone in the guild may change or clear a mark, as in the
-- addon; the marker or an officer may delete one. Each mark is broadcast to Discord and its post follows it.

create table if not exists public.kos (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 48),
  level int check (level between 1 and 63),
  race text not null default '' check (char_length(race) <= 20), -- the site's race id
  class_id text not null default '' check (char_length(class_id) <= 20),
  guild text not null default '' check (char_length(guild) <= 48),
  zone text not null default '' check (char_length(zone) <= 80), -- where they were last seen
  reason text not null default '' check (char_length(reason) <= 500),
  danger int not null default 2 check (danger between 1 and 3), -- 1 pest, 2 menace, 3 public enemy
  created_by uuid default auth.uid() references public.members on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), -- what the post shows last changed
  cleared_at timestamptz,
  cleared_by uuid references public.members on delete set null,
  discord_message_id text, -- its post
  discord_posting_at timestamptz -- a post on its way (discord_claim_kos_post)
);
create unique index if not exists kos_one_active_mark on public.kos (lower(name)) where cleared_at is null;

alter table public.kos enable row level security;
drop policy if exists "members read kos" on public.kos;
create policy "members read kos" on public.kos for select using (public.is_approved(auth.uid()));
drop policy if exists "members mark kos" on public.kos;
create policy "members mark kos" on public.kos for insert with check (public.is_approved(auth.uid()) and created_by = auth.uid());
drop policy if exists "members change kos" on public.kos;
create policy "members change kos" on public.kos for update using (public.is_approved(auth.uid())) with check (public.is_approved(auth.uid()));
drop policy if exists "marker or officer deletes kos" on public.kos;
create policy "marker or officer deletes kos" on public.kos for delete using (created_by = auth.uid() or public.is_officer());
-- The site writes only what a person types; who, when and the Discord columns are the database's.
revoke insert, update on public.kos from anon, authenticated;
grant insert (name, level, race, class_id, guild, zone, reason, danger) on public.kos to authenticated;
grant update (name, level, race, class_id, guild, zone, reason, danger, cleared_at) on public.kos to authenticated;

-- Tidies the name, stamps a clear with who and when (a clear can't be undone: mark them again instead), and
-- moves updated_at when anything the post shows changes, which is what sends the edit.
create or replace function public.kos_stamp() returns trigger language plpgsql set search_path = public as $$
begin
  new.name := btrim(regexp_replace(new.name, '\s+', ' ', 'g'));
  if tg_op = 'INSERT' then
    new.created_at := now(); new.updated_at := now(); new.cleared_at := null; new.cleared_by := null;
    return new;
  end if;
  if old.cleared_at is not null then
    new.cleared_at := old.cleared_at; new.cleared_by := old.cleared_by;
  elsif new.cleared_at is not null then
    new.cleared_at := now(); new.cleared_by := auth.uid();
  else
    new.cleared_by := null;
  end if;
  if (old.name, old.level, old.race, old.class_id, old.guild, old.zone, old.reason, old.danger, old.cleared_at)
     is distinct from (new.name, new.level, new.race, new.class_id, new.guild, new.zone, new.reason, new.danger, new.cleared_at) then
    new.updated_at := now();
  else
    new.updated_at := old.updated_at;
  end if;
  return new;
end $$;
drop trigger if exists kos_stamp on public.kos;
create trigger kos_stamp before insert or update on public.kos for each row execute function public.kos_stamp();

-- A mark made, changed, cleared or deleted on the site.
create or replace function public.discord_on_kos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.discord_message_id is not null then
      perform public.discord_call(jsonb_build_object('kind', 'kos_delete', 'message_id', old.discord_message_id));
    end if;
    return old;
  end if;
  perform public.discord_call(jsonb_build_object('kind', 'kos', 'kos_id', new.id));
  return new;
end $$;
drop trigger if exists discord_kos_marked_or_deleted on public.kos;
create trigger discord_kos_marked_or_deleted after insert or delete on public.kos
  for each row execute function public.discord_on_kos();
drop trigger if exists discord_kos_changed on public.kos;
create trigger discord_kos_changed after update on public.kos for each row
  when (old.updated_at is distinct from new.updated_at) execute function public.discord_on_kos();

-- ----- What the functions call (service key only) -----

create or replace function public.discord_hook_ok(p_secret text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.discord_state where id = 1 and p_secret <> '' and hook_secret = p_secret)
$$;

-- One post or edit per event per refresh_gap_seconds. 'now': go (and 'post' if any caller may create the post);
-- 'wait': come back in wait_ms as the one waiter; 'skip': a waiter already has it, and will see this change too.
create or replace function public.discord_claim_sync(p_event uuid, p_post boolean, p_waiter boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.discord_sync;
  gap interval := make_interval(secs => coalesce((select refresh_gap_seconds from public.discord_state where id = 1), 5));
  ready timestamptz;
begin
  if not exists (select 1 from public.events where id = p_event) then return jsonb_build_object('action', 'skip'); end if;
  insert into public.discord_sync (event_id) values (p_event) on conflict do nothing;
  select * into s from public.discord_sync where event_id = p_event for update;
  ready := greatest(s.synced_at + gap, s.busy_until);
  if ready > now() then
    if not p_waiter and s.pending_since > now() - interval '1 minute' then
      update public.discord_sync set pending_post = pending_post or p_post where event_id = p_event;
      return jsonb_build_object('action', 'skip');
    end if;
    update public.discord_sync set pending_since = now(), pending_post = pending_post or p_post where event_id = p_event;
    return jsonb_build_object('action', 'wait', 'wait_ms', ceil(extract(epoch from ready - now()) * 1000)::int);
  end if;
  update public.discord_sync
    set synced_at = now(), busy_until = now() + interval '20 seconds', pending_since = null, pending_post = false
    where event_id = p_event;
  return jsonb_build_object('action', 'now', 'post', p_post or s.pending_post);
end $$;

create or replace function public.discord_sync_done(p_event uuid) returns void
language sql security definer set search_path = public as $$
  update public.discord_sync set busy_until = null where event_id = p_event
$$;

-- An event as its post shows it: who's going is listed by character (else the member's name).
create or replace function public.discord_event_view(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'duration_minutes', e.duration_minutes,
    'description', e.description, 'need_tank', e.need_tank, 'need_healer', e.need_healer, 'need_dps', e.need_dps,
    'discord_message_id', e.discord_message_id,
    'guild_name', (select g.name from public.guild g where g.id = 1),
    'signups', coalesce((select jsonb_agg(jsonb_build_object('role', s.role, 'status', s.status,
                                                             'name', coalesce(c.name, m.display_name))
                                          order by c.is_main desc nulls last, coalesce(c.name, m.display_name))
                         from public.signups s
                         left join public.characters c on c.id = s.character_id
                         left join public.members m on m.id = s.member_id
                         where s.event_id = e.id), '[]'::jsonb))
  from public.events e where e.id = p_event
$$;

create or replace function public.discord_set_message(p_event uuid, p_message text) returns void
language sql security definer set search_path = public as $$
  update public.events set discord_message_id = p_message where id = p_event
$$;

-- A mark as its post shows it. Who marked or cleared it: their main character, else their name.
create or replace function public.discord_kos_view(p_kos uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', k.id, 'name', k.name, 'level', k.level, 'race', k.race, 'class_id', k.class_id, 'guild', k.guild,
    'zone', k.zone, 'reason', k.reason, 'danger', k.danger, 'created_at', k.created_at, 'updated_at', k.updated_at,
    'cleared_at', k.cleared_at, 'discord_message_id', k.discord_message_id,
    'marked_by', coalesce((select c.name from public.characters c where c.member_id = k.created_by and c.is_main limit 1),
                          (select m.display_name from public.members m where m.id = k.created_by), ''),
    'cleared_by', coalesce((select c.name from public.characters c where c.member_id = k.cleared_by and c.is_main limit 1),
                           (select m.display_name from public.members m where m.id = k.cleared_by)),
    'guild_name', (select g.name from public.guild g where g.id = 1))
  from public.kos k where k.id = p_kos
$$;

-- True for the one caller that may post the mark (no post yet, and none on its way in the last 30 seconds).
create or replace function public.discord_claim_kos_post(p_kos uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.kos set discord_posting_at = now()
    where id = p_kos and discord_message_id is null
      and (discord_posting_at is null or discord_posting_at < now() - interval '30 seconds');
  return found;
end $$;

create or replace function public.discord_set_kos_message(p_kos uuid, p_message text) returns void
language sql security definer set search_path = public as $$
  update public.kos set discord_message_id = p_message, discord_posting_at = null where id = p_kos
$$;

-- A button pressed by a Discord user: sign them up with that role (or mark them out), as the site would.
-- Their character: one that plays the role (their main first), else the one already signed up, else their main.
create or replace function public.discord_button(p_discord_id text, p_event uuid, p_choice text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  e public.events;
  uid uuid;
  approved boolean;
  cur public.signups;
  ch public.characters;
  picked text;
begin
  if p_choice not in ('tank', 'healer', 'dps', 'out') then raise exception 'Unknown choice %', p_choice; end if;
  select * into e from public.events where id = p_event;
  if not found then return jsonb_build_object('result', 'no_event'); end if;
  if e.starts_at + make_interval(mins => e.duration_minutes) < now() then
    return jsonb_build_object('result', 'over', 'title', e.title);
  end if;
  select i.user_id into uid from auth.identities i
    where i.provider = 'discord' and (i.provider_id = p_discord_id or i.identity_data ->> 'sub' = p_discord_id)
    limit 1;
  select m.rank_id is not null into approved from public.members m where m.id = uid;
  if approved is null then return jsonb_build_object('result', 'not_member', 'title', e.title); end if;
  if not approved then return jsonb_build_object('result', 'waiting', 'title', e.title); end if;

  select * into cur from public.signups s where s.event_id = p_event and s.member_id = uid;
  if p_choice = 'out' and cur.character_id is not null then
    update public.signups set status = 'out' where event_id = p_event and member_id = uid;
    return jsonb_build_object('result', 'out', 'title', e.title);
  end if;
  select * into ch from public.characters c where c.member_id = uid
    order by (c.role = p_choice) desc, (c.id is not distinct from cur.character_id) desc, c.is_main desc, c.level desc nulls last, c.name
    limit 1;
  if not found then return jsonb_build_object('result', 'no_character', 'title', e.title); end if;
  picked := case when p_choice = 'out' then ch.role else p_choice end;
  insert into public.signups (event_id, member_id, character_id, role, status)
    values (p_event, uid, ch.id, picked, case when p_choice = 'out' then 'out' else 'in' end)
    on conflict (event_id, member_id) do update
      set character_id = excluded.character_id, role = excluded.role, status = excluded.status;
  if p_choice = 'out' then return jsonb_build_object('result', 'out', 'title', e.title); end if;
  return jsonb_build_object('result', 'in', 'title', e.title, 'role', picked, 'character', ch.name);
end $$;

-- Events whose reminder is due: posted, not yet reminded, starting within reminder_minutes.
create or replace function public.discord_reminder_due(ev public.events) returns boolean
language sql stable set search_path = public as $$
  select ev.discord_message_id is not null and ev.discord_reminded_at is null and ev.starts_at > now()
     and ev.starts_at <= now() + make_interval(mins => coalesce((select reminder_minutes from public.discord_state where id = 1), 60))
$$;

-- Claims the due reminders (so each goes out once) and hands back who's going, with their Discord ids.
create or replace function public.discord_claim_reminders() returns jsonb
language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  with due as (
    update public.events ev set discord_reminded_at = now()
    where public.discord_reminder_due(ev)
    returning ev.id, ev.title, ev.starts_at, ev.discord_message_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'title', d.title, 'starts_at', d.starts_at, 'message_id', d.discord_message_id,
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
        'role', s.role, 'name', m.display_name,
        'discord_id', (select coalesce(i.provider_id, i.identity_data ->> 'sub') from auth.identities i
                       where i.user_id = s.member_id and i.provider = 'discord' limit 1)
      ) order by m.display_name)
      from public.signups s join public.members m on m.id = s.member_id
      where s.event_id = d.id and s.status = 'in'), '[]'::jsonb)
  )), '[]'::jsonb) into result
  from due d;
  return result;
end $$;

create or replace function public.discord_unclaim_reminder(p_event uuid) returns void
language sql security definer set search_path = public as $$
  update public.events set discord_reminded_at = null where id = p_event
$$;

-- The cron job: wakes the function only when a reminder is due.
create or replace function public.discord_reminder_tick() returns void
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.events ev where public.discord_reminder_due(ev)) then
    perform public.discord_call('{"kind": "reminders"}'::jsonb);
  end if;
end $$;

revoke execute on function public.discord_call(jsonb), public.discord_hook_ok(text), public.discord_claim_sync(uuid, boolean, boolean),
  public.discord_sync_done(uuid), public.discord_event_view(uuid), public.discord_set_message(uuid, text),
  public.discord_button(text, uuid, text), public.discord_reminder_due(public.events), public.discord_claim_reminders(),
  public.discord_unclaim_reminder(uuid), public.discord_reminder_tick(), public.discord_on_kos(), public.discord_kos_view(uuid),
  public.discord_claim_kos_post(uuid), public.discord_set_kos_message(uuid, text) from public, anon, authenticated;
grant execute on function public.discord_hook_ok(text), public.discord_claim_sync(uuid, boolean, boolean),
  public.discord_sync_done(uuid), public.discord_event_view(uuid), public.discord_set_message(uuid, text),
  public.discord_button(text, uuid, text), public.discord_claim_reminders(), public.discord_unclaim_reminder(uuid),
  public.discord_kos_view(uuid), public.discord_claim_kos_post(uuid), public.discord_set_kos_message(uuid, text) to service_role;

-- Every 5 minutes (Supabase: Integrations > Cron shows it as discord-reminders).
select cron.schedule('discord-reminders', '*/5 * * * *', 'select public.discord_reminder_tick()');

-- ---------- End of Discord bot ----------

-- This project's functions, which switches the bot on:
update public.discord_state set functions_url = 'https://nwxgcmcgmsvbnvolthrd.supabase.co/functions/v1' where id = 1;

-- Post the upcoming events already on the site (new ones post themselves from now on), and bring the posts
-- already up to the bot's current look.
select public.discord_call(jsonb_build_object('kind', 'event', 'event_id', id))
from public.events where starts_at > now() and discord_message_id is null;
select public.discord_call(jsonb_build_object('kind', 'counts', 'event_id', id))
from public.events where starts_at + make_interval(mins => duration_minutes) > now() and discord_message_id is not null;
