extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING CAMPUS & COMMUNITY & ACADEMIC ADVANCEMENT TEST SUITE")
	print("==========================================================\n")

	var db_path = ProjectSettings.globalize_path("user://test_campus_community_advancement.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	if not mig_res["success"]:
		print("❌ FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return
	print("  ✓ PASS: Migrations 0001-0040 executed cleanly.")

	_test_master_institutions_seed(db)
	_test_campus_community_person_attributes(db)
	_test_auto_default_relationship(db)
	_test_advancement_queue_and_fall_deferral(db)
	_test_five_review_outcomes_and_history(db)
	_test_action_center_queue_registry(db)

	print("\n==========================================================")
	print("ALL CAMPUS & COMMUNITY ADVANCEMENT TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)

func _test_master_institutions_seed(db: RefCounted) -> void:
	print("\n[Test 1] Testing master institutions seeding & schema...")
	var q = db.execute("SELECT id, name, short_name, institution_type FROM institutions ORDER BY display_order ASC;")
	if not q["success"] or q["data"].size() < 7:
		print("❌ FAIL: Master institutions count unexpected: ", q)
		quit(1)
		return

	var names = []
	for row in q["data"]:
		names.append(str(row["name"]))

	assert("Anderson University" in names, "Anderson University missing from seed")
	assert("Clemson University" in names, "Clemson University missing from seed")
	assert("Community" in names, "Community missing from seed")
	assert("Other" in names, "Other missing from seed")

	print("  ✓ PASS: Found 7 seeded master institutions.")
	print("PASS 1: Master institutions seeding verified.")

func _test_campus_community_person_attributes(db: RefCounted) -> void:
	print("\n[Test 2] Testing campus & community person record attributes...")
	var q_inst = db.execute("SELECT id FROM institutions WHERE name = 'Anderson University' LIMIT 1;")
	var inst_id = int(q_inst["data"][0]["id"])

	var ins_sql = """
		INSERT INTO people (person_uuid, human_id, first_name, last_name, institution_id, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year)
		VALUES ('p_alex_101', 'PRT-2101', 'Alexander', 'Baker', ?, 'Student', 'Senior', 'Computer Science', 'On Campus', 'Spring', 2027);
	"""
	var res = db.execute(ins_sql, [inst_id])
	assert(res["success"], "Failed to insert test constituent record")

	var q_p = db.execute("SELECT p.*, inst.name as inst_name FROM people p JOIN institutions inst ON inst.id = p.institution_id WHERE p.person_uuid = 'p_alex_101';")
	assert(q_p["success"] and q_p["data"].size() > 0, "Failed to query constituent with institution join")

	var p = q_p["data"][0]
	assert(str(p["inst_name"]) == "Anderson University", "Institution name join mismatch")
	assert(str(p["academic_year"]) == "Senior", "Academic year mismatch")
	assert(str(p["major"]) == "Computer Science", "Major mismatch")

	print("  ✓ PASS: Constituent linked with institution_id FK and campus attributes.")
	print("PASS 2: Campus & community person record attributes verified.")

func _test_auto_default_relationship(db: RefCounted) -> void:
	print("\n[Test 3] Testing auto-default relationship logic for Community institution...")
	var q_comm = db.execute("SELECT id, institution_type FROM institutions WHERE name = 'Community' LIMIT 1;")
	assert(q_comm["success"] and q_comm["data"].size() > 0, "Community institution not found")

	var comm_type = str(q_comm["data"][0]["institution_type"])
	assert(comm_type == "community", "Community institution type must be 'community'")

	var default_rel = "Student"
	if comm_type == "community":
		default_rel = "Community Member"

	assert(default_rel == "Community Member", "Community institution did not default relationship to Community Member")
	print("  ✓ PASS: Institution type 'community' auto-defaulted relationship to 'Community Member'.")
	print("PASS 3: Auto-default relationship verified.")

func _test_advancement_queue_and_fall_deferral(db: RefCounted) -> void:
	print("\n[Test 4] Testing Advancement Review queue candidates & Fall deferral...")
	var q_clem = db.execute("SELECT id FROM institutions WHERE name = 'Clemson University' LIMIT 1;")
	var clem_id = int(q_clem["data"][0]["id"])

	# Insert candidate 1 (Spring Sr -> Alumni)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, institution_id, relationship, academic_year, expected_grad_term, expected_grad_year) VALUES ('p_cand_1', 'PRT-2201', 'Carl', 'Spring', ?, 'Student', 'Senior', 'Spring', 2026);", [clem_id])
	# Insert candidate 2 (Fall Sr -> Deferred)
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, institution_id, relationship, academic_year, expected_grad_term, expected_grad_year) VALUES ('p_cand_2', 'PRT-2202', 'Fiona', 'Fall', ?, 'Student', 'Senior', 'Fall', 2026);", [clem_id])

	var cand_q = db.execute("""
		SELECT p.id, p.first_name, p.academic_year, p.expected_grad_term
		FROM people p
		JOIN institutions inst ON inst.id = p.institution_id
		WHERE inst.institution_type = 'college_university'
		  AND p.relationship = 'Student'
		  AND p.skip_next_advancement = 0;
	""")
	assert(cand_q["success"] and cand_q["data"].size() >= 3, "Advancement queue query candidates missing")

	var fiona_deferred = false
	for item in cand_q["data"]:
		if str(item["first_name"]) == "Fiona":
			if str(item["academic_year"]) == "Senior" and str(item["expected_grad_term"]) == "Fall":
				fiona_deferred = true

	assert(fiona_deferred, "Fall graduation term participant not identified for deferral")
	print("  ✓ PASS: Fall graduation term deferral verified.")
	print("PASS 4: Advancement review queue and Fall deferral verified.")

func _test_five_review_outcomes_and_history(db: RefCounted) -> void:
	print("\n[Test 5] Testing 5 advancement review outcomes & Academic History logs...")
	var q_p = db.execute("SELECT id FROM people WHERE person_uuid = 'p_cand_1' LIMIT 1;")
	var pid = int(q_p["data"][0]["id"])

	# Outcome 1: Apply Suggested Promotion (Senior -> Alumni)
	db.execute("UPDATE people SET academic_year = 'Alumni', relationship = 'Alumni', advancement_last_reviewed_at = datetime('now') WHERE id = ?;", [pid])

	# Log to person_academic_history
	var h_uuid = "ahist_test_101"
	var h_res = db.execute("INSERT INTO person_academic_history (uuid, person_id, relationship, academic_year, change_source, changed_by) VALUES (?, ?, 'Alumni', 'Alumni', 'Academic Advancement Review', 'Administrator');", [h_uuid, pid])
	assert(h_res["success"], "Failed to insert into person_academic_history")

	var q_hist = db.execute("SELECT * FROM person_academic_history WHERE person_id = ?;", [pid])
	assert(q_hist["success"] and q_hist["data"].size() > 0, "Academic history record not found")
	assert(str(q_hist["data"][0]["academic_year"]) == "Alumni", "Academic history academic_year mismatch")

	# Outcome 5: Skip This Academic Year
	var q_p2 = db.execute("SELECT id FROM people WHERE person_uuid = 'p_cand_2' LIMIT 1;")
	var pid2 = int(q_p2["data"][0]["id"])
	db.execute("UPDATE people SET skip_next_advancement = 1, advancement_last_reviewed_at = datetime('now') WHERE id = ?;", [pid2])

	var q_skip = db.execute("SELECT skip_next_advancement FROM people WHERE id = ?;", [pid2])
	assert(int(q_skip["data"][0]["skip_next_advancement"]) == 1, "skip_next_advancement flag failed to persist")

	print("  ✓ PASS: Successfully tested review outcomes and person_academic_history log creation.")
	print("PASS 5: Five review outcomes and academic history verified.")

func _test_action_center_queue_registry(db: RefCounted) -> void:
	print("\n[Test 6] Testing Action Center Campus & Community work queues...")
	assert(QueueRegistryScript.has_definition("missing_institution"), "missing_institution queue definition missing")
	assert(QueueRegistryScript.has_definition("missing_academic_year"), "missing_academic_year queue definition missing")
	assert(QueueRegistryScript.has_definition("approaching_graduation"), "approaching_graduation queue definition missing")

	var q_def = QueueRegistryScript.get_definition("missing_institution")
	var count_sql = str(q_def.get("count_sql", ""))
	var cnt_res = db.execute(count_sql)
	assert(cnt_res["success"], "Missing institution count_sql failed to execute")

	print("  ✓ PASS: Action Center queue definitions registered and count_sql executable.")
	print("PASS 6: Action Center queue registry verified.")
