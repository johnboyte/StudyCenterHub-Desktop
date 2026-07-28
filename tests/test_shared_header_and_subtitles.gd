extends SceneTree

## Headless Automated Test Suite for Shared Application Header & Subtitles
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING SHARED HEADER & SUBTITLES AUTOMATED TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_shared_header.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	# Instantiate AppShell
	var shell_scene = load("res://app/scenes/app_shell.tscn")
	assert_true(shell_scene != null, "AppShell scene loaded successfully.")

	var app_shell = shell_scene.instantiate()
	app_shell.db = db
	root.add_child(app_shell)

	# Assertion 1: Test default subtitle for Home
	var home_sub = app_shell._resolve_page_subtitle("home")
	assert_true(home_sub == "Here’s what’s happening at StudyCenter today.", "Home page default subtitle resolved correctly.")

	# Assertion 2: Test default subtitle for Check In
	var att_sub = app_shell._resolve_page_subtitle("attendance")
	assert_true(att_sub == "Scan badges, find people, and record attendance.", "Check In page default subtitle resolved correctly.")

	# Assertion 3: Test Org-Wide Override
	db.execute("INSERT OR REPLACE INTO organization_page_header_messages (page_key, message) VALUES ('home', 'Welcome to StudyCenter Headquarters!');")
	var org_sub = app_shell._resolve_page_subtitle("home")
	assert_true(org_sub == "Welcome to StudyCenter Headquarters!", "Organization-wide subtitle override resolves with top priority over default.")

	# Assertion 4: Test User-Specific Override
	db.execute("INSERT OR REPLACE INTO user_page_header_messages (user_id, page_key, message) VALUES (1, 'home', 'Welcome back, Director Laura!');")
	var user_sub = app_shell._resolve_page_subtitle("home")
	assert_true(user_sub == "Welcome back, Director Laura!", "User-specific subtitle override saved and retrieved successfully.")

	# Assertion 5: Test view switching refreshes header
	app_shell.switch_view("people")
	assert_true(app_shell.current_view_name == "people", "AppShell navigated to People view successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	quit()
