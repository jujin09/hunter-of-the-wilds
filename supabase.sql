-- Hunter of the Wilds: 세이브 테이블 + 보안(RLS) + 충돌 방지 저장 함수
-- Supabase 대시보드 → SQL Editor → New query 에 전체를 붙여 넣고 Run 하세요.

create table if not exists public.game_saves (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  slot        integer not null default 1,
  save_data   jsonb not null,
  revision    integer not null default 1,
  device      text,
  updated_at  timestamptz not null default now(),
  unique (user_id, slot)
);

-- 덮어쓰기 전에 이전 데이터를 보관하는 백업 테이블
create table if not exists public.game_save_backups (
  id           bigserial primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  slot         integer not null,
  save_data    jsonb not null,
  revision     integer not null,
  device       text,
  backed_up_at timestamptz not null default now()
);

alter table public.game_saves enable row level security;
alter table public.game_save_backups enable row level security;

-- 본인 데이터만 조회 가능 (쓰기는 아래 함수로만)
drop policy if exists "own saves read" on public.game_saves;
create policy "own saves read" on public.game_saves for select using (auth.uid() = user_id);
drop policy if exists "own backups read" on public.game_save_backups;
create policy "own backups read" on public.game_save_backups for select using (auth.uid() = user_id);

-- 저장 함수: 기기가 알고 있는 revision(p_base_rev)이 서버와 같을 때만 저장.
-- 다르면 덮어쓰지 않고 서버 데이터를 돌려줘서 게임이 사용자에게 고르게 함.
create or replace function public.save_game(p_slot int, p_data jsonb, p_base_rev int, p_device text, p_backup boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  cur public.game_saves%rowtype;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', '로그인이 필요해요');
  end if;
  -- 서버 측 유효성 검사
  if p_slot < 1 or p_slot > 3 then
    return jsonb_build_object('ok', false, 'error', '잘못된 슬롯');
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or (p_data ->> 'v') is null or not (p_data ? 'mats') then
    return jsonb_build_object('ok', false, 'error', '세이브 형식이 올바르지 않아요');
  end if;
  if pg_column_size(p_data) > 500000 then
    return jsonb_build_object('ok', false, 'error', '세이브 크기가 너무 커요');
  end if;

  select * into cur from public.game_saves where user_id = uid and slot = p_slot for update;

  if not found then
    insert into public.game_saves (user_id, slot, save_data, revision, device)
    values (uid, p_slot, p_data, 1, p_device);
    return jsonb_build_object('ok', true, 'revision', 1);
  end if;

  if cur.revision <> p_base_rev then
    return jsonb_build_object('ok', false, 'conflict', true, 'revision', cur.revision,
      'save_data', cur.save_data, 'updated_at', cur.updated_at, 'device', cur.device);
  end if;

  -- 다른 기기에서 저장된 데이터를 덮어쓰거나, 충돌 해결로 덮어쓸 때는 백업
  if p_backup or coalesce(cur.device, '') <> coalesce(p_device, '') then
    insert into public.game_save_backups (user_id, slot, save_data, revision, device)
    values (uid, p_slot, cur.save_data, cur.revision, cur.device);
    delete from public.game_save_backups
     where user_id = uid and slot = p_slot
       and id not in (select id from public.game_save_backups where user_id = uid and slot = p_slot order by id desc limit 20);
  end if;

  update public.game_saves
     set save_data = p_data, revision = cur.revision + 1, device = p_device, updated_at = now()
   where id = cur.id;

  return jsonb_build_object('ok', true, 'revision', cur.revision + 1);
end;
$$;

revoke all on function public.save_game(int, jsonb, int, text, boolean) from public, anon;
grant execute on function public.save_game(int, jsonb, int, text, boolean) to authenticated;
