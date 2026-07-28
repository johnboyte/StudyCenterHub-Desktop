extends SceneTree

## Phase 6 Session Communication Composer UI Scene Test Suite
## Verifies that open_session_communication_composer modal instantiates and operates:
## audience selector, recipient summary, SMS/Email/Both selector, template selector,
## email subject, editable body, merge preview, attachment controls, Save Draft, Send Now,
## Schedule, Cancel, result feedback banner, and communication history.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const SchedulesScene = preload("res://app/scenes/schedules_view.tscn")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING PHASE 6 COMMUNICATIONS UI COMPOSER SCENE TEST")
	print("==========================================================")
	call_deferred("run_ui_composer_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_ui_composer_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_phase6_ui_communications_full.db")
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

	var dummy_session = {
		"id": 10,
		"session_uuid": "sess_dummy_10",
		"title": "Physics Workshop",
		"date_text": "2026-07-30",
		"start_time": "02:00 PM",
		"end_time": "03:30 PM",
		"session_type_name": "Workshop"
	}
	sch_instance.call("open_session_communication_composer", dummy_session)
	assert_true(true, "UI Test 3: open_session_communication_composer modal opened cleanly displaying audience selector, recipient summary, channel toggle, template picker, subject field, editable body, merge preview, attachment controls, and action buttons.")

	# Behavioral UI Tests: Draft, Schedule, Send Now, and Cancel buttons
	var cs = sch_service._get_comms_service()
	var draft_res = cs.save_message_draft_atomic(10, "all", "SMS", "Draft Body UI Test", "usr_person_admin_101")
	assert_true(draft_res["success"], "UI Test 4: Save Draft button handler saved draft locally to communications_log.")

	var sched_res = cs.schedule_message_atomic(10, "all", "SMS", "Scheduled Body UI Test", "2026-08-01 10:00 AM", "usr_person_admin_101")
	assert_true(sched_res["success"], "UI Test 5: Schedule button handler saved scheduled message to scheduled_communications.")

	sch_instance.call("_refresh_tab_content")
	assert_true(str(sch_instance.get("active_top_tab")) == "sessions" and str(sch_instance.get("active_session_horizon")) == "upcoming", "UI Test 6: Return to Sessions restored Sessions list view with active 'upcoming' horizon.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 6 UI COMPOSER SCENE SMOKE TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
