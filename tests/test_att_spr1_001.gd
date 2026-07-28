extends SceneTree

## Headless Automated Test Suite for Story ATT-SPR1-001
## Attendance & On-Site Check-In Operations Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING ATT-SPR1-001 ATTENDANCE OPERATIONS TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_att_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	# Seed person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, grade) VALUES ('usr_att_test', 'P-20260720-7777', 'Isaac', 'Newton', 'active', 'Senior');")

	# Instantiate AttendanceView
	var att_scene = load("res://app/scenes/attendance_view.tscn")
	assert_true(att_scene != null, "AttendanceView scene loaded successfully.")

	var att_view = att_scene.instantiate()
	att_view.db = db
	root.add_child(att_view)

	# Verify dropdown population
	assert_true(att_view.person_list.size() >= 1, "Person dropdown populated from SQLite people table.")

	# Record Check-In
	att_view._on_record_check_in()

	var att_log_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_uuid = 'usr_att_test';")
	assert_true(att_log_res["success"] and att_log_res["data"][0]["cnt"] == 1, "Attendance check-in record saved to SQLite attendance_log.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'CheckInRecorded';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "CheckInRecorded transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL ATT-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
