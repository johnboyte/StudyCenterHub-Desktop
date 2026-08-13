-- Migration 0048: Scripture Verses & Inspirational Messages Subsystem

CREATE TABLE IF NOT EXISTS scripture_verses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    verse_uuid TEXT NOT NULL UNIQUE,
    verse_text TEXT NOT NULL,
    reference TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'Scripture',
    is_active INTEGER NOT NULL DEFAULT 1,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO scripture_verses (id, verse_uuid, verse_text, reference, category, is_active, sort_order) VALUES
(1, 'vrs-001', 'For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life.', 'John 3:16', 'Scripture', 1, 1),
(2, 'vrs-002', 'Trust in the LORD with all your heart, and do not lean on your own understanding. In all your ways acknowledge him, and he will make straight your paths.', 'Proverbs 3:5-6', 'Scripture', 1, 2),
(3, 'vrs-003', 'The LORD is my shepherd; I shall not want. He makes me lie down in green pastures. He leads me beside still waters. He restores my soul.', 'Psalm 23:1-3', 'Scripture', 1, 3),
(4, 'vrs-004', 'I can do all things through him who strengthens me.', 'Philippians 4:13', 'Scripture', 1, 4),
(5, 'vrs-005', 'Be strong and courageous. Do not be frightened, and do not be dismayed, for the LORD your God is with you wherever you go.', 'Joshua 1:9', 'Scripture', 1, 5);
