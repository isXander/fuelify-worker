# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Deploy

This is a Cloudflare Worker written in Rust, compiled to WASM via `worker-build`.

```bash
# Build (same command Wrangler runs)
cargo install -q "worker-build@^0.7" && worker-build --release

# Local dev server
npx wrangler dev

# Deploy
npx wrangler deploy

# Run D1 migrations (local)
npx wrangler d1 migrations apply fuelify-d1 --local

# Run D1 migrations (remote)
npx wrangler d1 migrations apply fuelify-d1 --remote
```

There are no tests currently configured.

## Architecture

Fuelify Worker ingests UK petrol station data from the GOV.UK Fuel Finder API and serves it via a REST API. It runs on Cloudflare Workers with D1 (SQLite) for storage and KV for sync state.

### Two entry points in a single worker

- **Scheduled (cron)** — `src/ingestion/mod.rs`: Hourly trigger kicks off sequential batch ingestion. Enqueues `SyncTask` messages to a Cloudflare Queue, processing one batch at a time (batch N completes → enqueue batch N+1). A 404 from the upstream API signals no more data; the sync date is then saved to KV for incremental updates next run.

- **HTTP (fetch)** — `src/api/mod.rs`: REST API with three routes:
  - `POST /nearby` — bounding-box station search with fuel type filter, returns up to 200 stations with latest prices
  - `POST /price_history` — historical price samples for a station/fuel type over a time interval
  - `/fuel-finder-proxy/*` — authenticated reverse proxy to the Fuel Finder API (required because the API geo-blocks non-UK IPs; the worker is pinned to `azure:ukwest`)

### Data flow

Upstream Fuel Finder API → proxy route (UK IP) → ingestion batches → D1 tables (`stations`, `fuel_prices`). Ingestion runs in two phases: all station info batches first (so rows exist), then all fuel price batches. Upserts use `ON CONFLICT ... DO UPDATE` with WHERE guards to skip no-op writes.

### Key constraints

- The Fuel Finder API returns batches of 500 with no filtering — hence local D1 storage.
- The worker must run from a UK datacenter (`placement.region: azure:ukwest`) or the upstream API rejects requests.
- Auth tokens from the Fuel Finder OAuth endpoint are cached in KV with TTL.

### Secrets (configured via `wrangler secret`)

`GOVUK_CLIENT_ID`, `GOVUK_CLIENT_SECRET`, `PROXY_URL`, `PROXY_SECRET`

### Module layout

- `src/models.rs` — D1 row structs for `stations` and `fuel_prices` tables (with `int_as_bool` deserializer for SQLite booleans)
- `src/api/apitypes.rs` — API request/response types, `FuelType` and `Amenity` enums
- `src/ingestion/apitypes.rs` — upstream Fuel Finder API response types
- `src/ingestion/fetch.rs` — HTTP calls to the Fuel Finder API through the proxy

### D1 migrations

Located in `migrations/`. Numbered sequentially (`0001_init.sql`, etc.). Apply with `wrangler d1 migrations apply`.

### Post-deploy: schema reset

Migration 0006 drops and recreates all tables (denormalization). After deploying, delete the KV key `last_sync_date` from the `fuelify_ingest` namespace to trigger a full re-sync:

```bash
npx wrangler kv key delete --namespace-id=f3bb7e1457b448e087552eaea78ae67c last_sync_date
npx wrangler kv key delete --namespace-id=f3bb7e1457b448e087552eaea78ae67c access_token
```
