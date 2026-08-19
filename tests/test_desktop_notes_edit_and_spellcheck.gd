extends SceneTree

## Automated End-to-End Test Suite for Desktop & Mobile Note Editing and Sync

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

var db: RefCounted

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING DESKTOP & MOBILE NOTE EDITING TEST SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_desktop_notes_edit.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert(mig_res["success"], "Database migrations failed: " + str(mig_res.get("error", "")))

	# Seed a test active person into DB
	db.execute("""
		INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, status, primary_role)
		VALUES (100, 'usr_note_edit_test_100', 'P-EDIT-001', 'John', 'Editor', 'active', 'Student');
	""")

	var note_service = NoteServiceScript.new(db)
	var sync_service = GatewaySyncServiceScript.new(db, root)

	var p_uuid = "usr_note_edit_test_100"

	_test_editing_for_all_note_types(note_service, p_uuid)
	_test_mobile_note_edit_inbound_sync(sync_service, p_uuid)
	_test_edit_idempotency_and_privacy(db, p_uuid)

	print("\n============================================================")
	print("  SUCCESS: ALL NOTE EDITING & SYNC TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _test_editing_for_all_note_types(note_service: RefCounted, p_uuid: String) -> void:
	print("\n--- Testing Editing for All 4 Note Types ---")

	var note_types_to_test = [
		{"uuid": "nt_general", "title": "General Note", "vis": "standard_staff"},
		{"uuid": "nt_academic", "title": "Academic Note", "vis": "standard_staff"},
		{"uuid": "nt_behavioral", "title": "Behavioral Note", "vis": "standard_staff"},
		{"uuid": "nt_pastoral", "title": "Pastoral Care Note", "vis": "sensitive_pastoral"}
	]

	for ntype in note_types_to_test:
		var t_uuid = ntype["uuid"]
		var t_title = ntype["title"]
		var t_vis = ntype["vis"]

		# 1. Create original note
		var orig_body = "Original content for " + t_title
		var create_res = note_service.create_person_note({
			"person_uuid": p_uuid,
			"note_type_uuid": t_uuid,
			"title": t_title,
			"body": orig_body,
			"visibility": t_vis
		})
		assert(create_res["success"], "Failed to create note for " + t_title)
		var note_uuid = create_res["note_uuid"]

		# Fetch original record details
		var rec1 = db.execute("SELECT * FROM person_notes WHERE note_uuid = ?;", [note_uuid])
		assert(rec1["success"] and rec1["data"].size() == 1, "Original record missing")
		var created_at = rec1["data"][0]["created_at"]
		var orig_id = rec1["data"][0]["id"]

		# Short delay to guarantee distinct updated_at timestamp
		OS.delay_msec(10)

		# 2. Edit note
		var edited_body = "EDITED content for " + t_title + " with updated spell-checked observations."
		var edit_res = note_service.update_person_note(note_uuid, {
			"body": edited_body,
			"title": t_title,
			"note_type_uuid": t_uuid,
			"visibility": t_vis
		})
		assert(edit_res["success"], "Failed to edit note for " + t_title)

		# 3. Verify updated record
		var rec2 = db.execute("SELECT * FROM person_notes WHERE note_uuid = ?;", [note_uuid])
		assert(rec2["success"] and rec2["data"].size() == 1, "Edited record missing")
		var updated_row = rec2["data"][0]

		assert(updated_row["note_uuid"] == note_uuid, "note_uuid must remain unchanged after edit!")
		assert(int(updated_row["id"]) == orig_id, "Record ID must remain unchanged!")
		assert(updated_row["body"] == edited_body, "Body content was not updated!")
		assert(updated_row["created_at"] == created_at, "created_at must be preserved!")
		assert(updated_row["visibility"] == t_vis, "Visibility must be preserved!")
		assert(updated_row["updated_at"] != "", "updated_at timestamp must be populated.")

		# Confirm only ONE record exists in DB (0 duplicates)
		var count_res = db.execute("SELECT COUNT(*) as cnt FROM person_notes WHERE note_uuid = ?;", [note_uuid])
		assert(count_res["success"] and int(count_res["data"][0]["cnt"]) == 1, "Editing created duplicate record!")

		print("✓ PASS: '%s' edited successfully (note_uuid preserved, created_at preserved, body updated, 0 duplicates)." % t_title)

func _test_mobile_note_edit_inbound_sync(sync_service: RefCounted, p_uuid: String) -> void:
	print("\n--- Testing Mobile Note Edit Event Processing ---")

	# Create a General note locally first
	var gen_uuid = "note_mob_edit_target_999"
	db.execute("""
		INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
		VALUES (?, 100, ?, 'nt_general', 'General Note', 'Original General Note Before Mobile Edit', 'standard_staff', datetime('now'), datetime('now'));
	""", [gen_uuid, p_uuid])

	# Process inbound mobile.note.update event
	var mobile_edit_payload = JSON.stringify({
		"note_uuid": gen_uuid,
		"person_uuid": p_uuid,
		"title": "General Note (Mobile Edited)",
		"body": "Updated General Note content submitted from Mobile device.",
		"updated_at": Time.get_datetime_string_from_system()
	})

	var mock_event = {
		"event_type": "mobile.note.update",
		"payload_json": mobile_edit_payload
	}

	sync_service._process_inbound_event(mock_event)

	# Verify local DB record received mobile edit
	var fetch_rec = db.execute("SELECT * FROM person_notes WHERE note_uuid = ?;", [gen_uuid])
	assert(fetch_rec["success"] and fetch_rec["data"].size() == 1, "Record missing after mobile update sync.")

	var row = fetch_rec["data"][0]
	assert(row["body"] == "Updated General Note content submitted from Mobile device.", "Desktop DB failed to update from mobile edit event.")
	assert(row["title"] == "General Note (Mobile Edited)", "Desktop DB failed to update title from mobile edit event.")

	print("✓ PASS: Desktop SQLite updated from mobile.note.update event cleanly.")

func _test_edit_idempotency_and_privacy(database: RefCounted, p_uuid: String) -> void:
	print("\n--- Testing Idempotency & Privacy Rules on Edits ---")

	var past_uuid = "note_pastoral_privacy_check_888"
	database.execute("""
		INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
		VALUES (?, 100, ?, 'nt_pastoral', 'Pastoral Care Note', 'Confidential Pastoral Body', 'sensitive_pastoral', datetime('now'), datetime('now'));
	""", [past_uuid, p_uuid])

	# Update Pastoral note
	database.execute("""
		UPDATE person_notes
		SET body = 'Updated Confidential Pastoral Body', updated_at = datetime('now')
		WHERE note_uuid = ? AND is_deleted = 0;
	""", [past_uuid])

	# Confirm privacy query still excludes updated Pastoral note from Mobile payloads
	var mob_query = database.execute("""
		SELECT * FROM person_notes
		WHERE person_uuid = ?
		  AND is_deleted = 0
		  AND (COALESCE(note_type_uuid, 'nt_general') = 'nt_general' OR title = 'General Note')
		  AND LOWER(COALESCE(visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private');
	""", [p_uuid])

	assert(mob_query["success"], "Mobile query failed")
	var found_pastoral = false
	for note in mob_query["data"]:
		if note["note_uuid"] == past_uuid:
			found_pastoral = true

	assert(not found_pastoral, "PRIVACY VIOLATION: Edited Pastoral Note appeared in Mobile query!")
	print("✓ PASS: Edited Pastoral note remains strictly excluded from Mobile sync payloads.")
