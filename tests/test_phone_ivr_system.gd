extends SceneTree

## Automated Headless Test Suite for Advanced Phone & IVR Settings
## Verifies that global settings, parent-child submenus, and voicemail workspace status shifts operate correctly.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING ADVANCED PHONE & IVR SYSTEM TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_phone_ivr.db")
	
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_phone_ivr.db"):
		dir.remove("studycenterhub_test_phone_ivr.db")

	var db = SQLiteDatabaseScript.new(db_path)
	
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	# Insert mock staff & sessions tables
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone) VALUES (1, 'staff_marcus', 'STF-0001', 'Marcus', 'Vance', 'staff', '509-555-0101');")
	
	# Seed mock hours
	db.execute("INSERT OR REPLACE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Monday', '09:00 AM', '05:00 PM', 0);")
	db.execute("INSERT OR REPLACE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Sunday', '09:00 AM', '05:00 PM', 1);")
	
	# Seed session types
	db.execute("INSERT INTO session_types (id, type_key, name) VALUES (1, 'reservation', 'Reservation');")
	db.execute("INSERT INTO session_types (id, type_key, name) VALUES (2, 'bible_study', 'Bible Study');")
	
	# Seed mock sessions
	db.execute("INSERT INTO sessions (title, date_text, start_time, end_time, is_active, session_type_id, description) VALUES ('Public Bible Study', '2026-08-08', '10:00 AM', '11:30 AM', 1, 2, 'A gathering to study scriptures.');")
	db.execute("INSERT INTO sessions (title, date_text, start_time, end_time, is_active, session_type_id, description) VALUES ('Private Staff Room Reservation', '2026-08-08', '01:00 PM', '02:00 PM', 1, 1, 'Closed reservation.');")

	var com_service = CommunicationsServiceScript.new(db)

	# Test 1: Global settings read/write
	var initial_settings = com_service.get_phone_settings()
	assert_true(initial_settings["rollover_rings"] == 4, "Default rollover rings is 4.")
	
	var save_res = com_service.save_phone_settings("1", 6, false, "Hello TTS override", "base64_audio_payload_example")
	assert_true(save_res, "Persisted custom phone settings successfully.")
	
	var updated_settings = com_service.get_phone_settings()
	assert_true(updated_settings["on_call_person_id"] == "1", "Saved on-call recipient verified.")
	assert_true(updated_settings["rollover_rings"] == 6, "Saved rollover rings verified.")
	assert_true(updated_settings["tts_greeting_active"] == false, "Saved TTS active toggle verified.")
	assert_true(updated_settings["automated_greeter_tts"] == "Hello TTS override", "Saved TTS welcome script verified.")
	assert_true(updated_settings["automated_greeter_audio"] == "base64_audio_payload_example", "Saved custom audio greeting payload verified.")

	# Test 2: Multi-level IVR options (Root and Child submenus) using backwards compatible wrappers
	# Add a parent option
	var root_save = com_service.save_ivr_menu_option("5", "Submenu test", "Speak script", "submenu", "", null, false, "")
	if not root_save:
		print("DEBUG root_save failed. DB error info might be in outbox or DB state.")
	assert_true(root_save, "Saved root IVR option successfully.")
	
	# Verify retrieved tree list
	var ivr_options = com_service.get_all_ivr_menu_options()
	var parent_found = false
	for opt in ivr_options:
		if opt["digit"] == "5":
			parent_found = true
			assert_true(opt["action_type"] == "submenu", "Root parent action type verified.")
			
	assert_true(parent_found, "IVR tree parent node verified.")

	# Test 3: Today Script Mode Automation Script compilation
	var save_today_res = com_service.save_today_settings("automatic", "Special Note Message", "", "Address text directions")
	assert_true(save_today_res, "Saved today script settings.")
	
	var auto_script = com_service.generate_today_script("2026-08-08", "Monday")
	print("DEBUG auto_script: ", auto_script)
	assert_true(auto_script.contains("Today is Monday"), "Spoken day name compiled correctly.")
	assert_true(auto_script.contains("Real Life House is open from 9 a.m. until 5 p.m."), "Spoken hours formatting compiled correctly.")
	assert_true(auto_script.contains("Public Bible Study, A gathering to study scriptures., is from 10 a.m. until 11:30 a.m."), "Spoken public events compiled correctly.")
	assert_true(not auto_script.contains("Private Staff Room Reservation"), "Internal room reservations filtered out successfully.")
	
	# Test 4: Today Script mode Custom Script Override
	com_service.save_today_settings("custom_override", "", "Custom overridden phone script.", "")
	var override_script = com_service.generate_today_script("2026-08-08", "Monday")
	assert_true(override_script == "Custom overridden phone script.", "Custom script override mode verified.")

	# Test 5: Staff Directory CRUD operations
	var save_staff_ok = com_service.save_staff_member("staff_john_test", "John Test", "555-1234", true, "1", 25, "voicemail")
	assert_true(save_staff_ok, "Created staff directory entry successfully.")
	
	var staff_list = com_service.get_all_staff_members()
	var staff_found = false
	for s in staff_list:
		if s["staff_uuid"] == "staff_john_test":
			staff_found = true
			assert_true(s["display_name"] == "John Test", "Staff display name matches.")
			assert_true(s["transfer_number"] == "555-1234", "Staff phone matches.")
			assert_true(s["menu_digit"] == "1", "Staff menu digit matches.")
			assert_true(s["ring_timeout"] == 25, "Staff timeout matches.")
	assert_true(staff_found, "Staff directory item recovered in query.")

	# Test 6: Recursive Flat Compiler compilation logic
	var sync_svc = GatewaySyncServiceScript.new(db, null)
	
	# Setup test tree nodes
	db.execute("DELETE FROM ivr_menu_nodes;")
	
	# Node 1: Root submenu (Key 1)
	com_service.save_ivr_menu_node(null, null, "1", "Info Submenu", "submenu", "", "Script text welcome", null, true, 0)
	var root_node_res = db.execute("SELECT id FROM ivr_menu_nodes WHERE digit = '1' LIMIT 1;")
	var root_node_id = int(root_node_res["data"][0]["id"])
	
	# Node 2: Child speak under Root (Key 1-2)
	com_service.save_ivr_menu_node(null, root_node_id, "2", "Address", "speak", "", "We are at 206 Williamston Road", null, true, 0)
	
	# Node 3: Child Staff Directory under Root (Key 1-3)
	com_service.save_ivr_menu_node(null, root_node_id, "3", "Directory", "staff_directory", "", "", null, true, 0)

	var active_staff = [{"display_name": "John Test", "menu_digit": "1"}]
	var compiled_options = {}
	
	var all_nodes_res = db.execute("SELECT * FROM ivr_menu_nodes;")
	var all_nodes = all_nodes_res["data"]
	var target_root = all_nodes[0]
	for n in all_nodes:
		if n["digit"] == "1":
			target_root = n
			
	sync_svc._compile_node_recursive(target_root, all_nodes, "", compiled_options, active_staff, com_service)
	
	# Assert flattened paths
	assert_true(compiled_options.has("1"), "Root path '1' compiled.")
	assert_true(compiled_options["1"]["action_type"] == "submenu", "Root path action compiles to submenu.")
	
	assert_true(compiled_options.has("1-2"), "Nested path '1-2' compiled.")
	assert_true(compiled_options["1-2"]["action_type"] == "speak", "Nested path '1-2' type verified.")
	assert_true(compiled_options["1-2"]["script_text"] == "We are at 206 Williamston Road", "Nested path '1-2' script content verified.")
	
	assert_true(compiled_options.has("1-3"), "Staff Directory path '1-3' compiled.")
	assert_true(compiled_options["1-3"]["action_type"] == "submenu", "Staff Directory node compiles to submenu type.")
	assert_true(compiled_options.has("1-3-1"), "Dynamic Staff member John path '1-3-1' compiled.")
	assert_true(compiled_options["1-3-1"]["action_type"] == "transfer_staff", "Dynamic Staff routing type verified.")
	assert_true(compiled_options["1-3-1"]["action_param"] == "John Test", "Dynamic Staff routing target parameter verified.")

	print("==========================================================")
	print("SUCCESS: ALL ADVANCED PHONE & IVR SYSTEM OBJECTIVES PASSED")
	print("==========================================================")
	quit(0)

func assert_true(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		print("FAIL: ", msg)
		quit(1)
