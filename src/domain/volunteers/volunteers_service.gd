extends RefCounted

## Volunteers & Shift Roster Domain Service (VOL-SPR1-001)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func assign_shift_atomic(person: Dictionary, session_id: int, shift_role: String = "Lead Tutor") -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()

	var shift_uuid = "shift_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()

	var person_id = int(person.get("id", 0))
	var person_uuid = str(person.get("person_uuid"))
	var first_name = str(person.get("first_name"))
	var last_name = str(person.get("last_name"))
	var volunteer_name = (first_name + " " + last_name).strip_edges()
	if volunteer_name == "": volunteer_name = str(person.get("human_id"))

	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "VolunteerShiftAssigned",
		"shift_uuid": shift_uuid,
		"session_id": session_id,
		"person_uuid": person_uuid,
		"volunteer_name": volunteer_name,
		"shift_role": shift_role,
		"device_uuid": device_uuid,
		"timestamp": timestamp
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt1 = {
		"sql": "INSERT INTO volunteer_shifts (shift_uuid, session_id, person_id, shift_role, status) VALUES (?, ?, ?, ?, 'assigned');",
		"args": [shift_uuid, session_id, person_id, shift_role]
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VolunteerShiftAssigned', 'Volunteers', ?, ?, ?, 'pending');",
		"args": [event_uuid, shift_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms, "shift_uuid": ""}

	return {
		"success": true,
		"error": "",
		"elapsed_ms": elapsed_ms,
		"shift_uuid": shift_uuid,
		"event_uuid": event_uuid
	}

func get_volunteers() -> Array:
	var res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, phone FROM people ORDER BY last_name ASC, first_name ASC;")
	if res["success"]:
		return res["data"]
	return []

func get_recent_shifts() -> Array:
	var sql = """
		SELECT vs.shift_uuid, vs.shift_role, vs.status, vs.assigned_at, p.first_name, p.last_name, p.human_id, s.title as session_title
		FROM volunteer_shifts vs
		JOIN people p ON p.id = vs.person_id
		LEFT JOIN sessions s ON s.id = vs.session_id
		ORDER BY vs.id DESC LIMIT 15;
	"""
	var res = db.execute(sql)
	if res["success"]:
		return res["data"]
	return []

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
