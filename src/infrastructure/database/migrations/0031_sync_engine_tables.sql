-- Migration 0031: Sync Engine Tables and Stable Entity UUIDs
-- Supports RFC 101 Durable 2-Way Synchronization

CREATE TABLE IF NOT EXISTS sync_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sync_devices (
    device_id TEXT PRIMARY KEY,
    customer_uuid TEXT NOT NULL,
    display_name TEXT NOT NULL,
    api_key TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sync_conflicts (
    conflict_uuid TEXT PRIMARY KEY,
    event_uuid TEXT NOT NULL,
    entity_uuid TEXT NOT NULL,
    conflict_type TEXT NOT NULL,
    local_value TEXT,
    remote_value TEXT,
    status TEXT NOT NULL DEFAULT 'unresolved',
    resolution_notes TEXT,
    resolved_by TEXT,
    resolved_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS event_inbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    sequence_num INTEGER NOT NULL,
    processed_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_event_inbox_uuid ON event_inbox(event_uuid);

CREATE TABLE IF NOT EXISTS event_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    retry_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    synced_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_event_outbox_status ON event_outbox(status, id);
