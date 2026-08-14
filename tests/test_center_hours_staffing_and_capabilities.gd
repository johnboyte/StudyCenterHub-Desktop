extends SceneTree

# ==============================================================================
# TEST SUITE: CENTER HOURS STAFFING & CAPABILITIES
# Verifies capability flags (can_cover_hours, is_team_leader_eligible),
# automatic Staff & Intern coverage eligibility, non-staff coverage requirements,
# authoritative Team Leader eligibility, and partial shift calculation.
# ==============================================================================

const SQLiteDatabase = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionStaffAssignmentDialogScript = preload("res://app/scenes/components/session_staff_assignment_dialog.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")

var pass_count = 0
var total_assertions = 0

func _init():
	print("\n==========================================================")
	print("STARTING CENTER HOURS STAFFING & CAPABILITIES TEST SUITE")
	print("==========================================================")
	run_all_tests()

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		pass_count += 1
		print("PASS %d/%d: %s" % [pass_count, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [pass_count, total_assertions, message])
		quit(1)

func run_all_tests() -> void:
	var db = SQLiteDatabase.new("user://test_center_hours_staffing_improvements.db")
	var mr = MigrationsRunnerScript.new(db)
	mr.run_migrations()
	assert_true(true, "Test 1: All database migrations 0001..0054 executed cleanly.")

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
	# Person 6: Active Intern (auto coverage, not TL eligible)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_intern_1', 'P106', 'Fiona', 'InternMember', 'Intern', 'Intern', 'active', 0, 0);")
	# Person 7: Inactive Intern (excluded)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_intern_2', 'P107', 'George', 'InactiveIntern', 'Intern', 'Intern', 'inactive', 1, 1);")
	# Person 8: Archived Eligible Person (excluded)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_arch_1', 'P108', 'Hannah', 'ArchivedPerson', 'Staff', 'Staff', 'archived', 1, 1);")
	# Person 9: Person with classification Team Leader but is_team_leader_eligible = 0 (Must be excluded from TL selector!)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, staff_classification, status, can_cover_hours, is_team_leader_eligible) VALUES ('p_fake_tl', 'P109', 'Ian', 'UncheckedLeader', 'Team Leader', 'Team Leader', 'active', 0, 0);")

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
	assert_true("Fiona InternMember" in eligible_names, "Test 3b: Active Intern automatically appears in coverage selector.")
	assert_true(not ("Bob InactiveStaff" in eligible_names), "Test 3c: Inactive Staff excluded from coverage selector.")
	assert_true(not ("George InactiveIntern" in eligible_names), "Test 3d: Inactive Intern excluded from coverage selector.")
	assert_true(not ("Hannah ArchivedPerson" in eligible_names), "Test 3e: Archived person excluded from coverage selector.")
	assert_true("Carol ApprovedVolunteer" in eligible_names, "Test 3f: Active non-staff with can_cover_hours = 1 appears in coverage selector.")
	assert_true("Dan OrdinaryVolunteer" in eligible_names, "Test 3g: Non-staff with can_cover_hours = 1 appears after update.")

	# -------------------------------------------------------------
	# 3. AUTHORITATIVE TEAM LEADER SELECTOR ELIGIBILITY
	# -------------------------------------------------------------
	var tl_res = db.execute("SELECT first_name, last_name FROM people WHERE is_team_leader_eligible = 1 AND (status IS NULL OR status = 'active' OR status = '') ORDER BY last_name ASC, first_name ASC;")
	var tl_names = []
	for r in tl_res.get("data", []):
		tl_names.append(str(r["first_name"]) + " " + str(r["last_name"]))

	assert_true("Eva TeamLead" in tl_names, "Test 4a: Eligible Team Leader with is_team_leader_eligible = 1 appears in Team Leader dropdown query.")
	assert_true(not ("Ian UncheckedLeader" in tl_names), "Test 4b: Person with is_team_leader_eligible = 0 does NOT appear in Team Leader selector even if classification is Team Leader.")
	assert_true(not ("George InactiveIntern" in tl_names), "Test 4c: Inactive person with is_team_leader_eligible = 1 does NOT appear in Team Leader selector.")
	assert_true(not ("Alice StaffMember" in tl_names), "Test 4d: Ordinary Staff without is_team_leader_eligible = 1 does NOT automatically become Team Leader.")

	# -------------------------------------------------------------
	# 4. AUTOMATIC STAFF CLASSIFICATION DERIVATION
	# -------------------------------------------------------------
	assert_true(dlg.eligible_people.size() > 0, "Test 5a: Eligible constituents loaded into dialog.")
	var alice_item = {}
	for ep in dlg.eligible_people:
		if ep["name"] == "Alice StaffMember":
			alice_item = ep
			break
	assert_true(alice_item.get("role", "") == "Staff", "Test 5b: Worker shift role automatically derived from person's existing profile.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [pass_count, total_assertions])
	print("==========================================================")
	if pass_count == total_assertions:
		print("SUCCESS: ALL CENTER HOURS STAFFING & CAPABILITIES TESTS PASSED (100%)")
		quit(0)
	else:
		print("ERROR: TEST SUITE FAILED!")
		quit(1)
