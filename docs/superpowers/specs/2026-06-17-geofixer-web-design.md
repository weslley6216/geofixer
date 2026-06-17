# Geofixer Web — mobile upload interface (design)

**Date:** 2026-06-17
**Status:** Approved direction, pending spec review

## Overview

Replace the Google-Drive-polling cron with a small web app that lets the user
upload an `.xlsx` of addresses from their phone, processes it on demand, and
serves the resulting `.csv` and log `.txt` for download. The existing
processing core (`AddressProcessor` and its services, hardened in Phase 1) is
reused unchanged.

## Goals

- Upload an `.xlsx` from a phone browser and get the processed `.csv` + log back.
- On-demand processing (no 5-minute polling wait).
- No dependency on the user's desktop being on.
- Stay **free to run** (hard constraint).

## Non-goals

- Google Drive integration, OAuth, accounts/users beyond a single shared login.
- Persisting jobs across restarts, multi-tenant use, or horizontal scaling.
- Real-time progress percentage (a simple queued/running/done status is enough).

## Architecture

A single Ruby process running **Sinatra** (modular `Sinatra::Base`) behind
**Puma**, with one **in-process background thread** that processes jobs from a
FIFO queue, one at a time.

> **This is a thread inside the web process, not a separate Render Background
> Worker** (those are not free). Everything — HTTP and processing — runs in one
> Render free Web Service. This works because Render does not throttle CPU
> between requests: the instance keeps running until it spins down after ~15 min
> idle, and the status-page polling keeps it alive for the 1–2 min a job takes.

```
phone ── GET /            ─▶ upload form (HTML, mobile-friendly)
      ── POST /upload      ─▶ save .xlsx, enqueue job, 302 ─▶ /jobs/:id
      ── GET /jobs/:id     ─▶ status page (auto-refresh): queued | running | done | failed
      ── GET /jobs/:id/download/csv  (and /log) ─▶ serves the result file
```

All routes are behind HTTP Basic Auth.

### Why a single worker (one job at a time)

`Utils::CacheManager` is process-wide global state that `AddressProcessor`
clears at the end of each run. Two concurrent `process_file` calls would clobber
each other's cache. A single FIFO worker sidesteps the race entirely and keeps
CPU/memory bounded on a 512 MB free instance. For a single user this is
invisible; a second upload simply waits in the queue.

## Components

Each is small, single-purpose, and testable in isolation.

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `Web::App` (`Sinatra::Base`) | HTTP routes only: form, upload, status, download. No business logic. | `JobRegistry`, `JobQueue` |
| `JobQueue` | FIFO queue + single in-process thread (started at boot inside the web process); runs one job at a time; updates the registry. | `JobRunner` |
| `JobRunner` | Process one job end to end: convert → `AddressProcessor` → record result paths; capture failures. | `XlsxConverter`, `AddressProcessor` |
| `JobRegistry` | Thread-safe map `job_id → {status, csv_path, log_path, error}`. Mutex-guarded. | — |
| `XlsxConverter` | `.xlsx → .csv` (extracted from the deleted `Main`). | `roo`, `csv` |
| `AddressProcessor` + services | **Unchanged Phase 1 core.** | — |

### Job lifecycle

1. `POST /upload` saves the upload to `tmp/jobs/<uuid>/input.xlsx`, registers the
   job as `queued`, enqueues it, and redirects to `/jobs/<uuid>`.
2. The worker pops the job, sets `running`, runs `JobRunner`:
   `input.xlsx → input.csv → <label>.csv` + `<label> log_enderecos.txt`.
3. On success the registry stores `done` + the two result paths; on any
   exception it stores `failed` + a short message. `CacheManager` is cleared
   between jobs (already done inside `process_file`).
4. The status page polls via `<meta http-equiv="refresh" content="3">` while
   `queued`/`running`; when `done` it shows download links; when `failed` it
   shows the error and a link back to the form.

## Storage & cleanup

Working files live under `tmp/jobs/<uuid>/` (ephemeral disk — fine, jobs are
transient). A lightweight sweep on each new upload deletes job directories older
than a TTL (default 60 min) to bound disk use. No database.

## Security

- All routes behind `Rack::Auth::Basic`; credentials from `BASIC_AUTH_USER` /
  `BASIC_AUTH_PASSWORD`. Without them, requests get `401`. This protects the
  paid Google Maps quota from anyone who finds the URL.
- The app refuses to boot if the auth env vars are unset (fail closed).

## Configuration (env vars)

| Var | Purpose |
|-----|---------|
| `GOOGLE_API_KEY` | Geocoding (existing). |
| `BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD` | App login. |
| `OUTPUT_LABEL` | Output filename label (default `Andreia Eslava`). |
| `PORT` | Provided by Render; Puma binds to it. |

No `credentials.json` / `token.yml` / OAuth.

## Input validation & error handling

- Accept only `.xlsx` (reject by extension; surface a friendly form error).
- A spreadsheet `roo` can't open, or missing expected columns, → job `failed`
  with a readable message rather than a 500.
- Network failures inside processing are already handled by `Utils::HttpClient`
  (timeouts, retries, nil-on-failure) — a slow API degrades a row, never hangs
  the worker.

## Deploy (Render, free)

- **One** Render free **Web Service** — no Background Worker, no cron, no Redis,
  no database, no paid add-ons. The processing thread lives inside this service.
- **Docker** image (`ruby:4.0.1` base) so the pinned Ruby version is honored
  regardless of Render's native runtimes. `config.ru` + Puma; `Dockerfile`
  installs gems and runs `bundle exec puma`.
- Render free web service, **not** kept warm by UptimeRobot — it sleeps when
  idle (occasional use keeps it within the shared 750 h/month free pool
  alongside the user's existing always-on app). Cold start (~30–60 s) only on
  the first request after idle; acceptable for on-demand use.

## Testing

- `Web::App` via `Rack::Test`: no credentials → `401`; `GET /` returns the form;
  `POST /upload` with a fixture `.xlsx` creates a job and redirects;
  `GET /jobs/:id` reflects status; download serves the file.
- `JobRunner` / `JobQueue`: a fixture job produces the expected result paths;
  a failing conversion marks the job `failed`. Run the worker synchronously in
  tests (inject the runner / drain the queue) to keep tests deterministic.
- `XlsxConverter`: a fixture `.xlsx` converts to the expected `.csv` rows.
- Processing core: already covered by Phase 1 specs.

## Removals

- `main.rb`, `run_main.sh`, and the cron entry.
- `app/services/google_drive/**` and `spec/services/google_drive/**`.
- Gems: `google-apis-drive_v3`, `googleauth`, `pstore` (only googleauth needed
  it). `config/credentials.json`, `config/token.yml`.
- README updated to describe the web flow instead of the Drive cron.

## Decisions resolved

- No Drive — direct upload → download.
- Render free, Docker, sleeps when idle.
- ~100 addresses/file average → asynchronous (queued) processing.
- Single FIFO worker; Sinatra + Puma; HTTP Basic Auth.
