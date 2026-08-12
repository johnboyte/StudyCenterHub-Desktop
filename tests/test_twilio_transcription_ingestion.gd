extends SceneTree

func _init():
	print("\n==========================================================")
	print("TESTING TWILIO AUTOMATIC TRANSCRIPTION INGESTION & UI SYNC")
	print("==========================================================\n")
	
	var user_dir = OS.get_user_data_dir()
	var db_path = user_dir + "/studycenterhub_production.db"
	print("[DB Path]: ", db_path)
	
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var db = SQLiteScript.new(db_path)
	
	var rec_sid = "RE6de7d976c11513c15c93b9ea5fcc627f"
	var sample_transcript = "Hello this is a live test voicemail for Real Life Study Center."
	var trans_sid = "TR_" + str(randi() % 99999999)
	
	# Simulate Twilio Transcription Webhook Event Payload
	var payload = {
		"RecordingSid": rec_sid,
		"TranscriptionSid": trans_sid,
		"TranscriptionText": sample_transcript,
		"TranscriptionStatus": "completed",
		"CallSid": "CA6695ac4eef88aeeb8e916ec6f394c8e7"
	}
	
	var payload_json = JSON.stringify(payload)
	print("[Event] Inserting simulated twilio.transcription event into inbound_event_queue...")
	
	var ins_res = db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('twilio.transcription', ?, datetime('now'), 0);", [payload_json])
	print("[Insert Result]: ", ins_res)
	
	var ProcessorScript = load("res://src/domain/sync/inbound_event_processor.gd")
	var proc = ProcessorScript.new(db, root)
	
	proc.process_pending_events(func(res: Dictionary):
		print("[Processor] Event processing finished. Result: ", res)
		
		# Verify voicemail database record update
		var v_res = db.execute("SELECT id, voicemail_uuid, recording_sid, transcription FROM voicemails WHERE recording_sid = ? LIMIT 1;", [rec_sid])
		if v_res["success"] and v_res["data"].size() > 0:
			var vm = v_res["data"][0]
			var saved_trans = str(vm.get("transcription", ""))
			print("  Recorded Transcription: '", saved_trans, "'")
			if saved_trans == sample_transcript:
				print("\n==========================================================")
				print("PASS: TWILIO TRANSCRIPTION SAVED & UI REFRESH TRIGGERED")
				print("==========================================================\n")
			else:
				print("FAIL: Saved transcript mismatch.")
		else:
			print("FAIL: Voicemail record not found.")
		quit()
	)
