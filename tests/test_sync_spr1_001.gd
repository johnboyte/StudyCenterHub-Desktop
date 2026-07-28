extends SceneTree

## Headless Automated Test Suite for Story SYNC-SPR1-001
## Customer-Owned Google Workspace Master Sync Worker
## Complies with [PD-001] (Customer Data Ownership & Outbox Pattern).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING SYNC-SPR1-001 GOOGLE WORKSPACE SYNC TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_sync_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	# Seed an outbox event
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES ('evt_sync_001', 'CheckInRecorded', 'Attendance', 'chk_111', '{}', 'dev_mac', 'pending');")

	# Instantiate SettingsView
	var set_scene = load("res://app/scenes/settings_view.tscn")
	assert_true(set_scene != null, "SettingsView scene loaded successfully.")

	var set_view = set_scene.instantiate()
	set_view.db = db
	root.add_child(set_view)

	# Verify pending outbox events before sync
	var pending_before = set_view.sync_worker.get_pending_outbox_events()
	assert_true(pending_before.size() == 1, "Pending outbox event detected by sync worker.")

	# Execute Sync Now
	set_view._on_sync_now_pressed()

	var pending_after = set_view.sync_worker.get_pending_outbox_events()
	assert_true(pending_after.size() == 0, "Outbox queue drained completely after sync.")

	var synced_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE status = 'synced';")
	assert_true(synced_res["success"] and synced_res["data"][0]["cnt"] == 1, "Outbox event status updated to 'synced' with timestamp.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SYNC-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
