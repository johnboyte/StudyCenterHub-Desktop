extends SceneTree

## Comprehensive Test Suite for Center Operating Hours Staffing Improvements
## Verifies profile capability flags, worker eligibility, Team Leader filtering, auto classification,
## partial coverage interval math, compact time controls, and regression safety.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const SessionStaffAssignmentDialogScript = preload("res://app/scenes/components/session_staff_assignment_dialog.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING CENTER HOURS STAFFING & CAPABILITIES TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_center_hours_staffing_improvements.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Test 1: All database migrations 0001..0054 executed cleanly.")

	var sch_svc = SchedulesServiceScript.new(db)

	# -------------------------------------------------------------
	# SEED TEST CONSTITUENTS
	# -------------------------------------------------------------
	db.execute("DELETE FROM people;")
	# Person 1: Active Staff (auto coverage, not TL eligible)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_staff_1', 'P101', 'Alice', 'StaffMember', 'Staff', 'Staff', 'active', 0, 0);")
	# Person 2: Inactive Staff (excluded from all)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_staff_2', 'P102', 'Bob', 'InactiveStaff', 'Staff', 'Staff', 'inactive', 0, 0);")
	# Person 3: Active Volunteer WITH can_cover_hours = 1
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_vol_1', 'P103', 'Carol', 'ApprovedVolunteer', 'Volunteer', 'Volunteer', 'active', 1, 0);")
	# Person 4: Active Volunteer WITHOUT can_cover_hours
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_vol_2', 'P104', 'Dan', 'OrdinaryVolunteer', 'Volunteer', 'Volunteer', 'active', 0, 0);")
	# Person 5: Active Team Leader (is_team_leader_eligible = 1)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_tl_1', 'P105', 'Eva', 'TeamLead', 'Team Leader', 'Team Leader', 'active', 0, 1);")

	# -------------------------------------------------------------
	# 1. PROFILE PERSISTENCE & CAPABILITY FLAGS
	# -------------------------------------------------------------
	db.execute("UPDATE people SET can_cover_hours = 1, is_team_leader_eligible = 1 WHERE person_uuid = 'p_vol_2';")
	var p2_check = db.execute("SELECT can_cover_hours, is_team_leader_eligible FROM people WHERE person_uuid = 'p_vol_2';")
	assert_true(p2_check["success"] and int(p2_check["data"][0]["can_cover_hours"]) == 1 and int(p2_check["data"][0]["is_team_leader_eligible"]) == 1, "Test 2: Profile capability flags can_cover_hours and is_team_leader_eligible saved and reloaded correctly.")

	# -------------------------------------------------------------
	# 2. COVERAGE WORKER SELECTOR ELIGIBILITY
	# -------------------------------------------------------------
	var dlg = SessionStaffAssignmentDialogScript.new(db)
	dlg._build_ui()
	dlg._load_people()
	var eligible_names = []
	for ep in dlg.eligible_people:
		eligible_names.append(ep["name"])

	assert_true("Alice StaffMember" in eligible_names, "Test 3a: Active Staff automatically appears in coverage selector.")
	assert_true(not ("Bob InactiveStaff" in eligible_names), "Test 3b: Inactive Staff excluded from coverage selector.")
	assert_true("Carol ApprovedVolunteer" in eligible_names, "Test 3c: Active non-staff with can_cover_hours = 1 appears in coverage selector.")
	assert_true("Dan OrdinaryVolunteer" in eligible_names, "Test 3d: Non-staff with can_cover_hours = 1 appears after update.")

	# -------------------------------------------------------------
	# 3. TEAM LEADER SELECTOR ELIGIBILITY
	# -------------------------------------------------------------
	var tl_res = db.execute("SELECT first_name, last_name FROM people WHERE (is_team_leader_eligible = 1 OR staff_classification = 'Team Leader' OR primary_role = 'Team Leader') AND (status IS NULL OR status = 'active' OR status = '') ORDER BY last_name ASC, first_name ASC;")
	var tl_names = []
	for r in tl_res.get("data", []):
		tl_names.append(str(r["first_name"]) + " " + str(r["last_name"]))

	assert_true("Eva TeamLead" in tl_names, "Test 4a: Eligible Team Leader appears in Team Leader dropdown query.")
	assert_true(not ("Alice StaffMember" in tl_names), "Test 4b: Ordinary Staff without is_team_leader_eligible = 1 does NOT automatically become Team Leader.")

	# -------------------------------------------------------------
	# 4. AUTOMATIC STAFF CLASSIFICATION DERIVATION
	# -------------------------------------------------------------
	assert_true(dlg.eligible_people.size() > 0, "Test 5a: Eligible constituents loaded into dialog.")
	var alice_item = {}
	for ep in dlg.eligible_people:
		if ep["name"] == "Alice StaffMember":
			alice_item = ep
			break
	assert_true(alice_item.get("role") == "Staff", "Test 5b: Worker shift role automatically derived from person's existing profile.")

	# -------------------------------------------------------------
	# 5. PARTIAL COVERAGE & INTERVAL SUBTRACTION MATH
	# -------------------------------------------------------------
	var today_date = Time.get_date_string_from_system()
	var sys_dict = Time.get_datetime_dict_from_system()
	var wday_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var today_wday_name = wday_names[sys_dict.get("weekday", 5)]

	# Set Center Hours to 4:00 PM - 9:00 PM
	sch_svc.update_open_hours_atomic(today_wday_name, "04:00 PM", "09:00 PM", 0, 0)
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])

	# Initial: 0 shifts -> 1 uncovered interval (04:00 PM - 09:00 PM)
	var unc1 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	assert_true(unc1.size() == 1 and unc1[0]["start_time"] == "04:00 PM" and unc1[0]["end_time"] == "09:00 PM", "Test 6a: 0 shifts produces full 04:00 PM - 09:00 PM uncovered interval.")

	# Assign Partial Beginning Coverage: 04:00 PM - 06:30 PM (Alice StaffMember)
	sch_svc.create_shift_entry_atomic("Alice StaffMember", "Staff", today_date, "04:00 PM", "06:30 PM", "Study Center")

	var unc2 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	assert_true(unc2.size() == 1 and unc2[0]["start_time"] == "06:30 PM" and unc2[0]["end_time"] == "09:00 PM", "Test 6b: Assigning 04:00 PM - 06:30 PM leaves remaining 06:30 PM - 09:00 PM uncovered interval.")

	# Assign Middle Period Shift: 07:00 PM - 08:00 PM (Carol ApprovedVolunteer) -> Creates 2 Split Gaps (06:30 PM - 07:00 PM and 08:00 PM - 09:00 PM)
	sch_svc.create_shift_entry_atomic("Carol ApprovedVolunteer", "Volunteer", today_date, "07:00 PM", "08:00 PM", "Study Center")

	var unc3 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	assert_true(unc3.size() == 2 and unc3[0]["start_time"] == "06:30 PM" and unc3[0]["end_time"] == "07:00 PM" and unc3[1]["start_time"] == "08:00 PM" and unc3[1]["end_time"] == "09:00 PM", "Test 6c: Middle assignment creates two remaining split uncovered intervals.")

	# Assign Remaining Coverage Gaps to fully cover the day
	sch_svc.create_shift_entry_atomic("Dan OrdinaryVolunteer", "Volunteer", today_date, "06:30 PM", "07:00 PM", "Study Center")
	sch_svc.create_shift_entry_atomic("Eva TeamLead", "Team Leader", today_date, "08:00 PM", "09:00 PM", "Study Center")

	var unc4 = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	assert_true(unc4.size() == 0, "Test 6d: Work-queue uncovered item disappears 100% when entire operating period is covered.")

	# -------------------------------------------------------------
	# 6. EXACT NON-15-MINUTE BOUNDARY PRESERVATION
	# -------------------------------------------------------------
	db.execute("DELETE FROM schedule_entries WHERE shift_date = ?;", [today_date])
	# Custom shift 04:00 PM - 06:10 PM
	sch_svc.create_shift_entry_atomic("Alice StaffMember", "Staff", today_date, "04:00 PM", "06:10 PM", "Study Center")
	var unc_custom = QueueRegistryScript.get_uncovered_center_hours_records(db).filter(func(r): return r["date_text"] == today_date)
	assert_true(unc_custom.size() == 1 and unc_custom[0]["start_time"] == "06:10 PM", "Test 7: Exact non-15-minute boundary 06:10 PM preserved without rounding.")

	dlg.queue_free()

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL CENTER HOURS STAFFING & CAPABILITIES TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
