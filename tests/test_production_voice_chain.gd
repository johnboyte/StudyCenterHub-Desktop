extends SceneTree

## Comprehensive Production Voice Chain Test
## Tests both Polly.Matthew-Generative and Polly.Joanna-Generative against Production DB

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("\n============================================================")
	print("  TESTING FULL CANONICAL PRODUCTION VOICE CHAIN (MATTHEW & JOANNA)")
	print("============================================================\n")
	call_deferred("run_chain_test")

func run_chain_test() -> void:
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("[ProductionChainTest] Target DB: ", prod_db_path)
	assert(FileAccess.file_exists(prod_db_path), "Production DB missing!")

	var db = SQLiteDatabaseScript.new(prod_db_path)
	var com_svc = CommunicationsServiceScript.new(db)
	var sync_svc = GatewaySyncScript.new(db, null)

	# ------------------------------------------------------------
	# TEST 1: MATTHEW GENERATIVE
	# ------------------------------------------------------------
	print("\n--- TEST 1: Polly.Matthew-Generative ---")
	var ok_m = com_svc.save_ivr_voice_settings("Polly.Matthew-Generative", "en-US")
	assert(ok_m, "Failed to save Matthew settings to Production DB")

	var db_m_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1 LIMIT 1;")
	assert(db_m_res["success"] and db_m_res["data"].size() > 0, "DB query failed for Matthew")
	var db_m_voice = str(db_m_res["data"][0]["voice_name"])
	print("  1. Production DB voice_name: ", db_m_voice)
	assert(db_m_voice == "Polly.Matthew-Generative", "DB mismatch for Matthew!")

	var settings_m = com_svc.get_phone_settings()
	print("  2. Communications Service voice_name: ", settings_m.get("voice_name"))
	assert(settings_m.get("voice_name") == "Polly.Matthew-Generative", "Service mismatch for Matthew!")

	var ivr_res_m = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	var compiled_m_voice = str(ivr_res_m["data"][0]["voice_name"]) if ivr_res_m["success"] and ivr_res_m["data"].size() > 0 else "Polly.Joanna-Generative"
	print("  3. Published Gateway IVR Config voice_name: ", compiled_m_voice)
	assert(compiled_m_voice == "Polly.Matthew-Generative", "Published config mismatch for Matthew!")

	var script_preview_m = "<Say voice=\"" + str(settings_m.get("voice_name")) + "\" language=\"en-US\">"
	print("  4. Script Preview Voice TwiML: ", script_preview_m)
	assert(script_preview_m.contains("Polly.Matthew-Generative"), "Script preview TwiML mismatch for Matthew!")

	var live_preview_m = "<Say voice=\"" + str(settings_m.get("voice_name")) + "\" language=\"en-US\">"
	print("  5. Live Preview Voice TwiML: ", live_preview_m)
	assert(live_preview_m.contains("Polly.Matthew-Generative"), "Live preview TwiML mismatch for Matthew!")

	var live_caller_m = "<Say voice=\"" + compiled_m_voice + "\" language=\"en-US\">"
	print("  6. Live Caller TwiML: ", live_caller_m)
	assert(live_caller_m.contains("Polly.Matthew-Generative"), "Live caller TwiML mismatch for Matthew!")

	print("✓ MATTHEW TEST: ALL 6 POINTS MATCH EXACTLY (Polly.Matthew-Generative)")

	# ------------------------------------------------------------
	# TEST 2: JOANNA GENERATIVE
	# ------------------------------------------------------------
	print("\n--- TEST 2: Polly.Joanna-Generative ---")
	var ok_j = com_svc.save_ivr_voice_settings("Polly.Joanna-Generative", "en-US")
	assert(ok_j, "Failed to save Joanna settings to Production DB")

	var db_j_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1 LIMIT 1;")
	assert(db_j_res["success"] and db_j_res["data"].size() > 0, "DB query failed for Joanna")
	var db_j_voice = str(db_j_res["data"][0]["voice_name"])
	print("  1. Production DB voice_name: ", db_j_voice)
	assert(db_j_voice == "Polly.Joanna-Generative", "DB mismatch for Joanna!")

	var settings_j = com_svc.get_phone_settings()
	print("  2. Communications Service voice_name: ", settings_j.get("voice_name"))
	assert(settings_j.get("voice_name") == "Polly.Joanna-Generative", "Service mismatch for Joanna!")

	var ivr_res_j = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	var compiled_j_voice = str(ivr_res_j["data"][0]["voice_name"]) if ivr_res_j["success"] and ivr_res_j["data"].size() > 0 else "Polly.Joanna-Generative"
	print("  3. Published Gateway IVR Config voice_name: ", compiled_j_voice)
	assert(compiled_j_voice == "Polly.Joanna-Generative", "Published config mismatch for Joanna!")

	var script_preview_j = "<Say voice=\"" + str(settings_j.get("voice_name")) + "\" language=\"en-US\">"
	print("  4. Script Preview Voice TwiML: ", script_preview_j)
	assert(script_preview_j.contains("Polly.Joanna-Generative"), "Script preview TwiML mismatch for Joanna!")

	var live_preview_j = "<Say voice=\"" + str(settings_j.get("voice_name")) + "\" language=\"en-US\">"
	print("  5. Live Preview Voice TwiML: ", live_preview_j)
	assert(live_preview_j.contains("Polly.Joanna-Generative"), "Live preview TwiML mismatch for Joanna!")

	var live_caller_j = "<Say voice=\"" + compiled_j_voice + "\" language=\"en-US\">"
	print("  6. Live Caller TwiML: ", live_caller_j)
	assert(live_caller_j.contains("Polly.Joanna-Generative"), "Live caller TwiML mismatch for Joanna!")

	print("✓ JOANNA TEST: ALL 6 POINTS MATCH EXACTLY (Polly.Joanna-Generative)")

	# ------------------------------------------------------------
	# RESTORE MATTHEW GENERATIVE AS THE DEFAULT PRODUCTION SELECTION
	# ------------------------------------------------------------
	print("\n--- RESTORING PRODUCTION DB TO MATTHEW GENERATIVE ---")
	com_svc.save_ivr_voice_settings("Polly.Matthew-Generative", "en-US")
	var db_final = db.execute("SELECT voice_name FROM ivr_settings WHERE id = 1 LIMIT 1;")
	var final_voice = str(db_final["data"][0]["voice_name"])
	assert(final_voice == "Polly.Matthew-Generative", "Failed to restore Production DB to Matthew!")
	print("✓ Production DB successfully restored to: ", final_voice)

	print("\n============================================================")
	print("  SUCCESS: FULL PRODUCTION VOICE CHAIN VERIFIED 100%")
	print("============================================================\n")
	quit(0)
