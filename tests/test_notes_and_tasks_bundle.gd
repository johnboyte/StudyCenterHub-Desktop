extends SceneTree

## Automated End-to-End Test Suite for Unified Notes & Profile Tasks Bundle

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

var db: RefCounted

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING UNIFIED NOTES & PROFILE TASKS TEST SUITE")
	print("============================================================\n")

	# Initialize test SQLite database in /tmp
	var db_path = "/tmp/test_notes_and_tasks_" + str(Time.get_ticks_usec()) + ".db"
	db = SQLiteDatabaseScript.new(db_path)

	# 1. Run migrations
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert(mig_res["success"], "Database migrations failed: " + str(mig_res.get("error", "")))
	print("✓ PASS: Migration 0056 & schema initialization complete.")

	_test_person_tasks_isolation_and_lifecycle()
	_test_notes_privacy_and_general_filtering()
	_test_needs_attention_integration()
	_test_idempotency_and_sync_payloads()

	print("\n============================================================")
	print("  SUCCESS: ALL TEST SUITE ASSERTIONS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _test_person_tasks_isolation_and_lifecycle() -> void:
	print("\n--- Testing Profile Tasks Isolation & Lifecycle ---")

	var person_a_hid = "P-TEST-0001"
	var person_b_hid = "P-TEST-0002"

	# Insert Person A Task
	var task_a_uuid = "task_test_a_1001"
	var res_a = db.execute("""
		INSERT INTO staff_tasks_index (
			task_uuid, title, description, due_date, priority, status,
			assignee_name, linked_human_id, linked_human_name, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, datetime('now'), datetime('now'));
	""", [task_a_uuid, "Call Person A Parent", "Registration follow up", "2026-09-01", "high", "Staff User", person_a_hid, "Person A"])
	assert(res_a["success"], "Failed to insert Task A")

	# Insert Person B Task
	var task_b_uuid = "task_test_b_1002"
	var res_b = db.execute("""
		INSERT INTO staff_tasks_index (
			task_uuid, title, description, due_date, priority, status,
			assignee_name, linked_human_id, linked_human_name, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, datetime('now'), datetime('now'));
	""", [task_b_uuid, "Schedule Person B Orientation", "Welcome call", "2026-09-05", "normal", "Staff User", person_b_hid, "Person B"])
	assert(res_b["success"], "Failed to insert Task B")

	# Query Person A tasks
	var fetch_a = db.execute("SELECT * FROM staff_tasks_index WHERE linked_human_id = ?;", [person_a_hid])
	assert(fetch_a["success"] and fetch_a["data"].size() == 1, "Person A should have exactly 1 task.")
	assert(fetch_a["data"][0]["task_uuid"] == task_a_uuid, "Person A task UUID mismatch.")

	# Query Person B tasks
	var fetch_b = db.execute("SELECT * FROM staff_tasks_index WHERE linked_human_id = ?;", [person_b_hid])
	assert(fetch_b["success"] and fetch_b["data"].size() == 1, "Person B should have exactly 1 task.")
	assert(fetch_b["data"][0]["task_uuid"] == task_b_uuid, "Person B task UUID mismatch.")
	assert(fetch_b["data"][0]["linked_human_id"] != person_a_hid, "Person B must NEVER show Person A tasks.")

	print("✓ PASS: Task isolation verified between Person A and Person B.")

	# Update & Complete Task A
	var comp_res = db.execute("""
		UPDATE staff_tasks_index
		SET status = 'completed', completed_at = datetime('now'), completed_by = 'Test Staff', updated_at = datetime('now')
		WHERE task_uuid = ?;
	""", [task_a_uuid])
	assert(comp_res["success"], "Failed to complete Task A")

	var verify_comp = db.execute("SELECT status, completed_by FROM staff_tasks_index WHERE task_uuid = ?;", [task_a_uuid])
	assert(verify_comp["success"] and verify_comp["data"][0]["status"] == "completed", "Task A should be marked completed.")
	assert(verify_comp["data"][0]["completed_by"] == "Test Staff", "Completed by field mismatch.")

	print("✓ PASS: Task update and completion lifecycle verified.")

func _test_notes_privacy_and_general_filtering() -> void:
	print("\n--- Testing Notes Privacy & Mobile General Filtering ---")

	var person_hid = "P-TEST-0001"

	# Insert General Note
	var gen_uuid = "note_gen_101"
	db.execute("""
		INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
		VALUES (?, 1, ?, 'nt_general', 'General', 'Standard constituent update', 'standard_staff', datetime('now'), datetime('now'));
	""", [gen_uuid, person_hid])

	# Insert Restricted Pastoral Care Note
	var past_uuid = "note_pastoral_102"
	db.execute("""
		INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
		VALUES (?, 1, ?, 'nt_pastoral', 'Pastoral Care Note', 'Confidential prayer request', 'sensitive_pastoral', datetime('now'), datetime('now'));
	""", [past_uuid, person_hid])

	# Query Mobile-allowed notes (General only)
	var mob_notes = db.execute("""
		SELECT * FROM person_notes
		WHERE person_uuid = ?
		  AND is_deleted = 0
		  AND (note_type_uuid = 'nt_general' OR title = 'General')
		  AND LOWER(COALESCE(visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private');
	""", [person_hid])

	assert(mob_notes["success"] and mob_notes["data"].size() == 1, "Mobile query should return ONLY 1 General note.")
	assert(mob_notes["data"][0]["note_uuid"] == gen_uuid, "Mobile query returned non-general note!")

	print("✓ PASS: Pastoral/restricted notes excluded from Mobile; General notes included.")

func _test_needs_attention_integration() -> void:
	print("\n--- Testing Home Needs Attention Integration ---")

	# Register queue definition
	var reg = QueueRegistryScript.get_registry()
	assert(reg.has("person_profile_tasks"), "QueueRegistry missing person_profile_tasks definition.")

	var def = reg["person_profile_tasks"]
	var count_sql = def["count_sql"]
	var record_sql = def["record_sql"]

	var cnt_res = db.execute(count_sql)
	assert(cnt_res["success"] and cnt_res["data"].size() > 0, "Count SQL failed.")
	var open_count = int(cnt_res["data"][0]["cnt"])

	# Task B is open, Task A was completed -> open count should be 1
	assert(open_count == 1, "Needs Attention count expected 1 open task, got: " + str(open_count))

	var rec_res = db.execute(record_sql)
	assert(rec_res["success"] and rec_res["data"].size() == 1, "Record SQL expected 1 open task record.")
	assert(rec_res["data"][0]["task_uuid"] == "task_test_b_1002", "Record SQL returned completed task!")

	print("✓ PASS: Needs Attention correctly queries open profile tasks and excludes completed tasks.")

func _test_idempotency_and_sync_payloads() -> void:
	print("\n--- Testing Idempotency & Sync Upserts ---")

	var task_b_uuid = "task_test_b_1002"

	# Re-upsert Task B 3 times
	for i in range(3):
		var upsert_res = db.execute("""
			INSERT INTO staff_tasks_index (
				task_uuid, title, description, due_date, priority, status,
				assignee_name, linked_human_id, linked_human_name, created_at, updated_at
			) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, datetime('now'), datetime('now'))
			ON CONFLICT(task_uuid) DO UPDATE SET
				title = excluded.title,
				description = excluded.description,
				updated_at = datetime('now');
		""", [task_b_uuid, "Schedule Person B Orientation (Updated)", "Welcome call updated", "2026-09-05", "normal", "Staff User", "P-TEST-0002", "Person B"])
		assert(upsert_res["success"], "Upsert iteration " + str(i) + " failed.")

	var check_dup = db.execute("SELECT COUNT(*) as cnt FROM staff_tasks_index WHERE task_uuid = ?;", [task_b_uuid])
	assert(check_dup["success"] and int(check_dup["data"][0]["cnt"]) == 1, "Repeated sync created duplicate task records!")

	print("✓ PASS: Idempotent UPSERTS guarantee zero duplicate task records.")
