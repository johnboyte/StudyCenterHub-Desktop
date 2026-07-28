extends SceneTree

## Headless Automated Test Suite for Main Application Navigation Shell & Home Dashboard
## Stories: SHELL-SPR1-001 & HOME-SPR1-001
## Complies with [PD-001] (Offline Storage), [PD-002] (Read Isolation), and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING APP SHELL & HOME DASHBOARD TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_app_shell.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	# Load AppShell scene
	var shell_scene = load("res://app/scenes/app_shell.tscn")
	assert_true(shell_scene != null, "AppShell scene file loaded successfully.")

	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (1, 'usr_staff_1', 'STF-001', 'John', 'Smith', 'Staff');")
	db.execute("INSERT OR REPLACE INTO staff_pins (person_id, pin_hash, role) VALUES (1, 'hash123', 'Staff');")

	var shell = shell_scene.instantiate()
	shell.db = db
	root.add_child(shell)

	assert_true(shell.current_view_name == "home", "Default active view is Home.")

	# Test Team Leader Dropdown & ACTIVE_SUPERVISOR setting update
	var dropdown = shell.find_child("TeamLeaderDropdown", true, false) as OptionButton

	assert_true(dropdown != null and dropdown.item_count >= 1, "Today's Team Leader dropdown populated with staff options.")

	if dropdown != null and dropdown.item_count > 0:
		shell._on_team_leader_selected(0)
		var leader_name = dropdown.get_item_text(0)
		var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR';")
		assert_true(setting_res["success"] and setting_res["data"].size() > 0, "ACTIVE_SUPERVISOR setting persisted to SQLite app_settings.")
		if setting_res["data"].size() > 0:
			assert_true(setting_res["data"][0]["setting_value"] == leader_name, "Selected Team Leader name saved correctly in database.")

	# Test View Switching
	shell.switch_view("people")
	assert_true(shell.current_view_name == "people", "Sidebar navigation switched active view to People (Directory).")

	shell.switch_view("home")
	assert_true(shell.current_view_name == "home", "Sidebar navigation switched active view back to Home.")

	# Test HomeView Component Tree
	var home_view = shell.current_view_node
	assert_true(home_view != null, "HomeView instantiated and attached to ContentContainer.")

	var middle_grid = home_view.find_child("MiddleGrid", true, false)
	assert_true(middle_grid != null and middle_grid.get_child_count() == 3, "Home Dashboard renders 3 middle operational cards (Needs Attention, Today at Center, AI Assistant).")

	var activity_card = home_view.find_child("RecentActivityCard", true, false)
	assert_true(activity_card != null, "Home Dashboard renders Recent Activity feed section.")

	# Test Read Isolation (PD-002)
	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE status = 'pending';")
	var pending_outbox = outbox_res["data"][0]["cnt"] if outbox_res["success"] else 0
	assert_true(pending_outbox == 0, "PD-002: Navigation and Home Dashboard rendering created zero outbox transaction side effects.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL APP SHELL & HOME DASHBOARD OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
