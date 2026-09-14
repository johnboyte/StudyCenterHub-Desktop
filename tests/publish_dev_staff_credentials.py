import sqlite3
import json
import urllib.request
import ssl

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

gateway_url = "https://dev-gateway.reallife-studycenter.org"
sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

print("==========================================================")
print("PUBLISHING DEVELOPMENT STAFF CREDENTIALS INDEX TO DEV GATEWAY")
print("==========================================================")

query = """
    SELECT 
        p.id as person_id,
        p.person_uuid,
        p.human_id,
        COALESCE(p.first_name, '') || ' ' || COALESCE(p.last_name, '') as display_name,
        COALESCE(p.primary_email, '') as email,
        COALESCE(p.primary_role, 'Staff') as role,
        smc.pin_pbkdf_hash as pin_hash,
        smc.credential_version,
        smc.mobile_access_enabled
    FROM people p
    JOIN staff_mobile_credentials smc ON smc.person_id = p.id AND smc.mobile_access_enabled = 1
    WHERE p.status = 'active';
"""

cursor.execute(query)
rows = cursor.fetchall()
staff_items = [dict(r) for r in rows]
print(f"[DevStaffSync] Active Staff Items Count: {len(staff_items)}")
for s in staff_items:
    print(f"  {s['human_id']} | {s['display_name']} | email: {s['email']} | ver: {s['credential_version']} | hash_prefix: {s['pin_hash'][:20]}")

url = gateway_url + "/api/v1/sync/staff-credentials-index"
payload = json.dumps({'staff': staff_items}).encode('utf-8')

req = urllib.request.Request(url, data=payload, headers={
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
    'X-Sync-Api-Key': sync_key,
    'X-Environment': 'development'
})

try:
    with urllib.request.urlopen(req, context=ctx) as resp:
        res_text = resp.read().decode('utf-8')
        print(f"[DevStaffSync] Response ({resp.status}):", res_text)
except Exception as e:
    print("[DevStaffSync] ERROR:", e)

conn.close()
