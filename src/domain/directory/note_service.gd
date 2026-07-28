extends RefCounted

## Note Service for StudyCenterHub Person Workspace Notes Sub-system
## Handles read queries and mutation commands for configurable Note Types and Person Notes.
## Complies with [PD-001] (Offline Storage & Outbox), [PD-002] (Read Isolation), [PD-006] (Feature Visibility), and [PD-007] (Admin Configuration First).

var db

func _init(database) -> void:
	db = database

# ==============================================================================
# READ SERVICE METHODS (PD-002 Compliance)
# ==============================================================================

## Retrieves all active, organization-enabled Note Types ordered by display_order
func get_note_types(options: Dictionary = {}) -> Dictionary:
	var include_inactive = options.get("include_inactive", false)
	var sql = "SELECT * FROM note_types WHERE 1=1"
	if not include_inactive:
		sql += " AND is_active = 1 AND org_visible = 1 AND org_enabled = 1"
	sql += " ORDER BY display_order ASC, name ASC;"

	var res = db.execute(sql)
	if not res["success"]:
		return {"success": false, "error": res["error"], "note_types": []}
	return {"success": true, "error": "", "note_types": res["data"]}

## Retrieves all active person notes for a constituent with Note Type details joined
func get_person_notes(person_uuid: String, options: Dictionary = {}) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "notes": []}

	var sql = """
		SELECT pn.*, nt.name as note_type_name, nt.display_order as note_type_display_order
		FROM person_notes pn
		JOIN note_types nt ON pn.note_type_uuid = nt.type_uuid
		WHERE pn.person_uuid = ?
		  AND pn.is_deleted = 0
		  AND nt.is_active = 1
		  AND nt.org_visible = 1
		  AND nt.org_enabled = 1
		ORDER BY nt.display_order ASC, pn.created_at DESC, pn.id DESC;
	"""
	var res = db.execute(sql, [person_uuid])
	if not res["success"]:
		return {"success": false, "error": res["error"], "notes": []}
	return {"success": true, "error": "", "notes": res["data"]}

## Retrieves notes grouped by Note Type, including empty arrays for active Note Types without notes
func get_person_notes_grouped(person_uuid: String, options: Dictionary = {}) -> Dictionary:
	var types_res = get_note_types(options)
	if not types_res["success"]:
		return {"success": false, "error": types_res["error"], "groups": []}

	var notes_res = get_person_notes(person_uuid, options)
	if not notes_res["success"]:
		return {"success": false, "error": notes_res["error"], "groups": []}

	var notes_by_type = {}
	for note in notes_res["notes"]:
		var t_uuid = note.get("note_type_uuid", "")
		if not notes_by_type.has(t_uuid):
			notes_by_type[t_uuid] = []
		notes_by_type[t_uuid].append(note)

	var groups = []
	for ntype in types_res["note_types"]:
		var t_uuid = ntype.get("type_uuid", "")
		var group_notes = notes_by_type.get(t_uuid, [])
		groups.append({
			"type_uuid": t_uuid,
			"name": ntype.get("name", "General Note"),
			"description": ntype.get("description", ""),
			"display_order": ntype.get("display_order", 0),
			"notes": group_notes
		})

	return {"success": true, "error": "", "groups": groups}

# ==============================================================================
# WRITE SERVICE METHODS (PD-001 Outbox Queueing)
# ==============================================================================

## Creates a new Person Note record and appends an outbox transaction event
func create_person_note(note_data: Dictionary) -> Dictionary:
	var person_uuid = String(note_data.get("person_uuid", ""))
	var note_type_uuid = String(note_data.get("note_type_uuid", "nt_general"))
	var body = String(note_data.get("body", "")).strip_edges()
	var title = String(note_data.get("title", "")).strip_edges()
	var visibility = String(note_data.get("visibility", "standard_staff"))

	if person_uuid == "":
		return {"success": false, "error": "person_uuid is required."}
	if body == "":
		return {"success": false, "error": "Note body content cannot be empty."}

	# Lookup person_id
	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [person_uuid])
	if not p_res["success"] or p_res["data"].size() == 0:
		return {"success": false, "error": "Person not found."}
	var person_id = p_res["data"][0]["id"]

	var note_uuid = "note_" + _generate_uuid_suffix()
	var timestamp = _get_utc_timestamp()

	var statements = []

	# 1. Insert note record
	statements.append({
		"sql": """
			INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
		""",
		"args": [note_uuid, person_id, person_uuid, note_type_uuid, title if title != "" else null, body, visibility, timestamp, timestamp]
	})

	# 2. Append to outbox_sync table if present, or event_outbox (PD-001)
	var outbox_sql = """
		INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?);
	"""
	var outbox_uuid = "evt_note_" + _generate_uuid_suffix()
	var payload = JSON.stringify({
		"note_uuid": note_uuid,
		"person_uuid": person_uuid,
		"note_type_uuid": note_type_uuid,
		"title": title,
		"body": body,
		"created_at": timestamp
	})

	# Check table availability for outbox safely
	var check_outbox = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND (name='outbox_sync' OR name='event_outbox');")
	if check_outbox["success"] and check_outbox["data"].size() > 0:
		var target_tbl = check_outbox["data"][0]["name"]
		if target_tbl == "outbox_sync":
			statements.append({
				"sql": "INSERT INTO outbox_sync (event_uuid, event_type, payload_json, created_at) VALUES (?, ?, ?, ?);",
				"args": [outbox_uuid, "NoteCreated", payload, timestamp]
			})
		else:
			statements.append({
				"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, created_at) VALUES (?, ?, ?, ?, ?, ?, ?);",
				"args": [outbox_uuid, "NoteCreated", "person_note", note_uuid, payload, "desktop_local", timestamp]
			})

	var tx_res = db.execute_transaction(statements)
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"]}

	return {"success": true, "error": "", "note_uuid": note_uuid}

## Soft-deletes a Person Note record
func delete_person_note(note_uuid: String) -> Dictionary:
	if note_uuid == "":
		return {"success": false, "error": "note_uuid is required."}

	var timestamp = _get_utc_timestamp()
	var sql = "UPDATE person_notes SET is_deleted = 1, updated_at = ? WHERE note_uuid = ?;"
	var res = db.execute(sql, [timestamp, note_uuid])
	if not res["success"]:
		return {"success": false, "error": res["error"]}

	return {"success": true, "error": ""}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

func _generate_uuid_suffix() -> String:
	return str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)

func _get_utc_timestamp() -> String:
	var dt = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
