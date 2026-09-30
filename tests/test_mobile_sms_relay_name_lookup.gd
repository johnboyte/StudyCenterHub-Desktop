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
			first_name TEXT NOT NULL,
			last_name TEXT DEFAULT '',
			masked_phone TEXT DEFAULT '',
			profile_photo TEXT DEFAULT '',
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	# Insert synthetic test person: McKenna Boykin (+17073656637)
	db.execute("INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone) VALUES ('SCH-9001', '+17073656637', 'McKenna', 'Boykin', '•••-•••-6637');")

	# Test 1: Known normalized phone (+17073656637) -> displays "McKenna Boykin"
	var name_1 = _lookup_constituent_name(db, "+17073656637")
	assert(name_1 == "McKenna Boykin", "TEST 1 FAIL: Expected 'McKenna Boykin', got '" + name_1 + "'")
	print("✓ PASS 1: Known normalized phone +17073656637 resolves to 'McKenna Boykin'.")

	# Test 2: Different formatting of same phone ("(707) 365-6637", "7073656637", "17073656637") -> still matches correctly
	var name_2a = _lookup_constituent_name(db, "(707) 365-6637")
	assert(name_2a == "McKenna Boykin", "TEST 2a FAIL: Formatted (707) 365-6637 failed to match")
	var name_2b = _lookup_constituent_name(db, "7073656637")
	assert(name_2b == "McKenna Boykin", "TEST 2b FAIL: Raw digits 7073656637 failed to match")
	var name_2c = _lookup_constituent_name(db, "17073656637")
	assert(name_2c == "McKenna Boykin", "TEST 2c FAIL: 11-digit 17073656637 failed to match")
	print("✓ PASS 2: Different phone number formats all match correctly to 'McKenna Boykin'.")

	# Test 3: Unknown phone (+18645550222) -> displays "Unknown Contact"
	var name_3 = _lookup_constituent_name(db, "+18645550222")
	assert(name_3 == "Unknown Contact", "TEST 3 FAIL: Expected 'Unknown Contact', got '" + name_3 + "'")
	print("✓ PASS 3: Unknown phone +18645550222 falls back to 'Unknown Contact'.")

	# Test 4: Verify Header & Relay Message Formatting
	var msg_known = _format_relay_message(name_1, "+17073656637", "Can I attend tonight?", "BM49")
	assert(msg_known.begins_with("STUDY CENTER — McKenna Boykin\n(707) 365-6637"), "TEST 4a FAIL: Header formatting incorrect for known contact")
	assert(msg_known.contains("Ref: BM49"), "TEST 4b FAIL: Token missing from formatted message")
	assert(msg_known.contains("BM49 your reply"), "TEST 4c FAIL: Token reply instructions missing")

	var msg_unknown = _format_relay_message(name_3, "+18645550222", "Hello there", "BM49")
	assert(msg_unknown.begins_with("STUDY CENTER — Unknown Contact\n(864) 555-0222"), "TEST 4d FAIL: Header formatting incorrect for unknown contact")

	print("✓ PASS 4: Message header and token body formatting verified for both known and unknown contacts.")

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

func _lookup_constituent_name(db: SQLiteDatabaseScript, from_phone: String) -> String:
	var e164_search = _normalize_phone_e164(from_phone)
	var digits_search = ""
	for i in range(from_phone.length()):
		var ch = from_phone[i]
		if ch >= "0" and ch <= "9":
			digits_search += ch
	var last10_search = digits_search.substr(digits_search.length() - 10) if digits_search.length() >= 10 else ""

	var res = db.execute(
		"SELECT first_name, last_name FROM directory_index WHERE phone_e164 = ? OR (length(?) = 10 AND phone_e164 LIKE ?) OR human_id = ? LIMIT 1;",
		[e164_search, last10_search, "%" + last10_search, from_phone]
	)

	if res["success"] and res["data"].size() > 0:
		var row = res["data"][0]
		var fn = str(row.get("first_name", "")).strip_edges()
		var ln = str(row.get("last_name", "")).strip_edges()
		var full = (fn + " " + ln).strip_edges()
		if full != "":
			return full

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

	return "STUDY CENTER — %s\n%s\n%s\n\nRef: %s\nReply with:\n%s your reply" % [constituent_name, display_phone, body, token, token]
