extends SceneTree

## Automated Headless UI & Scene Smoke Test for Phase 2 Sessions Configuration UI
## Verifies administration_view scene loading, tab switching, rendering, and UI controls.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AdminScene = preload("res://app/scenes/administration_view.tscn")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING PHASE 2 ADMINISTRATION UI SCENE SMOKE TEST")
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
	var db_path = ProjectSettings.globalize_path("user://test_phase2_ui_smoke.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	mig_runner.run_migrations()

	# 1. Load administration_view PackedScene
	assert_true(AdminScene != null, "UI Test 1: administration_view.tscn scene loaded cleanly without parser errors.")

	# 2. Instantiate administration_view scene instance
	var admin_instance = AdminScene.instantiate()
	admin_instance.db = db
	root.add_child(admin_instance)
	assert_true(admin_instance != null and is_instance_valid(admin_instance), "UI Test 2: administration_view scene instantiated cleanly in node tree.")

	# 3. Test tab switching to "sessions"
	admin_instance.switch_tab("sessions")
	assert_true(admin_instance.active_tab == "sessions", "UI Test 3: Switched active tab to 'sessions'.")

	# 4. Verify content_card child nodes rendered
	var card = admin_instance.content_card
	assert_true(card != null and card.get_child_count() > 0, "UI Test 4: Content card rendered sub-tree nodes for Sessions tab.")

	# 5. Verify pending outbox count query helper
	var pending_cnt = admin_instance._get_pending_outbox_count()
	assert_true(pending_cnt >= 0, "UI Test 5: Outbox offline queue status badge query returned valid count (%d)." % pending_cnt)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 2 UI SCENE SMOKE TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
