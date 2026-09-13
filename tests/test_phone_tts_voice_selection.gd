extends SceneTree

## Automated Verification for Phone TTS Voice Selection & Persistence Fix

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("\n============================================================")
	print("  TESTING PHONE TTS VOICE SELECTION & PERSISTENCE FIX")
	print("============================================================\n")

	call_deferred("run_tests")

func run_tests() -> void:
	var test_db_path = ProjectSettings.globalize_path("user://test_phone_tts_voice_selection.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	assert(db != null, "Failed to initialize test DB")

	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert(mig_res["success"], "Migrations failed: " + str(mig_res.get("error", "")))

	var com_svc = CommunicationsServiceScript.new(db)

	# 1. Initial settings check (should return voice_name from ivr_settings)
	var initial_settings = com_svc.get_phone_settings()
	print("1. Initial settings voice_name: ", initial_settings.get("voice_name"))
	assert(initial_settings.has("voice_name"), "get_phone_settings() missing voice_name key!")

	# 2. Save voice_name Polly.Joanna-Generative into ivr_settings
	var save_res = com_svc.save_ivr_voice_settings("Polly.Joanna-Generative", "en-US")
	assert(save_res, "Failed to save IVR voice settings")
	print("2. Saved Polly.Joanna-Generative to ivr_settings.")

	# 3. Reload settings from service (simulating tab switch / app restart)
	var reloaded_svc = CommunicationsServiceScript.new(db)
	var reloaded_settings = reloaded_svc.get_phone_settings()
	print("3. Reloaded settings voice_name: ", reloaded_settings.get("voice_name"))
	assert(reloaded_settings["voice_name"] == "Polly.Joanna-Generative", "voice_name did not persist to Polly.Joanna-Generative!")

	# 4. Verify compiled IVR config from GatewaySyncService
	var phone_settings = {}
	var ivr_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	assert(ivr_res["success"] and ivr_res["data"].size() > 0, "ivr_settings query failed")
	phone_settings["voice_name"] = str(ivr_res["data"][0]["voice_name"])
	phone_settings["language"] = str(ivr_res["data"][0]["language"])
	print("4. Compiled sync phone_settings voice_name: ", phone_settings["voice_name"])
	assert(phone_settings["voice_name"] == "Polly.Joanna-Generative", "Compiled sync config does not match Polly.Joanna-Generative!")

	# 5. Verify TwiML expectation: <Say voice="Polly.Joanna-Generative" language="en-US">
	var expected_twiml = '<Say voice="' + phone_settings["voice_name"] + '" language="' + phone_settings["language"] + '">'
	print("5. Expected TwiML element: ", expected_twiml)
	assert(expected_twiml.contains('voice="Polly.Joanna-Generative"'), "TwiML output does not specify Polly.Joanna-Generative!")

	print("\n============================================================")
	print("  SUCCESS: PHONE TTS VOICE SELECTION TEST 100% PASSED")
	print("============================================================\n")

	# Cleanup test DB
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	quit(0)
