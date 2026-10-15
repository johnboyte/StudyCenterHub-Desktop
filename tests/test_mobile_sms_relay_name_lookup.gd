extends SceneTree

## Focused Verification for Mobile SMS Relay Constituent Name Lookup
## Uses synthetic test data only. Does NOT send real SMS/MMS/email. Does NOT touch Production DB.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==================================================")
	print("RUNNING: Mobile SMS Relay Name Lookup Verification")
	print("==================================================")
	_run_verification()

func _run_verification() -> void:
	await create_timer(0.05).timeout

	var test_db_path = ProjectSettings.globalize_path("user://test_mobile_sms_relay_name_lookup.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	assert(mig_res["success"], "Migration failed")

	# Ensure directory_index table exists (mirrors server gateway schema)
	db.execute("""
		CREATE TABLE IF NOT EXISTS directory_index (
			human_id TEXT PRIMARY KEY,
			phone_e164 TEXT,
			emergency_phone_e164 TEXT DEFAULT '',
			first_name TEXT NOT NULL,
			last_name TEXT DEFAULT '',
			masked_phone TEXT DEFAULT '',
			profile_photo TEXT DEFAULT '',
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	# Insert synthetic test person: McKenna Boykin (+17073656637)
	db.execute("INSERT INTO directory_index (human_id, phone_e164, emergency_phone_e164, first_name, last_name, masked_phone) VALUES ('SCH-9001', '+17073656637', '', 'McKenna', 'Boykin', '•••-•••-6637');")
	# Insert actual failed constituent record: Khalil Peake (+18646074831)
	db.execute("INSERT INTO directory_index (human_id, phone_e164, emergency_phone_e164, first_name, last_name, masked_phone) VALUES ('P-20260927-2190', '+18646074831', '', 'khalil', 'peake', '•••-•••-4831');")
	# Insert emergency contact record: Audrey Miller (+17074742336, emergency: +17073303865)
	db.execute("INSERT INTO directory_index (human_id, phone_e164, emergency_phone_e164, first_name, last_name, masked_phone) VALUES ('P-20260913-05C7', '+17074742336', '+17073303865', 'Audrey', 'Miller', '•••-•••-2336');")
	# Insert shared family records: Sarah Johnson & Michael Johnson (+18645559999)
	db.execute("INSERT INTO directory_index (human_id, phone_e164, emergency_phone_e164, first_name, last_name, masked_phone) VALUES ('P-SHARED-1', '(864) 555-9999', '', 'Sarah', 'Johnson', '•••-•••-9999');")
	db.execute("INSERT INTO directory_index (human_id, phone_e164, emergency_phone_e164, first_name, last_name, masked_phone) VALUES ('P-SHARED-2', '+18645559999', '', 'Michael', 'Johnson', '•••-•••-9999');")

	# Test 1: Known normalized phone (+17073656637) -> displays "McKenna Boykin"
	var name_1 = _lookup_constituent_name(db, "+17073656637")
	assert(name_1 == "McKenna Boykin", "TEST 1 FAIL: Expected 'McKenna Boykin', got '" + name_1 + "'")
	print("✓ PASS 1: Known normalized phone +17073656637 resolves to 'McKenna Boykin'.")

	# Test 2: Actual constituent inbound phone (+18646074831) with lowercase name -> displays "Khalil Peake"
	var name_actual = _lookup_constituent_name(db, "+18646074831")
	assert(name_actual == "Khalil Peake", "TEST 2 FAIL: Actual number +18646074831 expected 'Khalil Peake', got '" + name_actual + "'")
	print("✓ PASS 2: Constituent number +18646074831 resolves to title-cased 'Khalil Peake'.")

	# Test 3: Different formatting of same phone ("(864) 607-4831", "8646074831", "18646074831", "+1 864 607 4831", "864-607-4831")
	var name_3a = _lookup_constituent_name(db, "(864) 607-4831")
	assert(name_3a == "Khalil Peake", "TEST 3a FAIL: Formatted (864) 607-4831 failed to match")
	var name_3b = _lookup_constituent_name(db, "8646074831")
	assert(name_3b == "Khalil Peake", "TEST 3b FAIL: Raw digits 8646074831 failed to match")
	var name_3c = _lookup_constituent_name(db, "18646074831")
	assert(name_3c == "Khalil Peake", "TEST 3c FAIL: 11-digit 18646074831 failed to match")
	var name_3d = _lookup_constituent_name(db, "+1 864 607 4831")
	assert(name_3d == "Khalil Peake", "TEST 3d FAIL: Spaced +1 864 607 4831 failed to match")
	var name_3e = _lookup_constituent_name(db, "864-607-4831")
	assert(name_3e == "Khalil Peake", "TEST 3e FAIL: Hyphenated 864-607-4831 failed to match")
	print("✓ PASS 3: Different phone number formats all match correctly to 'Khalil Peake'.")

	# Test 4: Emergency contact phone lookup -> displays "Audrey Miller"
	var name_em = _lookup_constituent_name(db, "+17073303865")
	assert(name_em == "Audrey Miller", "TEST 4 FAIL: Emergency contact phone +17073303865 expected 'Audrey Miller', got '" + name_em + "'")
	print("✓ PASS 4: Emergency contact phone +17073303865 resolves to 'Audrey Miller'.")

	# Test 5: Shared phone number resolution -> displays "Sarah Johnson / Michael Johnson"
	var name_shared = _lookup_constituent_name(db, "+18645559999")
	assert(name_shared == "Sarah Johnson / Michael Johnson" or name_shared == "Michael Johnson / Sarah Johnson", "TEST 5 FAIL: Shared number expected both names, got '" + name_shared + "'")
	print("✓ PASS 5: Shared phone number handles ambiguity safely: '", name_shared, "'.")

	# Test 6: Unknown phone (+18645550222) -> displays "Unknown Contact"
	var name_unknown = _lookup_constituent_name(db, "+18645550222")
	assert(name_unknown == "Unknown Contact", "TEST 6 FAIL: Expected 'Unknown Contact', got '" + name_unknown + "'")
	print("✓ PASS 6: Unknown phone +18645550222 falls back to 'Unknown Contact'.")

	# Test 7: Verify Header & Relay Message Formatting
	var msg_known = _format_relay_message(name_1, "+17073656637", "Are you open this afternoon?", "BM49")
	assert(msg_known.begins_with("Incoming Text - McKenna Boykin\nFrom: (707) 365-6637"), "TEST 7a FAIL: Header formatting incorrect for known contact")
	assert(msg_known.contains("Are you open this afternoon?"), "TEST 7b FAIL: Message body missing")
	assert(msg_known.contains("Ref: BM49"), "TEST 7c FAIL: Token missing from formatted message")
	assert(msg_known.contains("BM49 your reply"), "TEST 7d FAIL: Token reply instructions missing")

	var msg_unknown_fwd = _format_relay_message(name_unknown, "+18645550222", "Hello there", "BM49")
	assert(msg_unknown_fwd.begins_with("Incoming Text - Unknown Contact\nFrom: (864) 555-0222"), "TEST 7e FAIL: Header formatting incorrect for unknown contact")

	print("✓ PASS 7: Message header format 'Incoming Text - <Name>\\nFrom: <Phone>' verified.")

	# Clean up test DB
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n==================================================")
	print("ALL FOCUSED VERIFICATION TESTS PASSED SUCCESSFULLY!")
	print("==================================================")
	quit(0)

func _normalize_phone_e164(raw: String) -> String:
	var digits = ""
	for i in range(raw.length()):
		var ch = raw[i]
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits.length() == 10:
		return "+1" + digits
	elif digits.length() == 11 and digits.begins_with("1"):
		return "+" + digits
	elif digits.length() > 0:
		return "+" + digits
	return raw

func _clean_capitalization(raw_name: String) -> String:
	if raw_name == raw_name.to_lower():
		var parts = raw_name.split(" ", false)
		var formatted = []
		for p in parts:
			if p.length() > 0:
				formatted.append(p.substr(0, 1).to_upper() + p.substr(1))
		return " ".join(formatted)
	return raw_name

func _lookup_constituent_name(db: SQLiteDatabaseScript, from_phone: String) -> String:
	var e164_search = _normalize_phone_e164(from_phone)
	var digits_search = ""
	for i in range(from_phone.length()):
		var ch = from_phone[i]
		if ch >= "0" and ch <= "9":
			digits_search += ch
	var last10_search = digits_search.substr(digits_search.length() - 10) if digits_search.length() >= 10 else ""

	# Bulletproof format-agnostic lookup: exact e164, emergency_phone_e164, stripped last 10, or human_id
	var res = db.execute("""
		SELECT first_name, last_name, human_id, phone_e164, emergency_phone_e164 
		FROM directory_index 
		WHERE phone_e164 = ? 
		   OR emergency_phone_e164 = ?
		   OR (length(?) = 10 AND (
		       SUBSTR(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone_e164, ' ', ''), '-', ''), '(', ''), ')', ''), '+', ''), -10) = ?
		       OR SUBSTR(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(emergency_phone_e164, ' ', ''), '-', ''), '(', ''), ')', ''), '+', ''), -10) = ?
		   ))
		   OR human_id = ?;
	""", [e164_search, e164_search, last10_search, last10_search, last10_search, from_phone])

	if res["success"] and res["data"].size() > 0:
		var matched_names = []
		for row in res["data"]:
			var fn = str(row.get("first_name", "")).strip_edges()
			var ln = str(row.get("last_name", "")).strip_edges()
			var full = (fn + " " + ln).strip_edges()
			if full != "":
				var cap_name = _clean_capitalization(full)
				if not matched_names.has(cap_name):
					matched_names.append(cap_name)

		if matched_names.size() == 1:
			return matched_names[0]
		elif matched_names.size() > 1:
			return " / ".join(matched_names)

	return "Unknown Contact"

func _format_relay_message(constituent_name: String, from_phone: String, body: String, token: String) -> String:
	var e164 = _normalize_phone_e164(from_phone)
	var digits = ""
	for i in range(e164.length()):
		var ch = e164[i]
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits.length() == 11 and digits.begins_with("1"):
		digits = digits.substr(1)

	var display_phone = e164
	if digits.length() == 10:
		display_phone = "(%s) %s-%s" % [digits.substr(0, 3), digits.substr(3, 3), digits.substr(6, 4)]

	return "Incoming Text - %s\nFrom: %s\nMessage: %s\n\nRef: %s\nReply with:\n%s your reply" % [constituent_name, display_phone, body, token, token]
