extends SceneTree

## Automated Headless Test Suite for Extended Google Workspace Sync Subsystem
## Verifies that Kiosk event types sync correctly, profile photos upload to Drive, and extended columns sync to Sheets

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const GoogleApiAdapterScript = preload("res://src/infrastructure/google/google_api_adapter.gd")
const GoogleDriveClientScript = preload("res://src/infrastructure/google/google_drive_client.gd")
const GoogleSheetsClientScript = preload("res://src/infrastructure/google/google_sheets_client.gd")
const OutboxSyncWorkerScript = preload("res://src/domain/sync/outbox_sync_worker.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING GOOGLE WORKSPACE SYNC EXTENDED TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_sync_extended.db")
	
	# Delete existing test database file
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_sync_extended.db"):
		dir.remove("studycenterhub_test_sync_extended.db")

	var db = SQLiteDatabaseScript.new(db_path)
	
	# Run migrations
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	# Insert Kiosk Self-Registration event
	var reg_payload = {
		"person_uuid": "usr_sync_student_123",
		"human_id": "PRT-9099",
		"first_name": "Valerius",
		"last_name": "Gratus",
		"phone": "509-555-9999",
		"birthday": "2007-11-22",
		"sms_consent": 1,
		"profile_photo": "data:image/png;base64,sample_photo_stream"
	}
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES ('evt_reg_001', 'PARTICIPANT_REGISTERED', 'Directory', 'usr_sync_student_123', ?, 'kiosk_node', 'pending');",
		[JSON.stringify(reg_payload)])

	# Insert Kiosk Check-In event
	var chk_payload = {
		"person_uuid": "usr_sync_student_123",
		"checkin_uuid": "chk_sync_001",
		"check_in_date": "2026-07-22",
		"check_in_time": "15:30:00",
		"method": "Self Service PIN"
	}
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES ('evt_chk_001', 'PARTICIPANT_CHECKED_IN', 'Attendance', 'chk_sync_001', ?, 'kiosk_node', 'pending');",
		[JSON.stringify(chk_payload)])

	# Instantiate sheets and drive clients with local api adapter
	var api_adapter = GoogleApiAdapterScript.new()
	api_adapter.is_authorized = true
	api_adapter.is_online = true

	var drive_client = GoogleDriveClientScript.new(api_adapter)
	var sheets_client = GoogleSheetsClientScript.new(api_adapter, drive_client)
	var sync_worker = OutboxSyncWorkerScript.new(db, api_adapter, sheets_client)

	# Execute Outbox Sync
	var sync_res = sync_worker.process_pending_outbox()
	if not sync_res["success"]:
		print("FAIL: Sync worker process failed: ", sync_res["error"])
		quit(1)
		return
		
	if sync_res["processed_count"] != 2:
		print("FAIL: Expected 2 processed events, got: ", sync_res["processed_count"])
		quit(1)
		return
	print("PASS 1/3: Pending outbox events processed successfully.")

	# Verify sheet columns and rows
	var prov_res = sheets_client.provision_workbooks()
	var dir_sheet_id = prov_res["directory_sheet_id"]
	var att_sheet_id = prov_res["attendance_sheet_id"]
	
	var dir_rows = sheets_client.get_sheet_rows(dir_sheet_id)
	var att_rows = sheets_client.get_sheet_rows(att_sheet_id)
	
	# Verify Directory Headers
	var headers = dir_rows[0]
	if not "Birthday" in headers or not "SMS Consent" in headers or not "Profile Photo URL" in headers:
		print("FAIL: Directory sheets header missing extended fields: ", headers)
		quit(1)
		return
	print("PASS 2/3: Extended database columns correctly added to Sheets headers.")

	# Verify record values
	var student_row = dir_rows[1]
	# Birthday index is 5, SMS Consent index is 6, Profile Photo URL is 7
	if student_row[5] != "2007-11-22" or student_row[6] != "1" or not student_row[7].begins_with("https://drive.google.com/"):
		print("FAIL: Synced student row details mismatch: ", student_row)
		quit(1)
		return
	print("PASS 3/3: Profile photo uploaded to Drive and link synced to Sheets.")

	# Cleanup test db
	db = null
	if dir and dir.file_exists("studycenterhub_test_sync_extended.db"):
		dir.remove("studycenterhub_test_sync_extended.db")

	print("==========================================================")
	print("SUCCESS: GOOGLE WORKSPACE SYNC EXTENDED VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
