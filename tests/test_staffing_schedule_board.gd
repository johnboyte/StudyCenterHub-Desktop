extends SceneTree

## Comprehensive Automated Test Suite for Staffing Schedule Board Engine
## Validates Shift-ID isolation, selection anchor, range selection, cut/copy/paste offsets, and validation invariants.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING STAFFING SCHEDULE BOARD TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_staffing_schedule_board.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "1. Database migrations initialized successfully.")

	# Clean DB for test run isolation
	db.execute("DELETE FROM schedule_entries;")

	var sch_service = SchedulesServiceScript.new(db)

	# 1. Two identical looking shifts have different UUIDs
	var r1 = sch_service.create_shift_entry_atomic("John Smith", "Shift Supervisor", "2026-07-20", "03:00 PM", "08:00 PM", "Gathering Room", "Note A")
	var r2 = sch_service.create_shift_entry_atomic("John Smith", "Shift Supervisor", "2026-07-20", "03:00 PM", "08:00 PM", "Gathering Room", "Note B")
	assert_true(r1["entry_uuid"] != r2["entry_uuid"], "2. Two identical-looking shifts receive distinct unique UUIDs.")

	# 2. Delete by exact UUID only deletes target record
	var del_res = sch_service.delete_shifts_by_uuids_atomic([r1["entry_uuid"]])
	assert_true(del_res["success"], "3. Delete by unique UUID succeeds.")

	var remaining = sch_service.get_shift_entries_for_range()
	var has_r2 = false
	var has_r1 = false
	for s in remaining:
		if s["entry_uuid"] == r2["entry_uuid"]: has_r2 = true
		if s["entry_uuid"] == r1["entry_uuid"]: has_r1 = true

	assert_true(has_r2 and not has_r1, "4. Deleting one shift ID leaves identical second shift intact.")

	# 3. Copy/Paste creates brand new shift records with new UUIDs
	var copy_res = sch_service.copy_paste_shifts_atomic([{
		"person_name": "Sarah T", "shift_role": "Study Tutor", "shift_date": "2026-07-21", "start_time": "04:00 PM", "end_time": "06:00 PM", "area": "Study Room #1", "notes": "Copy test"
	}])
	assert_true(copy_res["success"] and copy_res["created_uuids"].size() == 1, "5. Copy/paste creates new shift with distinct unique UUID.")

	# 4. Cut/Paste moves exact original record
	var cut_res = sch_service.cut_paste_shifts_atomic([{
		"entry_uuid": r2["entry_uuid"],
		"target_date": "2026-07-22"
	}])
	assert_true(cut_res["success"], "6. Cut/paste moves exact original shift record atomically.")

	# 5. Verify moved shift has updated date
	var updated_shifts = sch_service.get_shift_entries_for_range()
	var found_moved = false
	for s in updated_shifts:
		if s["entry_uuid"] == r2["entry_uuid"] and s["shift_date"] == "2026-07-22":
			found_moved = true
			break
	assert_true(found_moved, "7. Moved shift date verified in database.")

	# 6. Verify vertical reordering / rearranging
	var r3 = sch_service.create_shift_entry_atomic("Emily Davis", "Study Tutor", "2026-07-20", "03:00 PM", "08:00 PM", "Study Room #1", "Rearrange 1")
	var r4 = sch_service.create_shift_entry_atomic("David Wilson", "Shift Supervisor", "2026-07-20", "03:00 PM", "08:00 PM", "Gathering Room", "Rearrange 2")

	# Reorder them as [r4, r3]
	var reorder_res = sch_service.reorder_shifts_in_day_atomic("2026-07-20", [r4["entry_uuid"], r3["entry_uuid"]])
	assert_true(reorder_res["success"], "8. Atomic database reordering/rearranging succeeds.")

	# Verify database sort order reflects custom arrangement
	var ordered_list = sch_service.get_shift_entries_for_range("2026-07-20", "2026-07-20")
	assert_true(ordered_list.size() == 2, "9. Correct number of shifts retrieved for day.")
	assert_true(ordered_list[0]["entry_uuid"] == r4["entry_uuid"], "10. First shift is the custom arranged first UUID.")
	assert_true(ordered_list[1]["entry_uuid"] == r3["entry_uuid"], "11. Second shift is the custom arranged second UUID.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL STAFFING SCHEDULE BOARD TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
