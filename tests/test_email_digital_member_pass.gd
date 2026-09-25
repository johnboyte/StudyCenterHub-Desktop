extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING EMAIL DIGITAL MEMBER PASS TEST SUITE")
	print("==========================================================")

	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	var db_path = "user://test_email_digital_member_pass.db"
	var global_path = ProjectSettings.globalize_path(db_path)
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	var db = SQLiteDatabaseScript.new(db_path)
	_setup_test_schema(db)

	var com_svc = CommunicationsServiceScript.new(db)

	# --------------------------------------------------------
	# Test 1: Missing Member Email -> Should return reason: invalid_email
	# --------------------------------------------------------
	print("[Test 1] Testing missing member email validation...")
	db.execute("INSERT INTO people (first_name, last_name, status, email) VALUES ('NoEmail', 'Member', 'active', '');")
	var q1 = db.execute("SELECT id FROM people ORDER BY id DESC LIMIT 1;")
	var pid_no_email = int(q1["data"][0]["id"])

	var email_res1 = await com_svc.email_digital_member_pass(pid_no_email, "Test Admin")
	assert(email_res1.get("success", true) == false, "FAIL 1a: Should fail when email is empty")
	assert(email_res1.get("reason") == "invalid_email", "FAIL 1b: Reason should be invalid_email")
	print("PASS 1: Missing email correctly rejected with reason='invalid_email'.")

	# --------------------------------------------------------
	# Test 2: Invalid Member Email Format -> Should return reason: invalid_email
	# --------------------------------------------------------
	print("[Test 2] Testing invalid member email format...")
	db.execute("INSERT INTO people (first_name, last_name, status, email) VALUES ('BadEmail', 'Member', 'active', 'not-an-email');")
	var q2 = db.execute("SELECT id FROM people ORDER BY id DESC LIMIT 1;")
	var pid_bad_email = int(q2["data"][0]["id"])

	var email_res2 = await com_svc.email_digital_member_pass(pid_bad_email, "Test Admin")
	assert(email_res2.get("success", true) == false, "FAIL 2a: Should fail when email lacks @ symbol")
	assert(email_res2.get("reason") == "invalid_email", "FAIL 2b: Reason should be invalid_email")
	print("PASS 2: Invalid email format correctly rejected with reason='invalid_email'.")

	# --------------------------------------------------------
	# Test 3: Isolated Provider Relay Dispatch (Mock Mode)
	# --------------------------------------------------------
	print("[Test 3] Testing provider relay dispatch in isolated mock mode...")
	com_svc.mock_relay_mode = true
	db.execute("INSERT INTO people (first_name, last_name, status, email) VALUES ('Test', 'Member', 'active', 'test_pass_member@example.com');")
	var q3 = db.execute("SELECT id FROM people ORDER BY id DESC LIMIT 1;")
	var pid_valid = int(q3["data"][0]["id"])

	# Pre-issue active QR credential (stores in db and OS Keychain)
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var cred_svc = QRCredentialServiceScript.new(db)
	var issue_res = cred_svc.issue_credential(pid_valid, "PRT-test-uuid-email")
	assert(issue_res.get("success") == true, "FAIL: Should issue credential successfully")

	var email_res3 = await com_svc.email_digital_member_pass(pid_valid, "Test Admin")
	print("Mock Relay Response: ", email_res3)
	
	assert(email_res3.get("success") == true, "FAIL 3a: Relay should accept valid test message: " + str(email_res3.get("error", "")))

	# Verify communications_log entry
	var log_q = db.execute("SELECT * FROM communications_log;")
	print("All Log Entries: ", log_q)
	assert(log_q["success"] and log_q["data"].size() > 0, "FAIL 3b: Log entry should exist")
	var logged_status = log_q["data"][0].get("status")
	assert(logged_status == "accepted", "FAIL 3c: Log status should be 'accepted'")
	print("PASS 3: Isolated provider relay dispatch handled correctly and logged status: ", logged_status)

	# --------------------------------------------------------
	# Test 4: Verify No Dummy Email Substitution
	# --------------------------------------------------------
	print("[Test 4] Verifying no dummy email addresses were written to database...")
	var dummy_q = db.execute("SELECT * FROM communications_log WHERE recipient_contact LIKE '%member_%@reallife-studycenter.org%';")
	assert(dummy_q["success"] and dummy_q["data"].size() == 0, "FAIL 4: Dummy emails must NEVER be generated or logged.")
	print("PASS 4: Zero dummy email substitutions found in communications log.")

	# --------------------------------------------------------
	# Test 5: Apple Wallet Identity & Caching Prevention
	# --------------------------------------------------------
	print("[Test 5] Testing Apple Wallet identity & caching prevention...")
	var AppleWalletServiceScript = load("res://src/domain/security/apple_wallet_service.gd")
	var apple_svc = AppleWalletServiceScript.new()
	
	# Same credential => same serialNumber
	var p_data = {"person_uuid": "usr_test_caching_prevent"}
	var raw_tok_1 = "tok_11112222333344445555666677778888"
	var cred_id_1 = "QRCR-1111-2222"
	
	var pass_json_1 = apple_svc.generate_pass_json(p_data, raw_tok_1, cred_id_1)
	var pass_dict_1 = JSON.parse_string(pass_json_1)
	assert(pass_dict_1.get("serialNumber") == "usr_test_caching_prevent_QRCR-1111-2222", "FAIL 5a: Serial number mismatch")
	assert(pass_dict_1.get("barcode", {}).get("message", "").contains(raw_tok_1), "FAIL 5b: Barcode message missing raw token")

	# Re-run same credential => same serialNumber
	var pass_json_1_dup = apple_svc.generate_pass_json(p_data, raw_tok_1, cred_id_1)
	var pass_dict_1_dup = JSON.parse_string(pass_json_1_dup)
	assert(pass_dict_1_dup.get("serialNumber") == pass_dict_1.get("serialNumber"), "FAIL 5c: Same credential should yield same serialNumber")

	# Reissued credential => different serialNumber
	var cred_id_2 = "QRCR-5555-6666"
	var pass_json_2 = apple_svc.generate_pass_json(p_data, raw_tok_1, cred_id_2)
	var pass_dict_2 = JSON.parse_string(pass_json_2)
	assert(pass_dict_2.get("serialNumber") == "usr_test_caching_prevent_QRCR-5555-6666", "FAIL 5d: Serial number mismatch")
	assert(pass_dict_2.get("serialNumber") != pass_dict_1.get("serialNumber"), "FAIL 5e: Reissued credential should yield different serialNumber")

	# No credential fallback => person_uuid
	var pass_json_fallback = apple_svc.generate_pass_json(p_data, raw_tok_1)
	var pass_dict_fallback = JSON.parse_string(pass_json_fallback)
	assert(pass_dict_fallback.get("serialNumber") == "usr_test_caching_prevent", "FAIL 5f: Fallback serial number mismatch")

	print("PASS 5: Apple Wallet identity and caching prevention verified successfully.")

	print("==========================================================")
	print("ALL EMAIL DIGITAL MEMBER PASS TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)

func _setup_test_schema(db: RefCounted) -> void:
	db.execute("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, first_name TEXT, last_name TEXT, email TEXT, email_address TEXT, phone TEXT, status TEXT, qr_code_value TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS participant_qr_credentials (id INTEGER PRIMARY KEY AUTOINCREMENT, credential_id TEXT NOT NULL UNIQUE, person_id INTEGER NOT NULL, token_hash TEXT NOT NULL UNIQUE, token_hint TEXT, status TEXT NOT NULL DEFAULT 'active', issued_at TEXT NOT NULL DEFAULT (datetime('now')));")
	db.execute("CREATE TABLE IF NOT EXISTS communications_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_uuid TEXT, recipient_person_id INTEGER, recipient_name TEXT, recipient_contact TEXT, channel TEXT, message_body TEXT, status TEXT, status_detail TEXT, sent_by_user TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS event_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, event_uuid TEXT, event_type TEXT, aggregate_type TEXT, aggregate_id TEXT, payload_json TEXT, device_uuid TEXT, status TEXT);")
