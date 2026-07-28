extends RefCounted

## Pastoral Care & Sensitive Notes Domain Service (PAST-SPR1-001)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-009] (Role-Based Access Control).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func create_pastoral_note_atomic(person: Dictionary, author: String, body: String, note_type: String = "Pastoral Care", sensitivity: String = "High") -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var person_id = int(person.get("id", 0))
	var person_uuid = str(person.get("person_uuid", ""))
	var note_uuid = "pnote_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "INSERT INTO pastoral_notes (note_uuid, person_id, author_user, note_type, body, sensitivity_level) VALUES (?, ?, ?, ?, ?, ?);",
		"args": [note_uuid, person_id, author, note_type, body, sensitivity]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PastoralNoteAdded",
		"note_uuid": note_uuid,
		"person_uuid": person_uuid,
		"author_user": author,
		"note_type": note_type,
		"sensitivity_level": sensitivity,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PastoralNoteAdded', 'PastoralCare', ?, ?, ?, 'pending');",
		"args": [event_uuid, note_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms, "note_uuid": ""}

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "note_uuid": note_uuid, "event_uuid": event_uuid}

func get_pastoral_notes_for_person(person_id: int) -> Array:
	var sql = "SELECT note_uuid, author_user, note_type, body, sensitivity_level, created_at FROM pastoral_notes WHERE person_id = ? ORDER BY id DESC;"
	var res = db.execute(sql, [person_id])
	if res["success"]:
		return res["data"]
	return []

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
