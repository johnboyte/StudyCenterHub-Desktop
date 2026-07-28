extends SceneTree

## Headless Automated Test Suite for Story REP-SPR1-001
## Operational Reports & Ministry Analytics Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING REP-SPR1-001 OPERATIONAL REPORTS TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_rep_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations executed successfully.")

	# Seed person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, grade, phone) VALUES ('usr_rep_test', 'P-20260720-5555', 'Galileo', 'Galilei', 'active', 'Senior', '555-0188');")

	# Instantiate ReportsView
	var rep_scene = load("res://app/scenes/reports_view.tscn")
	assert_true(rep_scene != null, "ReportsView scene loaded successfully.")

	var rep_view = rep_scene.instantiate()
	rep_view.db = db
	root.add_child(rep_view)

	# Test KPI metrics
	var kpis = rep_view.rep_service.get_summary_kpis()
	assert_true(kpis["active_people"] == 1, "KPI active people calculated correctly.")
	assert_true(kpis["total_people"] == 1, "KPI total registered constituents calculated correctly.")

	# Test CSV Report Generation
	var csv = rep_view.rep_service.generate_csv_report()
	assert_true(csv.contains("Galileo") and csv.contains("Galilei"), "CSV report output contains constituent data.")

	# Test Read Isolation (PD-002)
	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE status = 'pending';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 0, "PD-002: Reports calculation created zero outbox transaction side effects.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL REP-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
