-- Migration 0019: Advanced Phone System settings and multi-level IVR options
-- Complies with [PD-001] (Offline Storage) and [PD-006] (Admin Config First)

-- 0. Ensure app_settings table exists
CREATE TABLE IF NOT EXISTS app_settings (
    setting_key TEXT PRIMARY KEY,
    setting_value TEXT NOT NULL
);

-- 1. Extend ivr_menu_options to support parent digits and custom audio upload
ALTER TABLE ivr_menu_options ADD COLUMN parent_digit TEXT REFERENCES ivr_menu_options(digit) ON DELETE CASCADE;
ALTER TABLE ivr_menu_options ADD COLUMN use_custom_audio INTEGER DEFAULT 0;
ALTER TABLE ivr_menu_options ADD COLUMN audio_data TEXT;

-- 2. Seed initial global phone system settings
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ON_CALL_PERSON_ID', '');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_RINGS', '4');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TTS_GREETING_ACTIVE', '1');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_TTS', 'Welcome to the Real Life Study Center automated menu. Press 1 for General Info, 2 for Hours & Location, 3 to Leave a Message, or 4 for Emergency Pastoral Needs.');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_AUDIO', '');
