-- Migration number: 0001 	 2026-03-04T20:37:34.341Z
CREATE TABLE pfs
(
    id                TEXT PRIMARY KEY,
    phone_number      TEXT    NOT NULL,
    trading_name      TEXT    NOT NULL,
    brand_name        TEXT    NOT NULL,
    trading_as_brand  BOOLEAN NOT NULL,
    temporary_closure BOOLEAN NOT NULL,
    permanent_closure BOOLEAN NOT NULL,
    motorway          BOOLEAN NOT NULL,
    supermarket       BOOLEAN NOT NULL
);

CREATE TABLE pfs_locations
(
    station_id     TEXT PRIMARY KEY REFERENCES pfs (id) ON DELETE CASCADE,
    address_line_1 TEXT NOT NULL,
    address_line_2 TEXT NOT NULL,
    city           TEXT NOT NULL,
    country        TEXT NOT NULL,
    county         TEXT NOT NULL,
    postcode       TEXT NOT NULL,
    latitude       REAL NOT NULL,
    longitude      REAL NOT NULL
);

CREATE TABLE pfs_fuel_prices
(
    station_id TEXT NOT NULL REFERENCES pfs (id) ON DELETE CASCADE,
    fuel_type  TEXT NOT NULL,
    price      REAL NOT NULL,
    PRIMARY KEY (station_id, fuel_type)
);

CREATE TABLE pfs_amenities
(
    station_id TEXT NOT NULL REFERENCES pfs (id) ON DELETE CASCADE,
    type       TEXT NOT NULL,
    PRIMARY KEY (station_id, type)
);

CREATE TABLE pfs_opening_hours
(
    station_id  TEXT    NOT NULL REFERENCES pfs (id) ON DELETE CASCADE,
    day         TEXT    NOT NULL,
    open_time   TEXT    NOT NULL,
    close_time  TEXT    NOT NULL,
    is_24_hours BOOLEAN NOT NULL,
    PRIMARY KEY (station_id, day)
);

CREATE INDEX pfs_geo_lat_lon_idx ON pfs_locations (latitude, longitude);