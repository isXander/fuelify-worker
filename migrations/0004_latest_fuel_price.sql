-- Migration number: 0004 	 2026-07-05T14:20:23.539Z

CREATE TABLE latest_fuel_price (
    station_id     TEXT    NOT NULL,
    fuel_type      TEXT    NOT NULL,
    price          INTEGER NOT NULL,
    effective_date TEXT    NOT NULL,
    PRIMARY KEY (station_id, fuel_type)
);

INSERT INTO latest_fuel_price (station_id, fuel_type, price, effective_date)
SELECT station_id, fuel_type, price, effective_date
FROM fuel_prices fp
WHERE fp.effective_date = (
    SELECT MAX(fp2.effective_date) FROM fuel_prices fp2
    WHERE fp2.station_id = fp.station_id AND fp2.fuel_type = fp.fuel_type
);

DROP INDEX IF EXISTS fuel_prices_station_date_idx;
