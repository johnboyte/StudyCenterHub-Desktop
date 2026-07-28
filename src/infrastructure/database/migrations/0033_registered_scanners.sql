-- Migration 0033: Create registered_scanners table for hardware barcode scanners (NETUM DS2800)
-- Complies with offline-first synchronization & server-side location resolution

CREATE TABLE IF NOT EXISTS registered_scanners (
    scanner_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    facility TEXT NOT NULL DEFAULT 'Real Life House',
    location TEXT NOT NULL DEFAULT 'Main Entrance',
    mode TEXT NOT NULL DEFAULT 'Study Center Daily',
    secret_key TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed default hardware scanner configuration
INSERT OR IGNORE INTO registered_scanners (scanner_id, display_name, facility, location, mode, secret_key, status)
VALUES ('N324D5G0010', 'NETUM DS2800 Entry Scanner', 'Real Life House', 'Main Entrance', 'Study Center Daily', 'SCH_SCANNER_SECRET_MASKED_N324D5G0010', 'active');
