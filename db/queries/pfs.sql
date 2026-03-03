-- name: UpsertPFS :exec
INSERT INTO pfs (
    id,
    phone_number,
    trading_name,
    brand_name,
    trading_as_brand,
    temporary_closure,
    permanent_closure,
    motorway,
    supermarket
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9
)
ON CONFLICT (id) DO UPDATE SET
    phone_number = EXCLUDED.phone_number,
    trading_name = EXCLUDED.trading_name,
    brand_name = EXCLUDED.brand_name,
    trading_as_brand = EXCLUDED.trading_as_brand,
    temporary_closure = EXCLUDED.temporary_closure,
    permanent_closure = EXCLUDED.permanent_closure,
    motorway = EXCLUDED.motorway,
    supermarket = EXCLUDED.supermarket;

-- name: UpsertLocation :exec
INSERT INTO pfs_locations (
    station_id,
    address_line_1,
    address_line_2,
    city,
    country,
    county,
    postcode,
    latitude,
    longitude
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9
)
ON CONFLICT (station_id) DO UPDATE SET
    address_line_1 = EXCLUDED.address_line_1,
    address_line_2 = EXCLUDED.address_line_2,
    city = EXCLUDED.city,
    country = EXCLUDED.country,
    county = EXCLUDED.county,
    postcode = EXCLUDED.postcode,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude;

-- name: DeleteFuelPricesForStation :exec
DELETE FROM pfs_fuel_prices
WHERE station_id = $1;

-- name: InsertFuelPrice :exec
INSERT INTO pfs_fuel_prices (
    station_id,
    fuel_type,
    price
) VALUES (
    $1, $2, $3
)
ON CONFLICT (station_id, fuel_type) DO UPDATE SET
    price = EXCLUDED.price;

-- name: DeleteAmenitiesForStation :exec
DELETE FROM pfs_amenities
WHERE station_id = $1;

-- name: InsertAmenity :exec
INSERT INTO pfs_amenities (
    station_id,
    type
) VALUES (
    $1, $2
)
ON CONFLICT (station_id, type) DO NOTHING;

-- name: DeleteOpeningHoursForStation :exec
DELETE FROM pfs_opening_hours
WHERE station_id = $1;

-- name: InsertOpeningHour :exec
INSERT INTO pfs_opening_hours (
    station_id,
    day,
    open_time,
    close_time,
    is_24_hours
) VALUES (
    $1, $2, $3, $4, $5
)
ON CONFLICT (station_id, day) DO UPDATE SET
    open_time = EXCLUDED.open_time,
    close_time = EXCLUDED.close_time,
    is_24_hours = EXCLUDED.is_24_hours;

-- name: GetPFS :one
SELECT
    id,
    phone_number,
    trading_name,
    brand_name,
    trading_as_brand,
    temporary_closure,
    permanent_closure,
    motorway,
    supermarket
FROM pfs
WHERE id = $1;

-- name: GetLocation :one
SELECT
    station_id,
    address_line_1,
    address_line_2,
    city,
    country,
    county,
    postcode,
    latitude,
    longitude
FROM pfs_locations
WHERE station_id = $1;

-- name: ListFuelPrices :many
SELECT
    station_id,
    fuel_type,
    price
FROM pfs_fuel_prices
WHERE station_id = $1
ORDER BY fuel_type;

-- name: ListAmenities :many
SELECT
    station_id,
    type
FROM pfs_amenities
WHERE station_id = $1
ORDER BY type;

-- name: ListOpeningHours :many
SELECT
    station_id,
    day,
    open_time,
    close_time,
    is_24_hours
FROM pfs_opening_hours
WHERE station_id = $1
ORDER BY day;

-- name: GetSyncCursor :one
SELECT
    cursor_key,
    last_effective_ts,
    updated_at
FROM pfs_sync_cursors
WHERE cursor_key = $1;

-- name: UpsertSyncCursor :exec
INSERT INTO pfs_sync_cursors (
    cursor_key,
    last_effective_ts
) VALUES (
    $1, $2
)
ON CONFLICT (cursor_key) DO UPDATE SET
    last_effective_ts = EXCLUDED.last_effective_ts,
    updated_at = NOW();
