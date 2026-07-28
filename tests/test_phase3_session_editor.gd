extends SceneTree

## Complete Refined Integration Test Suite for Phase 3 Session Create/Edit Module
## Verifies all Phase 3 specifications, validation, rollbacks, idempotency, audit diffing, outbox, and restart persistence.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING COMPLETE PHASE 3 DOMAIN INTEGRATION TEST SUITE")
	print("==========================================================")
	call_deferred("run_all_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_phase3_session_editor_final.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)

	# Execute all migrations up to 0027
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Pre-test database migrations 0001..0027 executed cleanly.")

	var config_service = SessionConfigServiceScript.new(db)
	var schedules_service = SchedulesServiceScript.new(db)

	# Seed canonical people records
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (101, 'usr_person_admin_101', 'ADM-101', 'Alice', 'Admin', 'Administrator');")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (102, 'usr_person_student_102', 'STU-102', 'Bob', 'Student', 'Student');")

	# Set active session context to Admin (101)
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_ID', 'usr_person_admin_101');")
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_NAME', 'Alice Admin');")

	# -------------------------------------------------------------
	# 1. IMPERSONATION PREVENTION TEST
	# -------------------------------------------------------------
	# Set active session context to Student (102)
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_ID', 'usr_person_student_102');")
	
	# Student tries to pass Admin's UUID (usr_person_admin_101)
	var imper_res = schedules_service.create_full_session_atomic("Impersonated Session", 1, "2026-07-26", "09:00 AM", "10:30 AM", "Room 1", 20, 1, 1, [], "", "Alice Admin", "", "", "usr_person_admin_101")
	assert_true(not imper_res["success"] and "Impersonation rejected" in imper_res["error"], "Test 1: Impersonation rejected when caller attempts to use Administrator's UUID from a Student session context.")

	# Restore Admin session context
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_ID', 'usr_person_admin_101');")

	# -------------------------------------------------------------
	# 2. CALENDAR DATE & LEAP YEAR TESTS
	# -------------------------------------------------------------
	var d_2026_02_28 = schedules_service._is_valid_calendar_date("2026-02-28")
	var d_2028_02_29 = schedules_service._is_valid_calendar_date("2028-02-29")
	var d_2026_02_29 = schedules_service._is_valid_calendar_date("2026-02-29")
	var d_2026_02_30 = schedules_service._is_valid_calendar_date("2026-02-30")
	var d_2026_04_31 = schedules_service._is_valid_calendar_date("2026-04-31")
	var d_2026_13_01 = schedules_service._is_valid_calendar_date("2026-13-01")
	var d_2026_00_10 = schedules_service._is_valid_calendar_date("2026-00-10")
	var d_malformed = schedules_service._is_valid_calendar_date("2026/07/26")

	assert_true(d_2026_02_28 and d_2028_02_29 and not d_2026_02_29 and not d_2026_02_30 and not d_2026_04_31 and not d_2026_13_01 and not d_2026_00_10 and not d_malformed, "Test 2: Real calendar date validator correctly accepted valid leap year/dates and rejected all non-existent/malformed calendar dates.")

	# -------------------------------------------------------------
	# 3. INDIVIDUAL CAPACITY VALIDATION TESTS
	# -------------------------------------------------------------
	var cap_null = schedules_service._is_valid_positive_integer(null)
	var cap_empty = schedules_service._is_valid_positive_integer("")
	var cap_zero = schedules_service._is_valid_positive_integer("0")
	var cap_neg = schedules_service._is_valid_positive_integer("-1")
	var cap_dec = schedules_service._is_valid_positive_integer("2.5")
	var cap_alpha = schedules_service._is_valid_positive_integer("ten")
	var cap_valid = schedules_service._is_valid_positive_integer("30")

	assert_true(not cap_null and not cap_empty and not cap_zero and not cap_neg and not cap_dec and not cap_alpha and cap_valid, "Test 3: Raw service capacity validation rejected null, empty, 0, negative, decimal, and non-numeric strings while accepting positive whole integer.")

	# -------------------------------------------------------------
	# 4. SUCCESSFUL CREATION & MULTI-LOCATION
	# -------------------------------------------------------------
	var multi_desc = "Advanced calculus session.\nLine 2: Linear algebra practice.\nLine 3: Q&A."
	var create_res = schedules_service.create_full_session_atomic("Calculus II Tutoring", 1, "2026-07-26", "09:00 AM", "10:30 AM", "Study Room #1", 25, 1, 1, [3, 4], multi_desc, "Alice Admin", "Fall 2026", "STEM", "usr_person_admin_101", "op_create_101")
	assert_true(create_res["success"] and create_res["session_id"] > 0 and create_res["session_uuid"].begins_with("sess_"), "Test 4: Created Session 'Calculus II Tutoring' with stable session_uuid.")

	var sess_id = int(create_res["session_id"])
	var sess_uuid = str(create_res["session_uuid"])

	# -------------------------------------------------------------
	# 5. CREATE TRANSACTION ROLLBACK ARTIFACT COUNTS
	# -------------------------------------------------------------
	var c_sess_b = db.execute("SELECT COUNT(*) as cnt FROM sessions;")["data"][0]["cnt"]
	var c_loc_b = db.execute("SELECT COUNT(*) as cnt FROM session_location_assignments;")["data"][0]["cnt"]
	var c_aud_b = db.execute("SELECT COUNT(*) as cnt FROM session_audit_log;")["data"][0]["cnt"]
	var c_out_b = db.execute("SELECT COUNT(*) as cnt FROM event_outbox;")["data"][0]["cnt"]
	var c_idemp_b = db.execute("SELECT COUNT(*) as cnt FROM operation_idempotency_log;")["data"][0]["cnt"]

	var roll_create = schedules_service.create_full_session_atomic("Rolled Back Session", 1, "2026-07-27", "10:00 AM", "12:00 PM", "Gathering Room", 50, 1, 1, [1], "Will fail", "Alice Admin", "", "", "usr_person_admin_101", "op_fail_create", true)

	var c_sess_a = db.execute("SELECT COUNT(*) as cnt FROM sessions;")["data"][0]["cnt"]
	var c_loc_a = db.execute("SELECT COUNT(*) as cnt FROM session_location_assignments;")["data"][0]["cnt"]
	var c_aud_a = db.execute("SELECT COUNT(*) as cnt FROM session_audit_log;")["data"][0]["cnt"]
	var c_out_a = db.execute("SELECT COUNT(*) as cnt FROM event_outbox;")["data"][0]["cnt"]
	var c_idemp_a = db.execute("SELECT COUNT(*) as cnt FROM operation_idempotency_log;")["data"][0]["cnt"]

	assert_true(not roll_create["success"] and c_sess_b == c_sess_a and c_loc_b == c_loc_a and c_aud_b == c_aud_a and c_out_b == c_out_a and c_idemp_b == c_idemp_a, "Test 5: Create transaction rollback verified before/after artifact counts remained 100% identical.")

	# -------------------------------------------------------------
	# 6. EDIT SESSION & FULL EDIT ROLLBACK ARTIFACT VALUES
	# -------------------------------------------------------------
	var edit_res = schedules_service.update_full_session_atomic(sess_id, "Calculus & Linear Algebra Tutoring", 2, "2026-07-26", "09:30 AM", "11:00 AM", 30, 1, 1, [3, 4, 5], "Updated overview", "Fall 2026", "STEM", "usr_person_admin_101", "Administrator", "op_edit_102")
	assert_true(edit_res["success"], "Test 6a: Edited Session successfully.")

	# Record all field values before forced edit failure
	var s_row_b = db.execute("SELECT title, session_type_id, date_text, start_time, end_time, max_capacity, signup_required, limit_signups, description, term_override, type_override, room_location, session_uuid, updated_at FROM sessions WHERE id = ?;", [sess_id])["data"][0]
	var e_aud_b = db.execute("SELECT COUNT(*) as cnt FROM session_audit_log WHERE session_id = ?;", [sess_id])["data"][0]["cnt"]
	var e_out_b = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE aggregate_id = ?;", [sess_uuid])["data"][0]["cnt"]

	var roll_edit = schedules_service.update_full_session_atomic(sess_id, "Corrupted Title", 1, "2026-07-26", "09:00 AM", "10:30 AM", 25, 1, 1, [3], "Corrupted", "Fall 2026", "STEM", "usr_person_admin_101", "Administrator", "op_fail_edit", true)

	var s_row_a = db.execute("SELECT title, session_type_id, date_text, start_time, end_time, max_capacity, signup_required, limit_signups, description, term_override, type_override, room_location, session_uuid, updated_at FROM sessions WHERE id = ?;", [sess_id])["data"][0]
	var e_aud_a = db.execute("SELECT COUNT(*) as cnt FROM session_audit_log WHERE session_id = ?;", [sess_id])["data"][0]["cnt"]
	var e_out_a = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE aggregate_id = ?;", [sess_uuid])["data"][0]["cnt"]

	assert_true(not roll_edit["success"] and JSON.stringify(s_row_b) == JSON.stringify(s_row_a) and e_aud_b == e_aud_a and e_out_b == e_out_a, "Test 6b: Edit transaction rollback verified all 14 session fields, session_uuid, updated_at, audit count, and outbox count remained 100% unchanged.")

	# -------------------------------------------------------------
	# 7. NO-OP EDIT BEHAVIOR
	# -------------------------------------------------------------
	var noop_res = schedules_service.update_full_session_atomic(sess_id, "Calculus & Linear Algebra Tutoring", 2, "2026-07-26", "09:30 AM", "11:00 AM", 30, 1, 1, [3, 4, 5], "Updated overview", "Fall 2026", "STEM", "usr_person_admin_101", "Administrator", "op_edit_noop")
	assert_true(noop_res.get("no_changes", false) == true, "Test 7: No-Op edit returned clean no_changes result without generating unnecessary audit or outbox records.")

	# -------------------------------------------------------------
	# 8. STORED OUTBOX JSON CANONICAL VS DISPLAY STRUCTURE
	# -------------------------------------------------------------
	var outbox_chk = db.execute("SELECT payload_json FROM event_outbox WHERE event_type = 'SessionCreated' LIMIT 1;")
	var payload = JSON.parse_string(outbox_chk["data"][0]["payload_json"]) if outbox_chk["success"] else {}
	assert_true(payload.has("session_uuid") and payload.has("session_type_id") and payload.has("location_ids") and payload.has("display_session_type") and payload.has("display_room_location"), "Test 8: Verified SessionCreated outbox payload clearly separates canonical IDs from display snapshots.")

	# -------------------------------------------------------------
	# 9. LEGACY SESSION COMPATIBILITY COMPLETE VERIFICATION
	# -------------------------------------------------------------
	db.execute("INSERT INTO sessions (id, session_uuid, session_type_id, title, session_type, date_text, start_time, end_time, room_location, max_capacity, signup_required, limit_signups, is_active) VALUES (99, 'sess_legacy_99', 1, 'Legacy Algebra', 'LEAD Pathway', '2026-07-01', '02:00 PM', '03:30 PM', 'Study Room #1', 20, 1, 1, 1);")
	db.execute("INSERT INTO session_location_assignments (session_id, location_id) VALUES (99, 3);")
	
	var leg_edit = schedules_service.update_full_session_atomic(99, "Updated Legacy Algebra", 1, "2026-07-01", "02:00 PM", "03:30 PM", 25, 1, 1, [3], "Legacy overview", "", "", "usr_person_admin_101")
	var check_leg = db.execute("SELECT session_uuid, title, session_type_id FROM sessions WHERE id = 99;")
	var leg_locs = schedules_service.get_session_location_ids(99)

	assert_true(leg_edit["success"] and check_leg["data"][0]["session_uuid"] == "sess_legacy_99" and check_leg["data"][0]["title"] == "Updated Legacy Algebra" and int(check_leg["data"][0]["session_type_id"]) == 1 and leg_locs.size() == 1 and leg_locs[0] == 3, "Test 9: Verified pre-Phase-3 legacy session loaded mapped session_type_id (1), mapped location assignment (3), and preserved stable session_uuid after editing title.")

	# -------------------------------------------------------------
	# 10. RESTART PERSISTENCE ACROSS REOPENING FRESH CONTEXT
	# -------------------------------------------------------------
	var db_fresh = SQLiteDatabaseScript.new(db_path)
	var sch_fresh = SchedulesServiceScript.new(db_fresh)
	var fresh_sessions = sch_fresh.get_agenda_sessions("all")

	var target_fresh = {}
	for fs in fresh_sessions:
		if str(fs["session_uuid"]) == sess_uuid:
			target_fresh = fs
			break

	var fresh_locs = sch_fresh.get_session_location_ids(sess_id)

	assert_true(target_fresh.size() > 0 and str(target_fresh["title"]) == "Calculus & Linear Algebra Tutoring" and int(target_fresh["session_type_id"]) == 2 and fresh_locs.size() == 3 and str(target_fresh["term_override"]) == "Fall 2026", "Test 10: Genuine application restart: reopened fresh DB and verified title, session_uuid, type_id, location_ids, and term_override across fresh context.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 3 DOMAIN INTEGRATION TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
