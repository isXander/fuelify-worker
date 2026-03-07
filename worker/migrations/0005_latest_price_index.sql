-- Migration number: 0005 	 2026-03-07T01:00:09.236Z
CREATE INDEX pfs_fuel_prices_station_date_idx
    ON pfs_fuel_prices (station_id, fuel_type, effective_date DESC);

