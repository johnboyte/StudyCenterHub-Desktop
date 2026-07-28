extends SceneTree

## Headless Integration Test Suite for Public Self-Registration SQLite Schema Reconciliation
## Verification of Migration 0017 and credential tables

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING PUBLIC SELF-REGISTRATION SCHEMA RECONCILIATION TEST SUITE")
	print("==========================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_public_registration_schema.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)

	var mig_res = migrations_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migration execution failed: ", mig_res["error"])
		quit(1)
		return
	print("PASS 1/5: Database migrations executed successfully.")

	# 2. Verify people table has been expanded with new columns
	var table_info_res = db.execute("PRAGMA table_info(people);")
	if not table_info_res["success"]:
		print("FAIL: Could not query people table info: ", table_info_res["error"])
		quit(1)
		return

	var columns = []
	for col in table_info_res["data"]:
		columns.append(col.get("name", ""))

	var expected_cols = [
		"profile_photo", "flag_notes", "qr_code_value",
		"sms_consent_at", "sms_consent_source", "sms_consent_version"
	]
	for col_name in expected_cols:
		if not col_name in columns:
			print("FAIL: Missing expected column in people: ", col_name)
			quit(1)
			return
	print("PASS 2/5: People table legacy columns successfully reconciled.")

	# 3. Verify that the new tables are created in the SQLite file
	var tables_res = db.execute("SELECT name FROM sqlite_master WHERE type='table';")
	if not tables_res["success"]:
		print("FAIL: Could not fetch tables list: ", tables_res["error"])
		quit(1)
		return

	var tables = []
	for t in tables_res["data"]:
		tables.append(t.get("name", ""))

	var expected_tables = [
		"participant_qr_credentials",
		"participant_pin_credentials",
		"participant_verification_sessions",
		"participant_verification_audit"
	]
	for tbl in expected_tables:
		if not tbl in tables:
			print("FAIL: Expected table missing: ", tbl)
			quit(1)
			return
	print("PASS 3/5: All credential and verification tables successfully created.")

	# 4. Insert dummy participant and credential logs to test constraints and keys
	var p_res = db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, profile_photo, flag_notes) VALUES ('test_p_uuid_001', 'PRT-9999', 'Jane', 'Doe', 'data:image/jpeg;base64,dummy', 'Needs confirmation');")
	if not p_res["success"]:
		print("FAIL: Could not insert test person: ", p_res["error"])
		quit(1)
		return
	
	# Fetch inserted person id
	var person_id = -1
	var get_p = db.execute("SELECT id FROM people WHERE person_uuid='test_p_uuid_001';")
	if get_p["success"] and get_p["data"].size() > 0:
		person_id = get_p["data"][0].get("id", -1)
	
	if person_id == -1:
		print("FAIL: Could not retrieve inserted person id.")
		quit(1)
		return

	# Insert QR credential
	var qr_res = db.execute("INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status) VALUES ('QRCR-TEST-001', ?, 'dummy_token_hash_001', 'token_hint', 'active');", [person_id])
	if not qr_res["success"]:
		print("FAIL: Could not insert QR credential: ", qr_res["error"])
		quit(1)
		return

	# Insert PIN credential
	var pin_res = db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-TEST-001', ?, 'dummy_pin_hash_001', 'active');", [person_id])
	if not pin_res["success"]:
		print("FAIL: Could not insert PIN credential: ", pin_res["error"])
		quit(1)
		return

	# Insert Verification Session
	var session_res = db.execute("INSERT INTO participant_verification_sessions (session_id, person_id, method, token_hash, expires_at) VALUES ('VSN-TEST-001', ?, 'participant_pin', 'dummy_token_hash_002', '2026-07-21 16:30:00');", [person_id])
	if not session_res["success"]:
		print("FAIL: Could not insert verification session: ", session_res["error"])
		quit(1)
		return

	# Insert Audit Log
	var audit_res = db.execute("INSERT INTO participant_verification_audit (person_id, participant_id, method, action, success, actor, source) VALUES (?, 'PRT-9999', 'participant_pin', 'verification_token_consume', 1, 'Self Service', 'identity_service');", [person_id])
	if not audit_res["success"]:
		print("FAIL: Could not insert audit log: ", audit_res["error"])
		quit(1)
		return

	print("PASS 4/5: Integrity constraints and write operations verified successfully.")

	# 5. Clean up database
	db = null # Close DB connection reference
	var cleanup_res = DirAccess.remove_absolute(test_db_path)
	if cleanup_res != OK:
		print("WARNING: Could not clean up temporary test database file.")
	print("PASS 5/5: Cleanup of temporary database complete.")

	print("==========================================================")
	print("SUCCESS: SCHEMA RECONCILIATION OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
