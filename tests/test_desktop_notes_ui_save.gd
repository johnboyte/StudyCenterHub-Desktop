extends SceneTree

## Dedicated End-to-End Desktop UI Note Saving & Verification Test Suite

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var db: RefCounted

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING DESKTOP UI NOTE SAVING & VERIFICATION SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	# Initialize database in user:// or /tmp
	var db_path = ProjectSettings.globalize_path("user://test_desktop_notes_ui_save.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert(mig_res["success"], "Database migrations failed: " + str(mig_res.get("error", "")))

	# Instantiate directory_view
	var dir_scene = load("res://app/scenes/directory_view.tscn")
	assert(dir_scene != null, "Failed to load directory_view.tscn")
	var dir_view = dir_scene.instantiate()
	root.add_child(dir_view)
	dir_view.db = db

	# Seed a test active person into DB
	db.execute("""
		INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, status, primary_role)
		VALUES (10, 'usr_test_notes_save_1001', 'P-TEST-NOTES-001', 'TestUser', 'NotesSave', 'active', 'Student');
	""")

	# Fetch a real active person from people table
	var p_res = db.execute("SELECT * FROM people WHERE status = 'active' ORDER BY id ASC LIMIT 1;")
	assert(p_res["success"] and p_res["data"].size() > 0, "No active person found in test DB.")
	var person_data = p_res["data"][0]
	var p_uuid = str(person_data["person_uuid"])
	var p_id = int(person_data["id"])

	print("✓ Test Constituent: %s %s (UUID: %s, ID: %d)" % [person_data.get("first_name", ""), person_data.get("last_name", ""), p_uuid, p_id])

	# Test every single note type through the actual UI composition path
	_test_note_type_ui_save(dir_view, person_data, 0, "nt_general", "General Note", "Test General Note Body Content 101", "standard_staff")
	_test_note_type_ui_save(dir_view, person_data, 1, "nt_academic", "Academic Note", "Test Academic Note Body Content 202", "standard_staff")
	_test_note_type_ui_save(dir_view, person_data, 2, "nt_behavioral", "Behavioral Note", "Test Behavioral Note Body Content 303", "standard_staff")
	_test_note_type_ui_save(dir_view, person_data, 3, "nt_pastoral", "Pastoral Care Note", "Test Pastoral Care Note Body Content 404", "sensitive_pastoral")

	# Test persistence across view refresh and re-instantiation
	print("\n--- Verifying Notes Persistence Across Navigation & Re-instantiation ---")
	dir_view.queue_free()
	await process_frame

	var dir_view_2 = dir_scene.instantiate()
	root.add_child(dir_view_2)
	dir_view_2.db = db

	var fetch_all = db.execute("SELECT * FROM person_notes WHERE person_uuid = ? AND is_deleted = 0 ORDER BY id ASC;", [p_uuid])
	assert(fetch_all["success"] and fetch_all["data"].size() == 4, "Expected exactly 4 saved notes in DB, got: " + str(fetch_all["data"].size()))
	print("✓ PASS: All 4 saved notes survived UI re-instantiation and database re-query.")

	print("\n============================================================")
	print("  SUCCESS: ALL DESKTOP NOTE SAVING UI TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _test_note_type_ui_save(dir_view: Node, person_data: Dictionary, dropdown_idx: int, expected_type_uuid: String, expected_title: String, test_body: String, expected_visibility: String) -> void:
	print("\n--- Testing UI Save for Note Type: %s (%s) ---" % [expected_title, expected_type_uuid])

	var p_uuid = str(person_data["person_uuid"])
	var p_id = int(person_data["id"])

	# Populate notes section UI container
	var dummy_notes_section = VBoxContainer.new()
	dir_view.notes_section = dummy_notes_section
	dir_view._populate_notes_section(person_data)

	# Locate UI controls inside composer card
	var cat_dropdown: OptionButton = null
	var body_edit: TextEdit = null
	var btn_save: Button = null

	for child in dummy_notes_section.get_children():
		var opts = child.find_children("", "OptionButton", true, false)
		if opts.size() > 0 and not cat_dropdown:
			cat_dropdown = opts[0] as OptionButton

		var texts = child.find_children("", "TextEdit", true, false)
		if texts.size() > 0 and not body_edit:
			body_edit = texts[0] as TextEdit

		var btns = child.find_children("", "Button", true, false)
		for b in btns:
			if b.text.contains("Save Note"):
				btn_save = b as Button
				break

	assert(cat_dropdown != null, "UI OptionButton for note category not found!")
	assert(body_edit != null, "UI TextEdit for note body not found!")
	assert(btn_save != null, "UI Button for save note not found!")

	# Select requested note category in dropdown
	assert(cat_dropdown.item_count > dropdown_idx, "Dropdown index out of bounds: " + str(dropdown_idx))
	cat_dropdown.selected = dropdown_idx

	# Enter real test note text
	body_edit.text = test_body

	# Programmatically emit save button pressed signal (exact UI action)
	btn_save.emit_signal("pressed")

	# Verify record in SQLite person_notes table
	var res = db.execute("SELECT * FROM person_notes WHERE person_uuid = ? AND body = ?;", [p_uuid, test_body])
	assert(res["success"] and res["data"].size() == 1, "Note record missing from person_notes DB table for " + expected_title)

	var record = res["data"][0]
	assert(record["person_uuid"] == p_uuid, "person_uuid mismatch.")
	assert(int(record["person_id"]) == p_id, "person_id mismatch.")
	assert(record["note_type_uuid"] == expected_type_uuid, "note_type_uuid mismatch. Expected: " + expected_type_uuid + ", got: " + str(record["note_type_uuid"]))
	assert(record["body"] == test_body, "Note body mismatch.")
	assert(record["visibility"] == expected_visibility, "Visibility mismatch. Expected: " + expected_visibility + ", got: " + str(record["visibility"]))
	assert(str(record["created_at"]) != "", "Timestamp missing.")

	print("✓ PASS: UI Save for '%s' created valid DB record (ID: %d, UUID: %s, Vis: %s)." % [expected_title, record["id"], record["note_uuid"], record["visibility"]])
