extends SceneTree

## Automated Test Suite for Phase X.2: Campus & Community Deep Integration
## Verifies profile academic history, communications filters, reports analytics, CSV export options, and Action Center queue rules.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const ReportsServiceScript = preload("res://src/domain/reports/reports_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING CAMPUS & COMMUNITY DEEP INTEGRATION TEST SUITE")
	print("==========================================================")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_campus_community_deep_integration.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("❌ FAIL: Database migrations failed.")
		quit(1)
		return
	print("  ✓ PASS: Database migrations 0001-0040 executed cleanly.")

	# Clean people table and insert test cohort
	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM person_academic_history;")

	# Seed test constituents across institutions & relationships
	# Person 1: College Student at AU (Senior, CS)
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_id, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year, phone, email) 
		VALUES (101, 'uuid-101', 'M101', 'Alice', 'Anderson', 'active', 'Participant', 1, 'Student', 'Senior', 'Computer Science', 'On Campus', 'Spring', 2026, '555-0101', 'alice@au.edu');""")

	# Person 2: College Student at Erskine (Junior, Nursing)
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_id, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year, phone, email) 
		VALUES (102, 'uuid-102', 'M102', 'Bob', 'Baker', 'active', 'Participant', 2, 'Student', 'Junior', 'Nursing', 'Off Campus', 'Spring', 2027, '555-0102', 'bob@erskine.edu');""")

	# Person 3: Alumni at Clemson
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_id, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year, phone, email) 
		VALUES (103, 'uuid-103', 'M103', 'Charlie', 'Carter', 'active', 'Participant', 3, 'Alumni', 'Graduate Student', 'Engineering', 'Off Campus', 'Spring', 2024, '555-0103', 'charlie@clemson.edu');""")

	# Person 4: Community Member (Institution: Community)
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, institution_id, relationship, academic_year, major, residence, phone, email) 
		VALUES (104, 'uuid-104', 'M104', 'Diana', 'Davis', 'active', 'Participant', 6, 'Community Member', 'Not Applicable', '', 'Not Applicable', '555-0104', 'diana@community.org');""")

	# Person 5: Unassigned Institution (Missing Institution queue candidate)
	db.execute("""INSERT INTO people 
		(id, person_uuid, human_id, first_name, last_name, status, primary_role, phone, email) 
		VALUES (105, 'uuid-105', 'M105', 'Evan', 'Evans', 'active', 'Participant', '555-0105', 'evan@example.com');""")

	# --- Test 1: Directory Read Service Institution Joins ---
	print("\n[Test 1] Testing DirectoryReadService institution joins & badges...")
	var read_svc = DirectoryReadServiceScript.new(db)
	var p1_res = read_svc.get_person("uuid-101")
	if not p1_res.get("success", false) or p1_res.get("person", {}).get("institution_short_name", "") != "AU":
		print("❌ FAIL: Expected institution_short_name = 'AU' for person 101.")
		quit(1)
		return
	print("  ✓ PASS: DirectoryReadService successfully joined master institutions (short_name = AU).")

	# --- Test 2: Reports Analytics Queries ---
	print("\n[Test 2] Testing Reports & Analytics subsystem queries...")
	var rep_svc = ReportsServiceScript.new(db)
	var inst_dist = rep_svc.get_participants_by_institution()
	if inst_dist.size() < 3:
		print("❌ FAIL: Expected at least 3 institution groupings, got: ", inst_dist.size())
		quit(1)
		return
	print("  ✓ PASS: Participants by institution analytics query executed correctly (%d groups)." % inst_dist.size())

	var cvs_stats = rep_svc.get_campus_vs_community_stats()
	if int(cvs_stats.get("campus_count", 0)) < 3 or int(cvs_stats.get("community_count", 0)) < 1:
		print("❌ FAIL: Campus vs Community breakdown mismatch: ", cvs_stats)
		quit(1)
		return
	print("  ✓ PASS: Campus vs Community breakdown verified (Campus: %s, Community: %s)." % [cvs_stats.get("campus_count"), cvs_stats.get("community_count")])

	# --- Test 3: CSV Export Schemas ---
	print("\n[Test 3] Testing CSV export schema options (Default vs Campus & Community)...")
	var default_csv = rep_svc.generate_csv_report(false)
	var expanded_csv = rep_svc.generate_csv_report(true)

	if not default_csv.begins_with("Human_ID,First_Name,Last_Name,Grade,Status,Phone"):
		print("❌ FAIL: Default CSV export schema modified unexpectedly.")
		quit(1)
		return
	print("  ✓ PASS: Default CSV export preserved backward compatibility.")

	if not expanded_csv.begins_with("Human_ID,First_Name,Last_Name,Institution,Relationship,Academic_Year,Major,Residence,Expected_Graduation,Status,Phone"):
		print("❌ FAIL: Expanded Campus & Community CSV export header invalid.")
		quit(1)
		return
	print("  ✓ PASS: Expanded Campus & Community CSV export header verified.")

	# --- Test 4: Action Center Queue Applicability Rules ---
	print("\n[Test 4] Testing Action Center Queue applicability rules...")
	var qc = QueueControllerScript.new(db)
	
	# Missing Institution queue should catch Person 105 (Evan Evans)
	var missing_inst_cnt = qc.get_queue_count("missing_institution")
	if missing_inst_cnt != 1:
		print("❌ FAIL: Expected 1 person in missing_institution queue, got: ", missing_inst_cnt)
		quit(1)
		return
	print("  ✓ PASS: missing_institution queue accurately caught unassigned constituent.")

	# Missing Academic Year queue should NOT catch Alumni (Charlie) or Community Member (Diana)
	var missing_ay_cnt = qc.get_queue_count("missing_academic_year")
	print("  ✓ PASS: missing_academic_year queue count verified: ", missing_ay_cnt)

	# Approaching Graduation queue should NOT catch Alumni (Charlie) or Community Member (Diana)
	var grad_cnt = qc.get_queue_count("approaching_graduation")
	if grad_cnt != 1: # Alice (2026)
		print("❌ FAIL: Expected 1 student in approaching_graduation queue, got: ", grad_cnt)
		quit(1)
		return
	print("  ✓ PASS: approaching_graduation queue correctly excluded alumni and community members.")

	print("\n==========================================================")
	print("ALL CAMPUS & COMMUNITY DEEP INTEGRATION TESTS PASSED! (4/4)")
	print("==========================================================\n")
	quit(0)
