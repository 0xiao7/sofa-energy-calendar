-- ============================================================
-- B.CLASS Wallet｜人生現金流導航系統
-- Supabase / PostgreSQL：schema + RLS + 觸發器
-- 對應規劃書 v0.1 第 10 節「Database 規劃」
--
-- 設計原則：
--   1) 一切以「時間軸」為核心：transactions / debts / subscriptions 都有日期或到期日。
--   2) 所有業務表都帶 user_id，並開啟 Row Level Security（Supabase Auth）。
--   3) 金額一律以「最小貨幣單位（分）」存 bigint，避免浮點誤差；前端再除 100 顯示。
--   4) MVP 必做：wallets / transactions / debts / subscriptions / income_sources。
--      未來模組：skills / licenses / cashflow_predictions / life_events / ai_analysis_logs。
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- enum 型別
-- ------------------------------------------------------------
do $$ begin
  create type txn_type     as enum ('income','expense','transfer');
  create type debt_type    as enum ('credit_card','personal_loan','car_loan','bnpl','mortgage','personal_iou','other');
  create type sub_cycle    as enum ('weekly','monthly','quarterly','yearly');
  create type cashflow_lv  as enum ('safe','watch','tight','danger','broken'); -- 綠/黃/橘/紅/黑
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- users（對應 Supabase auth.users，存放 app 層級的偏好設定）
-- ------------------------------------------------------------
create table if not exists profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  display_name      text,
  base_currency     char(3)   not null default 'TWD',
  -- 現金流安全水位（分）：低於此值開始亮黃燈，0 以下為黑（斷裂）
  safety_buffer     bigint    not null default 3000000, -- 預設 30,000 元
  is_pro            boolean   not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ------------------------------------------------------------
-- wallets（現金 / 帳戶 / 電子支付，可有多個）
-- ------------------------------------------------------------
create table if not exists wallets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  name          text not null,
  kind          text not null default 'cash',         -- cash / bank / e-wallet ...
  balance       bigint not null default 0,            -- 目前餘額（分）
  is_archived   boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists idx_wallets_user on wallets(user_id);

-- ------------------------------------------------------------
-- income_sources（收入來源：薪資 / 副業 / 接案）
-- ------------------------------------------------------------
create table if not exists income_sources (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  name          text not null,                        -- 例：正職薪資、接案、家教
  category      text not null default 'salary',       -- salary / freelance / side / passive
  is_recurring  boolean not null default false,
  expected_day  smallint,                             -- 預期入帳日（1-31），僅 recurring
  expected_amt  bigint,                               -- 預期金額（分）
  created_at    timestamptz not null default now()
);
create index if not exists idx_income_user on income_sources(user_id);

-- ------------------------------------------------------------
-- transactions（核心：所有收支明細，時間軸的基本單位）
-- ------------------------------------------------------------
create table if not exists transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  wallet_id     uuid references wallets(id) on delete set null,
  type          txn_type not null,
  amount        bigint not null check (amount > 0),   -- 一律正數，方向看 type
  category      text not null,                        -- 早餐/房租/卡費/娛樂/副業收入...
  note          text,
  -- 關聯來源（讓報表能回推「這筆是哪個負債/訂閱/收入產生的」）
  debt_id       uuid,
  subscription_id uuid,
  income_source_id uuid references income_sources(id) on delete set null,
  occurred_on   date not null default current_date,   -- 發生日（月曆以此為準）
  created_at    timestamptz not null default now()
);
create index if not exists idx_txn_user_date on transactions(user_id, occurred_on);
create index if not exists idx_txn_category  on transactions(category);

-- ------------------------------------------------------------
-- debts（負債：信用卡 / 信貸 / 車貸 / BNPL / 人情借款）
-- ------------------------------------------------------------
create table if not exists debts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles(id) on delete cascade,
  name            text not null,
  type            debt_type not null default 'other',
  principal       bigint not null,                    -- 原始本金（分）
  remaining       bigint not null,                    -- 剩餘金額（分）
  apr             numeric(5,2) not null default 0,    -- 年利率 %（雪崩法依此排序）
  min_payment     bigint not null default 0,          -- 每期最低應繳（分）
  due_day         smallint,                           -- 每月還款日（1-31）
  next_due_on     date,                               -- 下一個到期日（提醒用）
  is_closed       boolean not null default false,
  created_at      timestamptz not null default now()
);
create index if not exists idx_debts_user on debts(user_id);
create index if not exists idx_debts_due  on debts(user_id, next_due_on);

-- ------------------------------------------------------------
-- subscriptions（訂閱 / 固定支出：Netflix、保險、房租）
-- ------------------------------------------------------------
create table if not exists subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  name          text not null,
  amount        bigint not null,                      -- 每期金額（分）
  cycle         sub_cycle not null default 'monthly',
  charge_day    smallint,                             -- 扣款日（1-31）
  next_charge_on date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists idx_subs_user on subscriptions(user_id);

-- ============================================================
-- 以下為未來模組（B.CLASS 整合 / Pro 版），先建表保留
-- ============================================================

-- skills（職能樹 / 技能變現）
create table if not exists skills (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  name          text not null,                        -- 例：記帳士、Excel、AI 工具
  level         smallint not null default 1,          -- 1-5
  monetizable   boolean not null default false,       -- 是否可變現
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_skills_user on skills(user_id);

-- licenses（證照）
create table if not exists licenses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  name          text not null,
  issued_on     date,
  expires_on    date,
  created_at    timestamptz not null default now()
);
create index if not exists idx_licenses_user on licenses(user_id);

-- life_events（人生事件：考試 / 轉職 / 搬家，用於區間分析）
create table if not exists life_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  title         text not null,
  category      text,                                 -- exam / career / move / medical ...
  start_on      date not null,
  end_on        date,
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_events_user on life_events(user_id, start_on);

-- cashflow_predictions（AI 現金流預測快照）
create table if not exists cashflow_predictions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  generated_at  timestamptz not null default now(),
  horizon_days  smallint not null default 60,
  survival_days smallint,                             -- 可維持天數
  danger_on     date,                                 -- 預測進入危險現金流的日期
  detail        jsonb,                                -- 每日預測明細
  created_at    timestamptz not null default now()
);
create index if not exists idx_pred_user on cashflow_predictions(user_id, generated_at);

-- ai_analysis_logs（AI 分析記錄：消費分析、副業建議）
create table if not exists ai_analysis_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  kind          text not null,                        -- spending / survival / side_hustle ...
  prompt        text,
  response      jsonb,
  model         text,                                 -- gemini-x / gpt-x
  created_at    timestamptz not null default now()
);
create index if not exists idx_ailog_user on ai_analysis_logs(user_id, created_at);

-- ============================================================
-- 觸發器：updated_at 自動更新
-- ============================================================
create or replace function touch_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

drop trigger if exists trg_profiles_touch on profiles;
create trigger trg_profiles_touch before update on profiles
  for each row execute function touch_updated_at();

-- ============================================================
-- Row Level Security：每位使用者只能存取自己的資料
-- ============================================================
alter table profiles             enable row level security;
alter table wallets              enable row level security;
alter table income_sources       enable row level security;
alter table transactions         enable row level security;
alter table debts                enable row level security;
alter table subscriptions        enable row level security;
alter table skills               enable row level security;
alter table licenses             enable row level security;
alter table life_events          enable row level security;
alter table cashflow_predictions enable row level security;
alter table ai_analysis_logs     enable row level security;

-- profiles：id 即 auth.uid()
drop policy if exists p_profiles_self on profiles;
create policy p_profiles_self on profiles
  using (id = auth.uid()) with check (id = auth.uid());

-- 其餘業務表：user_id = auth.uid()
do $$
declare t text;
begin
  foreach t in array array[
    'wallets','income_sources','transactions','debts','subscriptions',
    'skills','licenses','life_events','cashflow_predictions','ai_analysis_logs'
  ] loop
    execute format('drop policy if exists p_%1$s_self on %1$s;', t);
    execute format(
      'create policy p_%1$s_self on %1$s using (user_id = auth.uid()) with check (user_id = auth.uid());', t);
  end loop;
end $$;

-- ============================================================
-- 範例查詢：未來 N 天的「到期日」彙整（負債 + 訂閱），給月曆與提醒用
-- ============================================================
-- select d.next_due_on as on_date, 'debt' as src, d.name, d.min_payment as amount
--   from debts d where d.user_id = auth.uid() and not d.is_closed
--     and d.next_due_on between current_date and current_date + 60
-- union all
-- select s.next_charge_on, 'subscription', s.name, s.amount
--   from subscriptions s where s.user_id = auth.uid() and s.is_active
--     and s.next_charge_on between current_date and current_date + 60
-- order by on_date;
