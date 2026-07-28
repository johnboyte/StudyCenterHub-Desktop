extends SceneTree

## Automated Headless Test Suite for Phase 2.1 Checkpoint 1 (Local Foundation)

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING CHECKPOINT 1 AUTOMATED PROOF SUITE")
	print("==========================================================")
	
	var test_db_path = ProjectSettings.globalize_path("user://test_checkpoint1_operational.db")
	# Fresh database environment
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
		
	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)
	
	# Test 1: SQLite Init & Migrations
	var mig_res = migrations_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migration execution failed: ", mig_res["error"])
		quit(1)
		return
	print("PASS 1/6: SQLite initialized & schema migrations executed.")

	# Test 2: Device Identity Registration
	var dev_res = db.execute("INSERT INTO device_identity (device_id, device_name, role) VALUES ('dev_macbook_test', 'MacBook Test Rig', 'Primary Node');")
	if not dev_res["success"]:
		print("FAIL: Device identity registration failed: ", dev_res["error"])
		quit(1)
		return
	print("PASS 2/6: Local device identity registered (dev_macbook_test).")

	# Test 3: Person Creation
	var person_service = PersonServiceScript.new(db)
	var p_res = person_service.create_test_person("Arthur", "Pendelton", "555-0177")
	if not p_res["success"]:
		print("FAIL: Person creation failed: ", p_res["error"])
		quit(1)
		return
	var person = p_res["person"]
	print("PASS 3/6: Person record created (Human ID: ", person.get("human_id", ""), ")")

	# Test 4: Atomic Check-In & Outbox Write
	var attendance_service = AttendanceServiceScript.new(db)
	var c_res = attendance_service.record_check_in_atomic(person, "Barcode", "dev_macbook_test")
	if not c_res["success"]:
		print("FAIL: Check-in atomic transaction failed: ", c_res["error"])
		quit(1)
		return
	print("PASS 4/6: Atomic Check-In & Outbox commit succeeded. Acknowledgement time: %.2f ms" % c_res["elapsed_ms"])

	# Test 5: Verify Outbox Record in SQLite
	var outbox_query = db.execute("SELECT * FROM event_outbox WHERE event_uuid = ?;", [c_res["event_uuid"]])
	if not outbox_query["success"] or outbox_query["data"].size() != 1:
		print("FAIL: Event outbox persistence verification failed.")
		quit(1)
		return
	print("PASS 5/6: Transactional Event Outbox record verified in SQLite.")

	# Test 6: Transaction Rollback Verification (Forced Failure)
	var fail_res = attendance_service.record_check_in_forced_failure(person, "dev_macbook_test")
	var verify_rollback = db.execute("SELECT * FROM attendance_log WHERE checkin_uuid = ?;", [fail_res["checkin_uuid"]])
	if verify_rollback["success"] and verify_rollback["data"].size() == 0:
		print("PASS 6/6: Transaction Rollback verified; 0 orphan records remaining after forced failure.")
	else:
		print("FAIL: Transaction rollback failed; orphan record found.")
		quit(1)
		return

	print("==========================================================")
	print("SUCCESS: ALL CHECKPOINT 1 PROOF OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
