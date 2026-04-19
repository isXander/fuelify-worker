-- Migration number: 0003    2026-04-19
-- The Rust ingest wrote B7 fuel types as `B7Standard` / `B7Premium` (strum Display
-- emits variant names verbatim; #[serde(rename)] only affected deserialization). The
-- TypeScript rewrite writes `B7_STANDARD` / `B7_PREMIUM`, and the API readers only
-- recognise the underscored forms. Rewrite the legacy rows so historical B7 data
-- remains visible and the (station_id, fuel_type, effective_date) dedupe key holds
-- across the cutover.

UPDATE fuel_prices
SET fuel_type = 'B7_STANDARD'
WHERE fuel_type = 'B7Standard';

UPDATE fuel_prices
SET fuel_type = 'B7_PREMIUM'
WHERE fuel_type = 'B7Premium';

UPDATE regional_statistics
SET fuel_type = 'B7_STANDARD'
WHERE fuel_type = 'B7Standard';

UPDATE regional_statistics
SET fuel_type = 'B7_PREMIUM'
WHERE fuel_type = 'B7Premium';
