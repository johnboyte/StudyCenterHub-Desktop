extends RefCounted

## Legacy Pathways Domain Service (Real Life, Fellows, LEAD Tracks)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func get_person_legacy_pathway(person_id: int) -> Dictionary:
	var sql = "SELECT real_life_enrolled, fellows_enrolled, fellows_certificate, fellows_completions, lead_enrolled, lead_certificate, lead_current_year FROM legacy_pathway_tracks WHERE person_id = ?;"
	var res = db.execute(sql, [person_id])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {
		"real_life_enrolled": 0,
		"fellows_enrolled": 0,
		"fellows_certificate": 0,
		"fellows_completions": "[]",
		"lead_enrolled": 0,
		"lead_certificate": 0,
		"lead_current_year": "Year 1"
	}

func save_legacy_pathway_atomic(person: Dictionary, p_data: Dictionary) -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var person_id = int(person.get("id", 0))
	var person_uuid = str(person.get("person_uuid", ""))
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var real_life = int(p_data.get("real_life_enrolled", 0))
	var fellows_en = int(p_data.get("fellows_enrolled", 0))
	var fellows_cert = int(p_data.get("fellows_certificate", 0))
	var fellows_comp = str(p_data.get("fellows_completions", "[]"))
	var lead_en = int(p_data.get("lead_enrolled", 0))
	var lead_cert = int(p_data.get("lead_certificate", 0))
	var lead_year = str(p_data.get("lead_current_year", "Year 1"))

	var stmt1 = {
		"sql": """
			INSERT INTO legacy_pathway_tracks (person_id, real_life_enrolled, fellows_enrolled, fellows_certificate, fellows_completions, lead_enrolled, lead_certificate, lead_current_year, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
			ON CONFLICT(person_id) DO UPDATE SET
				real_life_enrolled = excluded.real_life_enrolled,
				fellows_enrolled = excluded.fellows_enrolled,
				fellows_certificate = excluded.fellows_certificate,
				fellows_completions = excluded.fellows_completions,
				lead_enrolled = excluded.lead_enrolled,
				lead_certificate = excluded.lead_certificate,
				lead_current_year = excluded.lead_current_year,
				updated_at = datetime('now');
		""",
		"args": [person_id, real_life, fellows_en, fellows_cert, fellows_comp, lead_en, lead_cert, lead_year]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PathwayProgressUpdated",
		"person_uuid": person_uuid,
		"real_life_enrolled": real_life,
		"fellows_enrolled": fellows_en,
		"fellows_certificate": fellows_cert,
		"lead_enrolled": lead_en,
		"lead_certificate": lead_cert,
		"lead_current_year": lead_year,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PathwayProgressUpdated', 'Pathways', ?, ?, ?, 'pending');",
		"args": [event_uuid, person_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms}

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "event_uuid": event_uuid}

func get_all_pathway_roster() -> Array:
	var sql = """
		SELECT p.id, p.person_uuid, p.human_id, p.first_name, p.last_name, p.status,
		       COALESCE(l.real_life_enrolled, 0) as real_life_enrolled,
		       COALESCE(l.fellows_enrolled, 0) as fellows_enrolled,
		       COALESCE(l.fellows_certificate, 0) as fellows_certificate,
		       COALESCE(l.fellows_completions, '[]') as fellows_completions,
		       COALESCE(l.lead_enrolled, 0) as lead_enrolled,
		       COALESCE(l.lead_certificate, 0) as lead_certificate,
		       COALESCE(l.lead_current_year, 'Year 1') as lead_current_year
		FROM people p
		LEFT JOIN legacy_pathway_tracks l ON l.person_id = p.id
		ORDER BY p.last_name ASC, p.first_name ASC;
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
