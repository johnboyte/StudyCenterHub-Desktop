extends RefCounted

## Directory Read Service for StudyCenterHub Next Generation
## Dedicated read-only service for querying Directory constituents, status lists, counts, and search.
## Strictly Read-Only: Zero write transactions, outbox events, or data modifications.

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func get_person(person_uuid: String) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "person": {}}
	var res = db.execute("SELECT * FROM people WHERE person_uuid = ?;", [person_uuid])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "error": "", "person": res["data"][0]}
	return {"success": false, "error": "Person not found.", "person": {}}

func get_person_by_human_id(human_id: String) -> Dictionary:
	if human_id == "":
		return {"success": false, "error": "human_id cannot be empty.", "person": {}}
	var res = db.execute("SELECT * FROM people WHERE human_id = ?;", [human_id])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "error": "", "person": res["data"][0]}
	return {"success": false, "error": "Person not found.", "person": {}}

func list_people(options: Dictionary = {}) -> Dictionary:
	var sql = "SELECT * FROM people"
	var args = []

	var status_filter = String(options.get("status", ""))
	if status_filter != "":
		sql += " WHERE status = ?"
		args.append(status_filter)

	sql += " ORDER BY last_name ASC, first_name ASC, id ASC;"
	var res = db.execute(sql, args)
	if not res["success"]:
		return {"success": false, "error": res["error"], "people": []}
	return {"success": true, "error": "", "people": res["data"]}

func list_active_people() -> Dictionary:
	return list_people({"status": "active"})

func list_pending_people() -> Dictionary:
	var sql = "SELECT * FROM people WHERE status IN ('pending', 'To Be Confirmed') ORDER BY last_name ASC, first_name ASC, id ASC;"
	var res = db.execute(sql)
	if not res["success"]:
		return {"success": false, "error": res["error"], "people": []}
	return {"success": true, "error": "", "people": res["data"]}

func list_inactive_people() -> Dictionary:
	return list_people({"status": "inactive"})

func person_exists(person_uuid: String) -> bool:
	if person_uuid == "":
		return false
	var res = db.execute("SELECT 1 FROM people WHERE person_uuid = ? LIMIT 1;", [person_uuid])
	return res["success"] and res["data"].size() > 0

func count_people() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM people;")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func count_active() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE status = 'active';")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func count_pending() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE status IN ('pending', 'To Be Confirmed');")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func count_inactive() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE status = 'inactive';")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

# --- STORY DIR-SPR1-003: SEARCH CAPABILITIES ---

func search_people(query_raw: String, options: Dictionary = {}) -> Dictionary:
	var query = _normalize_whitespace(query_raw)
	if query == "":
		return {"success": true, "error": "", "people": [], "count": 0}

	var status_filter = String(options.get("status", ""))
	if status_filter != "":
		var allowed = ["active", "pending", "To Be Confirmed", "inactive"]
		if not status_filter in allowed:
			return {"success": false, "error": "Invalid status filter: " + status_filter, "people": []}

	var limit_val = 50
	if options.has("limit"):
		limit_val = int(options.get("limit"))
	if limit_val <= 0 or limit_val > 200:
		limit_val = clampi(limit_val, 1, 200)

	var escaped_query = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
	var pattern = "%" + escaped_query + "%"

	var phone_digits = normalize_phone_digits(query)
	var phone_pattern = "%" + phone_digits + "%" if phone_digits.length() >= 3 else ""

	var sql = """
	SELECT * FROM people
	WHERE (
		LOWER(first_name) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(last_name) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(first_name || ' ' || last_name) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(last_name || ' ' || first_name) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(human_id) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(phone) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(emergency_contact_name) LIKE LOWER(?) ESCAPE '\\'
		OR LOWER(emergency_contact_phone) LIKE LOWER(?) ESCAPE '\\'
	"""
	var args = [pattern, pattern, pattern, pattern, pattern, pattern, pattern, pattern]

	if phone_pattern != "":
		sql += """
		OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone, '-', ''), '(', ''), ')', ''), ' ', ''), '+', '') LIKE ? ESCAPE '\\'
		OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(emergency_contact_phone, '-', ''), '(', ''), ')', ''), ' ', ''), '+', '') LIKE ? ESCAPE '\\'
		"""
		args.append(phone_pattern)
		args.append(phone_pattern)

	sql += ")"

	if status_filter == "pending":
		sql += " AND status IN ('pending', 'To Be Confirmed')"
	elif status_filter != "":
		sql += " AND status = ?"
		args.append(status_filter)

	sql += " ORDER BY last_name ASC, first_name ASC, id ASC LIMIT ?;"
	args.append(limit_val)

	var res = db.execute(sql, args)
	if not res["success"]:
		return {"success": false, "error": res["error"], "people": []}

	return {
		"success": true,
		"error": "",
		"people": res["data"],
		"count": res["data"].size()
	}

func get_person_attendance_history(person_uuid: String) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "history": []}
	var sql = "SELECT * FROM attendance_log WHERE person_uuid = ? ORDER BY check_in_date DESC, check_in_time DESC, id DESC;"
	var res = db.execute(sql, [person_uuid])
	if not res["success"]:
		return {"success": false, "error": res["error"], "history": []}
	return {"success": true, "error": "", "history": res["data"]}

func get_note_types(options: Dictionary = {}) -> Dictionary:
	const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
	return NoteServiceScript.new(db).get_note_types(options)

func get_person_notes_grouped(person_uuid: String, options: Dictionary = {}) -> Dictionary:
	const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
	return NoteServiceScript.new(db).get_person_notes_grouped(person_uuid, options)

func normalize_phone_digits(input: String) -> String:
	var digits = ""
	for i in range(input.length()):
		var c = input.substr(i, 1)
		if c >= "0" and c <= "9":
			digits += c
	return digits

func _normalize_whitespace(input: String) -> String:
	var s = input.strip_edges()
	while s.find("  ") != -1:
		s = s.replace("  ", " ")
	return s

func get_person_pathways(person_uuid: String) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "pathways": []}
	var sql = """
		SELECT pp.id as person_pathway_id, p.name as pathway_name, p.description, pp.current_stage, pp.progress_percent, pp.status, pp.started_at
		FROM person_pathways pp
		JOIN pathways p ON p.id = pp.pathway_id
		JOIN people pe ON pe.id = pp.person_id
		WHERE pe.person_uuid = ?
		ORDER BY pp.started_at DESC;
	"""
	var res = db.execute(sql, [person_uuid])
	if not res["success"]:
		return {"success": false, "error": res["error"], "pathways": []}

	var list = res["data"]
	for item in list:
		var m_sql = "SELECT milestone_name, milestone_order, is_completed FROM person_pathway_milestones WHERE person_pathway_id = ? ORDER BY milestone_order ASC;"
		var m_res = db.execute(m_sql, [item["person_pathway_id"]])
		item["milestones"] = m_res["data"] if m_res["success"] else []

	return {"success": true, "error": "", "pathways": list}

func get_person_sessions(person_uuid: String) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "sessions": []}
	var sql = """
		SELECT ps.id as person_session_id, s.title, s.session_type, s.date_text, s.start_time, s.end_time, s.room_location, ps.attendance_status, ps.registered_at
		FROM person_sessions ps
		JOIN sessions s ON s.id = ps.session_id
		JOIN people pe ON pe.id = ps.person_id
		WHERE pe.person_uuid = ?
		ORDER BY s.date_text DESC, s.start_time DESC;
	"""
	var res = db.execute(sql, [person_uuid])
	if not res["success"]:
		return {"success": false, "error": res["error"], "sessions": []}
	return {"success": true, "error": "", "sessions": res["data"]}
