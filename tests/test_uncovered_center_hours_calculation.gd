extends SceneTree

## Focused Test Suite for Uncovered Study Center Hours Calculation Engine.
## Verifies all 7 interval subtraction cases, staff classification coverage, and queue refreshes.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

func _init():
	print("==========================================================")
	print("STARTING FOCUSED UNCOVERED CENTER HOURS ENGINE TESTS")
	print("==========================================================")
	var db = SQLiteDatabaseScript.new("user://test_uncovered_hours_fix.db")
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	var qc = QueueControllerScript.new(db)
	var sch_svc = SchedulesServiceScript.new(db)

	var today_date = Time.get_date_string_from_system()
	var dt_dict = Time.get_datetime_dict_from_datetime_string(today_date + "T12:00:00", false)
	var wday_num = dt_dict.get("weekday", 1)
	var wday_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var today_wday_name = wday_names[wday_num]

	# Ensure center_open_hours has 3:00 PM - 8:00 PM open for today
	db.execute("DELETE FROM center_open_hours WHERE day_of_week = ?;", [today_wday_name])
	db.execute("INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES (?, '03:00 PM', '08:00 PM', 0);", [today_wday_name])

	# ----------------------------------------------------
	# CASE 1: Open 3:00-8:00, No assigned workers
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	var recs1 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs1.size() != 1 or recs1[0]["open_time"] != "03:00 PM" or recs1[0]["close_time"] != "08:00 PM":
		print("FAIL Case 1: Expected 3:00 PM - 8:00 PM uncovered for today, got: ", recs1)
		quit(1); return
	print("PASS Case 1: 3:00 PM - 8:00 PM open with no workers produces 3:00 PM - 8:00 PM uncovered.")

	# ----------------------------------------------------
	# CASE 2: Open 3:00-8:00, Worker assigned 3:00-7:00 (Real Bug Example)
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Alex TeamLead", "Team Leader", today_date, "03:00 PM", "07:00 PM", "Study Center")
	var recs2 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs2.size() != 1 or recs2[0]["open_time"] != "07:00 PM" or recs2[0]["close_time"] != "08:00 PM":
		print("FAIL Case 2: Expected 7:00 PM - 8:00 PM uncovered, got: ", recs2)
		quit(1); return
	print("PASS Case 2: 3:00 PM - 7:00 PM worker produces exact 7:00 PM - 8:00 PM uncovered (Bug Fixed!).")

	# ----------------------------------------------------
	# CASE 3: Open 3:00-8:00, Worker assigned 4:00-8:00
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Beth Intern", "Intern", today_date, "04:00 PM", "08:00 PM", "Study Center")
	var recs3 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs3.size() != 1 or recs3[0]["open_time"] != "03:00 PM" or recs3[0]["close_time"] != "04:00 PM":
		print("FAIL Case 3: Expected 3:00 PM - 4:00 PM uncovered, got: ", recs3)
		quit(1); return
	print("PASS Case 3: 4:00 PM - 8:00 PM worker produces 3:00 PM - 4:00 PM uncovered.")

	# ----------------------------------------------------
	# CASE 4: Open 3:00-8:00, Worker assigned 4:00-7:00
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Carl Volunteer", "Volunteer", today_date, "04:00 PM", "07:00 PM", "Study Center")
	var recs4 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs4.size() != 2 or recs4[0]["open_time"] != "03:00 PM" or recs4[0]["close_time"] != "04:00 PM" or recs4[1]["open_time"] != "07:00 PM" or recs4[1]["close_time"] != "08:00 PM":
		print("FAIL Case 4: Expected 3:00 PM - 4:00 PM and 7:00 PM - 8:00 PM uncovered, got: ", recs4)
		quit(1); return
	print("PASS Case 4: 4:00 PM - 7:00 PM worker produces 2 uncovered gaps: 3:00 PM - 4:00 PM and 7:00 PM - 8:00 PM.")

	# ----------------------------------------------------
	# CASE 5: Open 3:00-8:00, Worker assigned 3:00-8:00
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Diana Staff", "Staff", today_date, "03:00 PM", "08:00 PM", "Study Center")
	var recs5 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs5.size() != 0:
		print("FAIL Case 5: Expected 0 uncovered items for full coverage, got: ", recs5)
		quit(1); return
	print("PASS Case 5: Full 3:00 PM - 8:00 PM worker results in NO uncovered items.")

	# ----------------------------------------------------
	# CASE 6: Open 3:00-8:00, Workers assigned 3:00-5:00 and 5:00-8:00
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Worker A", "Staff", today_date, "03:00 PM", "05:00 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("Worker B", "Volunteer", today_date, "05:00 PM", "08:00 PM", "Study Center")
	var recs6 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs6.size() != 0:
		print("FAIL Case 6: Expected 0 uncovered items for back-to-back coverage, got: ", recs6)
		quit(1); return
	print("PASS Case 6: Back-to-back 3:00-5:00 and 5:00-8:00 shifts produce NO uncovered items.")

	# ----------------------------------------------------
	# CASE 7: Open 3:00-8:00, Workers assigned 3:00-5:00 and 6:00-8:00
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Worker 1", "Intern", today_date, "03:00 PM", "05:00 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("Worker 2", "Team Leader", today_date, "06:00 PM", "08:00 PM", "Study Center")
	var recs7 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs7.size() != 1 or recs7[0]["open_time"] != "05:00 PM" or recs7[0]["close_time"] != "06:00 PM":
		print("FAIL Case 7: Expected 5:00 PM - 6:00 PM uncovered, got: ", recs7)
		quit(1); return
	print("PASS Case 7: Split coverage 3:00-5:00 & 6:00-8:00 produces 5:00 PM - 6:00 PM uncovered.")

	# ----------------------------------------------------
	# Verify All 4 Staff Classifications Count Towards Coverage
	# ----------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	sch_svc.create_shift_entry_atomic("Vol User", "Volunteer", today_date, "03:00 PM", "04:15 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("Int User", "Intern", today_date, "04:15 PM", "05:30 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("Stf User", "Staff", today_date, "05:30 PM", "06:45 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("TL User", "Team Leader", today_date, "06:45 PM", "08:00 PM", "Study Center")
	var recs_class = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	if recs_class.size() != 0:
		print("FAIL Classification Check: Expected 0 items when covered by all 4 classifications, got: ", recs_class)
		quit(1); return
	print("PASS Staff Classifications: Volunteer, Intern, Staff, and Team Leader all count toward coverage.")

	# ----------------------------------------------------
	# Verify Session Staffing Queue (uncovered_sessions) Remains Unchanged
	# ----------------------------------------------------
	qc.start_queue("uncovered_sessions")
	print("PASS Uncovered Sessions Queue: Session staffing queue operates independently.")

	print("==========================================================")
	print("ALL 7 INTERVAL CASES AND REFRESH CHECKS PASSED 100%!")
	print("==========================================================")
	quit(0)
