-- Core enums
create type group_status as enum (
  'NEW',
  'ISSUED',
  'COLLECTING',
  'ANALYZING',
  'REPORTING',
  'DONE',
  'SENT'
);

create type invitation_state as enum (
  'UNUSED',
  'RESERVED',
  'USED'
);

create type question_type as enum (
  'LIKERT',
  'TEXT'
);

-- groups
create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  org_name text not null,
  owner_name text not null,
  owner_email text not null,
  requested_count int not null,
  status group_status not null default 'NEW',
  assessment_version text not null,
  report_pdf_path text,
  report_csv_path text,
  created_at timestamptz not null default now()
);

-- invitations
create table if not exists invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  participant_id text not null,
  participant_key text not null,
  state invitation_state not null default 'UNUSED',
  reserved_until timestamptz,
  reserved_token uuid,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (group_id, participant_id, participant_key)
);

create index if not exists invitations_group_id_idx on invitations(group_id);
create index if not exists invitations_reserved_token_idx on invitations(reserved_token);

-- responses
create table if not exists responses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references groups(id) on delete cascade,
  invitation_id uuid not null references invitations(id) on delete cascade,
  answers jsonb not null,
  individual_result jsonb,
  created_at timestamptz not null default now(),
  unique (invitation_id)
);

create index if not exists responses_group_id_idx on responses(group_id);

-- assessments
create table if not exists assessments (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

-- dimensions
create table if not exists dimensions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references assessments(id) on delete cascade,
  key text not null,
  label text not null,
  "order" int not null,
  created_at timestamptz not null default now()
);

create unique index if not exists dimensions_assessment_key_idx on dimensions(assessment_id, key);

-- questions
create table if not exists questions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references assessments(id) on delete cascade,
  type question_type not null,
  prompt text not null,
  dimension_id uuid references dimensions(id) on delete set null,
  weight numeric not null default 1,
  "order" int not null,
  created_at timestamptz not null default now()
);

create index if not exists questions_assessment_id_idx on questions(assessment_id);
