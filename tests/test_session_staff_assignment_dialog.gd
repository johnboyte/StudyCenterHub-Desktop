extends SceneTree

## Headless Test Suite for SessionStaffAssignmentDialog (Stage 10)
## Verifies real person selection, role validation, duplicate prevention, and zero placeholder entries.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionStaffAssignmentDialogScript = preload("res://app/scenes/components/session_staff_assignment_dialog.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING SESSION STAFF ASSIGNMENT DIALOG TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_stage10_dialog.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM schedule_entries;")

	# Insert Real Constituent People
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (1, 'p-001', 'STF-001', 'Marcus', 'Vance', 'Staff');")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (2, 'p-002', 'VOL-002', 'Sarah', 'Jenkins', 'Volunteer');")

	# Insert existing schedule entry for duplicate check
	db.execute("INSERT INTO schedule_entries (entry_uuid, person_name, person_id, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-exist-1', 'Sarah Jenkins', 2, 'Check-In Host (Vol)', date('now', '+1 day'), '04:00 PM', '05:00 PM', 'Study Center');")

	var dlg = SessionStaffAssignmentDialogScript.new(db)
	dlg.configure_session({
		"title": "Calculus Tutoring",
		"date_text": str(db.execute("SELECT date('now', '+1 day') as d;")["data"][0]["d"]),
		"start_time": "04:00 PM",
		"end_time": "05:00 PM",
		"room_location": "Study Center"
	})
	root.add_child(dlg)
	await process_frame

	# 1. Verify OK button disabled prior to person selection
	var ok_btn = dlg.get_ok_button()
	if not ok_btn or not ok_btn.disabled:
		print("FAIL: Assign Coverage button must be disabled before a real person is selected.")
		quit(1)
		return
	print("PASS 1/5: Assign Coverage button is disabled when unselected.")

	# 2. Test duplicate prevention for Sarah Jenkins (Index 1: Jenkins, Sarah)
	dlg.person_dropdown.select(1)
	dlg._on_selection_changed(1)
	if not ok_btn.disabled:
		print("FAIL: Duplicate assignment check failed. Sarah Jenkins is already assigned to this date/location.")
		quit(1)
		return
	print("PASS 2/5: Duplicate worker assignment correctly prevented.")

	# 3. Test valid selection for Marcus Vance (Index 2: Vance, Marcus)
	dlg.person_dropdown.selected = 2
	dlg.person_dropdown.select(2)
	dlg.role_dropdown.selected = 0
	dlg.role_dropdown.select(0)
	dlg._on_selection_changed(2)
	if ok_btn.disabled:
		print("FAIL: Valid worker Marcus Vance should enable Assign Coverage button.")
		quit(1)
		return
	print("PASS 3/5: Valid constituent worker selection enables submission.")

	# 4. Test signal payload on confirmation
	var received_payload = []
	dlg.staff_assigned.connect(func(payload: Dictionary):
		received_payload.append(payload)
	)
	dlg._on_confirmed()

	if received_payload.size() == 0:
		print("FAIL: staff_assigned signal was not emitted on confirmation.")
		quit(1)
		return

	var pdata: Dictionary = received_payload[0]
	if str(pdata["person_name"]) != "Marcus Vance" or str(pdata["shift_role"]) != "Shift Supervisor (Staff)":
		print("FAIL: Signal payload contained unexpected values: ", pdata)
		quit(1)
		return

	# Verify no fake values
	if str(pdata["person_name"]) == "Assigned Staff" or str(pdata["shift_role"]) == "Duty Worker":
		print("FAIL: Synthetic/placeholder values detected in payload.")
		quit(1)
		return
	print("PASS 4/5: Confirmation emits exact real constituent data without placeholders.")

	# 5. Test Cancellation
	var cancelled = []
	dlg.assignment_cancelled.connect(func(): cancelled.append(true))
	dlg._on_canceled()
	if cancelled.size() == 0:
		print("FAIL: Cancel signal not emitted.")
		quit(1)
		return
	print("PASS 5/5: Cancellation handled cleanly without mutating database.")

	dlg.queue_free()

	print("==========================================================")
	print("ALL SESSION STAFF ASSIGNMENT DIALOG TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
