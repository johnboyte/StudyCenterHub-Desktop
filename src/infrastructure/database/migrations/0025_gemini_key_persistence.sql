-- Migration 0025: Ensure app_settings preserves GEMINI_API_KEY permanently
CREATE TABLE IF NOT EXISTS app_settings (
    setting_key TEXT PRIMARY KEY,
    setting_value TEXT NOT NULL
);
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('GEMINI_API_KEY', '');
