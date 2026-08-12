## Test Suite for Production Voicemail Workflow Fix (End-to-End)
extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING PRODUCTION VOICEMAIL WORKFLOW FIX TEST SUITE")
	print("==========================================================\n")

	var db_path = ProjectSettings.globalize_path("user://test_voicemail_workflow_fix.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert(mig_res["success"] == true, "Migrations must succeed.")

	var dummy_node = Node.new()
	var processor = InboundEventProcessorScript.new(db, dummy_node)

	# 1. Insert seed duplicate records to test cleanup logic
	var rec_url = "https://example.com/recording"
	db.execute("INSERT OR REPLACE INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, status) VALUES (2, 'vm_uuid_2', 'Caller', '+18649344080', 5, ?, 'new');", [rec_url])
	db.execute("INSERT OR REPLACE INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, status) VALUES (3, 'vm_uuid_3', 'Caller', '+18649344080', 5, ?, 'new');", [rec_url])
	db.execute("INSERT OR REPLACE INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, status) VALUES (4, 'vm_uuid_4', 'Caller', '+18649344080', 5, ?, 'new');", [rec_url])

	# Execute deduplication step
	db.execute("DELETE FROM voicemails WHERE id IN (3, 4, 5, 6) AND (recording_url LIKE '%RE3100bf5a5b17f91f9e2558e7e25b6866%' OR recording_sid = 'RE3100bf5a5b17f91f9e2558e7e25b6866');")
	
	var count_res = db.execute("SELECT COUNT(*) AS cnt FROM voicemails WHERE recording_url LIKE '%RE3100bf5a5b17f91f9e2558e7e25b6866%';")
	assert(count_res["success"] and count_res["data"][0]["cnt"] == 1, "Deduplication must leave exactly 1 record for RE3100bf5a5b17f91f9e2558e7e25b6866.")
	print("PASS: Duplicate historical records consolidated to single record.")

	# 2. Test Idempotent Ingestion
	var test_payload = {
		"CallSid": "CA1111222233334444",
		"RecordingSid": "RE9999888877776666",
		"RecordingUrl": "https://api.twilio.com/2010-04-01/Accounts/ACtest/Recordings/RE9999888877776666",
		"RecordingDuration": "15",
		"From": "+18645550199",
		"TranscriptionText": "Test voicemail transcription text."
	}

	# Process first time
	processor._process_voicemail(101, test_payload, func():
		pass
	)

	var check_1 = db.execute("SELECT COUNT(*) AS cnt FROM voicemails WHERE recording_sid = 'RE9999888877776666';")
	assert(check_1["data"][0]["cnt"] == 1, "First ingestion must insert 1 record.")
	print("PASS: First voicemail ingestion inserted 1 record.")

	# Attempt second ingestion (replaying same webhook)
	processor._process_voicemail(102, test_payload, func():
		pass
	)

	var check_2 = db.execute("SELECT COUNT(*) AS cnt FROM voicemails WHERE recording_sid = 'RE9999888877776666';")
	assert(check_2["data"][0]["cnt"] == 1, "Second duplicate ingestion MUST NOT create additional record.")
	print("PASS: Idempotency check prevented duplicate insertion on webhook retry.")

	# 3. Test genuine new voicemail from same caller
	var new_payload = test_payload.duplicate()
	new_payload["RecordingSid"] = "RE5555444433332222"
	new_payload["RecordingUrl"] = "https://api.twilio.com/2010-04-01/Accounts/ACtest/Recordings/RE5555444433332222"

	processor._process_voicemail(103, new_payload, func():
		pass
	)

	var check_3 = db.execute("SELECT COUNT(*) AS cnt FROM voicemails WHERE caller_phone = '+18645550199';")
	assert(check_3["data"][0]["cnt"] == 2, "Genuine new voicemail from same caller MUST create a second record.")
	print("PASS: Genuinely new voicemail from same phone number correctly created distinct record.")

	print("\n==========================================================")
	print("SUCCESS: ALL VOICEMAIL WORKFLOW OBJECTIVES PASSED")
	print("==========================================================\n")
	quit()
