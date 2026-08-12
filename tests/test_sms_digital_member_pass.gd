extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING SMS DIGITAL MEMBER PASS TEST SUITE")
	print("==========================================================")
	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	var db_path = "user://test_sms_digital_member_pass.db"
	var global_path = ProjectSettings.globalize_path(db_path)
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	var db = SQLiteDatabaseScript.new(db_path)
	_setup_test_schema(db)

	var com_svc = CommunicationsServiceScript.new(db)
	var twilio_service = TwilioGatewayScript.new(db)

	# --------------------------------------------------------
	# Test 1: Missing Twilio Configuration
	# --------------------------------------------------------
	print("[Test 1] Testing missing Twilio configuration...")
	db.execute("DELETE FROM app_settings WHERE setting_key LIKE 'TWILIO_%';")
	
	db.execute("INSERT INTO people (first_name, last_name, status, phone) VALUES ('John', 'Doe', 'active', '864-555-0199');")
	var q1 = db.execute("SELECT id FROM people ORDER BY id DESC LIMIT 1;")
	var pid_valid_phone = int(q1["data"][0]["id"])
	
	var sms_res1 = await com_svc.sms_digital_member_pass(self, pid_valid_phone)
	assert(sms_res1.get("success") == false, "FAIL 1a: Should fail when Twilio config is missing")
	assert(sms_res1.get("error").contains("Twilio configuration is incomplete"), "FAIL 1b: Expected config incomplete error")
	
	# Verify log entry for config failure
	var log_q1 = db.execute("SELECT * FROM communications_log WHERE recipient_person_id = ? ORDER BY id DESC LIMIT 1;", [pid_valid_phone])
	assert(log_q1["success"] and log_q1["data"].size() > 0, "FAIL 1c: Failed log entry should be created")
	assert(log_q1["data"][0].get("status") == "failed", "FAIL 1d: Expected status 'failed' in log")
	assert(log_q1["data"][0].get("status_detail").contains("Twilio configuration is incomplete"), "FAIL 1e: Expected detailed error in log")
	print("PASS 1: Missing Twilio configuration rejected and logged correctly.")

	# --------------------------------------------------------
	# Test 2: Invalid Phone Number
	# --------------------------------------------------------
	print("[Test 2] Testing invalid phone number...")
	twilio_service.save_twilio_config("AC_demo_123", "token_demo_123", "+18005550199")
	
	db.execute("INSERT INTO people (first_name, last_name, status, phone) VALUES ('BadPhone', 'Member', 'active', '12345');")
	var q2 = db.execute("SELECT id FROM people ORDER BY id DESC LIMIT 1;")
	var pid_bad_phone = int(q2["data"][0]["id"])
	
	var sms_res2 = await com_svc.sms_digital_member_pass(self, pid_bad_phone)
	assert(sms_res2.get("success") == false, "FAIL 2a: Should fail when phone number is too short")
	assert(sms_res2.get("error").contains("invalid"), "FAIL 2b: Expected invalid phone number error")
	
	# Verify log entry for invalid phone number
	var log_q2 = db.execute("SELECT * FROM communications_log WHERE recipient_person_id = ? ORDER BY id DESC LIMIT 1;", [pid_bad_phone])
	assert(log_q2["success"] and log_q2["data"].size() > 0, "FAIL 2c: Failed log entry should be created")
	assert(log_q2["data"][0].get("status") == "failed", "FAIL 2d: Expected status 'failed' in log")
	assert(log_q2["data"][0].get("status_detail").contains("invalid"), "FAIL 2e: Expected detailed error in log")
	print("PASS 2: Invalid phone number correctly rejected and logged.")

	# --------------------------------------------------------
	# Test 3: Successful Send (Simulated/Demo)
	# --------------------------------------------------------
	print("[Test 3] Testing successful send (simulated)...")
	# Pre-issue active QR credential (stores in db and OS Keychain)
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var cred_svc = QRCredentialServiceScript.new(db)
	var issue_res = cred_svc.issue_credential(pid_valid_phone, "PRT-test-uuid-sms")
	assert(issue_res.get("success") == true, "FAIL: Should issue credential successfully")

	var sms_res3 = await com_svc.sms_digital_member_pass(self, pid_valid_phone)
	assert(sms_res3.get("success") == true, "FAIL 3a: Should succeed with valid config and phone: " + str(sms_res3.get("error", "")))
	var sid3 = sms_res3.get("twilio_msg_sid", "")
	assert(sid3.begins_with("SM"), "FAIL 3b: Should generate a valid simulated Message SID")
	
	# Verify log entry creation and Message SID persistence
	var log_q3 = db.execute("SELECT * FROM communications_log WHERE recipient_person_id = ? AND status = 'sent' ORDER BY id DESC LIMIT 1;", [pid_valid_phone])
	assert(log_q3["success"] and log_q3["data"].size() > 0, "FAIL 3c: Log entry should be created")
	var log_row = log_q3["data"][0]
	assert(log_row.get("status") == "sent", "FAIL 3d: Log status should be 'sent'")
	assert(log_row.get("provider_sid") == sid3, "FAIL 3e: Log provider_sid should match Message SID")
	print("PASS 3: Successful send logged and Message SID persisted correctly.")

	# --------------------------------------------------------
	# Test 4: Gateway Failure
	# --------------------------------------------------------
	print("[Test 4] Testing gateway failure...")
	twilio_service.save_twilio_config("AC_live_failed_sid", "auth_failed_token", "+18005550199")
	
	var sms_res4 = await com_svc.sms_digital_member_pass(self, pid_valid_phone)
	assert(sms_res4.get("success") == false, "FAIL 4a: Should fail when gateway rejects credentials")
	assert(sms_res4.get("error") != "", "FAIL 4b: Expected non-empty error message from gateway")
	
	# Verify log entry for failure
	var log_q4 = db.execute("SELECT * FROM communications_log WHERE status = 'failed' AND recipient_person_id = ? ORDER BY id DESC LIMIT 1;", [pid_valid_phone])
	assert(log_q4["success"] and log_q4["data"].size() > 0, "FAIL 4c: Failed log entry should be created")
	assert(log_q4["data"][0].get("status_detail") != "", "FAIL 4d: Expected failure details logged")
	print("PASS 4: Gateway failure captured, returned, and logged correctly.")

	print("==========================================================")
	print("ALL SMS DIGITAL MEMBER PASS TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)

func _setup_test_schema(db: RefCounted) -> void:
	db.execute("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, first_name TEXT, last_name TEXT, email TEXT, email_address TEXT, phone TEXT, status TEXT, sms_consent INTEGER DEFAULT 1, qr_code_value TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS participant_qr_credentials (id INTEGER PRIMARY KEY AUTOINCREMENT, credential_id TEXT NOT NULL UNIQUE, person_id INTEGER NOT NULL, token_hash TEXT NOT NULL UNIQUE, token_hint TEXT, status TEXT NOT NULL DEFAULT 'active', issued_at TEXT NOT NULL DEFAULT (datetime('now')));")
	db.execute("CREATE TABLE IF NOT EXISTS communications_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_uuid TEXT, recipient_person_id INTEGER, recipient_name TEXT, recipient_contact TEXT, channel TEXT, message_body TEXT, status TEXT, status_detail TEXT, provider_sid TEXT, sent_by_user TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS event_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, event_uuid TEXT, event_type TEXT, aggregate_type TEXT, aggregate_id TEXT, payload_json TEXT, device_uuid TEXT, status TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT);")

