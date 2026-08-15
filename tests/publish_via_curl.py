import sqlite3
import json
import subprocess
import sys

if "--allow-production-write" not in sys.argv:
    print("BLOCKED: Script refused to run against Production environment. Pass '--allow-production-write' to execute explicitly.")
    sys.exit(1)

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

sql = """
    SELECT 
        p.id, p.human_id, p.first_name, p.last_name, p.primary_role, p.email, p.status,
        smc.pin_pbkdf_hash, smc.credential_version
    FROM people p
    JOIN staff_mobile_credentials smc ON smc.person_id = p.id AND smc.mobile_access_enabled = 1
    WHERE LOWER(p.status) = 'active'
      AND (
          LOWER(p.primary_role) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
       OR LOWER(COALESCE(p.staff_classification, '')) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
      );
"""
cursor.execute(sql)
rows = cursor.fetchall()

staff_payload = []
for r in rows:
    hid = str(r["human_id"] or "").strip()
    fn = str(r["first_name"] or "").strip()
    ln = str(r["last_name"] or "").strip()
    disp_name = (fn + " " + ln).strip() or "Staff Member"
    email = str(r["email"] or "").strip()
    role = str(r["primary_role"] or "Staff").strip()
    pin_h = str(r["pin_pbkdf_hash"] or "").strip()
    cred_ver = int(r["credential_version"] or 1)

    if hid and pin_h:
        staff_payload.append({
            "human_id": hid,
            "display_name": disp_name,
            "email": email,
            "role": role,
            "pin_hash": pin_h,
            "credential_version": cred_ver,
            "capabilities": ["view_attendance"],
            "status": "active"
        })

print(f"Publishing {len(staff_payload)} staff record(s) via curl...")
payload_json = json.dumps({"staff": staff_payload})

cmd = [
    "curl", "-s", "-i", "-X", "POST",
    "https://app.reallife-studycenter.org/api/v1/sync/staff-credentials-index",
    "-H", "Content-Type: application/json",
    "-H", "X-Sync-Api-Key: SCH_SYNC_KEY_PLACEHOLDER_8f3d",
    "-d", payload_json
]

res = subprocess.run(cmd, capture_output=True, text=True)
print("Curl Output:\n", res.stdout)

conn.close()
