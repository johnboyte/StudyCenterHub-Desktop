extends SceneTree

## Headless Test Suite for Stage 3 — Participant Profile Integration
## Verifies Profile Pathways Summary, Independent Fellows & LEAD Cards, Track/Standing Changes, Requirement Completion Toggling, Catch-Up Assignments, Mentor Assignment, Attendance Summary, and Audit History.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING STAGE 3 UNIFIED PATHWAYS PROFILE TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage3_unified_pathways.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert_true(mig_res["success"], "Migrations 0001-0037 executed cleanly.")

	var svc = UnifiedPathwaysServiceScript.new(db)

	# Seed Test People
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('usr_prof_1', 'P-3001', 'David', 'Miller');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('usr_mentor_1', 'M-3002', 'Sarah', 'Mentor');")

	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_prof_1' LIMIT 1;")
	var m_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_mentor_1' LIMIT 1;")
	var person_id = int(p_res["data"][0]["id"])
	var mentor_id = int(m_res["data"][0]["id"])

	# Seed Test Session
	db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location) VALUES ('Fellows Bible Study', 'Study', '2026-07-01', '18:00', '19:30', 'Room 101');")
	var s_res = db.execute("SELECT id FROM sessions WHERE title = 'Fellows Bible Study' LIMIT 1;")
	var session_id = int(s_res["data"][0]["id"])

	# -------------------------------------------------------------------
	# TEST 1: Unenrolled Profile Summary State
	# -------------------------------------------------------------------
	print("\n[Test 1] Testing unenrolled profile summary state...")
	var initial_summary = svc.get_profile_pathway_summary(person_id)
	assert_true(initial_summary.has("fellows") and initial_summary["fellows"]["enrolled"] == false, "Fellows card reports unenrolled state.")
	assert_true(initial_summary.has("lead") and initial_summary["lead"]["enrolled"] == false, "LEAD card reports unenrolled state.")
	print("PASS 1: Unenrolled profile summary verified.")

	# -------------------------------------------------------------------
	# TEST 2: Independent Fellows & LEAD Profile Enrollments
	# -------------------------------------------------------------------
	print("\n[Test 2] Testing independent Fellows & LEAD profile enrollments...")
	var en_fel = svc.enroll_person_pathway(person_id, "fellows", "2026-2027", "certification", "year_1", mentor_id, "Fellows notes")
	assert_true(en_fel["success"], "Enrolled David in Fellows 2026-2027.")

	var en_lead = svc.enroll_person_pathway(person_id, "lead", "2026-2027", "standard", "year_2", null, "LEAD notes")
	assert_true(en_lead["success"], "Enrolled David in LEAD 2026-2027.")

	var sum2 = svc.get_profile_pathway_summary(person_id)
	assert_true(sum2["fellows"]["enrolled"] == true, "Fellows card reports enrolled state.")
	assert_true(sum2["lead"]["enrolled"] == true, "LEAD card reports enrolled state.")
	assert_true(sum2["fellows"]["current_track"] == "certification", "Fellows track is certification.")
	assert_true(sum2["lead"]["current_track"] == "standard", "LEAD track is standard.")
	print("PASS 2: Independent profile enrollments verified.")

	# -------------------------------------------------------------------
	# TEST 3: Track & Standing Changes with Audit Trail
	# -------------------------------------------------------------------
	print("\n[Test 3] Testing track & standing changes from profile...")
	var fel_ppid = int(sum2["fellows"]["person_pathway_id"])
	var tr_res = svc.change_person_track(fel_ppid, "standard", "Track adjustment from profile", "", "Staff User")
	assert_true(tr_res["success"], "Changed Fellows track to standard.")

	var st_res = svc.change_person_standing(fel_ppid, "year_2", "Year advancement from profile", "", "Staff User")
	assert_true(st_res["success"], "Changed Fellows standing to year_2.")

	var sum3 = svc.get_profile_pathway_summary(person_id)
	assert_true(sum3["fellows"]["current_track"] == "standard", "Fellows track updated to standard.")
	assert_true(sum3["fellows"]["current_standing"] == "year_2", "Fellows standing updated to year_2.")
	assert_true(sum3["fellows"]["history"].size() >= 2, "Audit trail recorded track and standing changes.")
	print("PASS 3: Track & standing changes from profile verified.")

	# -------------------------------------------------------------------
	# TEST 4: Catch-Up Requirement Assignment & Completion Toggling
	# -------------------------------------------------------------------
	print("\n[Test 4] Testing catch-up requirement assignment & completion toggling...")
	var ppy_id = int(sum3["fellows"]["person_pathway_program_year_id"])
	var cu_res = svc.create_catch_up_requirement(ppy_id, "Catch-Up Essay", "Submit 2-page essay", "2026-10-01", "Staff User")
	assert_true(cu_res["success"], "Created catch-up requirement for David.")

	var req_id = int(cu_res["requirement_id"])
	var sum4_before = svc.get_profile_pathway_summary(person_id)
	assert_true(sum4_before["fellows"]["total_requirements"] == 1, "Requirement listed under Fellows card.")
	assert_true(sum4_before["fellows"]["completed_requirements"] == 0, "Requirement initially incomplete.")

	# Toggle Complete
	var comp_res = svc.mark_requirement_complete(req_id, "Passed evaluation", "Staff User")
	assert_true(comp_res["success"], "Marked requirement complete.")

	var sum4_after = svc.get_profile_pathway_summary(person_id)
	assert_true(sum4_after["fellows"]["completed_requirements"] == 1, "Completed requirement count updated to 1.")

	# Toggle Incomplete
	var incomp_res = svc.mark_requirement_incomplete(req_id, "Staff User")
	assert_true(incomp_res["success"], "Marked requirement incomplete again.")

	var sum4_reset = svc.get_profile_pathway_summary(person_id)
	assert_true(sum4_reset["fellows"]["completed_requirements"] == 0, "Completed requirement count reset to 0.")
	print("PASS 4: Catch-up assignment and completion toggling verified.")

	# -------------------------------------------------------------------
	# TEST 5: Mentor Assignment & Removal
	# -------------------------------------------------------------------
	print("\n[Test 5] Testing mentor assignment and removal...")
	var m_res2 = svc.assign_pathway_mentor(fel_ppid, mentor_id)
	assert_true(m_res2["success"], "Assigned mentor to Fellows pathway.")

	var sum5 = svc.get_profile_pathway_summary(person_id)
	assert_true(sum5["fellows"]["mentor_name"] == "Sarah Mentor", "Mentor name resolved correctly.")

	var rem_res = svc.remove_pathway_mentor(fel_ppid)
	assert_true(rem_res["success"], "Removed mentor from Fellows pathway.")

	var sum5_cleared = svc.get_profile_pathway_summary(person_id)
	assert_true(sum5_cleared["fellows"]["mentor_name"] == "", "Mentor name cleared successfully.")
	print("PASS 5: Mentor assignment and removal verified.")

	# -------------------------------------------------------------------
	# TEST 6: Linked Session Attendance Summary Calculation
	# -------------------------------------------------------------------
	print("\n[Test 6] Testing linked session attendance calculation...")
	var prog_year_id = int(db.execute("SELECT pathway_program_year_id FROM person_pathway_program_years WHERE id = ? LIMIT 1;", [ppy_id])["data"][0]["pathway_program_year_id"])
	svc.link_session_to_program(prog_year_id, session_id, "required")

	# Record attendance in person_sessions
	db.execute("INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (?, ?, 'attended');", [person_id, session_id])

	var sum6 = svc.get_profile_pathway_summary(person_id)
	var att_sum = sum6["fellows"]["session_summary"]
	assert_true(int(att_sum["total_linked"]) == 1, "1 linked session found.")
	assert_true(int(att_sum["attended"]) == 1, "1 session attended.")
	assert_true(str(att_sum["wording"]).contains("past applicable sessions attended"), "Attendance wording accurately describes past applicable sessions.")
	print("PASS 6: Linked session attendance calculation verified.")

	print("\n==========================================================")
	print("ALL STAGE 3 UNIFIED PATHWAYS PROFILE TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ PASS: ", message)
	else:
		print("  ❌ FAIL: ", message)
		push_error("Assertion failed: " + message)
		quit(1)
