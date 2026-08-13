-- Migration 0049: Person Favorite Things Subsystem

CREATE TABLE IF NOT EXISTS person_favorite_things (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL UNIQUE,
    candy_treat TEXT DEFAULT '',
    snack TEXT DEFAULT '',
    drink TEXT DEFAULT '',
    food_meal TEXT DEFAULT '',
    restaurant TEXT DEFAULT '',
    dessert TEXT DEFAULT '',
    fruit TEXT DEFAULT '',
    movie_tv TEXT DEFAULT '',
    music TEXT DEFAULT '',
    activities_hobbies TEXT DEFAULT '',
    sports_teams TEXT DEFAULT '',
    stores_places TEXT DEFAULT '',
    other_favorites TEXT DEFAULT '',
    prefer_to_avoid TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
);
