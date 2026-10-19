-- shorty.memory baseline schema
-- Apply in the Supabase SQL Editor. Review policies before production use.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (char_length(username) between 3 and 18 and username ~ '^[a-zA-Z0-9_.-]+$'),
  display_name text not null check (char_length(display_name) between 1 and 32),
  bio text not null default '' check (char_length(bio) <= 240),
  avatar_url text not null default '',
  anniversary_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_uq on public.profiles (lower(username));
alter table public.profiles enable row level security;
drop policy if exists "Authenticated users can read profile directory" on public.profiles;
create policy "Authenticated users can read profile directory" on public.profiles
  for select to authenticated using (true);
drop policy if exists "Users can create own profile" on public.profiles;
create policy "Users can create own profile" on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendships_unique_pair unique (user_a, user_b),
  constraint friendships_sorted_pair check (user_a < user_b),
  constraint friendships_two_people check (user_a <> user_b),
  constraint friendships_requester_in_pair check (requested_by = user_a or requested_by = user_b)
);
alter table public.friendships enable row level security;
drop policy if exists "Participants can view friendship edges" on public.friendships;
create policy "Participants can view friendship edges" on public.friendships
  for select to authenticated using (auth.uid() = user_a or auth.uid() = user_b);
drop policy if exists "Users can request friendships" on public.friendships;
create policy "Users can request friendships" on public.friendships
  for insert to authenticated with check (
    requested_by = auth.uid() and (auth.uid() = user_a or auth.uid() = user_b) and status = 'pending'
  );
drop policy if exists "Request recipients can respond" on public.friendships;
create policy "Request recipients can respond" on public.friendships
  for update to authenticated
  using (status = 'pending' and auth.uid() <> requested_by and (auth.uid() = user_a or auth.uid() = user_b))
  with check (status in ('pending','accepted') and auth.uid() <> requested_by and (auth.uid() = user_a or auth.uid() = user_b));
drop policy if exists "Participants can delete friendship edges" on public.friendships;
create policy "Participants can delete friendship edges" on public.friendships
  for delete to authenticated using (auth.uid() = user_a or auth.uid() = user_b);

create table if not exists public.couples (
  id uuid primary key default gen_random_uuid(),
  user_one uuid not null references public.profiles(id) on delete cascade,
  user_two uuid not null references public.profiles(id) on delete cascade,
  linked_at timestamptz not null default now(),
  constraint couples_distinct_people check (user_one <> user_two),
  constraint couples_unique_pair unique (user_one, user_two)
);
create unique index if not exists couples_one_pair_per_user on public.couples (user_one);
create unique index if not exists couples_two_pair_per_user on public.couples (user_two);
alter table public.couples enable row level security;
drop policy if exists "Pair members can view couple" on public.couples;
create policy "Pair members can view couple" on public.couples
  for select to authenticated using (auth.uid() = user_one or auth.uid() = user_two);
drop policy if exists "Pair members can unlink" on public.couples;
create policy "Pair members can unlink" on public.couples
  for delete to authenticated using (auth.uid() = user_one or auth.uid() = user_two);

create table if not exists public.pair_invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.profiles(id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  accepted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  constraint pair_invite_not_self check (accepted_by is null or accepted_by <> inviter_id)
);
alter table public.pair_invites enable row level security;
drop policy if exists "Invite participants can read invitation" on public.pair_invites;
create policy "Invite participants can read invitation" on public.pair_invites
  for select to authenticated using (auth.uid() = inviter_id or auth.uid() = accepted_by);
drop policy if exists "Users can create own invite" on public.pair_invites;
create policy "Users can create own invite" on public.pair_invites
  for insert to authenticated with check (auth.uid() = inviter_id and accepted_by is null and expires_at > now() and expires_at <= now() + interval '25 hours');
-- Invite acceptance is performed by the security-definer function below, not by a direct UPDATE policy.

create or replace function public.accept_pair_code(code_input text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation public.pair_invites%rowtype;
  new_couple_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if exists (select 1 from public.couples where user_one = auth.uid() or user_two = auth.uid()) then
    raise exception 'This account is already paired';
  end if;
  select * into invitation
    from public.pair_invites
    where code = upper(trim(code_input))
      and accepted_by is null
      and expires_at > now()
      and inviter_id <> auth.uid()
    for update;
  if not found then
    raise exception 'Pair code is invalid, expired, or already used';
  end if;
  if exists (select 1 from public.couples where user_one = invitation.inviter_id or user_two = invitation.inviter_id) then
    raise exception 'The inviter is already paired';
  end if;
  insert into public.couples(user_one, user_two)
    values (invitation.inviter_id, auth.uid())
    returning id into new_couple_id;
  update public.pair_invites
    set accepted_by = auth.uid(), accepted_at = now()
    where id = invitation.id;
  return new_couple_id;
end;
$$;
revoke all on function public.accept_pair_code(text) from public;
grant execute on function public.accept_pair_code(text) to authenticated;

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  couple_id uuid references public.couples(id) on delete set null,
  caption text not null default '' check (char_length(caption) <= 160),
  object_path text not null,
  visibility text not null default 'private' check (visibility in ('private','couple')),
  created_at timestamptz not null default now(),
  constraint memory_path_owner check (object_path like user_id::text || '/%')
);
create index if not exists memories_user_created_idx on public.memories(user_id, created_at desc);
create index if not exists memories_couple_created_idx on public.memories(couple_id, created_at desc);
alter table public.memories enable row level security;
drop policy if exists "Owners and pair members can read memories" on public.memories;
create policy "Owners and pair members can read memories" on public.memories
  for select to authenticated using (
    user_id = auth.uid()
    or (
      visibility = 'couple' and couple_id is not null
      and exists (select 1 from public.couples c where c.id = memories.couple_id and (c.user_one = auth.uid() or c.user_two = auth.uid()))
    )
  );
drop policy if exists "Users can create own memories" on public.memories;
create policy "Users can create own memories" on public.memories
  for insert to authenticated with check (
    user_id = auth.uid()
    and object_path like auth.uid()::text || '/%'
    and (
      visibility = 'private'
      or (visibility = 'couple' and couple_id is not null and exists (
        select 1 from public.couples c where c.id = memories.couple_id and (c.user_one = auth.uid() or c.user_two = auth.uid())
      ))
    )
  );
drop policy if exists "Owners can update memories" on public.memories;
create policy "Owners can update memories" on public.memories
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and object_path like auth.uid()::text || '/%');
drop policy if exists "Owners can delete memories" on public.memories;
create policy "Owners can delete memories" on public.memories
  for delete to authenticated using (user_id = auth.uid());

-- Storage buckets for avatars and private memory photos.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('avatars','avatars',true,12582912,array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 12582912, allowed_mime_types = array['image/png','image/jpeg','image/webp'];
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('memory-photos','memory-photos',false,12582912,array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 12582912, allowed_mime_types = array['image/png','image/jpeg','image/webp'];

drop policy if exists "Avatar images are publicly readable" on storage.objects;
create policy "Avatar images are publicly readable" on storage.objects for select using (bucket_id = 'avatars');
drop policy if exists "Users can upload own avatar" on storage.objects;
create policy "Users can upload own avatar" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users can remove own avatar" on storage.objects;
create policy "Users can remove own avatar" on storage.objects for delete to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users can upload own memory photos" on storage.objects;
create policy "Users can upload own memory photos" on storage.objects for insert to authenticated with check (bucket_id = 'memory-photos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Users can read authorized memory photos" on storage.objects;
create policy "Users can read authorized memory photos" on storage.objects for select to authenticated using (
  bucket_id = 'memory-photos'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (
      select 1 from public.memories m
      where m.object_path = name and m.visibility = 'couple' and m.couple_id is not null
        and exists (select 1 from public.couples c where c.id = m.couple_id and (c.user_one = auth.uid() or c.user_two = auth.uid()))
    )
  )
);
drop policy if exists "Users can remove own memory photos" on storage.objects;
create policy "Users can remove own memory photos" on storage.objects for delete to authenticated using (bucket_id = 'memory-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Note: policies are intentionally scoped to authenticated users. Review and test in
-- Supabase's policy tester before production use; this schema is a starter, not an audit.
