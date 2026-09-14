#!/usr/bin/env python3
import sqlite3
import json

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

cursor.execute("SELECT * FROM people WHERE human_id = 'P-20260813-F9C7';")
row = cursor.fetchone()

if row:
    d = dict(row)
    # Remove binary photo if present
    if 'profile_photo' in d and isinstance(d['profile_photo'], bytes):
        d['profile_photo'] = f"<bytes len {len(d['profile_photo'])}>"
    print("Local DB John Boyte Record:")
    print(json.dumps(d, indent=2))
else:
    print("John Boyte record not found in local DB!")

cursor.execute("SELECT * FROM staff_mobile_credentials WHERE human_id = 'P-20260813-F9C7';")
smc = cursor.fetchone()
if smc:
    print("\nLocal DB staff_mobile_credentials:")
    print(json.dumps(dict(smc), indent=2))
else:
    print("\nNo staff_mobile_credentials found in local DB!")

conn.close()
