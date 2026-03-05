-- Migration number: 0003 	 2026-03-05T00:44:24.442Z
PRAGMA foreign_keys = OFF;

CREATE TABLE pfs_new (
    id                TEXT PRIMARY KEY,
    phone_number      TEXT,
    trading_name      TEXT    NOT NULL,
    brand_name        TEXT    NOT NULL,
    trading_as_brand  BOOLEAN NOT NULL,
    temporary_closure BOOLEAN NOT NULL,
    permanent_closure BOOLEAN NOT NULL,
    motorway          BOOLEAN NOT NULL,
    supermarket       BOOLEAN NOT NULL
);

INSERT INTO pfs_new SELECT * FROM pfs;
DROP TABLE pfs;
ALTER TABLE pfs_new RENAME TO pfs;

PRAGMA foreign_keys = ON;
