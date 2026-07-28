-- Migration 0021: Create local inbound_event_queue table for pulling and processing raw generic events from the cloud relay.
-- Complies with [PD-001] (Offline Storage)

CREATE TABLE IF NOT EXISTS inbound_event_queue (
    id INTEGER PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    received_at TEXT NOT NULL,
    processed INTEGER NOT NULL DEFAULT 0
);
