-- Migration number: 0001    2026-04-05
-- Full schema: stations + fuel_prices (denormalized, prices in tenths of pence)

CREATE TABLE stations (
    id                TEXT PRIMARY KEY,
    phone_number      TEXT,
    trading_name      TEXT    NOT NULL,
    brand_name        TEXT    NOT NULL,
    trading_as_brand  BOOLEAN NOT NULL,
    temporary_closure BOOLEAN NOT NULL,
    permanent_closure BOOLEAN NOT NULL,
    motorway          BOOLEAN NOT NULL,
    supermarket       BOOLEAN NOT NULL,
    address_line_1    TEXT    NOT NULL DEFAULT '',
    address_line_2    TEXT    NOT NULL DEFAULT '',
    city              TEXT    NOT NULL DEFAULT '',
    country           TEXT    NOT NULL DEFAULT '',
    county            TEXT    NOT NULL DEFAULT '',
    postcode          TEXT    NOT NULL DEFAULT '',
    latitude          REAL    NOT NULL DEFAULT 0,
    longitude         REAL    NOT NULL DEFAULT 0,
    h3_index_r6       TEXT    NOT NULL,
    h3_index_r3       TEXT    NOT NULL,
    amenities         TEXT    NOT NULL DEFAULT '[]',
    opening_hours     TEXT    NOT NULL DEFAULT '{}'
);

CREATE INDEX stations_h3_r6_idx ON stations (h3_index_r6);
CREATE INDEX stations_h3_r3_idx ON stations (h3_index_r3);

CREATE TABLE fuel_prices (
    station_id     TEXT    NOT NULL,
    fuel_type      TEXT    NOT NULL,
    price          INTEGER NOT NULL,
    -- SQLite stores temporal values as TEXT; keep UTC ISO-8601 for lexical ordering.
    effective_date TEXT    NOT NULL,
    PRIMARY KEY (station_id, fuel_type, effective_date)
);

CREATE INDEX fuel_prices_station_date_idx
    ON fuel_prices (station_id, fuel_type, effective_date DESC);
