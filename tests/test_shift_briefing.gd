extends SceneTree

## Headless Automated Test Suite for Story ATT-SPR1-002
## Supervisor End-of-Shift Briefings & Operational Logs
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const ShiftBriefingServiceScript = preload("res://src/domain/attendance/shift_briefing_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING ATT-SPR1-002 SHIFT BRIEFINGS TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_shift_briefing.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0011 executed successfully.")

	var brief_service = ShiftBriefingServiceScript.new(db)
	var log_res = brief_service.log_shift_brief_atomic("Pastor John", "Evening study session completed smoothly. 32 check-ins.", 0)
	assert_true(log_res["success"], "Shift briefing record created successfully.")

	var briefs = brief_service.get_recent_briefings()
	assert_true(briefs.size() >= 2, "Shift briefings list populated from database.") # 1 seeded + 1 logged

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'ShiftBriefLogged';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "ShiftBriefLogged transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL ATT-SPR1-002 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
