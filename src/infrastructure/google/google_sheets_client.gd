extends RefCounted

## Customer-Owned Google Sheets Provisioner & Data Adapter
## AP-001 Compliant: Provisions business workbooks with business headings.
## Idempotent: Uses Person UUID and Check-In UUID as primary keys to prevent duplicate rows.

var api_adapter: RefCounted
var drive_client: RefCounted

# Persistent mock spreadsheet data stores for testing
var _sheets_store: Dictionary = {}

func _init(adapter: RefCounted, drive: RefCounted) -> void:
	api_adapter = adapter
	drive_client = drive

func provision_workbooks() -> Dictionary:
	if not api_adapter.is_authorized:
		return {"success": false, "error": "Google Workspace not authorized."}
	if not api_adapter.is_online:
		return {"success": false, "error": "Network unavailable."}

	var drive_res = drive_client.provision_customer_drive_structure()
	if not drive_res["success"]:
		return drive_res

	# 1. Provision Directory Workbook
	var dir_sheet_id = _get_or_create_workbook(
		"StudyCenterHub Directory",
		drive_res["directory_folder_id"],
		["Person UUID", "Human ID", "First Name", "Last Name", "Profile Status", "Birthday", "SMS Consent", "Profile Photo URL", "Created At", "Updated At", "Source Device UUID", "Last Event UUID"]
	)

	# 2. Provision Attendance Workbook
	var att_sheet_id = _get_or_create_workbook(
		"StudyCenterHub Attendance",
		drive_res["attendance_folder_id"],
		["Check-In UUID", "Person UUID", "Human ID", "Check-In Timestamp", "Check-In Method", "Source Device UUID", "Event UUID", "Synced At"]
	)

	return {
		"success": true,
		"error": "",
		"directory_sheet_id": dir_sheet_id,
		"attendance_sheet_id": att_sheet_id
	}

func sync_person_record(sheet_id: String, person_data: Dictionary, event_uuid: String) -> Dictionary:
	if not api_adapter.is_online:
		return {"success": false, "error": "Network unavailable."}

	var person_uuid = person_data.get("person_uuid", "")
	if person_uuid == "":
		return {"success": false, "error": "Missing Person UUID."}

	var rows = _sheets_store.get(sheet_id, [])
	var found_index = -1
	for i in range(1, rows.size()):
		if rows[i].size() > 0 and rows[i][0] == person_uuid:
			found_index = i
			break

	var row_data = [
		person_uuid,
		person_data.get("human_id", ""),
		person_data.get("first_name", ""),
		person_data.get("last_name", ""),
		"Clear",
		person_data.get("birthday", ""),
		str(int(person_data.get("sms_consent", 1))),
		person_data.get("profile_photo_url", ""),
		person_data.get("created_at", ""),
		Time.get_datetime_string_from_system(),
		person_data.get("device_uuid", "dev_primary_node"),
		event_uuid
	]

	if found_index != -1:
		rows[found_index] = row_data
	else:
		rows.append(row_data)

	_sheets_store[sheet_id] = rows
	return {"success": true, "error": "", "action": "updated" if found_index != -1 else "appended"}

func sync_checkin_record(sheet_id: String, checkin_data: Dictionary, event_uuid: String) -> Dictionary:
	if not api_adapter.is_online:
		return {"success": false, "error": "Network unavailable."}

	var checkin_uuid = checkin_data.get("checkin_uuid", "")
	if checkin_uuid == "":
		return {"success": false, "error": "Missing Check-In UUID."}

	var rows = _sheets_store.get(sheet_id, [])
	var found_index = -1
	for i in range(1, rows.size()):
		if rows[i].size() > 0 and rows[i][0] == checkin_uuid:
			found_index = i
			break

	var row_data = [
		checkin_uuid,
		checkin_data.get("person_uuid", ""),
		checkin_data.get("human_id", ""),
		checkin_data.get("check_in_date", "") + " " + checkin_data.get("check_in_time", ""),
		checkin_data.get("method", "Manual"),
		checkin_data.get("device_uuid", "dev_primary_node"),
		event_uuid,
		Time.get_datetime_string_from_system()
	]

	if found_index != -1:
		rows[found_index] = row_data
	else:
		rows.append(row_data)

	_sheets_store[sheet_id] = rows
	return {"success": true, "error": "", "action": "updated" if found_index != -1 else "appended"}

func get_sheet_rows(sheet_id: String) -> Array:
	return _sheets_store.get(sheet_id, [])

func _get_or_create_workbook(title: String, folder_id: String, headers: Array) -> String:
	var key = folder_id + "/" + title
	if _sheets_store.has(key + "_id"):
		return _sheets_store[key + "_id"]

	var sheet_id = "sheet_" + _generate_uuid()
	_sheets_store[key + "_id"] = sheet_id
	_sheets_store[sheet_id] = [headers]
	return sheet_id

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
