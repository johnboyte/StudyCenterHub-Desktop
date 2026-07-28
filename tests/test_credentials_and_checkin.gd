extends SceneTree

## Automated Headless Test Suite for Kiosk Credentials and Scanning Mechanics
## Verifies that QR codes and PIN inputs resolve and check in constituents correctly

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING QR & PIN CREDENTIAL CHECK-IN TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_credentials.db")
	
	# Delete any existing test database file first to guarantee a clean state
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_credentials.db"):
		dir.remove("studycenterhub_test_credentials.db")
		print("[Test] Deleted existing test database file.")

	# Instantiate a clean database
	var db = SQLiteDatabaseScript.new(db_path)
	
	# Run all migrations from scratch
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed on test database: ", mig_res["error"])
		quit(1)
		return
	print("[Test] Database migrations ran successfully.")

	# Fetch / insert a test person
	var insert_person_res = db.execute("""
		INSERT INTO people (
			person_uuid, human_id, first_name, last_name, primary_role, qr_code_value
		) VALUES (
			'usr_test_student', 'PRT-9999', 'Marcus', 'Aurelius', 'Participant', 'marcus_qr_code'
		);
	""")
	if not insert_person_res["success"]:
		print("FAIL: Failed to insert test person: ", insert_person_res["error"])
		quit(1)
		return
		
	var pid_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_test_student' LIMIT 1;")
	var pid = int(pid_res["data"][0]["id"])

	# Seed QR & PIN credentials
	db.execute("INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status) VALUES ('QRCR-9999', ?, 'marcus_qr_code', 'Marcus QR Code', 'active');", [pid])
	db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-9999', ?, '9876', 'active');", [pid])

	var att_service = AttendanceServiceScript.new(db)

	# Test 1: Verify direct QR Scan check-in logic
	var token_input = "marcus_qr_code"
	var qr_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE token_hash = ? AND status = 'active' LIMIT 1;", [token_input])
	if not qr_res["success"] or qr_res["data"].size() == 0:
		print("FAIL: Could not locate active QR credential for test.")
		quit(1)
		return
	
	var person_id = int(qr_res["data"][0]["person_id"])
	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	var person = p_res["data"][0]

	# Record check-in via QR Scanner method
	var chk_res = att_service.record_check_in_atomic(person, "Self Service QR Scanner", "test_node", null, "Daily Check In", "Sarah Jenkins")
	if not chk_res["success"]:
		print("FAIL: QR Check-In recording failed: ", chk_res.get("error"))
		quit(1)
		return
	print("PASS 1/2: QR Code check-in resolves and logs correctly.")

	# Test 2: Verify PIN entry check-in logic
	var typed_id = "PRT-9999"
	var typed_pin = "9876"
	
	var p_lookup = db.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people WHERE human_id = ? LIMIT 1;", [typed_id])
	if not p_lookup["success"] or p_lookup["data"].size() == 0:
		print("FAIL: Student ID lookup failed.")
		quit(1)
		return
	
	var target_pid = int(p_lookup["data"][0]["id"])
	var pin_check = db.execute("SELECT id FROM participant_pin_credentials WHERE person_id = ? AND pin_hash = ? AND status = 'active' LIMIT 1;", [target_pid, typed_pin])
	if not pin_check["success"] or pin_check["data"].size() == 0:
		print("FAIL: PIN verification failed.")
		quit(1)
		return
		
	# Verify PIN check-in recording
	var chk_pin_res = att_service.record_check_in_atomic(p_lookup["data"][0], "Self Service PIN", "test_node", null, "Daily Check In", "Sarah Jenkins")
	if not chk_pin_res["success"]:
		print("FAIL: PIN Check-In recording failed.")
		quit(1)
		return
	print("PASS 2/2: PIN code verification and check-in resolves correctly.")

	# Cleanup test db
	db = null
	if dir and dir.file_exists("studycenterhub_test_credentials.db"):
		dir.remove("studycenterhub_test_credentials.db")

	print("==========================================================")
	print("SUCCESS: QR & PIN CHECK-IN MECHANICS VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
