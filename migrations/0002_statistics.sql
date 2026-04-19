-- Migration number: 0002 	 2026-04-07T14:26:17.365Z

CREATE TABLE regional_statistics (
    h3_res3       TEXT    NOT NULL,
    fuel_type     TEXT    NOT NULL,
    station_count INTEGER NOT NULL,
    min_price     INTEGER NOT NULL,
    max_price     INTEGER NOT NULL,
    mean_price    INTEGER NOT NULL,
    date          TEXT    NOT NULL,
    PRIMARY KEY (h3_res3, fuel_type, date)
);