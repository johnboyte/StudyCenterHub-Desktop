/* Migration 0022: IVR Settings (global voice configuration) */
CREATE TABLE IF NOT EXISTS ivr_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    voice_name TEXT NOT NULL DEFAULT 'Polly.Joanna',
    language TEXT NOT NULL DEFAULT 'en-US',
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT OR IGNORE INTO ivr_settings (id, voice_name, language) VALUES (1, 'Polly.Joanna', 'en-US');
