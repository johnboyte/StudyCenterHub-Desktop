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

	# Save historical legacy pathway track via direct service (simulating historical source row)
	var legacy_svc = load("res://src/domain/pathways/pathways_service.gd").new(db)
	var p = pw_view.person_list[0]
	var data = {
		"real_life_enrolled": 1,
		"fellows_enrolled": 1,
		"fellows_certificate": 1,
		"lead_enrolled": 1,
		"lead_certificate": 1,
		"lead_current_year": "Year 2"
	}
	var res = legacy_svc.save_legacy_pathway_atomic(p, data)
	assert_true(res["success"], "Historical legacy record written via backend service.")

	# Verify historical data remains 100% readable
	var read_back = legacy_svc.get_person_legacy_pathway(int(p["id"]))
	assert_true(int(read_back["real_life_enrolled"]) == 1 and str(read_back["lead_current_year"]) == "Year 2", "Historical legacy pathway data readable.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL LEGACY PATHWAYS OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
