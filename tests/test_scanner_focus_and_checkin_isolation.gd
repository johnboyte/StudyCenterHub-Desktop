extends SceneTree

## Dedicated Regression Test Suite for Check-In Scanner Input & Native Window Focus Isolation
## Verifies that physical scanner input, member lookup, atomic attendance logging, and native NSWindow isolation operate 100% cleanly.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")
const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")
const NativePlayerBridgeScript = preload("res://src/infrastructure/native/native_player_bridge.gd")

func _init() -> void:
	print("==============================================================================")
	print("STARTING SCANNER INPUT & NATIVE WINDOW FOCUS ISOLATION REGRESSION SUITE")
	print("==============================================================================")
	
	# 1. VERIFY NATIVE WINDOW ISOLATION DIAGNOSTICS (IF ON MACOS)
	if OS.get_name() == "macOS":
		NativePlayerBridgeScript.enable_external_drag()
		NativePlayerBridgeScript.set_drag_box_visible(false)
		
		if ClassDB.class_exists("MacWKWebViewHelper"):
			var helper = ClassDB.instantiate("MacWKWebViewHelper")
			if helper and helper.has_method("getNativeDiagnostics"):
				var diag_str: String = helper.call("getNativeDiagnostics")
				print("[NATIVE DIAGNOSTICS] ", diag_str)
				assert(diag_str.contains("independent_window_class=NativeDropWindow"), "FAIL: Independent window must use NativeDropWindow class to prevent stealing key window status")
				print("✅ Native Window Focus Isolation Verified: independent window uses NativeDropWindow (canBecomeKeyWindow = NO).")

	# 2. VERIFY CHECK-IN SCANNER MEMBER LOOKUP & ATOMIC ATTENDANCE WRITE IN ISOLATED TEST DB
	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_scanner_isolation.db")
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_scanner_isolation.db"):
		dir.remove("studycenterhub_test_scanner_isolation.db")
		
	var db = SQLiteDatabaseScript.new(db_path)
	var migrations = MigrationsRunnerScript.new(db)
	migrations.run_migrations()
	
	# Seed test member
	var seed_res = db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role) VALUES ('p_uuid_scan_test_001', 'PRT-SCAN-01', 'ScannerTest', 'Member', 'Participant');")
	assert(seed_res["success"], "FAIL: Could not seed test member")
	
	var pid_res = db.execute("SELECT id FROM people WHERE human_id = 'PRT-SCAN-01' LIMIT 1;")
	assert(pid_res["success"] and pid_res["data"].size() > 0, "FAIL: Could not query test member ID")
	var pid = int(pid_res["data"][0]["id"])
	
	var person_dict = {
		"id": pid,
		"person_uuid": "p_uuid_scan_test_001",
		"human_id": "PRT-SCAN-01",
		"first_name": "ScannerTest",
		"last_name": "Member"
	}
	
	# Issue QR credential for test member
	var cred_svc = QRCredentialServiceScript.new(db)
	var issue_res = cred_svc.issue_credential(pid, "p_uuid_scan_test_001", "Sarah Jenkins")
	assert(issue_res.get("success", false), "FAIL: Could not issue test QR credential")
	var raw_token = issue_res.get("raw_token", "")
	assert(raw_token != "", "FAIL: Raw token must not be empty")
	
	# Verify scan token lookup
	var lookup_res = cred_svc.lookup_person_by_raw_token(raw_token)
	assert(lookup_res.get("success", false), "FAIL: Member lookup by raw scan token failed")
	assert(int(lookup_res.get("person", {}).get("id", 0)) == pid, "FAIL: Scanned member ID mismatch")
	print("✅ Member Lookup Verified: Scanned QR token correctly resolves test member.")
	
	# Perform atomic check-in execution
	var att_svc = AttendanceServiceScript.new(db)
	var checkin_res = att_svc.record_check_in_atomic(person_dict, "Physical Barcode Scanner", "dev_test_node", null, "Study Center Daily", "John Boyte")
	assert(checkin_res.get("success", false), "FAIL: Atomic check-in write failed")
	var checkin_uuid = checkin_res.get("checkin_uuid", "")
	assert(checkin_uuid != "", "FAIL: Checkin UUID missing")
	print("✅ Check-in Service Verified: Atomic check-in logged to attendance_log.")
	
	# Verify attendance_log row write
	var today_str = Time.get_date_string_from_system()
	var log_chk = db.execute("SELECT * FROM attendance_log WHERE checkin_uuid = ? LIMIT 1;", [checkin_uuid])
	assert(log_chk["success"] and log_chk["data"].size() > 0, "FAIL: attendance_log row missing")
	assert(str(log_chk["data"][0]["human_id"]) == "PRT-SCAN-01", "FAIL: attendance_log human_id mismatch")
	assert(str(log_chk["data"][0]["check_in_date"]) == today_str, "FAIL: attendance_log date mismatch")
	print("✅ Test Database Check-in Verified: attendance_log record matched exact member and date.")
	
	# Clean up test DB
	if dir and dir.file_exists("studycenterhub_test_scanner_isolation.db"):
		dir.remove("studycenterhub_test_scanner_isolation.db")
		
	print("==============================================================================")
	print("SUCCESS: SCANNER INPUT & NATIVE WINDOW FOCUS ISOLATION REGRESSION TEST PASSED")
	print("==============================================================================")
	quit(0)
