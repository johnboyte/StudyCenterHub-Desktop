extends SceneTree

## Automated Test Suite for Phase X.3: Production Safeguards, Institution Merge & Major Normalization

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CampusCommunityAdminServiceScript = preload("res://src/domain/campus_community/campus_community_admin_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING CAMPUS & COMMUNITY PHASE X.3 TEST SUITE")
	print("==========================================================")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_campus_community_phase_x3.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("❌ FAIL: Database migrations 0001-0041 failed.")
		quit(1)
		return
	print("  ✓ PASS: Database migrations 0001-0041 executed cleanly.")

	var svc = CampusCommunityAdminServiceScript.new(db)

	# Clean people, institutions, person_academic_history
	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM person_academic_history;")

	# Insert duplicate institution & constituents
	db.execute("INSERT INTO institutions (uuid, name, short_name, institution_type, display_order, is_active) VALUES ('inst_dupe_1', 'Anderson Univ.', 'AU-Dupe', 'college_university', 8, 1);")

	# Constituent with custom institution_other_name
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_other_name, relationship, academic_year, major, phone, email) 
		VALUES (201, 'uuid-201', 'M201', 'Test', 'User1', 'active', 'Participant', 'Anderson Univ.', 'Student', 'Freshman', 'CS', '555-0201', 't1@au.edu');""")

	# Constituent linked to master institution #1 (AU)
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_id, relationship, academic_year, major, phone, email) 
		VALUES (202, 'uuid-202', 'M202', 'Test', 'User2', 'active', 'Participant', 1, 'Student', 'Senior', 'CompSci', '555-0202', 't2@au.edu');""")

	# --- Test 1: Duplicate Institution Detection ---
	print("\n[Test 1] Testing Duplicate Institution Detection...")
	var dupes = svc.find_duplicate_institutions()
	if dupes.size() < 1:
		print("❌ FAIL: Expected at least 1 duplicate institution match for 'Anderson Univ.'.")
		quit(1)
		return
	print("  ✓ PASS: Duplicate institution detected accurately (Match: %s)." % dupes[0]["reason"])

	# --- Test 2: Institution Merge Preview & Warning ---
	print("\n[Test 2] Testing Institution Merge Preview & Warnings...")
	var prev = svc.get_institution_merge_preview("Anderson Univ.", 1)
	if not prev.get("success", false) or prev.get("affected_people_count", 0) != 1:
		print("❌ FAIL: Merge preview count mismatch: ", prev)
		quit(1)
		return
	print("  ✓ PASS: Institution merge preview accurately reported %d affected constituents." % prev["affected_people_count"])

	# --- Test 3: Transactional Institution Reassignment ---
	print("\n[Test 3] Testing Transactional Institution Reassignment...")
	var merge_res = svc.merge_institutions_atomic("Anderson Univ.", 1, "AdminUser", "Standardizing university name")
	if not merge_res.get("success", false):
		print("❌ FAIL: Atomic institution merge failed.")
		quit(1)
		return

	# Verify constituent 201 was updated to institution_id = 1
	var p201_q = db.execute("SELECT institution_id, institution_other_name FROM people WHERE id = 201;")
	if int(p201_q["data"][0]["institution_id"]) != 1 or str(p201_q["data"][0]["institution_other_name"]) != "":
		print("❌ FAIL: Constituent 201 not properly reassigned to master institution ID 1.")
		quit(1)
		return
	print("  ✓ PASS: Custom institution_other_name converted safely to master institution ID 1.")

	# --- Test 4: Major Alias Normalization & Autocomplete ---
	print("\n[Test 4] Testing Major Alias Normalization...")
	var norm_cs = svc.normalize_major_name("CS")
	var norm_compsci = svc.normalize_major_name("CompSci")

	if norm_cs != "Computer Science" or norm_compsci != "Computer Science":
		print("❌ FAIL: Alias normalization failed. CS -> '%s', CompSci -> '%s'" % [norm_cs, norm_compsci])
		quit(1)
		return
	print("  ✓ PASS: Major alias normalization verified ('CS' ➔ 'Computer Science').")

	# --- Test 5: Major Merging & Audit History ---
	print("\n[Test 5] Testing Major Merging & Audit Outbox Event...")
	var maj_res = svc.merge_majors_atomic("CompSci", "Computer Science", "AdminUser")
	if not maj_res.get("success", false):
		print("❌ FAIL: Atomic major merge failed.")
		quit(1)
		return

	var p202_q = db.execute("SELECT major FROM people WHERE id = 202;")
	if str(p202_q["data"][0]["major"]) != "Computer Science":
		print("❌ FAIL: Major for constituent 202 was not updated to 'Computer Science'.")
		quit(1)
		return
	print("  ✓ PASS: Major successfully merged to canonical name ('Computer Science').")

	# --- Test 6: Audit Event Logging ---
	print("\n[Test 6] Testing Audit Log Event Outbox Records...")
	var evt_q = db.execute("SELECT * FROM event_outbox WHERE event_type IN ('institution.merged', 'major.merged');")
	if not evt_q["success"] or evt_q["data"].size() < 2:
		print("❌ FAIL: Expected at least 2 audit event outbox records, got: ", evt_q.get("data", []).size())
		quit(1)
		return
	print("  ✓ PASS: Audit log event outbox records successfully created for merge operations.")

	print("\n==========================================================")
	print("ALL CAMPUS & COMMUNITY PHASE X.3 TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)
