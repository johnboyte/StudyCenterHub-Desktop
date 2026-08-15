import sqlite3
import json
import subprocess
import os

# 1. Connect to Real Production SQLite Database
db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# 2. Query Real Active Members for directory_index
cursor.execute("""
    SELECT human_id, first_name, COALESCE(last_name, '') as last_name, phone, COALESCE(profile_photo, '') as profile_photo
    FROM people
    WHERE status = 'active'
""")
dir_members = [dict(r) for r in cursor.fetchall()]

# 3. Query Real Today Attendance Logs for today_attendance_index
# Operational date for today is 2026-08-14
cursor.execute("""
    SELECT al.human_id, p.phone, al.check_in_date as attendance_date, al.created_at as check_in_time
    FROM attendance_log al
    JOIN people p ON al.person_id = p.id
    WHERE al.check_in_date = '2026-08-14'
    ORDER BY al.created_at DESC
""")
att_logs = [dict(r) for r in cursor.fetchall()]
conn.close()

sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

# Verify John's payload before transmission
john_entry = next((m for m in dir_members if m['human_id'] == 'P-20260813-F9C7'), None)
if john_entry:
    print("=== VERIFYING JOHN BOYTE PAYLOAD BEFORE SYNC ===")
    print("human_id:", john_entry['human_id'])
    print("first_name:", john_entry['first_name'])
    print("last_name:", john_entry['last_name'])
    print("phone:", john_entry['phone'])
    print("profile_photo length:", len(john_entry['profile_photo']))

# 4. Write payload to temporary file to ensure curl transmits exact uncorrupted JSON
temp_dir_file = "/tmp/dir_payload_temp.json"
with open(temp_dir_file, "w") as f:
    json.dump({"members": dir_members}, f)

dir_cmd = [
    "curl", "-s", "-i", "-X", "POST", "https://app.reallife-studycenter.org/api/v1/sync/directory-index",
    "-H", "Content-Type: application/json",
    "-H", f"X-Sync-Api-Key: {sync_key}",
    "--data-binary", f"@{temp_dir_file}"
]
dir_res = subprocess.run(dir_cmd, capture_output=True, text=True)
print("\n=== REAL DIRECTORY SYNC RESPONSE ===")
print(dir_res.stdout[:500])
os.remove(temp_dir_file)

# 5. Post Real Today Attendance Index to SiteGround
temp_att_file = "/tmp/att_payload_temp.json"
with open(temp_att_file, "w") as f:
    json.dump({
        "attendance_date": "2026-08-14",
        "attendance": att_logs
    }, f)

att_cmd = [
    "curl", "-s", "-i", "-X", "POST", "https://app.reallife-studycenter.org/api/v1/sync/attendance-index",
    "-H", "Content-Type: application/json",
    "-H", f"X-Sync-Api-Key: {sync_key}",
    "--data-binary", f"@{temp_att_file}"
]
att_res = subprocess.run(att_cmd, capture_output=True, text=True)
print("\n=== REAL ATTENDANCE SYNC RESPONSE ===")
print(att_res.stdout[:500])
os.remove(temp_att_file)
