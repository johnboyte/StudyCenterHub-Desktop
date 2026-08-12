-- Migration 0047: IVR Script Drafts Table
-- Stores the administrator's edited drafts of suggested phone scripts.

CREATE TABLE IF NOT EXISTS ivr_script_drafts (
    prompt_key TEXT PRIMARY KEY,
    suggested_draft TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
