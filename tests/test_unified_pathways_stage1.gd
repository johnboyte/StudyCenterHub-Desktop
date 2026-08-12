extends SceneTree

## Headless Test Suite for Stage 1 Unified Pathways Foundation & Service
## Verifies schema, concurrent enrollments, track/standing history, group requirement targeting, and outbox logging.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")
const LegacyPathwaysServiceScript = preload("res://src/domain/pathways/pathways_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING STAGE 1 UNIFIED PATHWAYS TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage1_unified_pathways.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)

	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert_true(mig_res["success"], "Migration suite 0001-0037 executed cleanly.")

	var pathways_svc = UnifiedPathwaysServiceScript.new(db)
	var legacy_svc = LegacyPathwaysServiceScript.new(db)

	# Seed Test Constituent 1 (Jordan Smith)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status) VALUES ('usr_jordan_stage1', 'P-8801', 'Jordan', 'Smith', 'active');")
	var p1_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_jordan_stage1' LIMIT 1;")
	var person1_id = int(p1_res["data"][0]["id"])

	# Seed Test Constituent 2 (Ashley Taylor)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status) VALUES ('usr_ashley_stage1', 'P-8802', 'Ashley', 'Taylor', 'active');")
	var p2_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_ashley_stage1' LIMIT 1;")
	var person2_id = int(p2_res["data"][0]["id"])

	# -------------------------------------------------------------------
	# TEST 1: Concurrent Independent Fellows and LEAD Enrollments
	# -------------------------------------------------------------------
	print("\n[Test 1] Testing concurrent independent Fellows and LEAD enrollments...")
	var en_fellows = pathways_svc.enroll_person_pathway(person1_id, "fellows", "2026-2027", "certification", "year_2", null, "Initial Fellows enrollment")
	assert_true(en_fellows["success"], "Enrolled Jordan in Fellows 2026-2027 successfully.")
	var fellows_pw_id = int(en_fellows["person_pathway_id"])

	var en_lead = pathways_svc.enroll_person_pathway(person1_id, "lead", "2026-2027", "standard", "year_1", null, "Initial LEAD enrollment")
	assert_true(en_lead["success"], "Enrolled Jordan in LEAD 2026-2027 successfully.")
	var lead_pw_id = int(en_lead["person_pathway_id"])

	var enrollments = pathways_svc.get_person_enrollments(person1_id)
	assert_true(enrollments.size() == 2, "Jordan holds 2 active independent enrollments (Fellows + LEAD).")

	var fellows_item = _find_enrollment(enrollments, "fellows")
	var lead_item = _find_enrollment(enrollments, "lead")

	assert_true(fellows_item != null and fellows_item.get("current_track") == "certification", "Fellows track is certification.")
	assert_true(fellows_item != null and fellows_item.get("current_standing") == "year_2", "Fellows standing is year_2.")
	assert_true(lead_item != null and lead_item.get("current_track") == "standard", "LEAD track is standard.")
	assert_true(lead_item != null and lead_item.get("current_standing") == "year_1", "LEAD standing is year_1.")
	print("PASS 1: Concurrent independent enrollments verified.")

	# -------------------------------------------------------------------
	# TEST 2: Annual Record Preservation Across Academic Years
	# -------------------------------------------------------------------
	print("\n[Test 2] Testing annual record preservation across academic years...")
	var en_fellows_y2 = pathways_svc.enroll_person_pathway(person1_id, "fellows", "2027-2028", "certification", "year_3", null, "Advanced to Year 3")
	if not en_fellows_y2["success"]:
		print("DEBUG EN FELLOWS Y2 ERROR: ", en_fellows_y2)
	assert_true(en_fellows_y2["success"], "Enrolled Jordan in Fellows 2027-2028.")

	var q_records = db.execute("SELECT ppy.standing_for_that_year, py.academic_year FROM person_pathway_program_years ppy JOIN pathway_program_years py ON py.id = ppy.pathway_program_year_id WHERE ppy.person_pathway_id = ? ORDER BY py.academic_year ASC;", [fellows_pw_id])
	assert_true(q_records["success"] and q_records["data"].size() == 2, "Jordan has 2 historical annual program records for Fellows.")
	assert_true(str(q_records["data"][0]["academic_year"]) == "2026-2027" and str(q_records["data"][0]["standing_for_that_year"]) == "year_2", "2026-2027 annual standing preserved as year_2.")
	assert_true(str(q_records["data"][1]["academic_year"]) == "2027-2028" and str(q_records["data"][1]["standing_for_that_year"]) == "year_3", "2027-2028 annual standing set to year_3.")
	print("PASS 2: Annual record history preservation verified.")

	# -------------------------------------------------------------------
	# TEST 3: Track & Standing Change Audit History & Outbox Events
	# -------------------------------------------------------------------
	print("\n[Test 3] Testing track & standing change audit history and outbox logging...")
	var tr_res = pathways_svc.change_person_track(fellows_pw_id, "standard", "Focusing on core studies", "Complete Foundations", "Director Jane")
	assert_true(tr_res["success"] and tr_res["changed"], "Changed Fellows track to standard.")

	var st_res = pathways_svc.change_person_standing(fellows_pw_id, "year_4", "Discretionary promotion", "", "Director Jane")
	assert_true(st_res["success"] and st_res["changed"], "Changed Fellows standing to year_4.")

	var q_th = db.execute("SELECT previous_track, new_track, changed_by, reason FROM person_pathway_track_history WHERE person_pathway_id = ?;", [fellows_pw_id])
	assert_true(q_th["success"] and q_th["data"].size() == 1, "Track history record written.")
	assert_true(str(q_th["data"][0]["previous_track"]) == "certification" and str(q_th["data"][0]["new_track"]) == "standard", "Track history recorded previous/new tracks correctly.")

	var q_sh = db.execute("SELECT previous_standing, new_standing, changed_by FROM person_pathway_standing_history WHERE person_pathway_id = ?;", [fellows_pw_id])
	assert_true(q_sh["success"] and q_sh["data"].size() == 1, "Standing history record written.")
	assert_true(str(q_sh["data"][0]["previous_standing"]) == "year_3" and str(q_sh["data"][0]["new_standing"]) == "year_4", "Standing history recorded previous/new standings correctly.")

	var q_outbox = db.execute("SELECT event_type FROM event_outbox WHERE aggregate_type = 'Pathways' ORDER BY id ASC;")
	assert_true(q_outbox["success"] and q_outbox["data"].size() >= 3, "Outbox events created for enrollment and track/standing changes.")
	print("PASS 3: Track & standing audit history and outbox logging verified.")

	# -------------------------------------------------------------------
	# TEST 4: Group Requirement Scope & Exclusion Logic
	# -------------------------------------------------------------------
	print("\n[Test 4] Testing group requirement scope and exclusion logic...")
	# Enroll Ashley in Fellows 2026-2027 under Certification track
	pathways_svc.enroll_person_pathway(person2_id, "fellows", "2026-2027", "certification", "year_2", null, "Ashley Certification")

	var prog = pathways_svc.get_annual_program("fellows", "2026-2027")
	var prog_year_id = int(prog["program_year_id"])

	# Create a Certification-only requirement for Fellows 2026-2027
	var req_res = pathways_svc.create_program_requirement(prog_year_id, "Submit Capstone Proposal", "Written proposal for cert track", "writing", "required", "certification", "all", "2027-04-01")
	assert_true(req_res["success"], "Created Certification-only requirement.")
	var req_id = int(req_res["requirement_id"])

	# Assign requirement to group, excluding person1_id
	var assign_res = pathways_svc.assign_group_requirement(req_id, [person1_id], "Staff User")
	assert_true(assign_res["success"], "Executed group requirement assignment.")

	# Ashley (Certification) should receive the assignment; Jordan (excluded) should NOT
	var q_ashley_reqs = db.execute("SELECT pr.title FROM person_pathway_requirements pr JOIN person_pathway_program_years ppy ON ppy.id = pr.person_pathway_program_year_id JOIN person_pathways pp ON pp.id = ppy.person_pathway_id WHERE pp.person_id = ?;", [person2_id])
	assert_true(q_ashley_reqs["success"] and q_ashley_reqs["data"].size() == 1, "Ashley received Certification requirement.")

	var q_jordan_reqs = db.execute("SELECT pr.title FROM person_pathway_requirements pr JOIN person_pathway_program_years ppy ON ppy.id = pr.person_pathway_program_year_id JOIN person_pathways pp ON pp.id = ppy.person_pathway_id WHERE pp.person_id = ? AND pr.title = 'Submit Capstone Proposal';", [person1_id])
	assert_true(q_jordan_reqs["success"] and q_jordan_reqs["data"].size() == 0, "Jordan (excluded) did NOT receive the requirement.")
	print("PASS 4: Group requirement scope and exclusion logic verified.")

	# -------------------------------------------------------------------
	# TEST 5: Legacy Pathways Compatibility Fallback
	# -------------------------------------------------------------------
	print("\n[Test 5] Testing legacy pathways compatibility fallback...")
	var leg_data = {
		"real_life_enrolled": 1,
		"fellows_enrolled": 1,
		"fellows_certificate": 0,
		"fellows_completions": "[]",
		"lead_enrolled": 0,
		"lead_certificate": 0,
		"lead_current_year": "Year 1"
	}
	var p1_dict = {"id": person1_id, "person_uuid": "usr_jordan_stage1", "human_id": "P-8801"}
	var leg_res = legacy_svc.save_legacy_pathway_atomic(p1_dict, leg_data)
	assert_true(leg_res["success"], "Legacy pathways save_legacy_pathway_atomic still functions 100%.")

	var leg_read = legacy_svc.get_person_legacy_pathway(person1_id)
	assert_true(int(leg_read["real_life_enrolled"]) == 1, "Legacy real_life_enrolled flag readable.")
	print("PASS 5: Legacy pathways compatibility fallback verified.")

	# -------------------------------------------------------------------
	# TEST 6: Migration 0037 Upgrade on Pre-Existing Database with Data
	# -------------------------------------------------------------------
	print("\n[Test 6] Testing Migration 0037 upgrade on pre-existing database with un-uuid'd rows...")
	var upgrade_db_path = ProjectSettings.globalize_path("user://test_stage1_migration_upgrade.db")
	if FileAccess.file_exists(upgrade_db_path):
		DirAccess.remove_absolute(upgrade_db_path)

	var up_db = SQLiteDatabaseScript.new(upgrade_db_path)
	# Manually setup schema 0001-0004 & seed schema_migrations 0001-0036 so runner runs 0037 as upgrade
	up_db.execute("CREATE TABLE schema_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, executed_at TEXT NOT NULL DEFAULT (datetime('now')));")
	for i in range(1, 37):
		var v_str = "%04d" % i
		up_db.execute("INSERT INTO schema_migrations (version, name) VALUES (?, ?);", [v_str, v_str + "_migration.sql"])

	up_db.execute("CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, human_id TEXT, first_name TEXT, last_name TEXT, status TEXT);")
	up_db.execute("CREATE TABLE pathways (id INTEGER PRIMARY KEY AUTOINCREMENT, pathway_key TEXT UNIQUE NOT NULL, name TEXT NOT NULL, description TEXT, total_milestones INTEGER NOT NULL DEFAULT 4, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT (datetime('now')));")
	up_db.execute("CREATE TABLE person_pathways (id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL, pathway_id INTEGER NOT NULL, current_stage TEXT NOT NULL DEFAULT 'In Progress', progress_percent INTEGER NOT NULL DEFAULT 25, status TEXT NOT NULL DEFAULT 'active', started_at TEXT NOT NULL DEFAULT (datetime('now')), completed_at TEXT);")
	up_db.execute("CREATE TABLE event_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, event_uuid TEXT UNIQUE NOT NULL, event_type TEXT NOT NULL, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, payload_json TEXT NOT NULL, device_uuid TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL DEFAULT (datetime('now')), processed_at TEXT);")
	up_db.execute("CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, session_type TEXT NOT NULL DEFAULT 'General Study', date_text TEXT NOT NULL, start_time TEXT NOT NULL, end_time TEXT NOT NULL, room_location TEXT, max_capacity INTEGER NOT NULL DEFAULT 30, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL DEFAULT (datetime('now')));")
	
	up_db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('usr_legacy_1', 'P-7701', 'Legacy', 'Person');")
	up_db.execute("INSERT INTO pathways (pathway_key, name) VALUES ('discipleship_track', 'Discipleship Track');")
	up_db.execute("INSERT INTO person_pathways (person_id, pathway_id, current_stage, progress_percent) VALUES (1, 1, 'Stage 1', 25);")

	# Run Migration Runner (applies 0037 and any missing migrations)
	var up_mig = MigrationsRunnerScript.new(up_db)
	var up_mig_res = up_mig.run_migrations()
	assert_true(up_mig_res["success"], "Migration 0037 executed cleanly on pre-existing database.")

	var q_legacy_pp = up_db.execute("SELECT id, uuid, updated_at FROM person_pathways WHERE id = 1 LIMIT 1;")
	assert_true(q_legacy_pp["success"] and q_legacy_pp["data"].size() > 0, "Legacy person_pathways record queried successfully.")
	assert_true(str(q_legacy_pp["data"][0]["uuid"]) == "pp_legacy_1", "Pre-existing row received backfilled UUID ('pp_legacy_1').")
	assert_true(q_legacy_pp["data"][0]["updated_at"] != null and str(q_legacy_pp["data"][0]["updated_at"]) != "", "Pre-existing row received backfilled updated_at timestamp.")
	print("PASS 6: Migration 0037 upgrade & backfill on pre-existing data verified.")

	print("\n==========================================================")
	print("ALL STAGE 1 UNIFIED PATHWAYS TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ PASS: ", message)
	else:
		print("  ❌ FAIL: ", message)
		push_error("Assertion failed: " + message)
		quit(1)

func _find_enrollment(list: Array, pathway_key: String) -> Variant:
	for item in list:
		if str(item.get("pathway_key")) == pathway_key:
			return item
	return null
