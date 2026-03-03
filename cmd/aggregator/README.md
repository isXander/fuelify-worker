# Aggregator service

This binary runs the fuel aggregator as a standalone worker that writes into the shared Postgres database used by the API.

## Environment

- `DATABASE_URL` (required)
- `AGGREGATOR_CLIENT_ID` (required)
- `AGGREGATOR_CLIENT_SECRET` (required)
- `AGGREGATOR_INFO_SYNC_PERIOD` (optional, default `15m`)
- `AGGREGATOR_FULL_SYNC_ON_START` (optional, default `false`)

## Behavior

- Single worker loop (`1` concurrent request).
- Request pace is fixed at `30 req/min` (`1 request every 2s`).
- Incremental sync uses the exact last successful sync timestamp.
- On HTTP `429`, it waits for `Retry-After` (or `5s` fallback) and retries.
- Batch pagination stops on API terminal errors like `Requested batch N is not available`.
- Stores per-endpoint sync cursors in `pfs_sync_cursors`.

## Run

```bash
go run ./cmd/aggregator
```
