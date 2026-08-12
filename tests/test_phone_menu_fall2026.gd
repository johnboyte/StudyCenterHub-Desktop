extends SceneTree

## Automated Headless Test Suite for Fall 2026 Real Life House Phone Menu & Scripts
## Verifies 6-option structure (Keys 1-5 TTS, Key 6 Voicemail, Main Greeting persistence).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING FALL 2026 PHONE MENU & SCRIPTS TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_fall2026_phone_menu.db")
	
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("test_fall2026_phone_menu.db"):
		dir.remove("test_fall2026_phone_menu.db")

	var db = SQLiteDatabaseScript.new(db_path)
	
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	var com_service = CommunicationsServiceScript.new(db)
	
	# Verify Main Greeting
	var phone_settings = com_service.get_phone_settings()
	var greeting_txt = phone_settings.get("automated_greeter_tts", "")
	assert_true(greeting_txt.contains("Thank you for calling Real Life House"), "Main Greeting begins with 'Thank you for calling Real Life House'.")
	assert_true(greeting_txt.contains("Come in. Sit down. Stay awhile."), "Main Greeting ends with 'Come in. Sit down. Stay awhile.'.")

	var options = com_service.get_all_ivr_menu_options()
	assert_true(options.size() == 6, "Phone menu has exactly 6 configured options.")
	
	var expected_menu = {
		"1": {"name": "Hours & What’s Happening", "action": "speak", "snippet": "getting ready to welcome students for the Fall 2026 semester"},
		"2": {"name": "Real Life Sundays", "action": "speak", "snippet": "meets Sunday evenings beginning at 7:45 PM"},
		"3": {"name": "About Real Life House", "action": "speak", "snippet": "Christian Study Center and Hospitality House"},
		"4": {"name": "Get Involved", "action": "speak", "snippet": "volunteering at the House"},
		"5": {"name": "Location & Website", "action": "speak", "snippet": "206 Williamston Road in Anderson, South Carolina"},
		"6": {"name": "Leave a Message", "action": "voicemail", "snippet": "We would love to hear from you."}
	}
	
	var options_map = {}
	for opt in options:
		options_map[str(opt["digit"])] = opt

	for digit in expected_menu.keys():
		var exp = expected_menu[digit]
		assert_true(options_map.has(digit), "Phone Key " + digit + " exists in database.")
		if options_map.has(digit):
			var item = options_map[digit]
			assert_true(str(item["menu_option_name"]) == exp["name"], "Key " + digit + " name is '" + exp["name"] + "'.")
			assert_true(str(item["action_type"]) == exp["action"], "Key " + digit + " action_type is '" + exp["action"] + "'.")
			assert_true(str(item["script_text"]).contains(exp["snippet"]), "Key " + digit + " script contains expected snippet.")

	# Verify reload after simulated navigation / database re-fetch
	var reload_db = SQLiteDatabaseScript.new(db_path)
	var reload_service = CommunicationsServiceScript.new(reload_db)
	var reload_settings = reload_service.get_phone_settings()
	assert_true(reload_settings.get("automated_greeter_tts", "").contains("Thank you for calling Real Life House"), "Re-fetched Main Greeting reloads cleanly from app database.")
	
	var reload_options = reload_service.get_all_ivr_menu_options()
	assert_true(reload_options.size() == 6, "Re-fetched Phone Key options size is 6.")

	# Verify transfer call option and transfer phone number are NOT present anywhere
	var transfer_query = db.execute("SELECT * FROM ivr_menu_options WHERE action_type = 'transfer' OR action_param LIKE '%509-555-0101%';")
	assert_true(transfer_query["success"] and transfer_query["data"].size() == 0, "No transfer options or emergency phone numbers exist in the phone menu.")

	print("==========================================================")
	print("SUCCESS: ALL FALL 2026 PHONE MENU & SCRIPTS OBJECTIVES PASSED")
	print("==========================================================")
	quit(0)

func assert_true(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		print("FAIL: ", msg)
		quit(1)
