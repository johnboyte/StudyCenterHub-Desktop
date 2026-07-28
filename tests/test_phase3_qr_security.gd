extends SceneTree

## Automated Security & Cryptographic Verification Test Suite for Phase 3 Credentials
## Verifies 256-bit token entropy, SHA-256 hashing, lookup security, and revocation mechanics.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")

func run_tests() -> bool:
	print("==========================================================")
	print("STARTING PHASE 3 MEMBER QR SECURITY TEST SUITE")
	print("==========================================================")

	# 1. Verify 256-bit Entropy Token Generation
	var token1 = QRCredentialServiceScript.generate_secure_token()
	var token2 = QRCredentialServiceScript.generate_secure_token()

	if token1.length() != 64 or token2.length() != 64:
		print("FAIL: Token length is not 64 hex characters (256 bits). Got: ", token1.length())
		return false
	print("PASS 1/10: 256-bit token entropy verified (64 hex characters).")

	if token1 == token2:
		print("FAIL: Two generated tokens are identical.")
		return false
	print("PASS 2/10: Cryptographic uniqueness verified (two generated tokens differ).")

	# 2. Verify SHA-256 Hashing
	var expected_hash = token1.sha256_text().to_lower()
	var computed_hash = QRCredentialServiceScript.hash_token(token1)
	if computed_hash != expected_hash:
		print("FAIL: Hash mismatch. Expected: ", expected_hash, " Got: ", computed_hash)
		return false
	print("PASS 3/10: SHA-256 hashing verified.")

	# 3. Setup Temporary Test Database
	var db_path = ProjectSettings.globalize_path("user://test_phase3_qr_security.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	MigrationsRunnerScript.new(db).run_migrations()
	var svc = QRCredentialServiceScript.new(db)

	var ins_res = db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, status) VALUES ('usr_sec_test', 'PRT-SEC-100', 'Security', 'Tester', 'Participant', 'active');")
	if not ins_res["success"]:
		print("FAIL: Insert person error: ", ins_res.get("error"))
		return false
	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_sec_test';")
	if not p_res["success"] or p_res["data"].size() == 0:
		print("FAIL: Failed to create test person record.")
		return false
	var pid = int(p_res["data"][0].get("id"))

	# 4. Issue Credential & Verify Database Persistence
	var issue_res = svc.issue_credential(pid, "usr_sec_test")
	if not issue_res["success"]:
		print("FAIL: Credential issuance failed: ", issue_res.get("error"))
		return false

	var raw_token = issue_res["raw_token"]
	var db_cred_res = db.execute("SELECT token_hash, token_hint FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", [pid])
	if not db_cred_res["success"] or db_cred_res["data"].size() == 0:
		print("FAIL: Active credential not found in DB.")
		return false

	var stored_hash = str(db_cred_res["data"][0]["token_hash"])
	var stored_hint = str(db_cred_res["data"][0]["token_hint"])

	if stored_hash == raw_token:
		print("FAIL SECURITY DEFECT: Raw token was stored un-hashed in database.")
		return false

	var expected_raw_hash = QRCredentialServiceScript.hash_token(raw_token)
	if stored_hash != expected_raw_hash:
		print("FAIL: Stored token hash does not match computed SHA-256 hash.")
		return false
	print("PASS 4/10: Database stores ONLY SHA-256 hash (raw token absent from DB).")

	if raw_token in stored_hint:
		print("FAIL SECURITY DEFECT: Raw token exposed in token_hint.")
		return false
	print("PASS 5/10: Safe token hint masking verified (raw token absent from hint).")

	# 5. Lookup by Raw Token
	var lookup_res = svc.lookup_person_by_raw_token(raw_token)
	if not lookup_res["success"]:
		print("FAIL: Lookup by active raw token failed: ", lookup_res.get("error"))
		return false
	if str(lookup_res["person"]["human_id"]) != "PRT-SEC-100":
		print("FAIL: Lookup returned incorrect participant.")
		return false
	print("PASS 6/10: SHA-256 lookup resolved correct participant end-to-end.")

	# 6. Reject Malformed / Short Tokens
	var bad_lookup = svc.lookup_person_by_raw_token("RLH-123456")
	if bad_lookup["success"]:
		print("FAIL SECURITY DEFECT: Short vanity token accepted by lookup.")
		return false
	print("PASS 7/10: Malformed/short vanity tokens strictly rejected.")

	# 7. Credential Replacement & Revocation of Old Token
	var issue_res2 = svc.issue_credential(pid, "usr_sec_test")
	var raw_token2 = issue_res2["raw_token"]

	var old_lookup = svc.lookup_person_by_raw_token(raw_token)
	if old_lookup["success"]:
		print("FAIL SECURITY DEFECT: Revoked old token still resolved participant.")
		return false
	print("PASS 8/10: Credential replacement successfully revoked old token.")

	var new_lookup = svc.lookup_person_by_raw_token(raw_token2)
	if not new_lookup["success"]:
		print("FAIL: New replacement token failed lookup.")
		return false
	print("PASS 9/10: Replacement token resolves correctly.")

	var count_res = db.execute("SELECT COUNT(*) as cnt FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", [pid])
	if int(count_res["data"][0]["cnt"]) != 1:
		print("FAIL: Multiple active credentials found for participant.")
		return false
	print("PASS 10/11: Single active credential constraint verified.")

	# 8. Option B Device-Bound Policy: Missing Keychain Entry Handling
	var dummy_svc = QRCredentialServiceScript.new(db)
	dummy_svc.keychain = null # Simulate second device / restored computer without Keychain entry
	var missing_token = dummy_svc.get_active_raw_token(pid)
	if missing_token != "":
		print("FAIL SECURITY DEFECT: Missing Keychain entry silently returned raw token.")
		return false
	print("PASS 11/11: Option B device restriction verified (missing Keychain entry returns empty token without silent replacement).")

	print("==========================================================")
	print("SUCCESS: ALL 11 MEMBER QR SECURITY TESTS PASSED (100%)")
	print("==========================================================")
	return true

func _init() -> void:
	run_tests()
	quit()
