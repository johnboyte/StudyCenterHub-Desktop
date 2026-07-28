extends SceneTree

## Headless Automated Test Suite for Story VOL-SPR1-001
## Volunteers & Shift Roster Management Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING VOL-SPR1-001 VOLUNTEERS & SHIFT ROSTER TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_vol_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0007 executed successfully.")

	# Seed person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, phone) VALUES ('usr_vol_test', 'P-20260720-4444', 'Marcus', 'Aurelius', 'active', '555-0199');")

	# Instantiate VolunteersView
	var vol_scene = load("res://app/scenes/volunteers_view.tscn")
	assert_true(vol_scene != null, "VolunteersView scene loaded successfully.")

	var vol_view = vol_scene.instantiate()
	vol_view.db = db
	root.add_child(vol_view)

	# Verify volunteer list
	assert_true(vol_view.volunteer_list.size() >= 1, "Volunteer list populated from database.")

	# Assign Shift
	vol_view._on_assign_shift_pressed()

	var shift_res = db.execute("SELECT COUNT(*) as cnt FROM volunteer_shifts WHERE shift_role = 'Lead Tutor';")
	assert_true(shift_res["success"] and shift_res["data"][0]["cnt"] == 1, "Volunteer shift record persisted to SQLite volunteer_shifts table.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'VolunteerShiftAssigned';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "VolunteerShiftAssigned transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL VOL-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
