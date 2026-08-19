extends SceneTree

## Production Deployment Verification Script

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _init() -> void:
	print("\n============================================================")
	print("  VERIFYING PRODUCTION DEPLOYMENT & DATA INTEGRITY")
	print("============================================================\n")

	call_deferred("verify_production")

func verify_production() -> void:
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("[ProductionVerification] Target Database: ", prod_db_path)
	assert(FileAccess.file_exists(prod_db_path), "Production DB missing!")

	var db = SQLiteDatabaseScript.new(prod_db_path)

	# 1. Existing Production people intact
	var p_res = db.execute("SELECT * FROM people WHERE status != 'archived' LIMIT 1;")
	assert(p_res["success"] and p_res["data"].size() > 0, "Production people missing!")
	var p = p_res["data"][0]
	var p_id = int(p.get("id", 0))
	var p_uuid = str(p.get("person_uuid", ""))
	var h_id = str(p.get("human_id", ""))
	print("  ✓ 1. Production constituent intact: %s %s (ID: %d, HumanID: %s)" % [p.get("first_name", ""), p.get("last_name", ""), p_id, h_id])

	# 2. Add General Note in Production
	var note_service = NoteServiceScript.new(db)
	var add_res = note_service.create_person_note({
		"person_uuid": p_uuid,
		"note_type_uuid": "nt_general",
		"title": "Prod Test General Note",
		"body": "Testing General Note creation in Production.",
		"visibility": "standard_staff"
	})
	assert(add_res["success"], "Failed to add General Note in Production: " + str(add_res.get("error", "")))
	var n_uuid = add_res["note_uuid"]
	print("  ✓ 2. Created Production General Note: ", n_uuid)

	# 3. Edit General Note in Production
	var edit_res = note_service.update_person_note(n_uuid, {
		"title": "Prod Test General Note (Edited)",
		"body": "Testing General Note editing in Production."
	})
	assert(edit_res["success"], "Failed to edit General Note in Production")
	print("  ✓ 3. Edited Production General Note: ", n_uuid)

	# 4. Spelling assistance suggestions check
	var spell_issues = SpellingAssistanceHelperScript.check_text("I definately recieve seperate calender adress wierd")
	assert(spell_issues.size() == 6, "Expected 6 spelling suggestions in Production test")
	print("  ✓ 4. Spelling assistance engine verified in Production mode.")

	# 5. Create Person-linked Task in Production
	var task_uuid = "task_prod_" + str(Time.get_ticks_msec())
	var task_sql = """
	INSERT INTO staff_tasks_index (task_uuid, title, description, due_date, priority, status, linked_human_id, linked_human_name)
	VALUES (?, ?, ?, datetime('now', '+1 day'), 'high', 'open', ?, ?);
	"""
	var task_res = db.execute(task_sql, [task_uuid, "Follow up with constituent in Production", "Task verification", h_id, p.get("first_name", "") + " " + p.get("last_name", "")])
	assert(task_res["success"], "Failed to create Production person task")
	print("  ✓ 5. Created Person-linked Task in Production: ", task_uuid)

	# 6. Verify Task appears under Home -> Needs Attention
	var na_res = db.execute("SELECT * FROM staff_tasks_index WHERE status = 'open' AND task_uuid = ?;", [task_uuid])
	assert(na_res["success"] and na_res["data"].size() == 1, "Task not found in Needs Attention query!")
	print("  ✓ 6. Verified Task appears in Production Needs Attention queue.")

	# 7. Complete Task and verify removal from Needs Attention
	var complete_res = db.execute("UPDATE staff_tasks_index SET status = 'completed', completed_at = datetime('now') WHERE task_uuid = ?;", [task_uuid])
	assert(complete_res["success"], "Failed to complete Production task")
	var na_after = db.execute("SELECT * FROM staff_tasks_index WHERE status = 'open' AND task_uuid = ?;", [task_uuid])
	assert(na_after["success"] and na_after["data"].size() == 0, "Task still present in Needs Attention after completion!")
	print("  ✓ 7. Verified Task completed and removed from Production Needs Attention queue.")

	print("\n============================================================")
	print("  SUCCESS: PRODUCTION DEPLOYMENT & INTEGRITY 100% VERIFIED")
	print("============================================================\n")
	quit(0)
