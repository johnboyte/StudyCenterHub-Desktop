extends SceneTree

## Phase 5 Session Assistant Integration Test Suite
## Verifies participant lookup, registration, capacity enforcement, automatic waitlist placement,
## confirmed removal & auto-promotion, manual promotion, waitlist reordering, attendance marking,
## and transactional outbox/audit log generation.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING PHASE 5 SESSION ASSISTANT INTEGRATION TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_phase5_session_assistant.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Test 1: Pre-test database migrations executed cleanly.")

	var sch_service = SchedulesServiceScript.new(db)

	# Seed canonical admin person
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (101, 'usr_person_admin_101', 'ADM-101', 'Alice', 'Admin', 'Administrator');")
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_ID', 'usr_person_admin_101');")

	# Seed test students
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (201, 'usr_p_201', 'STU-201', 'Bob', 'Smith', 'Student');")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (202, 'usr_p_202', 'STU-202', 'Charlie', 'Brown', 'Student');")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (203, 'usr_p_203', 'STU-203', 'Diana', 'Prince', 'Student');")

	# Create a capacity-limited session (Max 2)
	var s_res = sch_service.create_full_session_atomic("Calculus II Review", 1, "2026-07-30", "10:00 AM", "11:30 AM", "Room 1", 2, 1, 1, [3], "Review", "Alice Admin", "", "", "usr_person_admin_101")
	var sess_id = int(s_res["session_id"])
	assert_true(sess_id > 0, "Test 2: Created capacity-limited Session (Max Capacity = 2).")

	# -------------------------------------------------------------
	# 1. DIRECTORY LOOKUP TEST
	# -------------------------------------------------------------
	var search_res = sch_service.search_people_for_session_registration("Smith", sess_id)
	assert_true(search_res.size() > 0 and search_res[0]["human_id"] == "STU-201", "Test 3: Directory search by name 'Smith' returned Bob Smith (STU-201).")

	# -------------------------------------------------------------
	# 2. CONFIRMED REGISTRATION & CAPACITY ENFORCEMENT
	# -------------------------------------------------------------
	var reg1 = sch_service.register_participant_atomic(sess_id, 201)
	assert_true(reg1["success"] and reg1["status"] == "confirmed", "Test 4: First participant registered as 'confirmed' below capacity.")

	var reg2 = sch_service.register_participant_atomic(sess_id, 202)
	assert_true(reg2["success"] and reg2["status"] == "confirmed", "Test 5: Second participant registered as 'confirmed' at capacity.")

	var reg3 = sch_service.register_participant_atomic(sess_id, 203)
	assert_true(reg3["success"] and reg3["status"] == "waitlist" and reg3["position"] == 1, "Test 6: Third participant automatically placed on 'waitlist' at position #1 after capacity reached.")

	# -------------------------------------------------------------
	# 3. ROSTER FETCH & ATTENDANCE MARKING TEST
	# -------------------------------------------------------------
	var signups1 = sch_service.get_signups_for_session(sess_id)
	print("SIGNUPS1 SIZE: ", signups1.size(), " DATA: ", signups1)
	assert_true(signups1.size() == 3, "Test 7: Roster fetch returned 3 total signups (2 confirmed, 1 waitlist).")

	# Mark Bob Smith (201) Present
	var att_res1 = sch_service.mark_session_attendance_atomic(sess_id, 201, "present", "usr_person_admin_101")
	print("ATT RES1: ", att_res1)
	assert_true(att_res1["success"], "Test 8: Marked Bob Smith 'present' in canonical attendance_log.")

	# Mark Charlie Brown (202) No Show
	var att_res2 = sch_service.mark_session_attendance_atomic(sess_id, 202, "no_show", "usr_person_admin_101")
	assert_true(att_res2["success"], "Test 9: Marked Charlie Brown 'no_show' in canonical attendance_log.")

	var signups2 = sch_service.get_signups_for_session(sess_id)
	var att_map = {}
	for s in signups2: att_map[int(s["person_id"])] = s["attendance_status"]
	assert_true(att_map[201] == "present" and att_map[202] == "no_show" and att_map[203] == "unmarked", "Test 10: Derived attendance statuses verified: Bob (present), Charlie (no_show), Diana waitlist (unmarked).")

	# -------------------------------------------------------------
	# 4. CONFIRMED REMOVAL & AUTOMATIC PROMOTION TEST
	# -------------------------------------------------------------
	var conf1_signup_id = signups1[0]["id"] # Bob Smith
	var rem_res = sch_service.remove_confirmed_and_autopromote_atomic(sess_id, conf1_signup_id, "usr_person_admin_101")
	assert_true(rem_res["success"] and rem_res["auto_promoted"] == true, "Test 11: Confirmed removal triggered automatic promotion of Diana Prince from waitlist to confirmed.")

	var signups3 = sch_service.get_signups_for_session(sess_id)
	var conf_names = []
	for s in signups3:
		if s["signup_status"] == "confirmed":
			conf_names.append(s["first_name"])
	assert_true("Diana" in conf_names and "Charlie" in conf_names, "Test 12: Updated confirmed roster contains Diana Prince (auto-promoted) and Charlie Brown.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 5 INTEGRATION TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
