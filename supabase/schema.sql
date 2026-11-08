-- Guild Roster: tables and row rules for Supabase.
-- Run once in your Supabase project: SQL Editor > New query > paste all of this > Run.
-- The row rules below are the real security: the website only asks, the database decides.
--
-- Who can do what:
--   Anyone (not signed in): read the guild, ranks, approved members, their characters, availability, events, sign-ups.
--   A signed-in member: edit their own profile, characters and week; sign up for events once approved.
--   An officer (a rank marked officer): everything above for anyone, plus approve people, ranks, events, officer notes.
-- New Discord sign-ins get a member row with no rank: "Waiting for approval" until an officer gives them one.

create extension if not exists pgcrypto;

-- ---------- Tables ----------

create table if not exists public.guild (
  id int primary key default 1 check (id = 1),
  name text not null default 'Fantasy Force',
  region text not null default 'us' check (region in ('us', 'eu', 'kr', 'tw')),
  ruleset text not null default 'RP-PvP', -- WoW Forever: one mega-realm per ruleset and region
  faction text not null default 'horde' check (faction in ('', 'horde', 'alliance')),
  about text not null default ''
);
insert into public.guild (id) values (1) on conflict do nothing;

create table if not exists public.ranks (
  id serial primary key,
  name text not null,
  sort int not null default 0,
  is_officer boolean not null default false
);
insert into public.ranks (name, sort, is_officer)
select * from (values ('Guild Master', 0, true), ('Officer', 1, true), ('Raider', 2, false), ('Member', 3, false), ('Trial', 4, false)) v
where not exists (select 1 from public.ranks);

create table if not exists public.members (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  discord_name text not null default '',
  avatar_url text,
  rank_id int references public.ranks on delete set null,
  timezone text not null default 'UTC',
  joined_at date not null default current_date,
  about text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.characters (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members on delete cascade,
  name text not null check (length(name) between 1 and 48), -- Forever has first and last names
  race text not null default '',
  class_id text not null,
  spec text not null,
  role text not null check (role in ('tank', 'healer', 'dps')),
  is_main boolean not null default false,
  level int check (level between 1 and 60),
  professions jsonb not null default '[]', -- [{name, skill, max}], from the addon or by hand
  note text not null default ''
);
create index if not exists characters_member on public.characters (member_id);

create table if not exists public.availability (
  member_id uuid primary key references public.members on delete cascade,
  slots smallint[] not null default '{}' -- UTC hour of the week, 0 = Monday 00:00 UTC
);

create table if not exists public.officer_notes (
  member_id uuid primary key references public.members on delete cascade,
  note text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  starts_at timestamptz not null,
  duration_minutes int not null default 180,
  description text not null default '',
  need_tank int not null default 2,
  need_healer int not null default 4,
  need_dps int not null default 14,
  created_by uuid references public.members on delete set null default auth.uid()
);

-- The in-game guild list, as an officer's addon last recorded it (one row). Public notes only: the addon never records officer notes.
create table if not exists public.ingame_roster (
  id int primary key default 1 check (id = 1),
  updated_at timestamptz not null default now(),
  recorded_by text not null default '',
  members jsonb not null default '[]' -- [{name, rank, rank_index, level, class_id, note, online, last_online_days}]
);

create table if not exists public.signups (
  event_id uuid not null references public.events on delete cascade,
  member_id uuid not null references public.members on delete cascade,
  character_id uuid not null references public.characters on delete cascade,
  role text not null check (role in ('tank', 'healer', 'dps')),
  status text not null check (status in ('in', 'maybe', 'out')),
  comment text not null default '',
  primary key (event_id, member_id)
);

-- ---------- Helpers ----------

create or replace function public.is_officer() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m join ranks r on r.id = m.rank_id where m.id = auth.uid() and r.is_officer)
$$;

create or replace function public.is_approved(who uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where id = who and rank_id is not null)
$$;

-- A new Discord sign-in becomes a member waiting for approval, named from their Discord profile.
create or replace function public.on_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into members (id, display_name, discord_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data #>> '{custom_claims,global_name}', new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', 'New member'),
    coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.on_new_user();

-- Members may edit their own profile, but only officers change a rank or a join date, and nobody their own rank.
create or replace function public.guard_member_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if; -- the SQL Editor (the project owner) may change anything
  if not public.is_officer() or new.id = auth.uid() then
    new.rank_id := old.rank_id;
    if not public.is_officer() then new.joined_at := old.joined_at; end if;
  end if;
  new.discord_name := old.discord_name;
  return new;
end $$;
drop trigger if exists guard_member_update on public.members;
create trigger guard_member_update before update on public.members for each row execute function public.guard_member_update();

create or replace function public.touch_officer_note() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists touch_officer_note on public.officer_notes;
create trigger touch_officer_note before insert or update on public.officer_notes for each row execute function public.touch_officer_note();

-- Officers remove a member (and their sign-in) in one step.
create or replace function public.remove_member(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_officer() then raise exception 'Only officers can remove members'; end if;
  if target = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  delete from auth.users where id = target;
end $$;

-- ---------- Row rules ----------

alter table public.guild enable row level security;
alter table public.ranks enable row level security;
alter table public.members enable row level security;
alter table public.characters enable row level security;
alter table public.availability enable row level security;
alter table public.officer_notes enable row level security;
alter table public.events enable row level security;
alter table public.signups enable row level security;
alter table public.ingame_roster enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.guild, public.ranks, public.members, public.characters, public.availability, public.events, public.signups to anon, authenticated;
grant insert, update, delete on public.guild, public.ranks, public.members, public.characters, public.availability,
  public.officer_notes, public.events, public.signups to authenticated;
grant select on public.officer_notes to authenticated;
grant select, insert, update on public.ingame_roster to authenticated;
grant usage, select on sequence public.ranks_id_seq to authenticated;
grant execute on function public.remove_member(uuid) to authenticated;

-- Guild settings and ranks: everyone reads, officers change.
drop policy if exists "read guild" on public.guild;
create policy "read guild" on public.guild for select using (true);
drop policy if exists "officers edit guild" on public.guild;
create policy "officers edit guild" on public.guild for update using (public.is_officer());

drop policy if exists "read ranks" on public.ranks;
create policy "read ranks" on public.ranks for select using (true);
drop policy if exists "officers edit ranks" on public.ranks;
create policy "officers edit ranks" on public.ranks for all using (public.is_officer()) with check (public.is_officer());

-- Members: approved ones are public; you always see yourself; officers see everyone.
drop policy if exists "read members" on public.members;
create policy "read members" on public.members for select using (rank_id is not null or id = auth.uid() or public.is_officer());
drop policy if exists "edit own or officer" on public.members;
create policy "edit own or officer" on public.members for update using (id = auth.uid() or public.is_officer());

-- Characters and availability follow their member.
drop policy if exists "read characters" on public.characters;
create policy "read characters" on public.characters for select
  using (public.is_approved(member_id) or member_id = auth.uid() or public.is_officer());
drop policy if exists "write own characters" on public.characters;
create policy "write own characters" on public.characters for all
  using (member_id = auth.uid() or public.is_officer()) with check (member_id = auth.uid() or public.is_officer());

drop policy if exists "read availability" on public.availability;
create policy "read availability" on public.availability for select
  using (public.is_approved(member_id) or member_id = auth.uid() or public.is_officer());
drop policy if exists "write own availability" on public.availability;
create policy "write own availability" on public.availability for all
  using (member_id = auth.uid() or public.is_officer()) with check (member_id = auth.uid() or public.is_officer());

-- Officer notes: officers only, both ways.
drop policy if exists "officers only" on public.officer_notes;
create policy "officers only" on public.officer_notes for all using (public.is_officer()) with check (public.is_officer());

-- In-game guild list: approved members read it (it carries public notes and last-online), officers bring it in.
drop policy if exists "members read ingame" on public.ingame_roster;
create policy "members read ingame" on public.ingame_roster for select using (public.is_approved(auth.uid()));
drop policy if exists "officers write ingame" on public.ingame_roster;
create policy "officers write ingame" on public.ingame_roster for all using (public.is_officer()) with check (public.is_officer());

-- Events: everyone reads, officers post.
drop policy if exists "read events" on public.events;
create policy "read events" on public.events for select using (true);
drop policy if exists "officers edit events" on public.events;
create policy "officers edit events" on public.events for all using (public.is_officer()) with check (public.is_officer());

-- Sign-ups: everyone reads; approved members sign themselves up with their own character; officers fix anyone's.
drop policy if exists "read signups" on public.signups;
create policy "read signups" on public.signups for select using (true);
drop policy if exists "sign up self" on public.signups;
create policy "sign up self" on public.signups for all
  using (member_id = auth.uid() or public.is_officer())
  with check (
    public.is_officer()
    or (member_id = auth.uid() and public.is_approved(auth.uid())
        and exists (select 1 from public.characters c where c.id = character_id and c.member_id = auth.uid()))
  );

-- ---------- After your first sign-in ----------
-- Make yourself Guild Master (put your Discord display name in), then everything else is done on the site:
--
--   update public.members set rank_id = (select id from public.ranks order by sort limit 1)
--   where display_name = 'YourDiscordName';
