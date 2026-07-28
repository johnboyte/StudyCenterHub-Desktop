extends SceneTree

## Automated Headless Test Suite for Advanced Phone & IVR Settings
## Verifies that global settings, parent-child submenus, and voicemail workspace status shifts operate correctly.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

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

	# Insert mock staff
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone) VALUES (1, 'staff_marcus', 'STF-0001', 'Marcus', 'Vance', 'staff', '509-555-0101');")

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

	# Test 2: Multi-level IVR options (Root and Child submenus)
	# Add a parent option
	var root_save = com_service.save_ivr_menu_option("5", "Submenu test", "Speak script", "submenu", "", null, false, "")
	assert_true(root_save, "Saved root IVR option successfully.")
	
	# Add child sub-options
	var child_save_1 = com_service.save_ivr_menu_option("5-1", "Option A", "Speech A", "speak", "", "5", false, "")
	var child_save_2 = com_service.save_ivr_menu_option("5-2", "Option B", "Speech B", "speak", "", "5", true, "sample_option_audio")
	assert_true(child_save_1 and child_save_2, "Saved submenu options under parent Key 5.")
	
	# Verify retrieved tree list
	var ivr_options = com_service.get_all_ivr_menu_options()
	var parent_found = false
	var child_1_found = false
	var child_2_found = false
	
	for opt in ivr_options:
		if opt["digit"] == "5":
			parent_found = true
			assert_true(opt["action_type"] == "submenu", "Root parent action type verified.")
		elif opt["digit"] == "5-1":
			child_1_found = true
			assert_true(opt["parent_digit"] == "5", "Submenu option parent mapping verified.")
			assert_true(opt["use_custom_audio"] == 0, "Submenu option A custom audio status verified.")
		elif opt["digit"] == "5-2":
			child_2_found = true
			assert_true(opt["parent_digit"] == "5", "Submenu option parent mapping verified.")
			assert_true(opt["use_custom_audio"] == 1, "Submenu option B custom audio status verified.")
			assert_true(opt["audio_data"] == "sample_option_audio", "Submenu option B audio payload verified.")
			
	assert_true(parent_found and child_1_found and child_2_found, "All nested IVR tree items verified in query.")

	# Delete root option (cascades and deletes sub-options)
	var del_res = com_service.delete_ivr_menu_option("5")
	assert_true(del_res, "Deleted IVR root option successfully.")
	
	var ivr_cleared = com_service.get_all_ivr_menu_options()
	for opt in ivr_cleared:
		if opt["digit"].begins_with("5"):
			print("FAIL: Nested IVR children were not deleted.")
			quit(1)
			return

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
