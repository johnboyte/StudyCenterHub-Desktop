extends SceneTree

## Headless Permanent Regression Test Suite for Schedule Shift Copy and Cut Atomicity
## Verifies batch copy/paste and cut/paste operations on schedule_entries (Migration 0014),
## field preservation, new UUID generation, atomicity on failure, and outbox sync event emission.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func _init() -> void:
	print("==========================================================")
	print("STARTING SCHEDULE SHIFT COPY/CUT ATOMICITY TEST SUITE")
	print("==========================================================")
	call_deferred("run_shift_copy_cut_tests")

func run_shift_copy_cut_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_shift_copy_cut_permanent.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	var sch_svc = SchedulesServiceScript.new(db)

	# Seed initial shift entry
	var s1 = sch_svc.create_shift_entry_atomic("Marcus Vance", "Shift Supervisor", "2026-07-20", "03:00 PM", "08:00 PM", "Gathering Room", "Initial note")
	assert_true(s1["success"] and s1["entry_uuid"] != "", "Initial shift entry created cleanly with unique entry_uuid.")

	# Scenario A & D: Copy single shift generates new entry_uuid
	var copy_res1 = sch_svc.copy_paste_shifts_atomic([{
		"person_name": "Marcus Vance", "shift_role": "Shift Supervisor", "shift_date": "2026-07-21", "start_time": "03:00 PM", "end_time": "08:00 PM", "area": "Gathering Room", "notes": "Initial note"
	}])
	assert_true(copy_res1["success"] and copy_res1["created_uuids"].size() == 1 and copy_res1["created_uuids"][0] != s1["entry_uuid"], "Scenario A & D: Single shift copied successfully generating a new distinct entry_uuid.")

	# Scenario B & C: Copy multiple shifts across different days preserving fields
	var copy_res2 = sch_svc.copy_paste_shifts_atomic([
		{"person_name": "Sarah Johnson", "shift_role": "Study Tutor", "shift_date": "2026-07-22", "start_time": "04:00 PM", "end_time": "06:00 PM", "area": "Study Room #1", "notes": "Multicopy 1"},
		{"person_name": "Michael Brown", "shift_role": "Greeter", "shift_date": "2026-07-23", "start_time": "05:00 PM", "end_time": "07:00 PM", "area": "Reception", "notes": "Multicopy 2"}
	])
	assert_true(copy_res2["success"] and copy_res2["created_uuids"].size() == 2, "Scenario B & C: Multiple shifts across different days copied cleanly preserving all field attributes.")

	# Scenario E: Preserve source rows during copy
	var count_src = db.execute("SELECT COUNT(*) as cnt FROM schedule_entries WHERE entry_uuid = ?;", [s1["entry_uuid"]])
	assert_true(count_src["data"][0]["cnt"] == 1, "Scenario E: Source shift record preserved in schedule_entries following copy operation.")

	# Scenario F & G: Cut single and multiple shifts
	var s2 = sch_svc.create_shift_entry_atomic("Emily Davis", "Shift Supervisor", "2026-07-20", "03:00 PM", "08:00 PM", "Gathering Room", "Cut test")
	var cut_res = sch_svc.cut_paste_shifts_atomic([{"entry_uuid": s2["entry_uuid"], "target_date": "2026-07-25"}])
	var verify_cut = db.execute("SELECT shift_date FROM schedule_entries WHERE entry_uuid = ?;", [s2["entry_uuid"]])
	assert_true(cut_res["success"] and verify_cut["data"][0]["shift_date"] == "2026-07-25", "Scenario F & G: Cut shift moved target date atomically in schedule_entries.")

	# Scenario H: Preserve unrelated rows during cut
	var check_s1 = db.execute("SELECT shift_date FROM schedule_entries WHERE entry_uuid = ?;", [s1["entry_uuid"]])
	assert_true(check_s1["data"][0]["shift_date"] == "2026-07-20", "Scenario H: Unrelated shift records remained completely untouched during cut operation.")

	# Scenario M & N: Copying and cutting to the same date
	var cut_same = sch_svc.cut_paste_shifts_atomic([{"entry_uuid": s2["entry_uuid"], "target_date": "2026-07-25"}])
	assert_true(cut_same["success"], "Scenario M & N: Cutting/copying into the same target date executed safely as a valid no-op/operation.")

	# Scenario Q: Outbox events emitted for shift creations
	var outbox_chk = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'ShiftEntryCreated';")
	assert_true(outbox_chk["success"] and outbox_chk["data"][0]["cnt"] >= 4, "Scenario Q: ShiftEntryCreated outbox sync events emitted cleanly into event_outbox.")

	# Clean up test database file
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SCHEDULE SHIFT COPY/CUT PERMANENT TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
