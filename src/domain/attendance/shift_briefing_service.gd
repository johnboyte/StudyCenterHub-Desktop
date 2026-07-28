extends RefCounted

## Supervisor End-of-Shift Briefing Domain Service (ATT-SPR1-002)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func log_shift_brief_atomic(leader_name: String, summary_notes: String, incident_count: int = 0) -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var brief_uuid = "brief_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var shift_date = Time.get_date_string_from_system()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "INSERT INTO shift_briefings (briefing_uuid, leader_name, shift_date, summary_notes, incident_count, status) VALUES (?, ?, ?, ?, ?, 'submitted');",
		"args": [brief_uuid, leader_name, shift_date, summary_notes, incident_count]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "ShiftBriefLogged",
		"briefing_uuid": brief_uuid,
		"leader_name": leader_name,
		"shift_date": shift_date,
		"summary_notes": summary_notes,
		"incident_count": incident_count,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ShiftBriefLogged', 'ShiftBriefing', ?, ?, ?, 'pending');",
		"args": [event_uuid, brief_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms}

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "briefing_uuid": brief_uuid}

func get_recent_briefings(limit: int = 10) -> Array:
	var res = db.execute("SELECT briefing_uuid, leader_name, shift_date, summary_notes, incident_count, created_at FROM shift_briefings ORDER BY id DESC LIMIT ?;", [limit])
	if res["success"]:
		return res["data"]
	return []

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
