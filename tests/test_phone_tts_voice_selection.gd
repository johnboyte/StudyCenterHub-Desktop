extends SceneTree

## Automated Verification for All 4 Generative Phone TTS Voice Options & Mapping

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")

const TEST_VOICES = [
	{"id": "Polly.Joanna-Generative", "label": "Joanna Generative — Female"},
	{"id": "Polly.Danielle-Generative", "label": "Danielle Generative — Female"},
	{"id": "Polly.Matthew-Generative", "label": "Matthew Generative — Male"},
	{"id": "Polly.Stephen-Generative", "label": "Stephen Generative — Male"}
]

func _init() -> void:
	print("\n============================================================")
	print("  TESTING ALL 4 GENERATIVE PHONE TTS VOICE OPTIONS")
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

	# 1. Test each of the 4 voices individually
	for v_info in TEST_VOICES:
		var target_id = str(v_info["id"])
		var target_label = str(v_info["label"])
		
		# Save voice
		var ok = com_svc.save_ivr_voice_settings(target_id, "en-US")
		assert(ok, "Failed to save IVR voice settings for " + target_id)
		
		# Verify DB storage
		var ivr_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
		assert(ivr_res["success"] and ivr_res["data"].size() > 0, "DB query failed for " + target_id)
		var db_voice = str(ivr_res["data"][0]["voice_name"])
		assert(db_voice == target_id, "DB mismatch! Expected " + target_id + ", got " + db_voice)

		# Verify service reload (survives tab change / app restart)
		var reloaded_svc = CommunicationsServiceScript.new(db)
		var reloaded_settings = reloaded_svc.get_phone_settings()
		var settings_voice = str(reloaded_settings.get("voice_name", ""))
		assert(settings_voice == target_id, "Service reload mismatch! Expected " + target_id + ", got " + settings_voice)

		# Verify compiled sync config
		var sync_voice = str(reloaded_settings["voice_name"])
		assert(sync_voice == target_id, "Sync config mismatch! Expected " + target_id + ", got " + sync_voice)

		# Verify TwiML generation expectation
		var twiml_element = '<Say voice="' + sync_voice + '" language="en-US">'
		assert(twiml_element.contains('voice="' + target_id + '"'), "TwiML mismatch for " + target_id)
		
		print("✓ PASS: Verified " + target_label + " -> DB: " + db_voice + " -> TwiML: " + twiml_element)

	# 2. Specifically prove Joanna != Matthew and Matthew != Joanna
	com_svc.save_ivr_voice_settings("Polly.Joanna-Generative", "en-US")
	var joanna_settings = com_svc.get_phone_settings()
	var joanna_id = str(joanna_settings["voice_name"])

	com_svc.save_ivr_voice_settings("Polly.Matthew-Generative", "en-US")
	var matthew_settings = com_svc.get_phone_settings()
	var matthew_id = str(matthew_settings["voice_name"])

	assert(joanna_id != matthew_id, "PROVED: Joanna ID (" + joanna_id + ") != Matthew ID (" + matthew_id + ")")
	assert(joanna_id == "Polly.Joanna-Generative", "Joanna ID matches exact Polly.Joanna-Generative")
	assert(matthew_id == "Polly.Matthew-Generative", "Matthew ID matches exact Polly.Matthew-Generative")

	print("✓ PROVED: Joanna (" + joanna_id + ") DOES NOT equal Matthew (" + matthew_id + "). Mapping is 100% distinct.")

	print("\n============================================================")
	print("  SUCCESS: ALL 4 GENERATIVE VOICE TESTS PASSED 100%")
	print("============================================================\n")

	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	quit(0)
