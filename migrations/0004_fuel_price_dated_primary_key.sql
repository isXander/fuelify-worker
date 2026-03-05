-- Migration number: 0004 	 2026-03-05T01:15:06.196Z
PRAGMA foreign_keys = OFF;

CREATE TABLE pfs_fuel_prices_new (
    station_id TEXT NOT NULL REFERENCES pfs (id) ON DELETE CASCADE,
    fuel_type  TEXT NOT NULL,
    price      REAL NOT NULL,
    effective_date DATE NOT NULL,
    PRIMARY KEY (station_id, fuel_type, effective_date)
);

INSERT INTO pfs_fuel_prices_new SELECT * FROM pfs_fuel_prices;
DROP TABLE pfs_fuel_prices;
ALTER TABLE pfs_fuel_prices_new RENAME TO pfs_fuel_prices;

PRAGMA foreign_keys = ON;
