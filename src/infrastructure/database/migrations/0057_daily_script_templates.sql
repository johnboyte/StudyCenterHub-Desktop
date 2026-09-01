-- Migration 0057: 7-Day Script Templates for Press 1 Today at the House
-- Preserves existing Production custom script data if present.

CREATE TABLE IF NOT EXISTS ivr_daily_scripts (
    day_of_week TEXT PRIMARY KEY,
    custom_script TEXT,
    is_custom INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed Monday through Sunday preserving existing custom Press 1 script from ivr_menu_nodes or app_settings if customized
INSERT OR IGNORE INTO ivr_daily_scripts (day_of_week, custom_script, is_custom)
SELECT 
    d.day,
    COALESCE(
        (SELECT script_text FROM ivr_menu_nodes WHERE id = 1 AND script_text IS NOT NULL AND TRIM(script_text) != ''),
        (SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_TODAY_CUSTOM_SCRIPT' AND setting_value IS NOT NULL AND TRIM(setting_value) != ''),
        NULL
    ) AS custom_script,
    CASE 
        WHEN (SELECT script_text FROM ivr_menu_nodes WHERE id = 1 AND script_text IS NOT NULL AND TRIM(script_text) != '') IS NOT NULL THEN 1
        WHEN (SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_TODAY_CUSTOM_SCRIPT' AND setting_value IS NOT NULL AND TRIM(setting_value) != '') IS NOT NULL THEN 1
        ELSE 0
    END AS is_custom
FROM (
    SELECT 'Monday' AS day UNION ALL
    SELECT 'Tuesday' UNION ALL
    SELECT 'Wednesday' UNION ALL
    SELECT 'Thursday' UNION ALL
    SELECT 'Friday' UNION ALL
    SELECT 'Saturday' UNION ALL
    SELECT 'Sunday'
) d;
