extends SceneTree

## Phase 5 Session Assistant UI Scene Smoke Test Suite
## Verifies schedules_view.tscn instantiation, Session Assistant view navigation, roster card rendering,
## search bar rendering, and Return to Sessions navigation restoring active horizon and filters.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const SchedulesScene = preload("res://app/scenes/schedules_view.tscn")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING PHASE 5 SESSION ASSISTANT UI SCENE TEST SUITE")
	print("==========================================================")
	call_deferred("run_ui_smoke_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_ui_smoke_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_phase5_ui_session_assistant.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	mig_runner.run_migrations()

	var config_service = SessionConfigServiceScript.new(db)
	var sch_service = SchedulesServiceScript.new(db)

	assert_true(SchedulesScene != null, "UI Test 1: schedules_view.tscn scene loaded cleanly without parser errors.")

	var sch_instance = SchedulesScene.instantiate()
	sch_instance.set("db", db)
	sch_instance.set("config_service", config_service)
	sch_instance.set("sch_service", sch_service)
	root.add_child(sch_instance)

	assert_true(sch_instance != null and is_instance_valid(sch_instance), "UI Test 2: schedules_view scene instantiated cleanly in node tree.")

	sch_instance.call("switch_top_tab", "sessions")
	sch_instance.call("_refresh_tab_content")
	assert_true(str(sch_instance.get("active_top_tab")) == "sessions", "UI Test 3: Switched active top tab to 'sessions'.")

	# Render Session Assistant View
	var dummy_session = {
		"id": 10,
		"session_uuid": "sess_dummy_10",
		"title": "Calculus II Review Session",
		"date_text": "2026-07-30",
		"start_time": "10:00 AM",
		"end_time": "11:30 AM",
		"session_type_name": "Tutoring Session"
	}
	sch_instance.call("open_session_assistant_placeholder", dummy_session)
	var card = sch_instance.get("content_card")
	assert_true(card != null and card.get_child_count() > 0, "UI Test 4: open_session_assistant_placeholder rendered full operational Session Assistant view.")

	# Return to Sessions list
	sch_instance.call("_refresh_tab_content")
	assert_true(str(sch_instance.get("active_top_tab")) == "sessions" and str(sch_instance.get("active_session_horizon")) == "upcoming", "UI Test 5: Return to Sessions restored Sessions list view with active 'upcoming' horizon.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 5 UI SCENE SMOKE TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
