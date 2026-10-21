# Lagom — Merchant Settlement Engine

Lagom is a Swedish word for balance and the right measure. This app calculates fair merchant disbursements and seQura commissions from order data.

Built for the [seQura backend coding challenge](https://sequra.github.io/backend-challenge/).

Planning: [docs/planning.md](docs/planning.md).

How the AI was used: [day 1](docs/registro-da-construcao.md), [day 2](docs/registro-da-construcao-dia-2.md), [day 3](docs/registro-da-construcao-dia-3.md). Those records stay in Portuguese. Translating them would replace the original wording of the prompts, and that wording is what the audit has to preserve.

## Stack

- Ruby 4.0.7
- Rails 8.1.4
- PostgreSQL
- Solid Queue (1 process, 1 thread)
- Solid Cable (messages in the primary database)
- Hotwire + Tailwind (Railway-inspired dark UI)
- Pagy (10 rows per page)
- RSpec, FactoryBot, SimpleCov
- Devise (email and password only)
- Mission Control at `/jobs` (not linked from the sidebar)

## Setup

```bash
docker compose up -d
bundle install
bin/rails db:prepare
bin/dev
```

In another terminal:

```bash
bin/jobs
```

The seed does not create a user. Create the operator outside `db/seeds.rb`.

Postgres defaults to `localhost:5434` so it does not collide with other local databases.

`docker compose up -d` also starts a local S3-compatible bucket (MinIO) on `localhost:9000` and creates a bucket named `lagom`. In development, these variables fall back to that local bucket when they are unset:

- `AWS_ACCESS_KEY_ID=lagom`
- `AWS_SECRET_ACCESS_KEY=lagom-secret`
- `AWS_DEFAULT_REGION=us-east-1`
- `AWS_ENDPOINT_URL=http://localhost:9000`
- `AWS_S3_BUCKET_NAME=lagom`

`CSV_IMPORT_BATCH_SIZE` defaults to `500`.

## CSV import

From **CSV imports**, choose Merchant or Orders and upload one `;`-separated CSV. The file is stored in the bucket as `{kind}-{timestamp}.csv` before the import record is created. The request returns immediately with status `processing`. Solid Queue reads the file in batches. A successful import stores the rows and does not settle them. `DailyMerchantsJob` and `WeeklyMerchantsJob` settle what is already stored.

A row error rolls the whole file back. Nothing from that CSV is stored, and no settlement job is enqueued. The import page offers a plain-text download of the line and column. An `id` that is already stored is one of those errors. The download reads `line 2, column id: has already been processed and cannot be imported again`. The same `id` repeated only inside a file that has not been stored yet keeps the last row.

The show page subscribes over Action Cable while the import is `pending` or `processing`. When the status changes, the page replaces the status block in place. A finished import does not subscribe. Solid Cable carries the message from the worker process to the web process.

## Operator console

The sidebar lists merchants, disbursements, monthly fees, the yearly report, and CSV imports.

Each index shows 10 rows per page. The footer reads `Showing 1–10 of 12 · 10 per page`, including when the list fits on one page. Filters update as you type: a partial, case-insensitive match on name or email, a calendar for dates, and a dropdown for tags such as frequency or status. There is no Filter button. Each column header has ↑ and ↓. Dates render as `DD/MM/YYYY`. Amounts group thousands and keep a dot decimal, as in `36,928,327.40 €`.

## Settlement rules implemented

- Orders are disbursed exactly once. Running a job again for a day that already has a disbursement does not insert another one, and does not insert a second monthly fee for the same merchant and month.
- `DailyMerchantsJob` settles `DAILY` merchants. `WeeklyMerchantsJob` settles `WEEKLY` merchants. Both run at 07:00 UTC every day. The weekly job runs every day because each merchant is paid on the weekday of their own `live_on`. On any other weekday that merchant gets no disbursement.
- The first run for a merchant starts at `live_on`. A later run starts the day after that merchant's latest disbursement. The run pays every eligible day up to the calendar day, one disbursement per day. Daily merchants get each missed day. Weekly merchants get only the weekday of `live_on`. An order belongs to one disbursement. Orders in that disbursement have `ordered_on <=` the day before it, and `ordered_on >= live_on`.
- An amount with a digit after the second decimal place rounds up to the next cent before commission is calculated. `1.239` becomes `1.24 €`. `1.230` stays `1.23 €`.
- Commission is calculated per order and rounded up to the next cent: `< 50€` → 1.00%, `50€..<300€` → 0.95%, `≥ 300€` → 0.85%.
- Net to merchant = gross − order commissions. Monthly fees are stored, not subtracted.
- Each job closes every month from that merchant's `live_on` month through the previous calendar month when the fee does not exist yet. It does not close the current month. `ChargeMonthlyFeeService` does not create a second row for the same merchant and month. Each month is charged from its own commissions.
- A charged month is not rewritten. When a later import adds orders to a month that already has a fee, the job keeps that fee row as it was and stores a `MonthlyFeeAdjustment` with the new commission total and the credit owed back: the part of the charge those commissions now cover. More late orders add another adjustment for the further difference only. A credit never exceeds what was charged. The yearly report counts that credit in the year the adjustment was recorded, not in the year of the closed month. Total monthly fees for a year are that year's charged amount minus the credits recorded in that year. The same charged amount is also shown on its own, in the marked column Total without adjustments. A year with only credits can show a negative total.
- A month with no commissions is charged the full minimum. The first month is charged in full even when `live_on` falls in the middle of it. There is no pro-rata.

## Yearly report

A disbursement counts in the year of `disbursed_on`. A monthly fee counts in the year of the closed month, which is the `year` stored on the fee. An order placed on 31/12/2022 and disbursed on 01/01/2023 counts in 2023. The December 2022 fee counts in 2022.

The page filters by year as you type, sorts every column, and pages 10 years at a time. It stays subscribed over Action Cable. A new or changed disbursement or monthly fee refreshes the table, at most once every 2 seconds, and each settlement job sends one more refresh when it finishes. The current year filter, sort, and page stay in the URL.

The table is the official file as settled through 14 Nov 2023. Importing a CSV does not settle it, and the jobs do not rebuild this table. Open **Yearly report** or run:

```bash
bin/rails runner 'puts YearlyReportService.call.inspect'
```

| Year | Number of disbursements | Amount disbursed to merchants | Amount of order fees | Number of monthly fees charged | Total without adjustments | Monthly fee adjustments | Total monthly fees |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2022 | 1509 | 36,928,327.40 € | 334,670.02 € | 31 | 562.83 € | 0.00 € | 562.83 € |
| 2023 | 10391 | 188,559,107.94 € | 1,714,752.55 € | 104 | 1,735.65 € | 0.00 € | 1,735.65 € |

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
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`
- `AWS_ENDPOINT_URL`
- `AWS_S3_BUCKET_NAME`

`CSV_IMPORT_BATCH_SIZE` is optional and defaults to 500.

Run web + worker processes from the `Procfile`. The Railway pre-deploy command and the production container both run `db:prepare` before the server starts. Neither creates an operator.

## Decisions not taken

- A run closes only the immediately previous month. If the job does not run for a whole month, that older month is never charged. Catching up every missed month was not part of this change.

## What I would improve with more time

- **P0.** No logging service such as Datadog. Server logs are the workaround today.
- **P1.** Railway Hobby will not absorb large data or user load. Measure infra behaviour next.
- Close every missed monthly fee, not only the previous month, if a run can be down for more than a few days.

## Questions for seQura

- Year axis: should a disbursement on 01/01/2023 of a 31/12/2022 order count in 2023, and the December fee in 2022? That is what this report does.
- Pro-rata: the first month is charged the full minimum when `live_on` is mid-month, and a month with no commissions is charged the full minimum. Should either case be prorated?
- Missed day: the next run creates one disbursement per eligible day (each day for a daily merchant, only the `live_on` weekday for a weekly merchant). Should a skipped day instead be folded into a single disbursement on the day the job recovers?

## Decisions and AI usage

- Money is stored as integer cents via `Finance::Amount`. The screen groups thousands (`131,931.34 €`). Product commission tiers live in `Commission`.
- Dates on screen use `DD/MM/YYYY`. Filter fields still submit `YYYY-MM-DD`, which is what the date input requires.
- UI strings go through Rails I18n (`en`) from day one.
- Tailwind ViewComponents mirror the railway.com dark palette without copying Railway branding.
- Cursor was used to plan and implement. Business rules come from the challenge text and the decisions recorded during planning, not from invented product behaviour.

## What was left out on purpose

- No manual order form; new orders arrive through CSV.
- No CORS setup; there is no separate frontend origin.
- No public signup, password recovery, confirmation, or account lock. One operator account owns the console.
