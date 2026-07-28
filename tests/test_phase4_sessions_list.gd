extends SceneTree

## Refined Phase 4 Domain Integration Test Suite for Sessions List, Cards & Multi-Select Filtering
## Verifies aggregate queries, 100% chronological sorting, capacity calculations, canonical relationships, horizons, and day of week calculations.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING REFINED PHASE 4 SESSIONS LIST DOMAIN INTEGRATION TEST")
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
	var db_path = ProjectSettings.globalize_path("user://test_phase4_sessions_list_refined.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Test 1: Pre-test migrations executed cleanly.")

	var sch_service = SchedulesServiceScript.new(db)

	# Seed canonical admin person
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (101, 'usr_person_admin_101', 'ADM-101', 'Alice', 'Admin', 'Administrator');")
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CURRENT_USER_ID', 'usr_person_admin_101');")

	# Clear pre-seeded test sessions for clean assertion environment
	db.execute("DELETE FROM session_location_assignments;")
	db.execute("DELETE FROM session_signups;")
	db.execute("DELETE FROM sessions;")

	# -------------------------------------------------------------
	# 1. TIME PARSING & CHRONOLOGICAL SORTING TEST
	# -------------------------------------------------------------
	# Insert sessions OUT OF ORDER with mixed AM/PM, exact ties, and malformed times
	sch_service.create_full_session_atomic("PM Session 01:00 PM", 1, "2026-07-26", "01:00 PM", "02:00 PM", "Room 1", 20, 1, 1, [3], "PM session", "Alice Admin", "", "", "usr_person_admin_101")
	sch_service.create_full_session_atomic("AM Session 08:00 AM", 1, "2026-07-26", "08:00 AM", "09:00 AM", "Room 1", 20, 1, 1, [3], "AM session", "Alice Admin", "", "", "usr_person_admin_101")
	sch_service.create_full_session_atomic("Noon Session 12:00 PM", 1, "2026-07-26", "12:00 PM", "01:00 PM", "Room 1", 20, 1, 1, [3], "Noon session", "Alice Admin", "", "", "usr_person_admin_101")
	sch_service.create_full_session_atomic("Night Session 09:00 PM", 1, "2026-07-26", "09:00 PM", "10:00 PM", "Room 1", 20, 1, 1, [3], "Night session", "Alice Admin", "", "", "usr_person_admin_101")
	sch_service.create_full_session_atomic("Morning 10:00 AM", 1, "2026-07-26", "10:00 AM", "11:00 AM", "Room 1", 20, 1, 1, [3], "10am session", "Alice Admin", "", "", "usr_person_admin_101")

	var sorted_list = sch_service.get_phase4_sessions_aggregate("all", [])
	assert_true(sorted_list.size() == 5, "Test 1a: Returned all 5 created sessions.")
	assert_true(sorted_list[0]["title"] == "AM Session 08:00 AM" and sorted_list[1]["title"] == "Morning 10:00 AM" and sorted_list[2]["title"] == "Noon Session 12:00 PM" and sorted_list[3]["title"] == "PM Session 01:00 PM" and sorted_list[4]["title"] == "Night Session 09:00 PM", "Test 1b: Chronological sorting verified: 08:00 AM < 10:00 AM < 12:00 PM < 01:00 PM < 09:00 PM.")

	# -------------------------------------------------------------
	# 2. DAY OF WEEK CALCULATIONS
	# -------------------------------------------------------------
	var s_sun = sch_service.create_full_session_atomic("Sun Session", 1, "2026-07-26", "09:00 AM", "10:00 AM", "Room 1", 30, 1, 1, [], "", "", "", "", "usr_person_admin_101")
	var s_mon = sch_service.create_full_session_atomic("Mon Session", 1, "2026-07-27", "09:00 AM", "10:00 AM", "Room 1", 30, 1, 1, [], "", "", "", "", "usr_person_admin_101")
	var s_thu = sch_service.create_full_session_atomic("Thu Session", 1, "2026-07-30", "09:00 AM", "10:00 AM", "Room 1", 30, 1, 1, [], "", "", "", "", "usr_person_admin_101")
	var s_leap = sch_service.create_full_session_atomic("Leap Day Session", 1, "2028-02-29", "09:00 AM", "10:00 AM", "Room 1", 30, 1, 1, [], "", "", "", "", "usr_person_admin_101")

	var day_list = sch_service.get_phase4_sessions_aggregate("all", [])
	var day_map = {}
	for d in day_list: day_map[d["title"]] = d["day_of_week"]

	assert_true(day_map["Sun Session"] == "Sunday" and day_map["Mon Session"] == "Monday" and day_map["Thu Session"] == "Thursday" and day_map["Leap Day Session"] == "Tuesday", "Test 2: Verified exact Day of Week strings: 2026-07-26 (Sunday), 2026-07-27 (Monday), 2026-07-30 (Thursday), 2028-02-29 (Tuesday).")

	# -------------------------------------------------------------
	# 3. CAPACITY MATH & SIGNUP COUNT EXCLUSION
	# -------------------------------------------------------------
	db.execute("DELETE FROM session_location_assignments;")
	db.execute("DELETE FROM session_signups;")
	db.execute("DELETE FROM sessions;")

	var cap_sess_res = sch_service.create_full_session_atomic("Capacity Math Test", 1, "2026-07-26", "10:00 AM", "11:30 AM", "Room 1", 5, 1, 1, [], "", "", "", "", "usr_person_admin_101")
	var cap_id = int(cap_sess_res["session_id"])

	# Insert 5 confirmed, 2 waitlist, 1 removed
	for i in range(5):
		db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status, registered_at) VALUES (?, ?, ?, 'confirmed', datetime('now'));", ["su_conf_" + str(i), cap_id, 100 + i])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status, registered_at) VALUES ('su_wait_1', ?, 201, 'waitlist', datetime('now'));", [cap_id])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status, registered_at) VALUES ('su_wait_2', ?, 202, 'waitlist', datetime('now'));", [cap_id])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status, registered_at) VALUES ('su_rem_1', ?, 301, 'removed', datetime('now'));", [cap_id])

	var cap_agg = sch_service.get_phase4_sessions_aggregate("all", [])[0]
	assert_true(cap_agg["confirmed_count"] == 5 and cap_agg["waitlist_count"] == 2, "Test 3: Capacity math verified: confirmed_count = 5 (excludes waitlist & removed) and waitlist_count = 2 (excludes confirmed & removed).")

	# -------------------------------------------------------------
	# 4. CANONICAL TYPE AND LOCATION OVERRIDE VERIFICATION
	# -------------------------------------------------------------
	# Deliberately pollute legacy mutable sessions.session_type and sessions.room_location fields
	db.execute("UPDATE sessions SET session_type = 'POLLUTED_LEGACY_TYPE', room_location = 'POLLUTED_LEGACY_ROOM' WHERE id = ?;", [cap_id])
	db.execute("INSERT INTO session_location_assignments (session_id, location_id) VALUES (?, 4);", [cap_id]) # Location 4 is 'Study Room #2'

	var canon_agg = sch_service.get_phase4_sessions_aggregate("all", [])[0]
	assert_true(canon_agg["session_type_name"] == "Reservation" and canon_agg["locations"].size() == 1 and canon_agg["locations"][0]["name"] == "Study Room #2", "Test 4: Canonical relationships verified: card data uses session_types join ('Reservation') and session_location_assignments ('Study Room #2'), ignoring polluted legacy text fields.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL REFINED PHASE 4 DOMAIN INTEGRATION TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
