extends SceneTree

func _init():
	print("\n==========================================================")
	print("TESTING IN-APP AUDIO PLAYBACK & TRANSCRIPTION FOR RECORD 66")
	print("==========================================================\n")
	
	var db_path = OS.get_user_data_dir() + "/studycenterhub_production.db"
	print("[DB] Loading production database from: ", db_path)
	
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var db = SQLiteScript.new(db_path)
	
	var res = db.execute("SELECT id, voicemail_uuid, caller_phone, duration_sec, recording_sid, recording_url, transcription FROM voicemails WHERE recording_sid = 'RE6de7d976c11513c15c93b9ea5fcc627f' LIMIT 1;")
	if not res["success"] or res["data"].size() == 0:
		print("FAIL: Record 66 not found in production DB.")
		quit()
		return
		
	var vm = res["data"][0]
	var rec_sid = str(vm.get("recording_sid", ""))
	var rec_url = str(vm.get("recording_url", ""))
	var vm_uuid = str(vm.get("voicemail_uuid", ""))
	var duration = int(vm.get("duration_sec", 0))
	
	print("[Record 66] Found Voicemail Record:")
	print("  ID: ", vm["id"])
	print("  UUID: ", vm_uuid)
	print("  Phone: ", vm["caller_phone"])
	print("  Duration: ", duration, " seconds")
	print("  RecordingSid: ", rec_sid)
	
	var ProcessorScript = load("res://src/domain/sync/inbound_event_processor.gd")
	var proc = ProcessorScript.new(db, root)
	var gemini_key = proc.get_gemini_api_key()
	print("  Gemini Key Configured: ", ("YES (len: " + str(gemini_key.length()) + ")") if gemini_key != "" else "NO")
	
	# Test Transcription Request
	print("\n[Transcription] Initiating background transcription...")
	if gemini_key != "":
		proc._call_gemini_transcribe(gemini_key, rec_url, func(trans_text: String):
			print("[Transcription Result]: ", trans_text)
			if trans_text != "" and not trans_text.begins_with("[Transcription failed"):
				db.execute("UPDATE voicemails SET transcription = ? WHERE voicemail_uuid = ?;", [trans_text, vm_uuid])
				print("PASS: Transcript saved to production SQLite DB for Record 66.")
			quit()
		)
	else:
		print("WARN: Gemini API key missing in environment/settings. Skipping live API call.")
		quit()
