extends RefCounted

## Voicemail Inbox & Threaded Messaging Domain Service (COM-SPR1-002)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func record_voicemail_atomic(caller_name: String, caller_phone: String, duration_sec: int, transcription: String) -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var vm_uuid = "vm_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status) VALUES (?, ?, ?, ?, ?, 'new');",
		"args": [vm_uuid, caller_name, caller_phone, duration_sec, transcription]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "VoicemailReceived",
		"voicemail_uuid": vm_uuid,
		"caller_name": caller_name,
		"caller_phone": caller_phone,
		"duration_sec": duration_sec,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VoicemailReceived', 'Voicemail', ?, ?, ?, 'pending');",
		"args": [event_uuid, vm_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms}

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "voicemail_uuid": vm_uuid}

func get_voicemails() -> Array:
	var res = db.execute("SELECT voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status, created_at FROM voicemails ORDER BY id DESC;")
	if res["success"]:
		return res["data"]
	return []

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
