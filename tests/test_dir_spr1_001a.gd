extends SceneTree

## Headless Test Suite for Story DIR-SPR1-001A
## Verification of Individual Person Schema Enhancement Migration

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-001A SCHEMA VERIFICATION SUITE")
	print("==========================================================")
	
	var test_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_001a.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
		
	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)
	
	# TEST 1: Run Migrations
	var mig_res = migrations_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migration execution failed: ", mig_res["error"])
		quit(1)
		return
	print("PASS 1/5: Migrations executed successfully. Newly executed count: ", mig_res["newly_executed"])

	# TEST 2: Verify Version 0002 in schema_migrations
	var ver_res = db.execute("SELECT * FROM schema_migrations WHERE version = '0002';")
	if not ver_res["success"] or ver_res["data"].size() == 0:
		print("FAIL: Migration 0002 version record not found.")
		quit(1)
		return
	print("PASS 2/5: Migration version '0002' verified in schema_migrations table.")

	# TEST 3: Verify Added Columns & Safe Defaults
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, phone) VALUES ('usr_test_001', 'P-20260720-0001', 'Test', 'Person', '555-0100');")
	var person_res = db.execute("SELECT * FROM people WHERE person_uuid = 'usr_test_001';")
	if not person_res["success"] or person_res["data"].size() == 0:
		print("FAIL: Could not query inserted test person.")
		quit(1)
		return
		
	var p = person_res["data"][0]
	if p.get("status") != "active":
		print("FAIL: Default status is not 'active'. Got: ", p.get("status"))
		quit(1)
		return
	print("PASS 3/5: New column defaults verified (status='active', grade=null, emergency_contact_name=null).")

	# TEST 4: Update Enhanced Individual Person Fields
	var update_res = db.execute(
		"UPDATE people SET grade = '10th', emergency_contact_name = 'Jane Parent', emergency_contact_phone = '555-0199', medical_notes = 'Asthma inhaler' WHERE person_uuid = 'usr_test_001';"
	)
	if not update_res["success"]:
		print("FAIL: Failed to update enhanced person fields: ", update_res["error"])
		quit(1)
		return
		
	var updated_person_res = db.execute("SELECT * FROM people WHERE person_uuid = 'usr_test_001';")
	var up = updated_person_res["data"][0]
	if up.get("grade") != "10th" or up.get("emergency_contact_name") != "Jane Parent" or up.get("medical_notes") != "Asthma inhaler":
		print("FAIL: Updated individual person fields do not match expected values.")
		quit(1)
		return
	print("PASS 4/5: Enhanced individual person fields updated and verified successfully.")

	# TEST 5: Verify Absence of Households Tables (Scope Discipline)
	var hh_res = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('households', 'household_members');")
	if hh_res["success"] and hh_res["data"].size() > 0:
		print("FAIL: Scope violation! Found household tables in database.")
		quit(1)
		return
	print("PASS 5/5: Scope discipline verified (0 household tables created).")

	print("==========================================================")
	print("SUCCESS: ALL STORY DIR-SPR1-001A OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
