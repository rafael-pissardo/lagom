# Lagom — Merchant Settlement Engine

Lagom is a Swedish word for balance and the right measure. This app calculates fair merchant disbursements and seQura commissions from order data.

Built for the [seQura backend coding challenge](https://sequra.github.io/backend-challenge/).

Planning: [docs/planning.md](docs/planning.md).

How the AI was used: [docs/registro-da-construcao.md](docs/registro-da-construcao.md).

## Stack

- Ruby 4.0.7
- Rails 8.1.4
- PostgreSQL
- Solid Queue (1 process, 1 thread)
- Hotwire + Tailwind (Railway-inspired dark UI)
- RSpec, FactoryBot, SimpleCov
- Devise (email and password only)
- Mission Control for job inspection

## Setup

```bash
docker compose up -d
bundle install
bin/rails db:prepare db:seed
bin/dev
```

In another terminal:

```bash
bin/jobs
```

`db:seed` creates the operator in every environment, including production:

- email: `operator@lagom.local`
- password: `lagom-operator-password`

`OPERATOR_EMAIL` and `OPERATOR_PASSWORD` override those values when set. They are optional.

Postgres defaults to `localhost:5434` so it does not collide with other local databases.

## CSV import

Upload the official SeQura `merchants.csv` and `orders.csv` (`;` separator) from **CSV imports**. The request returns immediately; Solid Queue processes the files and then backfills disbursements and monthly fees.

## Settlement rules implemented

- Orders are disbursed exactly once.
- Daily merchants settle every day; weekly merchants settle on the weekday of `live_on`.
- Production queries take undisbursed orders with `ordered_on <= yesterday` and `ordered_on >= live_on`, so a missed day is caught up.
- Commission: `< 50€` → 1.00%, `50€..<300€` → 0.95%, `≥ 300€` → 0.85%, always rounded up to 2 decimals.
- Net to merchant = gross − order commissions. Monthly fees are stored, not subtracted.
- Monthly fees close on the 1st for the previous calendar month. Backfill uses the CSV clock (`max(ordered_on)`), so November 2023 orders are disbursed and November 2023 monthly fees are not charged.

## Yearly report

After importing and backfilling, open **Yearly report** or run:

```bash
bin/rails runner 'puts YearlyReport.call.inspect'
```

Fill the challenge table in your submission with those numbers.

| Year | Number of disbursements | Amount disbursed to merchants | Amount of order fees | Number of monthly fees charged | Amount of monthly fees charged |
| --- | --- | --- | --- | --- | --- |
| _run import first_ |  |  |  |  |  |

## Tests

```bash
bundle exec rspec
COVERAGE=true bundle exec rspec
bundle exec rubocop
bundle exec bundler-audit check --update
bundle exec brakeman -q -w2
```

RSpec runs in random order with the documentation formatter.

## CI/CD

GitHub Actions runs four parallel jobs on every pull request and push:

1. RSpec
2. RuboCop
3. Vulnerability (`bundler-audit` + `brakeman`)
4. Coverage (SimpleCov, minimum 95%)

Deploy waits for all four. Configure Railway to deploy `staging` → staging and `main` → production.

## Railway

Create two environments (staging, production), attach Postgres, set:

- `RAILS_ENV`
- `DATABASE_URL`
- `SECRET_KEY_BASE`
- `APP_HOST`

`OPERATOR_EMAIL` and `OPERATOR_PASSWORD` are optional. When they are absent, seed uses `operator@lagom.local` and `lagom-operator-password`.

Run web + worker processes from the `Procfile`. The Railway pre-deploy command and the production container both run `db:prepare db:seed` before the server starts, including when the database already exists.

## Trade-offs for the next version

- **P0.** No logging service such as Datadog. Server logs are the workaround today.
- **P1.** Railway Hobby will not absorb large data or user load. Measure infra behaviour next.
- **P2.** CSV files are not stored in a bucket, so file-level traceability is lost after processing.

## Decisions and AI usage

- Money is stored as integer cents via `Finance::Amount`. Product commission tiers live in `Commission`.
- UI strings go through Rails I18n (`en`) from day one.
- Tailwind ViewComponents mirror the railway.com dark palette without copying Railway branding.
- Cursor was used to plan and implement. Business rules come from the challenge text and the decisions recorded during planning, not from invented product behaviour.

## What was left out on purpose

- No manual order form; new orders arrive through CSV.
- No CORS setup; there is no separate frontend origin.
- No public signup, password recovery, confirmation, or account lock. One operator account owns the console.
