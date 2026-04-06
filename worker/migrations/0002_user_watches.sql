-- Migration number: 0002    2026-04-06
-- User identity, device registration, and station price watches

CREATE TABLE users (
    id         TEXT PRIMARY KEY,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE devices (
    device_token TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users(id),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX devices_user_idx ON devices(user_id);

CREATE TABLE watched_stations (
    user_id              TEXT    NOT NULL REFERENCES users(id),
    station_id           TEXT    NOT NULL REFERENCES stations(id),
    fuel_type            TEXT    NOT NULL,
    last_notified_price  INTEGER,
    PRIMARY KEY (user_id, station_id, fuel_type)
);

CREATE INDEX watched_stations_station_idx ON watched_stations(station_id);
