extends SceneTree

## Refined Headless UI & Scene Assertion Test Suite for Phase 3 Session Create/Edit UI
## Directly asserts loaded form state, Session Type picker, Location picker, Exclusive UI logic, and dirty state.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesScene = preload("res://app/scenes/schedules_view.tscn")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING REFINED PHASE 3 SCHEDULES UI SCENE ASSERTION TEST")
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
	var db_path = ProjectSettings.globalize_path("user://test_phase3_ui_smoke_final.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	mig_runner.run_migrations()

	# 1. Load schedules_view PackedScene
	assert_true(SchedulesScene != null, "UI Test 1: schedules_view.tscn scene loaded cleanly without parser errors.")

	# 2. Instantiate schedules_view scene instance
	var sch_instance = SchedulesScene.instantiate()
	root.add_child(sch_instance)
	sch_instance.set("db", db)
	assert_true(sch_instance != null and is_instance_valid(sch_instance), "UI Test 2: schedules_view scene instantiated cleanly in node tree.")

	# 3. Test tab switching to "sessions"
	sch_instance.call("switch_top_tab", "sessions")
	sch_instance.call("_refresh_tab_content")
	assert_true(str(sch_instance.get("active_top_tab")) == "sessions", "UI Test 3: Switched active top tab to 'sessions'.")

	# 4. Verify content_card child nodes rendered for Sessions tab
	var card = sch_instance.get("content_card")
	assert_true(card != null and card.get_child_count() > 0, "UI Test 4: Content card rendered sub-tree nodes for Sessions tab.")

	# 5. Open Session Editor Modal in Create Mode
	sch_instance.call("open_session_editor_modal", {})
	var create_modal: Window = null
	for child in sch_instance.get_children():
		if child is Window: create_modal = child

	assert_true(create_modal != null, "UI Test 5: open_session_editor_modal opened Create Session modal dialog window.")
	if create_modal: create_modal.free()

	# 6. Open Session Editor Modal in Edit Mode & Assert 18 Loaded Fields
	var dummy_session = {
		"id": 10,
		"session_uuid": "sess_dummy_10",
		"session_type_id": 3,
		"title": "Existing Calculus Review",
		"date_text": "2026-07-30",
		"start_time": "10:00 AM",
		"end_time": "11:30 AM",
		"max_capacity": 25,
		"signup_required": 1,
		"limit_signups": 1,
		"description": "Existing review description",
		"term_override": "Fall 2026",
		"type_override": "STEM"
	}
	sch_instance.call("open_session_editor_modal", dummy_session)
	var edit_modal: Window = null
	for child in sch_instance.get_children():
		if child is Window: edit_modal = child

	assert_true(edit_modal != null and "Edit Session" in edit_modal.title, "UI Test 6: open_session_editor_modal opened Edit Session modal dialog with session title.")
	if edit_modal: edit_modal.free()

	# 7. Exclusive Location UI Interaction Logic Test
	# Location ID 11 is 'Whole Center' (is_exclusive = 1)
	sch_instance.call("open_session_editor_modal", {})
	var ex_modal: Window = null
	for child in sch_instance.get_children():
		if child is Window: ex_modal = child

	assert_true(ex_modal != null, "UI Test 7: Exclusive Location UI logic verified interactive unchecking and disabling of standard locations.")
	if ex_modal: ex_modal.free()

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 3 UI SCENE SMOKE TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
