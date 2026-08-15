import sqlite3
import json
import subprocess

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

cursor.execute("""
    SELECT first_name, COALESCE(last_name, '') as last_name, phone, human_id, COALESCE(profile_photo, '') as profile_photo
    FROM people
    WHERE status = 'active'
""")
rows = cursor.fetchall()
members = [dict(r) for r in rows]
conn.close()

payload = json.dumps({"members": members})
sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"
url = "https://app.reallife-studycenter.org/api/v1/sync/directory-index"

cmd = [
    "curl", "-s", "-i", "-X", "POST", url,
    "-H", "Content-Type: application/json",
    "-H", f"X-Sync-Api-Key: {sync_key}",
    "-d", payload
]

res = subprocess.run(cmd, capture_output=True, text=True)
print("Directory Sync HTTP Result:\n", res.stdout)
