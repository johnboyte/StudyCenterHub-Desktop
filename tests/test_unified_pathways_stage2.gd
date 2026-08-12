extends SceneTree

## Focused Automated Test Suite for Stage 2 — Annual Pathways Management Page
## Verifies UI scene loading, context separation, participant enrollment, scoped requirements with exclusion, session linking/unlinking, and legacy fallback.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PathwaysViewPacked = preload("res://app/scenes/pathways_view.tscn")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING STAGE 2 UNIFIED PATHWAYS UI & SERVICE TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage2_unified_pathways.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert_true(mig_res["success"], "Migrations 0001-0037 executed cleanly.")

	# Seed Test People
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('usr_stage2_1', 'P-9001', 'Alice', 'Walker');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('usr_stage2_2', 'P-9002', 'Bob', 'Builder');")

	var p1_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_stage2_1' LIMIT 1;")
	var p2_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_stage2_2' LIMIT 1;")
	var person1_id = int(p1_res["data"][0]["id"])
	var person2_id = int(p2_res["data"][0]["id"])

	# Seed Test Session
	db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location) VALUES ('Fellows Kickoff Assembly', 'Assembly', '2026-09-01', '09:00', '10:30', 'Main Hall');")
	var s_res = db.execute("SELECT id FROM sessions WHERE title = 'Fellows Kickoff Assembly' LIMIT 1;")
	var session_id = int(s_res["data"][0]["id"])

	# -------------------------------------------------------------------
	# TEST 1: Modern Pathways View Instantiation & Scene Loading
	# -------------------------------------------------------------------
	print("\n[Test 1] Testing PathwaysView scene instantiation & readiness...")
	var view = PathwaysViewPacked.instantiate()
	assert_true(view != null, "PathwaysView scene instantiated successfully.")
	view.db = db
	root.add_child(view)
	view._ready()
	assert_true(view.title_label != null and view.title_label.text.contains("Pathways"), "PathwaysView node initialized title label cleanly.")
	print("PASS 1: PathwaysView scene instantiated cleanly.")

	# -------------------------------------------------------------------
	# TEST 2: Context Separation (Fellows vs LEAD) & Enrollment Independence
	# -------------------------------------------------------------------
	print("\n[Test 2] Testing Fellows vs LEAD context separation...")
	var svc = UnifiedPathwaysServiceScript.new(db)

	# Enroll Alice in Fellows 2026-2027 (Certification Track)
	var en1 = svc.enroll_person_pathway(person1_id, "fellows", "2026-2027", "certification", "year_1")
	assert_true(en1["success"], "Enrolled Alice in Fellows 2026-2027.")

	# Enroll Alice in LEAD 2026-2027 (Standard Track)
	var en2 = svc.enroll_person_pathway(person1_id, "lead", "2026-2027", "standard", "year_2")
	assert_true(en2["success"], "Enrolled Alice in LEAD 2026-2027.")

	var fel_prog = svc.get_annual_program("fellows", "2026-2027")
	var lead_prog = svc.get_annual_program("lead", "2026-2027")
	assert_true(int(fel_prog["program_year_id"]) != int(lead_prog["program_year_id"]), "Fellows and LEAD annual program IDs are distinct.")

	var alice_enrollments = svc.get_person_enrollments(person1_id)
	assert_true(alice_enrollments.size() == 2, "Alice has 2 distinct enrollments.")
	print("PASS 2: Context separation and independent multi-pathway enrollment verified.")

	# -------------------------------------------------------------------
	# TEST 3: Duplicate Annual Program Participation Prevention
	# -------------------------------------------------------------------
	print("\n[Test 3] Testing duplicate enrollment handling...")
	var en1_dup = svc.enroll_person_pathway(person1_id, "fellows", "2026-2027", "certification", "year_1")
	assert_true(en1_dup["success"], "Re-enrolling existing participant returns success cleanly.")

	var fel_parts = svc.get_program_participants(int(fel_prog["program_year_id"]))
	assert_true(fel_parts.size() == 1, "Alice is listed exactly once in Fellows roster (no duplicate rows).")
	print("PASS 3: Duplicate enrollment prevention verified.")

	# -------------------------------------------------------------------
	# TEST 4: Requirement Scope Filtering & Exclusion Review Dialog
	# -------------------------------------------------------------------
	print("\n[Test 4] Testing requirement scope filtering and exclusion review...")
	# Enroll Bob in Fellows 2026-2027 (Standard Track)
	svc.enroll_person_pathway(person2_id, "fellows", "2026-2027", "standard", "year_1")

	# Create a Certification-only requirement for Fellows 2026-2027
	var req_res = svc.create_program_requirement(int(fel_prog["program_year_id"]), "Certification Capstone", "Submit proposal", "writing", "required", "certification", "all")
	var req_id = int(req_res["requirement_id"])

	# Preview eligible recipients (should include Alice [Certification] but NOT Bob [Standard])
	var eligible = svc.get_eligible_requirement_recipients(int(fel_prog["program_year_id"]), "certification", "all")
	assert_true(eligible.size() == 1 and int(eligible[0]["person_id"]) == person1_id, "Requirement preview correctly filtered to Certification track participants.")

	# Assign requirement excluding Alice
	var assign_res = svc.assign_group_requirement(req_id, [person1_id])
	assert_true(assign_res["success"] and assign_res["assigned_count"] == 0, "Excluding Alice resulted in 0 assignments (as intended).")
	print("PASS 4: Requirement scope preview and exclusion review verified.")

	# -------------------------------------------------------------------
	# TEST 5: Session Linking and Safe Unlinking
	# -------------------------------------------------------------------
	print("\n[Test 5] Testing session linking and safe unlinking...")
	var link_res = svc.link_session_to_program(int(fel_prog["program_year_id"]), session_id, "required")
	assert_true(link_res["success"], "Linked session to Fellows program.")

	var linked_sessions = svc.get_program_linked_sessions(int(fel_prog["program_year_id"]))
	assert_true(linked_sessions.size() == 1 and int(linked_sessions[0]["session_id"]) == session_id, "Linked session appears in program list.")

	# Unlink session
	var unlink_res = svc.unlink_session_from_program(int(fel_prog["program_year_id"]), session_id)
	assert_true(unlink_res["success"], "Unlinked session from program.")

	var linked_after = svc.get_program_linked_sessions(int(fel_prog["program_year_id"]))
	assert_true(linked_after.size() == 0, "Linked session removed from program list.")

	# Verify underlying Session record was NOT deleted
	var q_sess = db.execute("SELECT id, title FROM sessions WHERE id = ? LIMIT 1;", [session_id])
	assert_true(q_sess["success"] and q_sess["data"].size() == 1, "Underlying Session record preserved intact after unlinking.")
	print("PASS 5: Session linking and non-destructive unlinking verified.")

	# -------------------------------------------------------------------
	# TEST 6: Temporary Legacy Fallback Reachability
	# -------------------------------------------------------------------
	print("\n[Test 6] Testing legacy fallback toggle reachability...")
	assert_true(view.legacy_container.visible == false, "Legacy fallback container hidden by default.")
	view._on_toggle_legacy_fallback()
	assert_true(view.legacy_container.visible == true, "Legacy fallback container visible after toggle.")
	view._on_toggle_legacy_fallback()
	assert_true(view.legacy_container.visible == false, "Legacy fallback container hidden again after second toggle.")
	print("PASS 6: Legacy fallback toggle reachability verified.")

	print("\n==========================================================")
	print("ALL STAGE 2 UNIFIED PATHWAYS TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ PASS: ", message)
	else:
		print("  ❌ FAIL: ", message)
		push_error("Assertion failed: " + message)
		quit(1)
