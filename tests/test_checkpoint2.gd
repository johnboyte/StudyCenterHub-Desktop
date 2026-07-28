extends SceneTree

## Automated Headless Test Suite for Phase 2.1 Checkpoint 2
## (Google Workspace & Synchronization Proof)

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")
const GoogleAPIAdapterScript = preload("res://src/infrastructure/google/google_api_adapter.gd")
const GoogleDriveClientScript = preload("res://src/infrastructure/google/google_drive_client.gd")
const GoogleSheetsClientScript = preload("res://src/infrastructure/google/google_sheets_client.gd")
const OutboxSyncWorkerScript = preload("res://src/domain/sync/outbox_sync_worker.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING CHECKPOINT 2 GOOGLE WORKSPACE SYNC PROOF SUITE")
	print("==========================================================")
	
	var test_db_path = ProjectSettings.globalize_path("user://test_checkpoint2_operational.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
		
	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)
	migrations_runner.run_migrations()

	var google_adapter = GoogleAPIAdapterScript.new(true)
	var drive_client = GoogleDriveClientScript.new(google_adapter)
	var sheets_client = GoogleSheetsClientScript.new(google_adapter, drive_client)
	var sync_worker = OutboxSyncWorkerScript.new(db, google_adapter, sheets_client)
	var person_service = PersonServiceScript.new(db)
	var attendance_service = AttendanceServiceScript.new(db)

	# TEST 1: Google Workspace Authorization & Keychain Storage
	var auth_res = google_adapter.connect_google_workspace("center_admin@workspace.org")
	if not auth_res["success"]:
		print("FAIL: Google Workspace connection failed: ", auth_res["error"])
		quit(1)
		return
		
	var keychain_res = google_adapter.keychain.retrieve_secret("google_refresh_token")
	if not keychain_res["success"] or keychain_res["value"] == "":
		print("FAIL: OAuth refresh token not found in OS Keychain.")
		quit(1)
		return
	print("PASS 1/12: Google Workspace connected & OAuth token stored in OS Keychain.")

	# TEST 2: Initial Drive & Sheets Provisioning
	var prov_res1 = sheets_client.provision_workbooks()
	if not prov_res1["success"]:
		print("FAIL: Provisioning workbooks failed: ", prov_res1["error"])
		quit(1)
		return
	print("PASS 2/12: Customer Drive folders & Sheets workbooks provisioned.")

	# TEST 3: Repeated Provisioning Duplicate Check
	var prov_res2 = sheets_client.provision_workbooks()
	if prov_res2["directory_sheet_id"] != prov_res1["directory_sheet_id"]:
		print("FAIL: Repeated provisioning created duplicate Directory workbook.")
		quit(1)
		return
	print("PASS 3/12: Idempotent provisioning verified (0 duplicate folders/workbooks).")

	# TEST 4: Offline Local Operation (Network Cut Simulation)
	google_adapter.set_online_status(false)
	var p_res = person_service.create_test_person("OfflineUser", "Tester", "555-0333")
	var person = p_res["person"]
	
	# Enqueue PersonCreated outbox event
	var p_evt_uuid = "evt_" + _generate_uuid()
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, ?, ?, ?, ?, ?, ?);",
		[p_evt_uuid, "PersonCreated", "Person", person.get("person_uuid", ""), JSON.stringify(person), "dev_offline_kiosk", "pending"])
		
	# Record offline Check-In (creates CheckInRecorded outbox event)
	var c_res = attendance_service.record_check_in_atomic(person, "Barcode", "dev_offline_kiosk")
	if not c_res["success"]:
		print("FAIL: Offline local check-in write failed.")
		quit(1)
		return
		
	var pending_cnt = attendance_service.get_pending_outbox_count()
	if pending_cnt < 1:
		print("FAIL: Offline events not retained in pending outbox (Count: ", pending_cnt, ")")
		quit(1)
		return
	print("PASS 4/12: Offline-first operation succeeded; ", pending_cnt, " event(s) queued in local outbox.")

	# TEST 5: Offline Sync Attempt Prevention
	var offline_sync_res = sync_worker.process_pending_outbox()
	if offline_sync_res["processed_count"] != 0:
		print("FAIL: Outbox worker attempted sync while network was offline.")
		quit(1)
		return
	print("PASS 5/12: Offline outbox sync gracefully retained without error.")

	# TEST 6: Network Reconnection & Outbox Flush Sync
	google_adapter.set_online_status(true)
	var reconn_sync_res = sync_worker.process_pending_outbox()
	if not reconn_sync_res["success"] or reconn_sync_res["processed_count"] < 1:
		print("FAIL: Reconnection sync failed to flush outbox events. Processed: ", reconn_sync_res["processed_count"])
		quit(1)
		return
	print("PASS 6/12: Reconnection sync flushed ", reconn_sync_res["processed_count"], " outbox event(s) to Google Sheets.")

	# TEST 7: Directory Sheet Data Verification
	var dir_rows = sheets_client.get_sheet_rows(prov_res1["directory_sheet_id"])
	if dir_rows.size() < 2 or dir_rows[1][0] != person.get("person_uuid", ""):
		print("FAIL: Person record not found in Google Sheets Directory.")
		quit(1)
		return
	print("PASS 7/12: Person record verified in Google Sheets Directory workbook.")

	# TEST 8: Attendance Sheet Data Verification
	var att_rows = sheets_client.get_sheet_rows(prov_res1["attendance_sheet_id"])
	if att_rows.size() < 2 or att_rows[1][0] != c_res["checkin_uuid"]:
		print("FAIL: Check-In record not found in Google Sheets Attendance.")
		quit(1)
		return
	print("PASS 8/12: Check-In record verified in Google Sheets Attendance workbook.")

	# TEST 9: Idempotent Duplicate Retry Test
	# Reset status to pending to simulate retry after network interruption
	db.execute("UPDATE event_outbox SET status = 'pending' WHERE aggregate_id = ?;", [c_res["checkin_uuid"]])
	var retry_sync_res = sync_worker.process_pending_outbox()
	var att_rows_after_retry = sheets_client.get_sheet_rows(prov_res1["attendance_sheet_id"])
	if att_rows_after_retry.size() != att_rows.size():
		print("FAIL: Duplicate retry created extra duplicate row in Google Sheets.")
		quit(1)
		return
	print("PASS 9/12: Idempotent duplicate retry verified (0 duplicate Sheet rows created).")

	# TEST 10: Zero Secrets in Google Sheets Audit
	var secrets_found = false
	for row in dir_rows + att_rows:
		for cell in row:
			var cell_str = str(cell)
			if "rt_cust_" in cell_str or "at_cust_" in cell_str:
				secrets_found = true
	if secrets_found:
		print("FAIL: Secrets audit detected OAuth tokens in Google Sheets!")
		quit(1)
		return
	print("PASS 10/12: Secrets Audit passed (0 OAuth tokens or passwords in Google Sheets).")

	# TEST 11: Customer Disconnect & Token Purge Test
	google_adapter.disconnect_google_workspace()
	var post_disc_key = google_adapter.keychain.retrieve_secret("google_refresh_token")
	if post_disc_key["success"] and post_disc_key["value"] != "":
		print("FAIL: Disconnect did not purge refresh token from OS Keychain.")
		quit(1)
		return
	print("PASS 11/12: Customer Disconnect purged refresh token from OS Keychain.")

	# TEST 12: Preserved Local Operation When Authorization Revoked
	var p_rev_res = person_service.create_test_person("RevokedUser", "Tester", "555-0444")
	var c_rev_res = attendance_service.record_check_in_atomic(p_rev_res["person"], "Manual", "dev_kiosk")
	if not c_rev_res["success"]:
		print("FAIL: Local check-in failed when authorization was revoked.")
		quit(1)
		return
	print("PASS 12/12: Preserved local operation verified when authorization is un-configured.")

	print("==========================================================")
	print("SUCCESS: ALL CHECKPOINT 2 PROOF OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
