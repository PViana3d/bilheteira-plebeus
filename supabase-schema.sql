-- Bilheteira Plebeus: data model for the standalone box-office app.
-- Staff allowlist gates everything through RLS; seat rows double as tickets.

create table public.staff (
  email text primary key check (email = lower(email)),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.venue (
  id int primary key default 1 check (id = 1),
  zones jsonb not null,
  types jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  date date not null,
  time text not null default '',
  notes text not null default '',
  paper text not null default '80' check (paper in ('80', '58')),
  blocked jsonb not null default '[]'::jsonb,
  logo text,
  created_at timestamptz not null default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  contact text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now()
);
create index bookings_event_idx on public.bookings(event_id);

create table public.seats (
  event_id uuid not null references public.events(id) on delete cascade,
  seat_id text not null,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  code text not null unique,
  entered_at timestamptz,
  primary key (event_id, seat_id)
);
create index seats_booking_idx on public.seats(booking_id);

-- Access helpers
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.staff where email = lower(coalesce(auth.jwt() ->> 'email', '')) and is_admin);
$$;
revoke execute on function public.is_staff() from public, anon;
revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_staff() to authenticated;
grant execute on function public.is_admin() to authenticated;

alter table public.staff enable row level security;
alter table public.venue enable row level security;
alter table public.events enable row level security;
alter table public.bookings enable row level security;
alter table public.seats enable row level security;

create policy staff_read on public.staff for select to authenticated
  using (email = lower(coalesce(auth.jwt() ->> 'email', '')) or (select public.is_staff()));
create policy staff_admin_insert on public.staff for insert to authenticated with check ((select public.is_admin()));
create policy staff_admin_update on public.staff for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy staff_admin_delete on public.staff for delete to authenticated using ((select public.is_admin()));

create policy venue_all on public.venue for all to authenticated using ((select public.is_staff())) with check ((select public.is_staff()));
create policy events_all on public.events for all to authenticated using ((select public.is_staff())) with check ((select public.is_staff()));
create policy bookings_all on public.bookings for all to authenticated using ((select public.is_staff())) with check ((select public.is_staff()));
create policy seats_all on public.seats for all to authenticated using ((select public.is_staff())) with check ((select public.is_staff()));

-- Booking with seats in one transaction; a per-event lock plus the primary key stop double booking.
create or replace function public.create_booking(p_event uuid, p_name text, p_contact text, p_notes text, p_seats text[], p_codes text[])
returns uuid language plpgsql security invoker set search_path = public as $$
declare bid uuid; taken text[];
begin
  if coalesce(array_length(p_seats, 1), 0) = 0 or array_length(p_seats, 1) <> array_length(p_codes, 1) then
    raise exception 'bad_seats';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_event::text));
  select array_agg(seat_id) into taken from public.seats where event_id = p_event and seat_id = any(p_seats);
  if taken is not null then raise exception 'conflict:%', array_to_string(taken, ','); end if;
  insert into public.bookings(event_id, name, contact, notes) values (p_event, p_name, coalesce(p_contact, ''), coalesce(p_notes, ''))
    returning id into bid;
  insert into public.seats(event_id, seat_id, booking_id, code)
    select p_event, s, bid, upper(c) from unnest(p_seats, p_codes) as t(s, c);
  return bid;
end $$;

-- Replace a booking's seats; kept seats keep their ticket code and entry time.
create or replace function public.set_booking_seats(p_booking uuid, p_seats text[], p_codes text[])
returns void language plpgsql security invoker set search_path = public as $$
declare ev uuid; taken text[];
begin
  select event_id into ev from public.bookings where id = p_booking;
  if ev is null then raise exception 'not_found'; end if;
  if coalesce(array_length(p_seats, 1), 0) = 0 then raise exception 'bad_seats'; end if;
  perform pg_advisory_xact_lock(hashtext(ev::text));
  select array_agg(seat_id) into taken from public.seats where event_id = ev and seat_id = any(p_seats) and booking_id <> p_booking;
  if taken is not null then raise exception 'conflict:%', array_to_string(taken, ','); end if;
  delete from public.seats where booking_id = p_booking and not (seat_id = any(p_seats));
  insert into public.seats(event_id, seat_id, booking_id, code)
    select ev, s, p_booking, upper(c) from unnest(p_seats, p_codes) as t(s, c)
    on conflict (event_id, seat_id) do nothing;
end $$;

create or replace function public.checkin_booking(p_booking uuid, p_in boolean)
returns void language sql security invoker set search_path = public as $$
  update public.seats set entered_at = case when p_in then coalesce(entered_at, now()) else null end
  where booking_id = p_booking;
$$;

-- Door scan: atomic, so two scanners can never admit the same ticket twice.
create or replace function public.validate_ticket(p_event uuid, p_code text)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare r record; ev record; t timestamptz;
begin
  select s.event_id, s.seat_id, s.booking_id, b.name into r
    from public.seats s join public.bookings b on b.id = s.booking_id
    where s.code = upper(p_code);
  if not found then return jsonb_build_object('status', 'invalid'); end if;
  if r.event_id <> p_event then
    select name, date, time into ev from public.events where id = r.event_id;
    return jsonb_build_object('status', 'other', 'event_name', ev.name, 'event_date', ev.date, 'event_time', ev.time);
  end if;
  update public.seats set entered_at = now()
    where event_id = r.event_id and seat_id = r.seat_id and entered_at is null
    returning entered_at into t;
  if t is not null then
    return jsonb_build_object('status', 'ok', 'seat_id', r.seat_id, 'name', r.name,
      'left', (select count(*) from public.seats where booking_id = r.booking_id and entered_at is null));
  end if;
  select entered_at into t from public.seats where event_id = r.event_id and seat_id = r.seat_id;
  return jsonb_build_object('status', 'used', 'seat_id', r.seat_id, 'name', r.name, 'entered_at', t);
end $$;

revoke execute on function public.create_booking(uuid, text, text, text, text[], text[]) from public, anon;
revoke execute on function public.set_booking_seats(uuid, text[], text[]) from public, anon;
revoke execute on function public.checkin_booking(uuid, boolean) from public, anon;
revoke execute on function public.validate_ticket(uuid, text) from public, anon;
grant execute on function public.create_booking(uuid, text, text, text, text[], text[]) to authenticated;
grant execute on function public.set_booking_seats(uuid, text[], text[]) to authenticated;
grant execute on function public.checkin_booking(uuid, boolean) to authenticated;
grant execute on function public.validate_ticket(uuid, text) to authenticated;

alter table public.bookings replica identity full;
alter table public.seats replica identity full;
alter publication supabase_realtime add table public.venue, public.events, public.bookings, public.seats, public.staff;
