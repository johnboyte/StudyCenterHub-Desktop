import sqlite3
import json
import os

# 1. Create a synthetic temporary legacy SQLite database
test_db_path = "/tmp/test_legacy_relay_strict.db"
if os.path.exists(test_db_path):
    os.remove(test_db_path)

conn = sqlite3.connect(test_db_path)
cursor = conn.cursor()

# Create legacy schema where phone_e164 IS THE PRIMARY KEY, but human_id MAY exist on some rows
cursor.execute("""
    CREATE TABLE directory_index (
        phone_e164 TEXT PRIMARY KEY,
        human_id TEXT DEFAULT NULL,
        first_name TEXT NOT NULL,
        masked_phone TEXT DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
""")

# Insert Row A: Valid real human_id ('P-20260813-F9C7')
cursor.execute("""
    INSERT INTO directory_index (phone_e164, human_id, first_name, masked_phone)
    VALUES ('+18649344080', 'P-20260813-F9C7', 'John', '•••-•••-4080');
""")

# Insert Row B: Legacy row with NO human_id (NULL)
cursor.execute("""
    INSERT INTO directory_index (phone_e164, human_id, first_name, masked_phone)
    VALUES ('+18645550999', NULL, 'AnonymousLegacy', '•••-•••-0999');
""")

# Insert Row C: Legacy row with empty string human_id ("")
cursor.execute("""
    INSERT INTO directory_index (phone_e164, human_id, first_name, masked_phone)
    VALUES ('+18645550888', '', 'BlankLegacy', '•••-•••-0888');
""")
conn.commit()

# Verify legacy primary key
cursor.execute("PRAGMA table_info(directory_index)")
legacy_cols = cursor.fetchall()
print("=== BEFORE MIGRATION SCHEMA ===")
for col in legacy_cols:
    print(col)

# 2. Run the exact Migration Logic (NO INVENTED IDs)
pragma = legacy_cols
pk_col = ''
has_last_name = False
has_profile_photo = False

for c in pragma:
    if c[5] != 0: # pk col index
        pk_col = c[1] # col name
    if c[1] == 'last_name':
        has_last_name = True
    if c[1] == 'profile_photo':
        has_profile_photo = True

if pk_col == 'phone_e164' or not has_last_name or not has_profile_photo:
    cursor.execute("SELECT COUNT(*) FROM directory_index")
    total_old = cursor.fetchone()[0]

    cursor.execute("ALTER TABLE directory_index RENAME TO directory_index_legacy_backup;")
    cursor.execute("""
        CREATE TABLE directory_index (
            human_id TEXT PRIMARY KEY,
            phone_e164 TEXT,
            first_name TEXT NOT NULL,
            last_name TEXT DEFAULT '',
            masked_phone TEXT DEFAULT '',
            profile_photo TEXT DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
    """)
    cursor.execute("CREATE INDEX idx_directory_phone_e164 ON directory_index(phone_e164);")
    
    # Copy ONLY rows with valid, non-empty human_id (NO P-LEGACY-* GENERATION)
    cursor.execute("""
        INSERT OR IGNORE INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
        SELECT trim(human_id), COALESCE(phone_e164, ''), COALESCE(first_name, 'Member'), '', COALESCE(masked_phone, ''), '', COALESCE(updated_at, datetime('now'))
        FROM directory_index_legacy_backup
        WHERE human_id IS NOT NULL AND trim(human_id) != '';
    """)
    migrated_count = cursor.rowcount
    cursor.execute("DROP TABLE directory_index_legacy_backup;")
    conn.commit()

    skipped_count = total_old - migrated_count

print("\n=== MIGRATION EXECUTION METRICS ===")
print(f"Total Legacy Rows: {total_old}")
print(f"Migrated Identifiable Rows: {migrated_count}")
print(f"Skipped Unidentifiable Rows: {skipped_count}")

# Verify no synthetic IDs were generated
cursor.execute("SELECT human_id FROM directory_index")
migrated_ids = [r[0] for r in cursor.fetchall()]
print(f"Migrated IDs in Canonical Table: {migrated_ids}")

for m_id in migrated_ids:
    assert not m_id.startswith("P-LEGACY-"), f"Forbidden synthetic ID generated: {m_id}"

# Verify schema
cursor.execute("PRAGMA table_info(directory_index)")
migrated_cols = cursor.fetchall()
new_pk = ''
for col in migrated_cols:
    if col[5] != 0:
        new_pk = col[1]

print(f"\nNEW PRIMARY KEY IS: {new_pk}")
assert new_pk == 'human_id', "Primary key migration failed!"

# 3. Simulate Authoritative Directory Publication (Post-Migration UPSERT)
sample_photo = "data:image/jpeg;base64," + "B" * 152291
cursor.execute("""
    INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(human_id) DO UPDATE SET
        phone_e164 = excluded.phone_e164,
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        masked_phone = excluded.masked_phone,
        profile_photo = excluded.profile_photo,
        updated_at = datetime('now')
""", ('P-20260813-F9C7', '+18649344080', 'John', 'Boyte', '•••-•••-4080', sample_photo))
conn.commit()

cursor.execute("SELECT human_id, first_name, last_name, phone_e164, length(profile_photo) FROM directory_index WHERE human_id = 'P-20260813-F9C7'")
record = cursor.fetchone()
print("\n=== VERIFIED AUTHORITATIVE POST-SYNC RECORD ===")
print("human_id:", record[0])
print("first_name:", record[1])
print("last_name:", record[2])
print("phone_e164:", record[3])
print("profile_photo length:", record[4])

assert record[0] == 'P-20260813-F9C7'
assert record[1] == 'John'
assert record[2] == 'Boyte'
assert record[3] == '+18649344080'
assert record[4] == 152314

conn.close()
os.remove(test_db_path)
print("\n=== MIGRATION TEST COMPLETED 100% SUCCESSFULLY ===")
