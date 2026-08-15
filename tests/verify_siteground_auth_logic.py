import sqlite3
import hashlib

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

cursor.execute("SELECT person_id, human_id, pin_pbkdf_hash, credential_version, mobile_access_enabled FROM staff_mobile_credentials WHERE human_id = 'P-20260813-F9C7';")
local_row = cursor.fetchone()

print("=== LOCAL DB RECORD ===")
print("Human ID:", local_row["human_id"])
print("Credential Version:", local_row["credential_version"])
print("Mobile Access Enabled:", local_row["mobile_access_enabled"])

parts = local_row["pin_pbkdf_hash"].split(":")
print("Verifier Prefix:", parts[0] + ":" + parts[1])
print("Iteration Count:", parts[2])
print("Salt Hex Length:", len(parts[3]), "(16 bytes binary)")
print("Digest Hex Length:", len(parts[4]), "(32 bytes binary)")

conn.close()
