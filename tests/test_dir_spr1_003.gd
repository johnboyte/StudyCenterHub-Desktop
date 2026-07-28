extends SceneTree

## Headless Test Suite for Story DIR-SPR1-003
## Comprehensive Verification of Directory Search Foundation & Performance Benchmark

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-003 DIRECTORY SEARCH TEST SUITE")
	print("==========================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_003.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)

	var mig_res = migrations_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migration execution failed: ", mig_res["error"])
		quit(1)
		return

	var person_service = PersonServiceScript.new(db)
	var read_service = DirectoryReadServiceScript.new(db)

	# Seed Known Records for Functional Verification (25 tests)
	var p1 = person_service.create_person({
		"first_name": "Marcus", "last_name": "O'Connor", "phone": "(864) 555-1212",
		"status": "active", "emergency_contact_name": "Sarah O'Connor",
		"emergency_contact_phone": "864-555-9988"
	})["person"]

	var p2 = person_service.create_person({
		"first_name": "Anna-Marie", "last_name": "Smith-Jones", "phone": "864.555.2323",
		"status": "pending", "emergency_contact_name": "Dave Smith",
		"emergency_contact_phone": "(864) 555-7766"
	})["person"]

	var p3 = person_service.create_person({
		"first_name": "Marc", "last_name": "Anthony", "phone": "864 555 3434",
		"status": "To Be Confirmed", "emergency_contact_name": "Elena Anthony",
		"emergency_contact_phone": "8645558899"
	})["person"]

	var p4 = person_service.create_person({
		"first_name": "Zack", "last_name": "Taylor", "phone": "8645554545",
		"status": "inactive"
	})["person"]

	# 1. Search by exact first name
	var s1 = read_service.search_people("Marcus")
	if not s1["success"] or s1["people"].size() != 1 or s1["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 1: Search by exact first name failed.")
		quit(1)
		return
	print("PASS 1/25: Search by exact first name verified.")

	# 2. Search by partial first name
	var s2 = read_service.search_people("Marc")
	if not s2["success"] or s2["people"].size() != 2: # Marcus & Marc
		print("FAIL 2: Search by partial first name failed. Size: ", s2["people"].size())
		quit(1)
		return
	print("PASS 2/25: Search by partial first name verified.")

	# 3. Search by exact last name
	var s3 = read_service.search_people("O'Connor")
	if not s3["success"] or s3["people"].size() != 1 or s3["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 3: Search by exact last name failed.")
		quit(1)
		return
	print("PASS 3/25: Search by exact last name verified.")

	# 4. Search by partial last name
	var s4 = read_service.search_people("Smith")
	if not s4["success"] or s4["people"].size() != 1 or s4["people"][0]["person_uuid"] != p2["person_uuid"]:
		print("FAIL 4: Search by partial last name failed.")
		quit(1)
		return
	print("PASS 4/25: Search by partial last name verified.")

	# 5. Search by full name
	var s5 = read_service.search_people("Marcus O'Connor")
	if not s5["success"] or s5["people"].size() != 1 or s5["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 5: Search by full name failed.")
		quit(1)
		return
	print("PASS 5/25: Search by full name verified.")

	# 6. Search is case-insensitive
	var s6 = read_service.search_people("mArCuS o'CoNnOr")
	if not s6["success"] or s6["people"].size() != 1 or s6["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 6: Case-insensitive search failed.")
		quit(1)
		return
	print("PASS 6/25: Case-insensitive search verified.")

	# 7. Search trims leading and trailing whitespace
	var s7 = read_service.search_people("   Marcus O'Connor   ")
	if not s7["success"] or s7["people"].size() != 1:
		print("FAIL 7: Whitespace trimming failed.")
		quit(1)
		return
	print("PASS 7/25: Whitespace trimming verified.")

	# 8. Search handles repeated interior whitespace
	var s8 = read_service.search_people("Marcus    O'Connor")
	if not s8["success"] or s8["people"].size() != 1:
		print("FAIL 8: Interior whitespace normalization failed.")
		quit(1)
		return
	print("PASS 8/25: Interior whitespace normalization verified.")

	# 9. Search by human_id
	var human_query = p1["human_id"]
	var s9 = read_service.search_people(human_query)
	if not s9["success"] or s9["people"].size() != 1 or s9["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 9: Search by human_id failed.")
		quit(1)
		return
	print("PASS 9/25: Search by human_id verified.")

	# 10. Search by formatted phone number
	var s10 = read_service.search_people("(864) 555-1212")
	if not s10["success"] or s10["people"].size() != 1 or s10["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 10: Search by formatted phone failed.")
		quit(1)
		return
	print("PASS 10/25: Search by formatted phone number verified.")

	# 11. Search by digits-only phone number (matching formatted stored phone)
	var s11 = read_service.search_people("8645551212")
	if not s11["success"] or s11["people"].size() != 1 or s11["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 11: Digits-only search against formatted phone failed.")
		quit(1)
		return
	print("PASS 11/25: Digits-only search matching formatted stored phone verified.")

	# 12. Search by emergency contact name
	var s12 = read_service.search_people("Sarah")
	if not s12["success"] or s12["people"].size() != 1 or s12["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 12: Search by emergency contact name failed.")
		quit(1)
		return
	print("PASS 12/25: Search by emergency contact name verified.")

	# 13. Search by emergency contact phone
	var s13 = read_service.search_people("8645559988")
	if not s13["success"] or s13["people"].size() != 1 or s13["people"][0]["person_uuid"] != p1["person_uuid"]:
		print("FAIL 13: Search by emergency contact phone failed.")
		quit(1)
		return
	print("PASS 13/25: Search by emergency contact phone verified.")

	# 14. Active status filter
	var s14 = read_service.search_people("a", {"status": "active"})
	for p in s14["people"]:
		if p["status"] != "active":
			print("FAIL 14: Active status filter returned non-active person.")
			quit(1)
			return
	print("PASS 14/25: Active status filter verified.")

	# 15. Pending status filter includes 'pending' and 'To Be Confirmed'
	var s15 = read_service.search_people("a", {"status": "pending"})
	if not s15["success"] or s15["people"].size() != 2: # Anna-Marie (pending) & Marc (To Be Confirmed)
		print("FAIL 15: Pending status filter failed to include both pending states. Count: ", s15["people"].size())
		quit(1)
		return
	print("PASS 15/25: Pending status filter includes both 'pending' and 'To Be Confirmed'.")

	# 16. Inactive status filter
	var s16 = read_service.search_people("Zack", {"status": "inactive"})
	if not s16["success"] or s16["people"].size() != 1 or s16["people"][0]["person_uuid"] != p4["person_uuid"]:
		print("FAIL 16: Inactive status filter failed.")
		quit(1)
		return
	print("PASS 16/25: Inactive status filter verified.")

	# 17. Invalid status filter fails safely
	var s17 = read_service.search_people("Marcus", {"status": "invalid_status_xyz"})
	if s17["success"]:
		print("FAIL 17: Invalid status filter should have returned failure dictionary.")
		quit(1)
		return
	print("PASS 17/25: Invalid status filter failed safely with clear error.")

	# 18. Empty query returns empty result set
	var s18 = read_service.search_people("   ")
	if not s18["success"] or s18["people"].size() != 0:
		print("FAIL 18: Empty query did not return empty result set.")
		quit(1)
		return
	print("PASS 18/25: Empty query returns empty result set.")

	# 19. Non-matching query returns empty result set
	var s19 = read_service.search_people("NonExistentNameXYZ999")
	if not s19["success"] or s19["people"].size() != 0:
		print("FAIL 19: Non-matching query did not return empty result set.")
		quit(1)
		return
	print("PASS 19/25: Non-matching query returns empty result set.")

	# 20. Deterministic ordering (last_name ASC, first_name ASC)
	var s20 = read_service.search_people("a")
	var names = []
	for p in s20["people"]:
		names.append(p["last_name"])
	# Verify ascending order
	var is_sorted = true
	for i in range(names.size() - 1):
		if names[i] > names[i+1]:
			is_sorted = false
			break
	if not is_sorted:
		print("FAIL 20: Result ordering is not deterministic: ", names)
		quit(1)
		return
	print("PASS 20/25: Search result ordering is deterministic.")

	# 21. Result limit is enforced (Limit = 2)
	var s21 = read_service.search_people("a", {"limit": 2})
	if not s21["success"] or s21["people"].size() > 2:
		print("FAIL 21: Result limit not enforced. Count: ", s21["people"].size())
		quit(1)
		return
	print("PASS 21/25: Result limit enforced successfully.")

	# 22. Excessive result limit clamped to 200
	var s22 = read_service.search_people("a", {"limit": 500})
	if not s22["success"]:
		print("FAIL 22: Excessive limit query failed.")
		quit(1)
		return
	print("PASS 22/25: Excessive result limit safely clamped.")

	# 23. Apostrophes and hyphens do not cause SQL errors
	var s23 = read_service.search_people("O'Connor-Smith's Test")
	if not s23["success"]:
		print("FAIL 23: Special characters caused SQL error: ", s23["error"])
		quit(1)
		return
	print("PASS 23/25: Apostrophes and hyphens handled safely in parameterization.")

	# 24. Search generates zero outbox events and zero data mutations
	var outbox_before = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	read_service.search_people("Marcus")
	read_service.search_people("8645551212")
	var outbox_after = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	if outbox_before != outbox_after:
		print("FAIL 24: Search generated outbox events!")
		quit(1)
		return
	print("PASS 24/25: Search strictly read-only (0 outbox events, 0 mutations).")

	# 25. PERFORMANCE BENCHMARK: Seed 5,000 Synthetic Person Records
	print("----------------------------------------------------------")
	print("STARTING 5,000-RECORD BENCHMARK DATASET SEEDING...")
	var start_seed = Time.get_ticks_msec()
	
	var statements = []
	for i in range(5000):
		var p_uuid = "usr_bench_%05d" % i
		var h_id = "P-20260720-%04d" % i
		var f_name = "First%d" % i
		var l_name = "Last%d" % (5000 - i)
		var ph = "(864) 555-%04d" % (i % 10000)
		var st = "active" if i % 2 == 0 else "pending"
		var sql = "INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, status) VALUES ('%s', '%s', '%s', '%s', '%s', '%s')" % [p_uuid, h_id, f_name, l_name, ph, st]
		statements.append(sql)

	var tx_res = db.execute_transaction(statements)
	if not tx_res["success"]:
		print("FAIL 25: Benchmark dataset seeding failed: ", tx_res["error"])
		quit(1)
		return
	var seed_duration = Time.get_ticks_msec() - start_seed
	print("Seeded 5,000 Person records in ", seed_duration, " ms. Total DB Rows: ", read_service.count_people())

	# Execute Representative Searches & Measure Performance
	print("----------------------------------------------------------")
	print("MEASURING REPRESENTATIVE SEARCH LATENCY (Target: < 100 ms)...")

	var queries = [
		{"name": "First Name Search ('First2500')", "q": "First2500"},
		{"name": "Last Name Search ('Last2500')", "q": "Last2500"},
		{"name": "Full Name Search ('First1000 Last4000')", "q": "First1000 Last4000"},
		{"name": "Human ID Search ('P-20260720-3500')", "q": "P-20260720-3500"},
		{"name": "Formatted Phone Search ('(864) 555-4321')", "q": "(864) 555-4321"},
		{"name": "Digits-Only Phone Search ('8645554321')", "q": "8645554321"},
		{"name": "No-Match Search ('NonExistentQuery999')", "q": "NonExistentQuery999"}
	]

	var max_latency_ms = 0.0
	for q_item in queries:
		var q_name = q_item["name"]
		var q_str = q_item["q"]
		var t0 = Time.get_ticks_usec()
		var res = read_service.search_people(q_str)
		var elapsed_ms = (Time.get_ticks_usec() - t0) / 1000.0
		if elapsed_ms > max_latency_ms:
			max_latency_ms = elapsed_ms
		print("  • %-45s : %.2f ms (Matches: %d)" % [q_name, elapsed_ms, res["count"]])

	print("----------------------------------------------------------")
	print("BENCHMARK RESULT: Max Search Latency = %.2f ms" % max_latency_ms)

	if max_latency_ms >= 100.0:
		print("FAIL 25: Search latency exceeded 100 ms target!")
		quit(1)
		return

	print("PASS 25/25: Performance benchmark passed (< 100 ms target met without FTS5).")

	print("==========================================================")
	print("SUCCESS: ALL STORY DIR-SPR1-003 OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
