extends RefCounted

## Attendance Service for Check-In operations & Transactional Outbox Writes

var db

func _init(database) -> void:
	db = database

func record_check_in_atomic(person: Dictionary, method: String = "Manual", device_uuid: String = "dev_macbook_primary_node", session_id = null, mode: String = "Study Center Daily", shift_lead: String = "John Boyte") -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	
	db.execute("ALTER TABLE attendance_log ADD COLUMN session_id INTEGER DEFAULT NULL;")
	db.execute("ALTER TABLE attendance_log ADD COLUMN mode TEXT DEFAULT 'Study Center Daily';")
	db.execute("ALTER TABLE attendance_log ADD COLUMN shift_lead TEXT DEFAULT 'John Boyte';")

	var checkin_uuid = "chk_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	
	var person_id = int(person.get("id", 0))
	var person_uuid = String(person.get("person_uuid", ""))
	var human_id = String(person.get("human_id", ""))
	var check_in_date = Time.get_date_string_from_system()
	var check_in_time = Time.get_time_string_from_system()
	
	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "CheckInRecorded",
		"checkin_uuid": checkin_uuid,
		"person_uuid": person_uuid,
		"human_id": human_id,
		"person_id": person_id,
		"check_in_date": check_in_date,
		"check_in_time": check_in_time,
		"method": method,
		"session_id": session_id,
		"mode": mode,
		"shift_lead": shift_lead,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)
	
	var stmt1 = {
		"sql": "INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid, session_id, mode, shift_lead) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		"args": [checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid, session_id, mode, shift_lead]
	}
	
	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
		"args": [event_uuid, "CheckInRecorded", "Attendance", checkin_uuid, payload_json, device_uuid, "pending"]
	}
	
	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0
	
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms, "checkin": {}}
		
	return {
		"success": true,
		"error": "",
		"elapsed_ms": elapsed_ms,
		"checkin_uuid": checkin_uuid,
		"event_uuid": event_uuid,
		"person_uuid": person_uuid,
		"human_id": human_id
	}

func record_check_in_forced_failure(person: Dictionary, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	var checkin_uuid = "chk_fail_" + _generate_uuid()
	var person_id = int(person.get("id", 0))
	var person_uuid = String(person.get("person_uuid", ""))
	var human_id = String(person.get("human_id", ""))
	
	var stmt1 = {
		"sql": "INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
		"args": [checkin_uuid, person_id, person_uuid, human_id, Time.get_date_string_from_system(), Time.get_time_string_from_system(), "Manual", device_uuid]
	}
	
	# Deliberately invalid statement to trigger SQL constraint failure and transaction rollback
	var stmt2 = {
		"sql": "INSERT INTO INVALID_NONEXISTENT_TABLE (column_x) VALUES ('invalid')",
		"args": []
	}
	
	var tx_res = db.execute_transaction([stmt1, stmt2])
	return {
		"success": tx_res["success"],
		"error": tx_res["error"],
		"checkin_uuid": checkin_uuid
	}

func get_pending_outbox_count() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox WHERE status = 'pending';")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
