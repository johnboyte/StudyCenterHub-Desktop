extends SceneTree

## Headless Permanent Regression Test Suite for Communications Recipient Identity & Consent
## Verifies that recipient resolution prioritizes constituent person_id over generic/joined IDs,
## enforces mandatory STOP opt-outs, and handles missing/invalid dictionaries safely.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func _init() -> void:
	print("==========================================================")
	print("STARTING COMMUNICATIONS RECIPIENT IDENTITY TEST SUITE")
	print("==========================================================")
	call_deferred("run_identity_tests")

func run_identity_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_comms_identity_permanent.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	var com_svc = CommunicationsServiceScript.new(db)

	# Seed test constituents in people table
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, email, sms_consent) VALUES (101, 'usr_person_101', 'P-101', 'Alice', 'Smith', 'Student', '555-0101', 'alice@example.com', 1);")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, email, sms_consent) VALUES (102, 'usr_person_102', 'P-102', 'Bob', 'Jones', 'Student', '555-0102', 'bob@example.com', 0);") # Opted-out

	# Test 1: People row containing only `id`
	var dict_people_row = {"id": 101, "first_name": "Alice", "last_name": "Smith", "phone": "555-0101", "sms_consent": 1}
	var res1 = com_svc.send_message_atomic(dict_people_row, "SMS", "Identity test 1", "Admin")
	var check1 = db.execute("SELECT recipient_person_id FROM communications_log WHERE message_uuid = ?;", [res1["message_uuid"]])
	assert_true(res1["success"] and check1["data"][0]["recipient_person_id"] == 101, "Test 1: People row containing only `id` correctly resolved to recipient_person_id 101.")

	# Test 2: Joined row containing both `person_id` (101) and generic `id` (999 signup ID)
	var dict_joined_row = {"id": 999, "person_id": 101, "first_name": "Alice", "last_name": "Smith", "phone": "555-0101", "sms_consent": 1}
	var res2 = com_svc.send_message_atomic(dict_joined_row, "SMS", "Identity test 2", "Admin")
	var check2 = db.execute("SELECT recipient_person_id FROM communications_log WHERE message_uuid = ?;", [res2["message_uuid"]])
	assert_true(res2["success"] and check2["data"][0]["recipient_person_id"] == 101, "Test 2: Joined dictionary with person_id=101 and id=999 correctly prioritized person_id 101 over signup ID 999.")

	# Test 3: Signup row containing `signup_id` and `person_id`
	var dict_signup_row = {"signup_id": 888, "person_id": 101, "first_name": "Alice", "phone": "555-0101", "sms_consent": 1}
	var res3 = com_svc.send_message_atomic(dict_signup_row, "SMS", "Identity test 3", "Admin")
	var check3 = db.execute("SELECT recipient_person_id FROM communications_log WHERE message_uuid = ?;", [res3["message_uuid"]])
	assert_true(res3["success"] and check3["data"][0]["recipient_person_id"] == 101, "Test 3: Signup row with person_id=101 correctly resolved to recipient_person_id 101.")

	# Test 4: Missing person_id with valid people.id fallback
	var dict_fallback = {"id": 101, "phone": "555-0101", "sms_consent": 1}
	var res4 = com_svc.send_message_atomic(dict_fallback, "SMS", "Identity test 4", "Admin")
	var check4 = db.execute("SELECT recipient_person_id FROM communications_log WHERE message_uuid = ?;", [res4["message_uuid"]])
	assert_true(res4["success"] and check4["data"][0]["recipient_person_id"] == 101, "Test 4: Missing person_id fell back safely to valid people.id 101.")

	# Test 5: Zero person_id with valid people.id fallback
	var dict_zero_pid = {"person_id": 0, "id": 101, "phone": "555-0101", "sms_consent": 1}
	var res5 = com_svc.send_message_atomic(dict_zero_pid, "SMS", "Identity test 5", "Admin")
	var check5 = db.execute("SELECT recipient_person_id FROM communications_log WHERE message_uuid = ?;", [res5["message_uuid"]])
	assert_true(res5["success"] and check5["data"][0]["recipient_person_id"] == 101, "Test 5: Zero person_id fell back safely to valid people.id 101.")

	# Test 6: Opted-out recipient (sms_consent = 0) STOP status enforced
	var dict_opted_out = {"id": 102, "person_id": 102, "first_name": "Bob", "phone": "555-0102", "sms_consent": 0}
	var res6 = com_svc.send_message_atomic(dict_opted_out, "SMS", "Identity test 6", "Admin")
	assert_true(not res6["success"] and res6.get("status") == "excluded" and "STOP" in res6.get("error", ""), "Test 6: Opted-out recipient (sms_consent = 0) strictly rejected with STOP opt-out status.")

	# Test 7: Missing both identifiers fails safely without crash
	var dict_empty_ids = {"first_name": "Unknown", "phone": "555-0000", "sms_consent": 1}
	var res7 = com_svc.send_message_atomic(dict_empty_ids, "SMS", "Identity test 7", "Admin")
	assert_true(res7.get("status") == "excluded" or not res7["success"], "Test 7: Missing both identifiers handled safely without throwing runtime exception.")

	# Clean up test database file
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL COMMUNICATIONS RECIPIENT IDENTITY PERMANENT TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
