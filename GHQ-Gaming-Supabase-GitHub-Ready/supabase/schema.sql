-- GHQ Supabase backend: clean reset + complete installation.
-- WARNING: rerunning this file deletes all GHQ public-table data.
-- Supabase Auth accounts and passwords in auth.users are preserved.

drop trigger if exists on_auth_user_created on auth.users;
drop view if exists public.tournament_list cascade;
drop view if exists public.public_profiles cascade;
drop function if exists public.handle_new_user() cascade;
drop function if exists public.claim_daily_bonus() cascade;
drop function if exists public.join_free_tournament(bigint) cascade;
drop function if exists public.admin_grant_coins(uuid, integer, text) cascade;
drop function if exists public.is_admin() cascade;
drop table if exists public.daily_bonus_claims cascade;
drop table if exists public.user_achievements cascade;
drop table if exists public.achievements cascade;
drop table if exists public.coin_transactions cascade;
drop table if exists public.user_game_profiles cascade;
drop table if exists public.bracket_matches cascade;
drop table if exists public.registrations cascade;
drop table if exists public.tournaments cascade;
drop table if exists public.announcements cascade;
drop table if exists public.advertisements cascade;
drop table if exists public.platform_config cascade;
drop table if exists public.profiles cascade;

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  email text not null unique,
  avatar text not null default '',
  role text not null default 'PLAYER' check (role in ('PLAYER','ADMIN')),
  platform text not null default '',
  favorite_game text not null default '',
  gollers integer not null default 0 check (gollers >= 0),
  total_bought integer not null default 0,
  total_spent integer not null default 0,
  coins integer not null default 100 check (coins >= 0),
  total_earned integer not null default 100,
  wins integer not null default 0,
  losses integer not null default 0,
  rank integer,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tournaments (
  id bigint generated always as identity primary key,
  name text not null,
  game text not null,
  platform text not null,
  type text not null check (type in ('TOURNAMENT','CHAMPIONS')),
  mode text not null check (mode in ('FREE','PAID')),
  status text not null default 'UPCOMING' check (status in ('DRAFT','UPCOMING','LIVE','COMPLETED','CANCELLED')),
  team_size text not null default 'Solo',
  entry_fee integer not null default 0,
  prize_pool integer not null default 0,
  coin_reward integer not null default 100,
  max_players integer not null default 64,
  description text not null default '',
  rules text[] not null default '{}',
  tags text[] not null default '{}',
  organizer text not null default 'GHQ Staff',
  region text not null default 'India',
  registration_start timestamptz,
  registration_end timestamptz,
  start_date timestamptz not null,
  tournament_end timestamptz,
  prize_tiers jsonb not null default '[]',
  ads_required integer not null default 0,
  room_id text,
  room_password text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.registrations (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  tournament_id bigint not null references public.tournaments(id) on delete cascade,
  status text not null default 'REGISTERED',
  placement integer,
  coins_earned integer not null default 0,
  gollars_won integer not null default 0,
  gollers_paid integer not null default 0,
  created_at timestamptz not null default now(),
  unique(user_id, tournament_id)
);

create table if not exists public.bracket_matches (
  id bigint generated always as identity primary key,
  tournament_id bigint not null references public.tournaments(id) on delete cascade,
  round integer not null,
  round_name text not null,
  match_number integer not null,
  player1_name text not null default 'TBD',
  player1_score integer,
  player2_name text not null default 'TBD',
  player2_score integer,
  status text not null default 'UPCOMING',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_game_profiles (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  platform text not null,
  game_user_id text not null default '',
  rank text not null default '',
  wins integer not null default 0,
  losses integer not null default 0,
  tournaments_played integer not null default 0,
  gollers_spent integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, game)
);

create table if not exists public.coin_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('EARN','SPEND')),
  amount integer not null check (amount > 0),
  label text not null,
  game text,
  created_at timestamptz not null default now()
);

create table if not exists public.achievements (
  id bigint generated always as identity primary key,
  key text not null unique,
  icon text not null,
  label text not null,
  description text not null,
  coin_reward integer not null default 0,
  game text
);

create table if not exists public.user_achievements (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id bigint not null references public.achievements(id) on delete cascade,
  earned_at timestamptz not null default now(),
  unique(user_id, achievement_id)
);

create table if not exists public.announcements (
  id bigint generated always as identity primary key,
  title text not null,
  message text not null,
  type text not null default 'info',
  icon text not null default '📢',
  is_active boolean not null default true,
  pinned boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.advertisements (
  id bigint generated always as identity primary key,
  title text not null,
  description text not null default '',
  image_url text not null,
  link_url text not null default '',
  placement text not null default 'general',
  is_active boolean not null default true,
  view_seconds integer not null default 5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_config (
  id bigint generated always as identity primary key,
  key text not null unique,
  value text not null,
  label text not null,
  category text not null default 'general',
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_bonus_claims (
  user_id uuid not null references public.profiles(id) on delete cascade,
  claim_date date not null default current_date,
  coins integer not null default 25,
  primary key(user_id, claim_date)
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'ADMIN' and is_active); $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare desired_username text;
begin
  desired_username := coalesce(nullif(trim(new.raw_user_meta_data->>'username'), ''), split_part(new.email, '@', 1));
  if exists(select 1 from public.profiles where lower(username) = lower(desired_username)) then
    desired_username := desired_username || '_' || substr(new.id::text, 1, 6);
  end if;
  insert into public.profiles(id, username, email, avatar, platform)
  values(new.id, desired_username, lower(new.email), upper(left(desired_username, 2)), coalesce(new.raw_user_meta_data->>'platform',''));
  insert into public.coin_transactions(user_id, type, amount, label)
  values(new.id, 'EARN', 100, 'Welcome bonus - 100 GHQ Coins');
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Restore profiles for any Auth accounts created before this reset.
insert into public.profiles(id, username, email, avatar, platform)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data->>'username'), ''), split_part(coalesce(u.email, u.id::text), '@', 1)) || '_' || substr(u.id::text, 1, 6),
  lower(coalesce(u.email, u.id::text || '@local.invalid')),
  upper(left(coalesce(nullif(trim(u.raw_user_meta_data->>'username'), ''), 'GH'), 2)),
  coalesce(u.raw_user_meta_data->>'platform', '')
from auth.users u
on conflict (id) do nothing;

insert into public.coin_transactions(user_id, type, amount, label)
select p.id, 'EARN', 100, 'Welcome bonus - 100 GHQ Coins'
from public.profiles p
where not exists (select 1 from public.coin_transactions c where c.user_id = p.id);

create or replace function public.claim_daily_bonus()
returns jsonb language plpgsql security definer set search_path = public
as $$
declare reward integer := 25;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  insert into public.daily_bonus_claims(user_id, coins) values(auth.uid(), reward);
  update public.profiles set coins = coins + reward, total_earned = total_earned + reward where id = auth.uid();
  insert into public.coin_transactions(user_id,type,amount,label) values(auth.uid(),'EARN',reward,'Daily bonus');
  return jsonb_build_object('message','Daily bonus claimed!','coinsEarned',reward);
exception when unique_violation then raise exception 'Daily bonus already claimed today';
end; $$;

create or replace function public.join_free_tournament(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare t public.tournaments; player_count integer;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  select * into t from public.tournaments where id = p_tournament_id for update;
  if not found then raise exception 'Tournament not found'; end if;
  if t.mode <> 'FREE' or t.entry_fee <> 0 then raise exception 'Paid tournaments are disabled in this demo'; end if;
  if t.status not in ('UPCOMING','LIVE') then raise exception 'Registration is closed'; end if;
  select count(*) into player_count from public.registrations where tournament_id = p_tournament_id;
  if player_count >= t.max_players then raise exception 'Tournament is full'; end if;
  insert into public.registrations(user_id,tournament_id) values(auth.uid(),p_tournament_id);
  return jsonb_build_object('message','Joined tournament successfully');
exception when unique_violation then raise exception 'You already joined this tournament';
end; $$;

create or replace function public.admin_grant_coins(p_user_id uuid, p_amount integer, p_label text)
returns jsonb language plpgsql security definer set search_path = public
as $$ begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  update public.profiles set coins=coins+p_amount,total_earned=total_earned+p_amount where id=p_user_id;
  insert into public.coin_transactions(user_id,type,amount,label) values(p_user_id,'EARN',p_amount,p_label);
  return jsonb_build_object('message','Coins granted');
end; $$;

create or replace view public.tournament_list with (security_barrier=true) as
select t.id,t.name,t.game,t.platform,t.type,t.mode,t.status,t.team_size,t.entry_fee,t.prize_pool,t.coin_reward,t.max_players,t.description,t.rules,t.tags,t.organizer,t.region,t.registration_start,t.registration_end,t.start_date,t.tournament_end,t.prize_tiers,t.ads_required,t.created_at,t.updated_at,count(r.id)::integer as registered_players
from public.tournaments t left join public.registrations r on r.tournament_id=t.id
group by t.id;

create or replace view public.public_profiles as
select id,username,avatar,coins,wins,losses,rank,favorite_game,created_at
from public.profiles where is_active and role='PLAYER';

alter table public.profiles enable row level security;
alter table public.tournaments enable row level security;
alter table public.registrations enable row level security;
alter table public.bracket_matches enable row level security;
alter table public.user_game_profiles enable row level security;
alter table public.coin_transactions enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.announcements enable row level security;
alter table public.advertisements enable row level security;
alter table public.platform_config enable row level security;
alter table public.daily_bonus_claims enable row level security;

create policy "Own profile read" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
create policy "Own profile update" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid() and role='PLAYER');
create policy "Admin profile update" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Published tournaments readable" on public.tournaments for select using (status<>'DRAFT' or public.is_admin());
create policy "Admins manage tournaments" on public.tournaments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Registration participants read" on public.registrations for select using (user_id=auth.uid() or public.is_admin());
create policy "Brackets readable" on public.bracket_matches for select using (true);
create policy "Admins manage brackets" on public.bracket_matches for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Game profiles readable" on public.user_game_profiles for select using (true);
create policy "Own game profiles insert" on public.user_game_profiles for insert to authenticated with check (user_id=auth.uid());
create policy "Own game profiles update" on public.user_game_profiles for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "Own game profiles delete" on public.user_game_profiles for delete to authenticated using (user_id=auth.uid());
create policy "Own transactions read" on public.coin_transactions for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Achievements readable" on public.achievements for select using (true);
create policy "Own achievements read" on public.user_achievements for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Active announcements readable" on public.announcements for select using ((is_active and (expires_at is null or expires_at>now())) or public.is_admin());
create policy "Admins manage announcements" on public.announcements for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Active advertisements readable" on public.advertisements for select using (is_active or public.is_admin());
create policy "Admins manage advertisements" on public.advertisements for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Config readable" on public.platform_config for select using (true);
create policy "Admins manage config" on public.platform_config for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Own bonus claims read" on public.daily_bonus_claims for select to authenticated using (user_id=auth.uid());

grant execute on function public.claim_daily_bonus() to authenticated;
grant execute on function public.join_free_tournament(bigint) to authenticated;
grant execute on function public.admin_grant_coins(uuid,integer,text) to authenticated;

-- The browser receives only the minimum grants; RLS still applies on every table.
grant usage on schema public to anon, authenticated;
grant select on public.public_profiles, public.tournament_list to anon, authenticated;
grant select on public.announcements, public.advertisements, public.platform_config, public.achievements, public.bracket_matches to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.user_game_profiles to authenticated;
grant select on public.registrations, public.coin_transactions, public.user_achievements, public.daily_bonus_claims to authenticated;
grant insert, update, delete on public.tournaments, public.announcements, public.advertisements, public.platform_config, public.bracket_matches to authenticated;
grant usage, select on all sequences in schema public to authenticated;
revoke select on public.tournaments from anon, authenticated;
grant select (id,name,game,platform,type,mode,status,team_size,entry_fee,prize_pool,coin_reward,max_players,description,rules,tags,organizer,region,registration_start,registration_end,start_date,tournament_end,prize_tiers,ads_required,created_at,updated_at) on public.tournaments to authenticated;

insert into public.platform_config(key,value,label,category) values
('demoMode','true','Demo mode','general'),
('siteName','GHQ','Site name','general')
on conflict (key) do nothing;

insert into public.achievements(key,icon,label,description,coin_reward) values
('WELCOME','🎮','Welcome to GHQ','Create your GHQ account',100),
('FIRST_WIN','🏆','First Victory','Win your first tournament',250)
on conflict (key) do nothing;

insert into public.announcements(title,message,type,icon,pinned) values
('Welcome to GHQ','Create an account and join a free tournament.','info','🎮',true);
