extends SceneTree

## Headless Test Suite for Staging Test Member Seeder Idempotency & Safety

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGING SEED IDEMPOTENCY TEST SUITE")
	print("==========================================================")
	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	var db_path = "user://test_staging_seed_idempotency.db"
	var global_path = ProjectSettings.globalize_path(db_path)
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)

	# --------------------------------------------------------
	# Test 1: Verify it is NOT created when env is development
	# --------------------------------------------------------
	print("[Test 1] Testing env=development...")
	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	var res1 = mig_runner.run_migrations()
	assert(res1["success"], "FAIL 1a: Migrations should succeed")
	
	var check_q1 = db.execute("SELECT COUNT(*) as cnt FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q1["success"] and check_q1["data"][0]["cnt"] == 0, "FAIL 1b: Seed should NOT be created in development")
	print("PASS 1: Seed was not created in development environment.")

	# --------------------------------------------------------
	# Test 2: Verify it is NOT created when env is production
	# --------------------------------------------------------
	print("[Test 2] Testing env=production...")
	OS.set_environment("STUDYCENTERHUB_ENV", "production")
	var res2 = mig_runner.run_migrations()
	assert(res2["success"], "FAIL 2a: Migrations should succeed")
	
	var check_q2 = db.execute("SELECT COUNT(*) as cnt FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q2["success"] and check_q2["data"][0]["cnt"] == 0, "FAIL 2b: Seed should NOT be created in production")
	print("PASS 2: Seed was not created in production environment.")

	# --------------------------------------------------------
	# Test 3: Verify it is NOT created when env is empty/unknown
	# --------------------------------------------------------
	print("[Test 3] Testing env=empty/unknown...")
	OS.set_environment("STUDYCENTERHUB_ENV", "")
	var res3 = mig_runner.run_migrations()
	assert(res3["success"], "FAIL 3a: Migrations should succeed")
	
	var check_q3 = db.execute("SELECT COUNT(*) as cnt FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q3["success"] and check_q3["data"][0]["cnt"] == 0, "FAIL 3b: Seed should NOT be created with empty environment")
	print("PASS 3: Seed was not created with empty/unknown environment.")

	# --------------------------------------------------------
	# Test 4: Verify it is created in staging when absent
	# --------------------------------------------------------
	print("[Test 4] Testing env=staging creation...")
	OS.set_environment("STUDYCENTERHUB_ENV", "staging")
	var res4 = mig_runner.run_migrations()
	assert(res4["success"], "FAIL 4a: Migrations should succeed")
	
	var check_q4 = db.execute("SELECT * FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q4["success"] and check_q4["data"].size() == 1, "FAIL 4b: Seed should be created in staging")
	var person_row = check_q4["data"][0]
	var person_id = int(person_row["id"])
	
	# Verify fields
	assert(person_row["first_name"] == "John", "FAIL 4c: Expected John")
	assert(person_row["last_name"] == "Boyte", "FAIL 4d: Expected Boyte")
	assert(person_row["phone"] == "(864) 934-4080", "FAIL 4e: Normalized primary mobile phone check")
	assert(person_row["emergency_contact_name"] == "Cheryl Boyte", "FAIL 4f: Expected Cheryl Boyte")
	assert(person_row["emergency_contact_phone"] == "(864) 934-5017", "FAIL 4g: Expected emergency contact phone")
	assert(int(person_row["sms_consent"]) == 1, "FAIL 4h: Expected SMS consent active")
	assert(int(person_row["sms_consent_given"]) == 1, "FAIL 4i: Expected SMS consent given active")
	
	# Verify QR credential is created through the normal service
	var check_cred4 = db.execute("SELECT * FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", [person_id])
	assert(check_cred4["success"] and check_cred4["data"].size() == 1, "FAIL 4j: Active QR credential should exist")
	var cred_row = check_cred4["data"][0]
	assert(cred_row.get("token_hash") == person_row.get("qr_code_value"), "FAIL 4k: QR code hash in people should match active credential hash")
	assert(cred_row.get("token_hint").begins_with("Pass ***"), "FAIL 4l: Hint format should match normal credential generation pattern")
	print("PASS 4: Seed and valid QR credentials created successfully in staging.")

	# --------------------------------------------------------
	# Test 5: Verify idempotency (no duplicates on second startup)
	# --------------------------------------------------------
	print("[Test 5] Testing idempotency on second run...")
	var res5 = mig_runner.run_migrations()
	assert(res5["success"], "FAIL 5a: Second run migrations should succeed")
	
	var check_q5 = db.execute("SELECT COUNT(*) as cnt FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q5["success"] and check_q5["data"][0]["cnt"] == 1, "FAIL 5b: No duplicate record should be created")
	
	var check_cred5 = db.execute("SELECT COUNT(*) as cnt FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", [person_id])
	assert(check_cred5["success"] and check_cred5["data"][0]["cnt"] == 1, "FAIL 5c: Active QR credential count must remain 1")
	print("PASS 5: Idempotency verified. No duplicate people or credentials created.")

	# --------------------------------------------------------
	# Test 6: Verify existing edits to the record are preserved
	# --------------------------------------------------------
	print("[Test 6] Testing preservation of existing edits...")
	# Simulate editing the phone number, status, and emergency contact
	var update_res = db.execute("""
		UPDATE people 
		SET phone = '(864) 934-0000', status = 'inactive', emergency_contact_name = 'Cheryl B.'
		WHERE email = 'johnboytejr@gmail.com';
	""")
	assert(update_res["success"], "FAIL 6a: Setup update should succeed")
	
	# Run migrations again (simulating another startup)
	var res6 = mig_runner.run_migrations()
	assert(res6["success"], "FAIL 6b: Migration run after edit should succeed")
	
	var check_q6 = db.execute("SELECT phone, status, emergency_contact_name FROM people WHERE email = 'johnboytejr@gmail.com';")
	assert(check_q6["success"] and check_q6["data"].size() == 1, "FAIL 6c: Record should exist")
	var row = check_q6["data"][0]
	assert(row.get("phone") == "(864) 934-0000", "FAIL 6d: Edited phone number should be preserved")
	assert(row.get("status") == "inactive", "FAIL 6e: Edited status should be preserved")
	assert(row.get("emergency_contact_name") == "Cheryl B.", "FAIL 6f: Edited emergency contact name should be preserved")
	print("PASS 6: Existing edits to the seeded record are preserved.")

	# Clean up test DB
	db = null
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	print("==========================================================")
	print("ALL STAGING SEED IDEMPOTENCY TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
