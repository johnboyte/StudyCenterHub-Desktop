-- Migration 0061: Playlist Provider Integration and Synchronization
-- Extends Playlists schema for provider management (General, YouTube, Spotify, Apple Music)

ALTER TABLE playlists ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'general';

CREATE TABLE IF NOT EXISTS playlist_provider_links (
    id TEXT PRIMARY KEY,
    playlist_id TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'youtube',
    external_playlist_id TEXT DEFAULT '',
    external_playlist_url TEXT DEFAULT '',
    sync_enabled INTEGER NOT NULL DEFAULT 1,
    sync_status TEXT NOT NULL DEFAULT 'not_synced',
    last_synced_at TEXT DEFAULT '',
    last_sync_error TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS playlist_item_provider_links (
    id TEXT PRIMARY KEY,
    playlist_item_id TEXT NOT NULL,
    provider TEXT NOT NULL DEFAULT 'youtube',
    external_item_id TEXT DEFAULT '',
    external_media_id TEXT DEFAULT '',
    sync_status TEXT NOT NULL DEFAULT 'synced',
    last_synced_at TEXT DEFAULT '',
    last_sync_error TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (playlist_item_id) REFERENCES playlist_items(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlist_provider_links_pid ON playlist_provider_links(playlist_id);
CREATE INDEX IF NOT EXISTS idx_playlist_item_provider_links_itemid ON playlist_item_provider_links(playlist_item_id);
