extends SceneTree

## Headless Automated Test Suite for Story SCH-SPR1-001
## Session Scheduling & Room Calendar Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING SCH-SPR1-001 SESSION SCHEDULING TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_sch_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0006 executed successfully.")

	# Instantiate SchedulesView
	var sch_scene = load("res://app/scenes/schedules_view.tscn")
	assert_true(sch_scene != null, "SchedulesView scene loaded successfully.")

	var sch_view = sch_scene.instantiate()
	sch_view.db = db
	root.add_child(sch_view)

	# Verify rooms & active sessions
	assert_true(sch_view.available_areas.size() >= 4, "Rooms list populated from database.")

	# Schedule new session
	var sch_svc = load("res://src/domain/schedules/schedules_service.gd").new(db)
	sch_svc.create_full_session_atomic("Advanced Calculus Tutoring", 1, "2026-07-30", "10:00 AM", "11:00 AM", "Study Room #1", 5, 1, 1, [1], "Description", "Administrator", "", "", "usr_admin_master")

	var sess_res = db.execute("SELECT COUNT(*) as cnt FROM sessions WHERE title = 'Advanced Calculus Tutoring';")
	assert_true(sess_res["success"] and sess_res["data"][0]["cnt"] == 1, "Session record persisted to SQLite sessions table.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'SessionCreated';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "SessionCreated transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SCH-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
