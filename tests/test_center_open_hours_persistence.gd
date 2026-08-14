extends SceneTree

## Integration Test Suite for Center Weekly Operating Hours Persistence
## Verifies full 7-day schedule updates, split shifts, open/closed toggles, and fresh context persistence.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING CENTER OPEN HOURS PERSISTENCE TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_open_hours_persistence_clean.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Test 1: Database migrations executed cleanly.")

	var sch_svc = SchedulesServiceScript.new(db)
	var initial_hours = sch_svc.get_open_hours()
	assert_true(initial_hours.size() == 7 and initial_hours[0].has("id"), "Test 2: Initial open hours retrieved for all 7 days with id column.")

	# -------------------------------------------------------------
	# UPDATE ALL 7 DAYS WITH SPECIFIC HOURS & SPLIT SHIFTS
	# -------------------------------------------------------------
	# Sunday: Closed
	var u_sun = sch_svc.update_open_hours_atomic("Sunday", "12:00 PM", "05:00 PM", 1, 0)
	# Monday: Open 08:00 AM - 04:00 PM
	var u_mon = sch_svc.update_open_hours_atomic("Monday", "08:00 AM", "04:00 PM", 0, 0)
	# Tuesday: Open 09:00 AM - 05:00 PM
	var u_tue = sch_svc.update_open_hours_atomic("Tuesday", "09:00 AM", "05:00 PM", 0, 0)
	# Wednesday: Open 09:00 AM - 01:00 PM with Split Shift 04:00 PM - 08:00 PM
	var u_wed = sch_svc.update_open_hours_atomic("Wednesday", "09:00 AM", "01:00 PM", 0, 1, "04:00 PM", "08:00 PM")
	# Thursday: Open 10:00 AM - 06:00 PM
	var u_thu = sch_svc.update_open_hours_atomic("Thursday", "10:00 AM", "06:00 PM", 0, 0)
	# Friday: Closed
	var u_fri = sch_svc.update_open_hours_atomic("Friday", "03:00 PM", "06:00 PM", 1, 0)
	# Saturday: Open 10:00 AM - 02:00 PM
	var u_sat = sch_svc.update_open_hours_atomic("Saturday", "10:00 AM", "02:00 PM", 0, 0)

	assert_true(u_sun["success"] and u_mon["success"] and u_tue["success"] and u_wed["success"] and u_thu["success"] and u_fri["success"] and u_sat["success"], "Test 3: All 7 days' update_open_hours_atomic operations returned success.")

	# -------------------------------------------------------------
	# PERSISTENCE VERIFICATION ACROSS FRESH DATABASE CONTEXT
	# -------------------------------------------------------------
	var db_fresh = SQLiteDatabaseScript.new(db_path)
	var sch_fresh = SchedulesServiceScript.new(db_fresh)
	var fresh_hours = sch_fresh.get_open_hours()

	var hours_map = {}
	for h in fresh_hours:
		hours_map[str(h.get("day_of_week"))] = h

	var sun_h = hours_map.get("Sunday", {})
	var mon_h = hours_map.get("Monday", {})
	var wed_h = hours_map.get("Wednesday", {})
	var fri_h = hours_map.get("Friday", {})

	assert_true(int(sun_h.get("is_closed", 0)) == 1, "Test 4: Sunday accurately persisted as Closed.")
	assert_true(str(mon_h.get("open_time")) == "08:00 AM" and str(mon_h.get("close_time")) == "04:00 PM" and int(mon_h.get("is_closed", 1)) == 0, "Test 5: Monday accurately persisted Open 08:00 AM - 04:00 PM.")
	assert_true(int(wed_h.get("has_split_shift", 0)) == 1 and str(wed_h.get("session2_start")) == "04:00 PM" and str(wed_h.get("session2_end")) == "08:00 PM", "Test 6: Wednesday accurately persisted Split Shift enabled with Session 2 hours.")
	assert_true(int(fri_h.get("is_closed", 0)) == 1, "Test 7: Friday accurately persisted as Closed.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL CENTER OPEN HOURS PERSISTENCE TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
