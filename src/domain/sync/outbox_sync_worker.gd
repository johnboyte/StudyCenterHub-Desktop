extends RefCounted

## Outbox Synchronization Worker for StudyCenterHub Next Generation
## Processes pending outbox events from SQLite and streams them to customer Google Sheets.
## AP-001 & AP-005 Compliant: Local writes complete instantly; sync flushes when online.
## Idempotent: Uses stable Event UUID and Entity UUIDs to prevent duplicate cloud records.

var db: RefCounted
var api_adapter: RefCounted
var sheets_client: RefCounted

var last_sync_time: String = "Never"
var last_sync_count: int = 0

func _init(database: RefCounted, adapter: RefCounted, sheets: RefCounted) -> void:
	db = database
	api_adapter = adapter
	sheets_client = sheets

func process_pending_outbox() -> Dictionary:
	if not api_adapter.is_authorized:
		return {"success": false, "error": "Saved on this device. Waiting for authorization.", "processed_count": 0}
	if not api_adapter.is_online:
		return {"success": false, "error": "Saved on this device. Waiting to sync.", "processed_count": 0}

	# Provision workbooks first if needed
	var prov_res = sheets_client.provision_workbooks()
	if not prov_res["success"]:
		return {"success": false, "error": prov_res["error"], "processed_count": 0}

	var dir_sheet_id = prov_res["directory_sheet_id"]
	var att_sheet_id = prov_res["attendance_sheet_id"]

	# Read pending outbox rows
	var query_res = db.execute("SELECT * FROM event_outbox WHERE status = 'pending' ORDER BY id ASC;")
	if not query_res["success"]:
		return {"success": false, "error": query_res["error"], "processed_count": 0}

	var pending_rows = query_res["data"]
	if pending_rows.size() == 0:
		return {"success": true, "error": "", "processed_count": 0}

	var processed_count = 0
	for row in pending_rows:
		var event_id = row.get("id")
		var event_uuid = row.get("event_uuid", "")
		var event_type = row.get("event_type", "")
		var payload_raw = row.get("payload_json", {})
		var payload: Dictionary = {}
		if typeof(payload_raw) == TYPE_DICTIONARY:
			payload = payload_raw
		elif typeof(payload_raw) == TYPE_STRING:
			var parsed = JSON.parse_string(payload_raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				payload = parsed
		
		if payload.is_empty():
			continue
			
		var sync_res = {"success": false}

		if event_type == "PersonCreated" or event_type == "PARTICIPANT_REGISTERED":
			var photo_base64 = String(payload.get("profile_photo")) if payload.get("profile_photo") != null else ""
			if photo_base64 != "":
				var drive_client = sheets_client.drive_client
				var photos_folder_id = ""
				var drive_prov_res = drive_client.provision_customer_drive_structure()
				if drive_prov_res["success"]:
					photos_folder_id = drive_prov_res.get("photos_folder_id", "")
				
				if photos_folder_id != "":
					var file_name = payload.get("first_name", "student") + "_" + payload.get("last_name", "photo") + "_" + event_uuid + ".png"
					var upload_res = drive_client.upload_profile_photo(photos_folder_id, file_name, photo_base64)
					if upload_res["success"]:
						payload["profile_photo_url"] = upload_res["web_view_link"]
			
			sync_res = sheets_client.sync_person_record(dir_sheet_id, payload, event_uuid)
		elif event_type == "CheckInRecorded" or event_type == "PARTICIPANT_CHECKED_IN":
			sync_res = sheets_client.sync_checkin_record(att_sheet_id, payload, event_uuid)
		else:
			# Unknown event type, mark processed to unblock outbox
			sync_res = {"success": true}

		if sync_res["success"]:
			db.execute("UPDATE event_outbox SET status = 'synchronized', processed_at = (datetime('now')) WHERE id = ?;", [event_id])
			processed_count += 1

	if processed_count > 0:
		last_sync_time = Time.get_datetime_string_from_system()
		last_sync_count = processed_count

	return {
		"success": true,
		"error": "",
		"processed_count": processed_count
	}
