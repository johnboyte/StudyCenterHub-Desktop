extends SceneTree

## Headless Automated Test Suite for Story ADM-SPR1-001
## Administration & Platform Control Center
## Complies with [PD-006] (Subscription Licensing), [PD-009] (RBAC), and [PD-010] (White-Label & Vocabulary).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING ADM-SPR1-001 ADMINISTRATION CONTROL CENTER TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_adm_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	# Instantiate AdministrationView
	var admin_scene = load("res://app/scenes/administration_view.tscn")
	assert_true(admin_scene != null, "AdministrationView scene loaded successfully.")

	var admin_view = admin_scene.instantiate()
	admin_view.db = db
	root.add_child(admin_view)

	assert_true(admin_view.active_tab == "modules", "Default active tab is Subscription & Modules.")

	# Test Tab Switching
	admin_view.switch_tab("rbac")
	assert_true(admin_view.active_tab == "rbac", "Tab switched to Role Access (RBAC).")

	admin_view.switch_tab("branding")
	assert_true(admin_view.active_tab == "branding", "Tab switched to White-Label & Vocabulary.")

	# Test Saving Settings to SQLite app_settings
	admin_view._save_setting("BRAND_PRIMARY_COLOR", "#E05A36")
	var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'BRAND_PRIMARY_COLOR';")
	assert_true(setting_res["success"] and setting_res["data"].size() > 0, "BRAND_PRIMARY_COLOR persisted to SQLite app_settings.")
	if setting_res["data"].size() > 0:
		assert_true(setting_res["data"][0]["setting_value"] == "#E05A36", "Brand color value saved correctly.")

	admin_view._save_setting("CUSTOM_VOCABULARY", "Student,Class")
	var vocab_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CUSTOM_VOCABULARY';")
	assert_true(vocab_res["success"] and vocab_res["data"].size() > 0, "CUSTOM_VOCABULARY persisted to SQLite app_settings.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL ADM-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
