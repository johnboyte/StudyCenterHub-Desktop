extends SceneTree

## Headless Automated Test Suite for Legacy Pathways Integration (Real Life, Fellows, LEAD)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING LEGACY PATHWAYS TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_pathways_legacy.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res["success"]:
		print("DEBUG MIGRATION ERROR: ", mig_res["error"])
	assert_true(mig_res["success"], "Database migration 0008 executed successfully.")

	# Seed person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status) VALUES ('usr_pw_test', 'P-20260720-6666', 'Isaac', 'Newton', 'active');")

	# Instantiate PathwaysView
	var pw_scene = load("res://app/scenes/pathways_view.tscn")
	assert_true(pw_scene != null, "PathwaysView scene loaded successfully.")

	var pw_view = pw_scene.instantiate()
	pw_view.db = db
	root.add_child(pw_view)

	# Verify constituent in dropdown
	assert_true(pw_view.person_list.size() >= 1, "Constituent list populated from database.")

	# Check and save legacy pathway state
	pw_view.chk_real_life.button_pressed = true
	pw_view.chk_fellows.button_pressed = true
	pw_view.chk_fellows_cert.button_pressed = true
	pw_view.chk_lead.button_pressed = true
	pw_view.chk_lead_cert.button_pressed = true
	pw_view.lead_year_dropdown.select(1) # Year 2

	pw_view._on_save_pathway_pressed()

	var record_res = db.execute("SELECT * FROM legacy_pathway_tracks WHERE real_life_enrolled = 1 AND fellows_certificate = 1 AND lead_current_year = 'Year 2';")
	assert_true(record_res["success"] and record_res["data"].size() == 1, "Legacy pathway tracks (Real Life, Fellows, LEAD) persisted to SQLite table.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'PathwayProgressUpdated';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "PathwayProgressUpdated transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL LEGACY PATHWAYS OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
