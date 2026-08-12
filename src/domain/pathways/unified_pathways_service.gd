extends RefCounted

## Unified Pathways Service (Fellows and LEAD Stage 1 Foundation)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	_sync_pathway_tracks_and_standings()

func _sync_pathway_tracks_and_standings() -> void:
	if not db: return
	db.execute("UPDATE person_pathway_program_years SET track_for_that_year = (SELECT current_track FROM person_pathways WHERE person_pathways.id = person_pathway_program_years.person_pathway_id), standing_for_that_year = (SELECT current_standing FROM person_pathways WHERE person_pathways.id = person_pathway_program_years.person_pathway_id) WHERE person_pathway_id IN (SELECT id FROM person_pathways);")

func create_annual_program(pathway_key: String, academic_year: String, display_name: String, notes: String = "") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var p_res = db.execute("SELECT id FROM pathways WHERE pathway_key = ? LIMIT 1;", [pathway_key])
	if not p_res["success"] or p_res["data"].size() == 0:
		return {"success": false, "error": "Pathway definition not found for key: " + pathway_key}

	var pathway_id = int(p_res["data"][0]["id"])
	var uuid = _generate_uuid("prog")

	var sql = "INSERT INTO pathway_program_years (uuid, pathway_id, academic_year, display_name, notes) VALUES (?, ?, ?, ?, ?);"
	var res = db.execute(sql, [uuid, pathway_id, academic_year, display_name, notes])

	if not res["success"]:
		# If already exists, return existing record
		var q_exist = db.execute("SELECT id, uuid FROM pathway_program_years WHERE pathway_id = ? AND academic_year = ? LIMIT 1;", [pathway_id, academic_year])
		if q_exist["success"] and q_exist["data"].size() > 0:
			return {
				"success": true,
				"program_id": int(q_exist["data"][0]["id"]),
				"uuid": str(q_exist["data"][0]["uuid"]),
				"already_existed": true
			}
		return {"success": false, "error": res["error"]}

	var id_res = db.execute("SELECT id FROM pathway_program_years WHERE uuid = ? LIMIT 1;", [uuid])
	var program_id = int(id_res["data"][0]["id"]) if (id_res["success"] and id_res["data"].size() > 0) else 0

	return {"success": true, "program_id": program_id, "uuid": uuid, "already_existed": false}

func enroll_person_pathway(person_id: int, pathway_key: String, academic_year: String, track: String = "standard", standing: String = "year_1", mentor_id: Variant = null, notes: String = "") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var person_res = db.execute("SELECT id, person_uuid, human_id FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not person_res["success"] or person_res["data"].size() == 0:
		return {"success": false, "error": "Constituent person not found."}
	var person_uuid = str(person_res["data"][0]["person_uuid"])

	var prog_res = create_annual_program(pathway_key, academic_year, pathway_key.to_upper() + " — " + academic_year)
	if not prog_res["success"]:
		return prog_res
	var program_year_id = int(prog_res["program_id"])

	var p_res = db.execute("SELECT id FROM pathways WHERE pathway_key = ? LIMIT 1;", [pathway_key])
	var pathway_id = int(p_res["data"][0]["id"])

	var stmts = []
	var event_uuid = _generate_uuid("evt")
	var pp_uuid = _generate_uuid("pp")
	var ppy_uuid = _generate_uuid("ppy")

	var q_pp = db.execute("SELECT id FROM person_pathways WHERE person_id = ? AND pathway_id = ? LIMIT 1;", [person_id, pathway_id])
	var person_pathway_id = 0

	if q_pp["success"] and q_pp["data"].size() > 0:
		person_pathway_id = int(q_pp["data"][0]["id"])
		stmts.append({
			"sql": "UPDATE person_pathways SET current_track = ?, current_standing = ?, enrollment_status = 'active', assigned_mentor_person_id = ?, general_notes = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [track, standing, mentor_id, notes, person_pathway_id]
		})
	else:
		stmts.append({
			"sql": "INSERT INTO person_pathways (uuid, person_id, pathway_id, current_track, current_standing, enrollment_status, assigned_mentor_person_id, general_notes) VALUES (?, ?, ?, ?, ?, 'active', ?, ?);",
			"args": [pp_uuid, person_id, pathway_id, track, standing, mentor_id, notes]
		})

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonPathwayEnrolled",
		"person_uuid": person_uuid,
		"pathway_key": pathway_key,
		"academic_year": academic_year,
		"track": track,
		"standing": standing,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayEnrolled', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, person_uuid, payload_json]
	})

	var tx_res = db.execute_transaction(stmts)
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"]}

	if person_pathway_id == 0:
		var q_pp_new = db.execute("SELECT id FROM person_pathways WHERE person_id = ? AND pathway_id = ? LIMIT 1;", [person_id, pathway_id])
		if q_pp_new["success"] and q_pp_new["data"].size() > 0:
			person_pathway_id = int(q_pp_new["data"][0]["id"])

	# Create Annual Participant Record in person_pathway_program_years
	var annual_stmts = []
	var q_ppy = db.execute("SELECT id FROM person_pathway_program_years WHERE person_pathway_id = ? AND pathway_program_year_id = ? LIMIT 1;", [person_pathway_id, program_year_id])
	var ppy_id = 0

	if q_ppy["success"] and q_ppy["data"].size() > 0:
		ppy_id = int(q_ppy["data"][0]["id"])
		annual_stmts.append({
			"sql": "UPDATE person_pathway_program_years SET standing_for_that_year = ?, track_for_that_year = ?, participation_status = 'active', mentor_person_id = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [standing, track, mentor_id, ppy_id]
		})
	else:
		annual_stmts.append({
			"sql": "INSERT INTO person_pathway_program_years (uuid, person_pathway_id, pathway_program_year_id, standing_for_that_year, track_for_that_year, participation_status, mentor_person_id, annual_plan_notes) VALUES (?, ?, ?, ?, ?, 'active', ?, ?);",
			"args": [ppy_uuid, person_pathway_id, program_year_id, standing, track, mentor_id, notes]
		})

	var tx2_res = db.execute_transaction(annual_stmts)
	if not tx2_res["success"]:
		return {"success": false, "error": tx2_res["error"]}

	if ppy_id == 0:
		var q_ppy_new = db.execute("SELECT id FROM person_pathway_program_years WHERE person_pathway_id = ? AND pathway_program_year_id = ? LIMIT 1;", [person_pathway_id, program_year_id])
		if q_ppy_new["success"] and q_ppy_new["data"].size() > 0:
			ppy_id = int(q_ppy_new["data"][0]["id"])

	return {
		"success": true,
		"person_pathway_id": person_pathway_id,
		"person_pathway_program_year_id": ppy_id,
		"event_uuid": event_uuid
	}

func change_person_track(person_pathway_id: int, new_track: String, reason: String = "", catch_up_plan: String = "", acting_user: String = "System") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var q_pp = db.execute("SELECT pp.id, pp.person_id, pp.current_track, pe.person_uuid FROM person_pathways pp JOIN people pe ON pe.id = pp.person_id WHERE pp.id = ? LIMIT 1;", [person_pathway_id])
	if not q_pp["success"] or q_pp["data"].size() == 0:
		return {"success": false, "error": "Person pathway record not found."}

	var row = q_pp["data"][0]
	var old_track = str(row.get("current_track", "standard"))
	var person_uuid = str(row.get("person_uuid", ""))

	var track_hist_uuid = _generate_uuid("th")
	var event_uuid = _generate_uuid("evt")

	var stmts = [
		{
			"sql": "UPDATE person_pathways SET current_track = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [new_track, person_pathway_id]
		},
		{
			"sql": "UPDATE person_pathway_program_years SET track_for_that_year = ?, updated_at = datetime('now') WHERE person_pathway_id = ?;",
			"args": [new_track, person_pathway_id]
		},
		{
			"sql": "INSERT INTO person_pathway_track_history (uuid, person_pathway_id, previous_track, new_track, changed_by, reason, catch_up_plan) VALUES (?, ?, ?, ?, ?, ?, ?);",
			"args": [track_hist_uuid, person_pathway_id, old_track, new_track, acting_user, reason, catch_up_plan]
		}
	]

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonPathwayTrackChanged",
		"person_uuid": person_uuid,
		"previous_track": old_track,
		"new_track": new_track,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayTrackChanged', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, person_uuid, JSON.stringify(payload_dict)]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]:
		return {"success": false, "error": res["error"]}

	return {"success": true, "changed": true, "previous_track": old_track, "new_track": new_track, "event_uuid": event_uuid}

func change_person_standing(person_pathway_id: int, new_standing: String, reason: String = "", catch_up_plan: String = "", acting_user: String = "System") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var q_pp = db.execute("SELECT pp.id, pp.person_id, pp.current_standing, pe.person_uuid FROM person_pathways pp JOIN people pe ON pe.id = pp.person_id WHERE pp.id = ? LIMIT 1;", [person_pathway_id])
	if not q_pp["success"] or q_pp["data"].size() == 0:
		return {"success": false, "error": "Person pathway record not found."}

	var row = q_pp["data"][0]
	var old_standing = str(row.get("current_standing", "year_1"))
	var person_uuid = str(row.get("person_uuid", ""))

	var standing_hist_uuid = _generate_uuid("sh")
	var event_uuid = _generate_uuid("evt")

	var stmts = [
		{
			"sql": "UPDATE person_pathways SET current_standing = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [new_standing, person_pathway_id]
		},
		{
			"sql": "UPDATE person_pathway_program_years SET standing_for_that_year = ?, updated_at = datetime('now') WHERE person_pathway_id = ?;",
			"args": [new_standing, person_pathway_id]
		},
		{
			"sql": "INSERT INTO person_pathway_standing_history (uuid, person_pathway_id, previous_standing, new_standing, changed_by, reason, catch_up_plan) VALUES (?, ?, ?, ?, ?, ?, ?);",
			"args": [standing_hist_uuid, person_pathway_id, old_standing, new_standing, acting_user, reason, catch_up_plan]
		}
	]

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonPathwayStandingChanged",
		"person_uuid": person_uuid,
		"previous_standing": old_standing,
		"new_standing": new_standing,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayStandingChanged', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, person_uuid, JSON.stringify(payload_dict)]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]:
		return {"success": false, "error": res["error"]}

	return {"success": true, "changed": true, "previous_standing": old_standing, "new_standing": new_standing, "event_uuid": event_uuid}

func create_program_requirement(pathway_program_year_id: int, title: String, description: String = "", category: String = "other", required_or_optional: String = "required", applies_to_track: String = "all", applies_to_standing: String = "all", due_date: String = "", display_order: int = 1, acting_user: String = "System") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var req_uuid = _generate_uuid("req")
	var event_uuid = _generate_uuid("evt")

	var stmts = [
		{
			"sql": "INSERT INTO pathway_program_requirements (uuid, pathway_program_year_id, title, description, category, required_or_optional, applies_to_track, applies_to_standing, due_date, display_order, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			"args": [req_uuid, pathway_program_year_id, title, description, category, required_or_optional, applies_to_track, applies_to_standing, due_date, display_order, acting_user]
		}
	]

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PathwayProgramRequirementCreated",
		"requirement_uuid": req_uuid,
		"title": title,
		"category": category,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PathwayProgramRequirementCreated', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, req_uuid, JSON.stringify(payload_dict)]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]:
		return {"success": false, "error": res["error"]}

	var id_q = db.execute("SELECT id FROM pathway_program_requirements WHERE uuid = ? LIMIT 1;", [req_uuid])
	var req_id = int(id_q["data"][0]["id"]) if (id_q["success"] and id_q["data"].size() > 0) else 0

	return {"success": true, "requirement_id": req_id, "uuid": req_uuid}

func assign_group_requirement(program_requirement_id: int, excluded_person_ids: Array = [], acting_user: String = "System") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference is null."}

	var req_q = db.execute("SELECT pathway_program_year_id, title, description, category, required_or_optional, applies_to_track, applies_to_standing, due_date FROM pathway_program_requirements WHERE id = ? LIMIT 1;", [program_requirement_id])
	if not req_q["success"] or req_q["data"].size() == 0:
		return {"success": false, "error": "Program requirement not found."}

	var req = req_q["data"][0]
	var program_year_id = int(req["pathway_program_year_id"])
	var app_track = str(req.get("applies_to_track", "all"))
	var app_standing = str(req.get("applies_to_standing", "all"))

	var participants_q = db.execute("SELECT ppy.id as ppy_id, ppy.standing_for_that_year, ppy.track_for_that_year, pp.person_id FROM person_pathway_program_years ppy JOIN person_pathways pp ON pp.id = ppy.person_pathway_id WHERE ppy.pathway_program_year_id = ? AND ppy.participation_status = 'active';", [program_year_id])
	if not participants_q["success"]:
		return {"success": false, "error": participants_q["error"]}

	var stmts = []
	var assigned_count = 0

	for p in participants_q["data"]:
		var pid = int(p["person_id"])
		var ppy_id = int(p["ppy_id"])
		var p_standing = str(p.get("standing_for_that_year", "year_1"))
		var p_track = str(p.get("track_for_that_year", "standard"))

		if pid in excluded_person_ids:
			continue
		if app_track != "all" and p_track != app_track:
			continue
		if app_standing != "all" and p_standing != app_standing:
			continue

		var preq_uuid = _generate_uuid("preq")
		stmts.append({
			"sql": "INSERT INTO person_pathway_requirements (uuid, person_pathway_program_year_id, source_program_requirement_id, title, description, category, required_or_optional, due_date, status, assigned_by, assignment_source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'assigned', ?, 'annual_program');",
			"args": [preq_uuid, ppy_id, program_requirement_id, req.get("title"), req.get("description"), req.get("category"), req.get("required_or_optional"), req.get("due_date"), acting_user]
		})
		assigned_count += 1

	if stmts.size() > 0:
		var event_uuid = _generate_uuid("evt")
		var payload_dict = {
			"event_uuid": event_uuid,
			"event_type": "PersonPathwayRequirementAssigned",
			"program_requirement_id": program_requirement_id,
			"assigned_count": assigned_count,
			"acting_user": acting_user,
			"timestamp": Time.get_datetime_string_from_system()
		}
		stmts.append({
			"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayRequirementAssigned', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
			"args": [event_uuid, str(program_requirement_id), JSON.stringify(payload_dict)]
		})

		var res = db.execute_transaction(stmts)
		if not res["success"]:
			return {"success": false, "error": res["error"]}

	return {"success": true, "assigned_count": assigned_count}

func get_person_enrollments(person_id: int) -> Array:
	if not db: return []
	var sql = """
		SELECT pp.id as person_pathway_id, pp.uuid, pp.person_id, pp.pathway_id, pp.current_track, pp.current_standing, pp.enrollment_status, pp.general_notes,
		       p.pathway_key, p.name as pathway_name, p.description as pathway_description
		FROM person_pathways pp
		JOIN pathways p ON p.id = pp.pathway_id
		WHERE pp.person_id = ? AND pp.enrollment_status != 'withdrawn'
		ORDER BY p.name ASC;
	"""
	var res = db.execute(sql, [person_id])
	if not res["success"]: return []

	var list = res["data"]
	for item in list:
		var ppid = int(item["person_pathway_id"])
		var q_year = db.execute("SELECT ppy.id as person_pathway_program_year_id, ppy.standing_for_that_year, ppy.track_for_that_year, ppy.participation_status, ppy.annual_plan_notes, ppy.catch_up_plan, py.academic_year, py.display_name FROM person_pathway_program_years ppy JOIN pathway_program_years py ON py.id = ppy.pathway_program_year_id WHERE ppy.person_pathway_id = ? ORDER BY py.academic_year DESC LIMIT 1;", [ppid])
		item["current_annual_record"] = q_year["data"][0] if (q_year["success"] and q_year["data"].size() > 0) else {}

		var q_th = db.execute("SELECT previous_track, new_track, effective_at, changed_by, reason, catch_up_plan FROM person_pathway_track_history WHERE person_pathway_id = ? ORDER BY effective_at DESC;", [ppid])
		item["track_history"] = q_th["data"] if q_th["success"] else []

		var q_sh = db.execute("SELECT previous_standing, new_standing, effective_at, changed_by, reason, catch_up_plan FROM person_pathway_standing_history WHERE person_pathway_id = ? ORDER BY effective_at DESC;", [ppid])
		item["standing_history"] = q_sh["data"] if q_sh["success"] else []

	return list

func get_annual_program(pathway_key: String, academic_year: String) -> Dictionary:
	if not db: return {}
	var sql = """
		SELECT py.id as program_year_id, py.uuid, py.pathway_id, py.academic_year, py.display_name, py.status, py.notes,
		       p.pathway_key, p.name as pathway_name
		FROM pathway_program_years py
		JOIN pathways p ON p.id = py.pathway_id
		WHERE p.pathway_key = ? AND py.academic_year = ?
		LIMIT 1;
	"""
	var res = db.execute(sql, [pathway_key, academic_year])
	if not res["success"] or res["data"].size() == 0:
		return {}

	var prog = res["data"][0]
	var py_id = int(prog["program_year_id"])

	var q_participants = db.execute("SELECT COUNT(*) as cnt FROM person_pathway_program_years WHERE pathway_program_year_id = ? AND participation_status = 'active';", [py_id])
	prog["participant_count"] = int(q_participants["data"][0]["cnt"]) if (q_participants["success"] and q_participants["data"].size() > 0) else 0

	var q_reqs = db.execute("SELECT id, uuid, title, category, required_or_optional, applies_to_track, applies_to_standing, due_date FROM pathway_program_requirements WHERE pathway_program_year_id = ? ORDER BY display_order ASC;", [py_id])
	prog["requirements"] = q_reqs["data"] if q_reqs["success"] else []

	return prog

func get_annual_programs(pathway_key: String = "") -> Array:
	if not db: return []
	var sql = ""
	var args = []
	if pathway_key != "":
		sql = "SELECT py.id as program_year_id, py.uuid, py.academic_year, py.display_name, py.status, p.pathway_key, p.name as pathway_name FROM pathway_program_years py JOIN pathways p ON p.id = py.pathway_id WHERE p.pathway_key = ? ORDER BY py.academic_year DESC;"
		args = [pathway_key]
	else:
		sql = "SELECT py.id as program_year_id, py.uuid, py.academic_year, py.display_name, py.status, p.pathway_key, p.name as pathway_name FROM pathway_program_years py JOIN pathways p ON p.id = py.pathway_id ORDER BY py.academic_year DESC, p.name ASC;"
	var res = db.execute(sql, args)
	return res["data"] if res["success"] else []

func get_program_participants(pathway_program_year_id: int, track_filter: String = "all", standing_filter: String = "all", status_filter: String = "all", search_query: String = "") -> Array:
	if not db: return []
	var sql = """
		SELECT ppy.id as person_pathway_program_year_id, ppy.person_pathway_id, ppy.standing_for_that_year, ppy.track_for_that_year, ppy.participation_status, ppy.mentor_person_id, ppy.annual_plan_notes, ppy.catch_up_plan,
		       pe.id as person_id, pe.person_uuid, pe.human_id, pe.first_name, pe.last_name,
		       COALESCE(m.first_name || ' ' || m.last_name, '') as mentor_name
		FROM person_pathway_program_years ppy
		JOIN person_pathways pp ON pp.id = ppy.person_pathway_id
		JOIN people pe ON pe.id = pp.person_id
		LEFT JOIN people m ON m.id = ppy.mentor_person_id
		WHERE ppy.pathway_program_year_id = ?
	"""
	var args: Array = [pathway_program_year_id]

	if track_filter != "all":
		sql += " AND ppy.track_for_that_year = ?"
		args.append(track_filter)

	if standing_filter != "all":
		sql += " AND ppy.standing_for_that_year = ?"
		args.append(standing_filter)

	if status_filter != "all":
		sql += " AND ppy.participation_status = ?"
		args.append(status_filter)

	if search_query.strip_edges() != "":
		sql += " AND (pe.first_name LIKE ? OR pe.last_name LIKE ? OR pe.human_id LIKE ?)"
		var q = "%" + search_query.strip_edges() + "%"
		args.append(q); args.append(q); args.append(q)

	sql += " ORDER BY pe.last_name ASC, pe.first_name ASC;"

	var res = db.execute(sql, args)
	if not res["success"]: return []

	var list = res["data"]
	for item in list:
		var ppy_id = int(item["person_pathway_program_year_id"])
		var q_reqs = db.execute("SELECT COUNT(*) as total, SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed FROM person_pathway_requirements WHERE person_pathway_program_year_id = ?;", [ppy_id])
		if q_reqs["success"] and q_reqs["data"].size() > 0:
			item["total_requirements"] = int(q_reqs["data"][0].get("total", 0))
			item["completed_requirements"] = int(q_reqs["data"][0].get("completed", 0)) if q_reqs["data"][0].get("completed") != null else 0
		else:
			item["total_requirements"] = 0
			item["completed_requirements"] = 0

	return list

func get_program_stats(pathway_program_year_id: int) -> Dictionary:
	if not db: return {}
	var participants = get_program_participants(pathway_program_year_id)
	var stats = {
		"total_participants": participants.size(),
		"standard_count": 0,
		"certification_count": 0,
		"year_1_count": 0,
		"year_2_count": 0,
		"year_3_count": 0,
		"year_4_count": 0,
		"incomplete_req_count": 0
	}

	for p in participants:
		var tr = str(p.get("track_for_that_year", "standard"))
		var st = str(p.get("standing_for_that_year", "year_1"))
		var tot = int(p.get("total_requirements", 0))
		var comp = int(p.get("completed_requirements", 0))

		if tr == "certification": stats["certification_count"] += 1
		else: stats["standard_count"] += 1

		if st == "year_1": stats["year_1_count"] += 1
		elif st == "year_2": stats["year_2_count"] += 1
		elif st == "year_3": stats["year_3_count"] += 1
		elif st == "year_4": stats["year_4_count"] += 1

		if tot > comp:
			stats["incomplete_req_count"] += 1

	return stats

func get_eligible_requirement_recipients(pathway_program_year_id: int, applies_to_track: String = "all", applies_to_standing: String = "all") -> Array:
	return get_program_participants(pathway_program_year_id, applies_to_track, applies_to_standing, "active")

func link_session_to_program(pathway_program_year_id: int, session_id: int, attendance_expectation: String = "required", applies_to_track: String = "all", applies_to_standing: String = "all", acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var event_uuid = _generate_uuid("evt")
	var sql = "INSERT OR REPLACE INTO pathway_program_sessions (pathway_program_year_id, session_id, attendance_expectation, applies_to_track, applies_to_standing, created_by) VALUES (?, ?, ?, ?, ?, ?);"
	
	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PathwayProgramSessionLinked",
		"pathway_program_year_id": pathway_program_year_id,
		"session_id": session_id,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var stmt1 = {"sql": sql, "args": [pathway_program_year_id, session_id, attendance_expectation, applies_to_track, applies_to_standing, acting_user]}
	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PathwayProgramSessionLinked', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, str(session_id), JSON.stringify(payload_dict)]
	}

	var res = db.execute_transaction([stmt1, stmt2])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true, "event_uuid": event_uuid}

func unlink_session_from_program(pathway_program_year_id: int, session_id: int) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var sql = "DELETE FROM pathway_program_sessions WHERE pathway_program_year_id = ? AND session_id = ?;"
	var res = db.execute(sql, [pathway_program_year_id, session_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func get_program_linked_sessions(pathway_program_year_id: int) -> Array:
	if not db: return []
	var sql = """
		SELECT pps.id as link_id, pps.pathway_program_year_id, pps.session_id, pps.attendance_expectation, pps.applies_to_track, pps.applies_to_standing,
		       s.title as session_title, s.session_type, s.date_text, s.start_time, s.end_time, s.room_location, s.max_capacity
		FROM pathway_program_sessions pps
		JOIN sessions s ON s.id = pps.session_id
		WHERE pps.pathway_program_year_id = ?
		ORDER BY s.date_text ASC, s.start_time ASC;
	"""
	var res = db.execute(sql, [pathway_program_year_id])
	return res["data"] if res["success"] else []

func get_profile_pathway_summary(person_id: int) -> Dictionary:
	var summary = {
		"fellows": _get_single_pathway_profile_summary(person_id, "fellows"),
		"lead": _get_single_pathway_profile_summary(person_id, "lead")
	}
	return summary

func _get_single_pathway_profile_summary(person_id: int, pathway_key: String) -> Dictionary:
	if not db: return {"enrolled": false}

	var p_res = db.execute("SELECT id, name FROM pathways WHERE pathway_key = ? LIMIT 1;", [pathway_key])
	if not p_res["success"] or p_res["data"].size() == 0:
		return {"enrolled": false}

	var pathway_id = int(p_res["data"][0]["id"])
	var pathway_name = str(p_res["data"][0]["name"])

	var pp_q = db.execute("""
		SELECT pp.id as person_pathway_id, pp.uuid, pp.current_track, pp.current_standing, pp.enrollment_status, pp.assigned_mentor_person_id, pp.general_notes, pp.updated_at,
		       COALESCE(m.first_name || ' ' || m.last_name, '') as mentor_name
		FROM person_pathways pp
		LEFT JOIN people m ON m.id = pp.assigned_mentor_person_id
		WHERE pp.person_id = ? AND pp.pathway_id = ? AND pp.enrollment_status != 'withdrawn'
		LIMIT 1;
	""", [person_id, pathway_id])

	if not pp_q["success"] or pp_q["data"].size() == 0:
		return {"enrolled": false, "pathway_key": pathway_key, "pathway_name": pathway_name}

	var pp = pp_q["data"][0]
	var ppid = int(pp["person_pathway_id"])

	# Current Annual Record
	var ppy_q = db.execute("""
		SELECT ppy.id as person_pathway_program_year_id, ppy.pathway_program_year_id, ppy.standing_for_that_year, ppy.track_for_that_year, ppy.annual_plan_notes, ppy.catch_up_plan,
		       py.academic_year, py.display_name
		FROM person_pathway_program_years ppy
		JOIN pathway_program_years py ON py.id = ppy.pathway_program_year_id
		WHERE ppy.person_pathway_id = ?
		ORDER BY py.academic_year DESC LIMIT 1;
	""", [ppid])

	var annual_record = ppy_q["data"][0] if (ppy_q["success"] and ppy_q["data"].size() > 0) else {}
	var ppy_id = int(annual_record.get("person_pathway_program_year_id", 0))

	# Requirements List & Progress
	var reqs = []
	var total_reqs = 0
	var completed_reqs = 0
	if ppy_id > 0:
		var reqs_q = db.execute("SELECT id, uuid, source_program_requirement_id, title, description, category, required_or_optional, due_date, status, completed_at, completion_notes, assignment_source FROM person_pathway_requirements WHERE person_pathway_program_year_id = ? ORDER BY status ASC, created_at ASC;", [ppy_id])
		if reqs_q["success"]:
			reqs = reqs_q["data"]
			total_reqs = reqs.size()
			for r in reqs:
				if str(r.get("status")) == "completed":
					completed_reqs += 1

	# Linked Sessions Attendance Summary
	var session_summary = {"total_linked": 0, "past_applicable": 0, "attended": 0, "upcoming": 0, "attendance_pct": 0.0, "wording": "No linked sessions."}
	var py_id = int(annual_record.get("pathway_program_year_id", 0))
	var c_track = str(pp.get("current_track", "standard"))
	var c_standing = str(pp.get("current_standing", "year_1"))

	if py_id > 0:
		var today_str = Time.get_date_string_from_system()
		var sess_q = db.execute("""
			SELECT pps.session_id, pps.attendance_expectation, pps.applies_to_track, pps.applies_to_standing,
			       s.date_text, ps.attendance_status
			FROM pathway_program_sessions pps
			JOIN sessions s ON s.id = pps.session_id
			LEFT JOIN person_sessions ps ON ps.session_id = pps.session_id AND ps.person_id = ?
			WHERE pps.pathway_program_year_id = ?;
		""", [person_id, py_id])

		if sess_q["success"]:
			session_summary["total_linked"] = sess_q["data"].size()
			for s in sess_q["data"]:
				var app_tr = str(s.get("applies_to_track", "all"))
				var app_st = str(s.get("applies_to_standing", "all"))
				var d_text = str(s.get("date_text", ""))

				# Filter scope
				if app_tr != "all" and app_tr != c_track: continue
				if app_st != "all" and app_st != c_standing: continue

				var st = str(s.get("attendance_status", ""))
				if d_text <= today_str:
					session_summary["past_applicable"] += 1
					if st in ["attended", "present"]:
						session_summary["attended"] += 1
				else:
					session_summary["upcoming"] += 1

			var past_cnt = session_summary["past_applicable"]
			var att_cnt = session_summary["attended"]
			var up_cnt = session_summary["upcoming"]

			if past_cnt > 0:
				session_summary["attendance_pct"] = (float(att_cnt) / float(past_cnt)) * 100.0
				session_summary["wording"] = "%d of %d past applicable sessions attended (%d upcoming)" % [att_cnt, past_cnt, up_cnt]
			elif session_summary["total_linked"] > 0:
				session_summary["wording"] = "0 past sessions (%d upcoming linked sessions)" % [up_cnt]
			else:
				session_summary["wording"] = "No linked sessions."

	return {
		"enrolled": true,
		"person_pathway_id": ppid,
		"pathway_key": pathway_key,
		"pathway_name": pathway_name,
		"academic_year": annual_record.get("academic_year", ""),
		"enrollment_status": pp.get("enrollment_status", "active"),
		"current_track": pp.get("current_track", "standard"),
		"current_standing": pp.get("current_standing", "year_1"),
		"mentor_person_id": pp.get("assigned_mentor_person_id"),
		"mentor_name": pp.get("mentor_name", ""),
		"general_notes": str(pp.get("general_notes", "")),
		"annual_plan_notes": str(annual_record.get("annual_plan_notes", "")),
		"catch_up_plan": str(annual_record.get("catch_up_plan", "")),
		"last_updated": str(pp.get("updated_at", "")),
		"person_pathway_program_year_id": ppy_id,
		"requirements": reqs,
		"total_requirements": total_reqs,
		"completed_requirements": completed_reqs,
		"session_summary": session_summary,
		"history": get_pathway_history(ppid)
	}

func assign_individual_requirement(person_pathway_program_year_id: int, title: String, description: String = "", category: String = "individual", required_or_optional: String = "required", due_date: String = "", assignment_source: String = "individual", acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var preq_uuid = _generate_uuid("preq")
	var event_uuid = _generate_uuid("evt")

	var stmts = [
		{
			"sql": "INSERT INTO person_pathway_requirements (uuid, person_pathway_program_year_id, title, description, category, required_or_optional, due_date, status, assigned_by, assignment_source) VALUES (?, ?, ?, ?, ?, ?, ?, 'assigned', ?, ?);",
			"args": [preq_uuid, person_pathway_program_year_id, title, description, category, required_or_optional, due_date, acting_user, assignment_source]
		}
	]

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonPathwayRequirementAssigned",
		"requirement_uuid": preq_uuid,
		"person_pathway_program_year_id": person_pathway_program_year_id,
		"title": title,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayRequirementAssigned', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, preq_uuid, JSON.stringify(payload_dict)]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]: return {"success": false, "error": res["error"]}

	var id_q = db.execute("SELECT id FROM person_pathway_requirements WHERE uuid = ? LIMIT 1;", [preq_uuid])
	var req_id = int(id_q["data"][0]["id"]) if (id_q["success"] and id_q["data"].size() > 0) else 0

	return {"success": true, "requirement_id": req_id}

func create_catch_up_requirement(person_pathway_program_year_id: int, title: String, description: String = "", due_date: String = "", acting_user: String = "System") -> Dictionary:
	return assign_individual_requirement(person_pathway_program_year_id, title, description, "catch_up", "required", due_date, "catch_up", acting_user)

func mark_requirement_complete(person_pathway_requirement_id: int, completion_notes: String = "", acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var req_q = db.execute("SELECT uuid FROM person_pathway_requirements WHERE id = ? LIMIT 1;", [person_pathway_requirement_id])
	if not req_q["success"] or req_q["data"].size() == 0: return {"success": false, "error": "Requirement not found."}
	var req_uuid = str(req_q["data"][0]["uuid"])

	var event_uuid = _generate_uuid("evt")
	var stmts = [
		{
			"sql": "UPDATE person_pathway_requirements SET status = 'completed', completed_at = datetime('now'), completion_notes = ?, completed_by = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [completion_notes, acting_user, person_pathway_requirement_id]
		}
	]

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonPathwayRequirementCompleted",
		"requirement_uuid": req_uuid,
		"acting_user": acting_user,
		"timestamp": Time.get_datetime_string_from_system()
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonPathwayRequirementCompleted', 'Pathways', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [event_uuid, req_uuid, JSON.stringify(payload_dict)]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func mark_requirement_incomplete(person_pathway_requirement_id: int, acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var sql = "UPDATE person_pathway_requirements SET status = 'assigned', completed_at = NULL, completion_notes = NULL, completed_by = NULL, updated_at = datetime('now') WHERE id = ?;"
	var res = db.execute(sql, [person_pathway_requirement_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func update_requirement(person_pathway_requirement_id: int, new_title: String, new_category: String = "requirement", new_due_date: String = "", acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var sql = "UPDATE person_pathway_requirements SET title = ?, requirement_category = ?, due_date = ?, updated_at = datetime('now') WHERE id = ?;"
	var due_val = new_due_date if new_due_date != "" else null
	var res = db.execute(sql, [new_title, new_category, due_val, person_pathway_requirement_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func delete_requirement(person_pathway_requirement_id: int, acting_user: String = "System") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var sql = "DELETE FROM person_pathway_requirements WHERE id = ?;"
	var res = db.execute(sql, [person_pathway_requirement_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func update_program_year_status(person_pathway_program_year_id: int, status: String) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var norm_status = status.to_lower().replace(" ", "_")
	var valid_statuses = ["active", "on_hold", "inactive"]
	if not norm_status in valid_statuses:
		norm_status = "active"
	var sql = "UPDATE person_pathway_program_years SET status = ?, updated_at = datetime('now') WHERE id = ?;"
	var res = db.execute(sql, [norm_status, person_pathway_program_year_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func update_pathway_notes(person_pathway_id: int, notes: String) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var sql = "UPDATE person_pathways SET general_notes = ?, updated_at = datetime('now') WHERE id = ?;"
	var res = db.execute(sql, [notes, person_pathway_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func get_staff_and_interns() -> Array:
	if not db: return []
	var res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, system_role FROM people WHERE LOWER(system_role) LIKE '%staff%' OR LOWER(system_role) LIKE '%intern%' OR LOWER(system_role) LIKE '%leader%' OR LOWER(system_role) LIKE '%admin%' ORDER BY last_name ASC, first_name ASC;")
	if res["success"] and res["data"].size() > 0:
		return res["data"]
	var fb = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, system_role FROM people ORDER BY last_name ASC, first_name ASC LIMIT 50;")
	return fb["data"] if (fb["success"] and fb["data"].size() > 0) else []

func add_pathway_running_note(person_pathway_id: int, note_text: String, author_person_id: Variant = null, author_name: String = "Staff User") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var note_uuid = _generate_uuid("nt")
	var sql = "INSERT INTO person_pathway_running_notes (uuid, person_pathway_id, note_text, author_person_id, author_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'));"
	var res = db.execute(sql, [note_uuid, person_pathway_id, note_text, author_person_id, author_name])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func get_pathway_running_notes(person_pathway_id: int) -> Array:
	if not db: return []
	var sql = "SELECT id, uuid, person_pathway_id, note_text, author_person_id, author_name, created_at, updated_at FROM person_pathway_running_notes WHERE person_pathway_id = ? ORDER BY created_at DESC;"
	var res = db.execute(sql, [person_pathway_id])
	return res["data"] if (res["success"] and res["data"].size() > 0) else []

func update_pathway_running_note(note_id: int, note_text: String, author_person_id: Variant = null, author_name: String = "Staff User") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var sql = "UPDATE person_pathway_running_notes SET note_text = ?, author_person_id = ?, author_name = ?, updated_at = datetime('now') WHERE id = ?;"
	var res = db.execute(sql, [note_text, author_person_id, author_name, note_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func delete_pathway_running_note(note_id: int) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}
	var sql = "DELETE FROM person_pathway_running_notes WHERE id = ?;"
	var res = db.execute(sql, [note_id])
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func assign_pathway_mentor(person_pathway_id: int, mentor_person_id: int) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var stmts = [
		{
			"sql": "UPDATE person_pathways SET assigned_mentor_person_id = ?, updated_at = datetime('now') WHERE id = ?;",
			"args": [mentor_person_id, person_pathway_id]
		},
		{
			"sql": "UPDATE person_pathway_program_years SET mentor_person_id = ?, updated_at = datetime('now') WHERE person_pathway_id = ?;",
			"args": [mentor_person_id, person_pathway_id]
		}
	]
	var res = db.execute_transaction(stmts)
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func remove_pathway_mentor(person_pathway_id: int) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var stmts = [
		{
			"sql": "UPDATE person_pathways SET assigned_mentor_person_id = NULL, updated_at = datetime('now') WHERE id = ?;",
			"args": [person_pathway_id]
		},
		{
			"sql": "UPDATE person_pathway_program_years SET mentor_person_id = NULL, updated_at = datetime('now') WHERE person_pathway_id = ?;",
			"args": [person_pathway_id]
		}
	]
	var res = db.execute_transaction(stmts)
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {"success": true}

func get_pathway_history(person_pathway_id: int) -> Array:
	if not db: return []
	var trail = []

	# 0. Initial Enrollment
	var en_q = db.execute("SELECT started_at, created_at FROM person_pathways WHERE id = ? LIMIT 1;", [person_pathway_id])
	if en_q["success"] and en_q["data"].size() > 0:
		var ts = str(en_q["data"][0].get("started_at", en_q["data"][0].get("created_at", "")))
		trail.append({
			"type": "enrollment",
			"timestamp": ts,
			"description": "Initial pathway enrollment recorded",
			"details": "Enrollment recorded on " + ts
		})

	# 1. Track Changes
	var th_q = db.execute("SELECT previous_track, new_track, changed_by, reason, catch_up_plan, effective_at FROM person_pathway_track_history WHERE person_pathway_id = ?;", [person_pathway_id])
	if th_q["success"]:
		for r in th_q["data"]:
			trail.append({
				"type": "track_change",
				"timestamp": r.get("effective_at"),
				"description": "Track changed from '%s' to '%s' by %s" % [str(r.get("previous_track")).to_upper(), str(r.get("new_track")).to_upper(), str(r.get("changed_by"))],
				"details": str(r.get("reason", ""))
			})

	# 2. Standing Changes
	var sh_q = db.execute("SELECT previous_standing, new_standing, changed_by, reason, catch_up_plan, effective_at FROM person_pathway_standing_history WHERE person_pathway_id = ?;", [person_pathway_id])
	if sh_q["success"]:
		for r in sh_q["data"]:
			trail.append({
				"type": "standing_change",
				"timestamp": r.get("effective_at"),
				"description": "Standing changed from '%s' to '%s' by %s" % [str(r.get("previous_standing")).to_upper(), str(r.get("new_standing")).to_upper(), str(r.get("changed_by"))],
				"details": str(r.get("reason", ""))
			})

	# 3. Requirement Assignments & Completions
	var req_q = db.execute("""
		SELECT pr.title, pr.status, pr.assigned_date, pr.completed_at, pr.assigned_by, pr.completed_by, pr.assignment_source
		FROM person_pathway_requirements pr
		JOIN person_pathway_program_years ppy ON ppy.id = pr.person_pathway_program_year_id
		WHERE ppy.person_pathway_id = ?;
	""", [person_pathway_id])

	if req_q["success"]:
		for r in req_q["data"]:
			trail.append({
				"type": "requirement_assigned",
				"timestamp": r.get("assigned_date"),
				"description": "Assigned requirement '%s' (%s)" % [str(r.get("title")), str(r.get("assignment_source")).to_upper()],
				"details": "Assigned by " + str(r.get("assigned_by", "System"))
			})
			if str(r.get("status")) == "completed" and r.get("completed_at") != null:
				trail.append({
					"type": "requirement_completed",
					"timestamp": r.get("completed_at"),
					"description": "Completed requirement '%s'" % [str(r.get("title"))],
					"details": "Completed by " + str(r.get("completed_by", "System"))
				})

	# Sort trail by timestamp descending
	trail.sort_custom(func(a, b): return str(a.get("timestamp")) > str(b.get("timestamp")))
	return trail

func export_program_roster_csv(pathway_program_year_id: int) -> String:
	var participants = get_program_participants(pathway_program_year_id)
	var csv = "Human_ID,First_Name,Last_Name,Track,Standing,Enrollment_Status,Requirements_Completed,Total_Requirements,Mentor_Name,Notes\n"
	for p in participants:
		var line = '"%s","%s","%s","%s","%s","%s",%d,%d,"%s","%s"\n' % [
			str(p.get("human_id", "")),
			str(p.get("first_name", "")),
			str(p.get("last_name", "")),
			str(p.get("track_for_that_year", "standard")).to_upper(),
			str(p.get("standing_for_that_year", "year_1")).replace("_", " ").to_upper(),
			str(p.get("participation_status", "active")).to_upper(),
			int(p.get("completed_requirements", 0)),
			int(p.get("total_requirements", 0)),
			str(p.get("mentor_name", "")),
			str(p.get("annual_plan_notes", "")).replace('"', '""')
		]
		csv += line
	return csv

# --- STAGE 5 LEGACY MIGRATION, STAGING, & CUTOVER SERVICE METHODS ---

func import_legacy_tracks_to_staging(migration_batch_id: String = "", acting_user: String = "usr_admin_master") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var auth = authorize_admin_operation(acting_user, "CAP_PATHWAYS_MIGRATION")
	if not auth["authorized"]:
		return {"success": false, "error": auth["error"]}

	var batch_id = migration_batch_id
	if batch_id == "":
		var dt = Time.get_datetime_dict_from_system()
		batch_id = "batch_%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]

	var leg_q = db.execute("SELECT id, person_id, real_life_enrolled, fellows_enrolled, fellows_certificate, lead_enrolled, lead_certificate, lead_current_year FROM legacy_pathway_tracks;")
	if not leg_q["success"]:
		return {"success": false, "error": leg_q["error"]}

	var rows = leg_q["data"]
	var imported_cnt = 0
	var conflict_cnt = 0
	var stmts = []

	for r in rows:
		var pid = int(r["person_id"])

		# Idempotency check: check if already staged in this batch
		var check_q = db.execute("SELECT id FROM legacy_pathway_migration_staging WHERE source_person_id = ? AND migration_batch_id = ? LIMIT 1;", [pid, batch_id])
		if check_q["success"] and check_q["data"].size() > 0:
			continue

		var f_en = int(r.get("fellows_enrolled", 0))
		var f_cert = int(r.get("fellows_certificate", 0))
		var l_en = int(r.get("lead_enrolled", 0))
		var l_cert = int(r.get("lead_certificate", 0))
		var l_yr = str(r.get("lead_current_year", ""))

		var f_act = "none"
		if f_cert == 1: f_act = "convert_certification"
		elif f_en == 1: f_act = "convert_standard"

		var l_act = "none"
		if l_cert == 1: l_act = "convert_certification"
		elif l_en == 1: l_act = "convert_standard"

		var warn = ""
		if f_cert == 1 and f_en == 0: warn += "Fellows Cert=1 without Fellows Enrolled=1; "
		if l_cert == 1 and l_en == 0: warn += "LEAD Cert=1 without LEAD Enrolled=1; "
		if l_en == 1 and l_yr == "": warn += "LEAD Enrolled=1 but Standing Year missing; "

		var status = "pending_review"
		if warn != "":
			status = "conflict"
			conflict_cnt += 1

		# Snapshot JSON
		var snap = JSON.stringify(r)

		stmts.append({
			"sql": """
				INSERT INTO legacy_pathway_migration_staging (
					source_legacy_id, source_person_id, real_life_enrolled, fellows_enrolled, fellows_certificate,
					lead_enrolled, lead_certificate, lead_current_year, source_snapshot_json, migration_batch_id,
					review_status, selected_fellows_action, selected_lead_action, validation_warnings
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
			""",
			"args": [r.get("id"), pid, int(r.get("real_life_enrolled", 0)), f_en, f_cert, l_en, l_cert, l_yr, snap, batch_id, status, f_act, l_act, warn]
		})
		imported_cnt += 1

	if stmts.size() > 0:
		var res = db.execute_transaction(stmts)
		if not res["success"]: return {"success": false, "error": res["error"]}

	return {
		"success": true,
		"batch_id": batch_id,
		"imported_count": imported_cnt,
		"conflict_count": conflict_cnt
	}

func get_staging_records(status_filter: String = "all", batch_id: String = "") -> Array:
	if not db: return []
	var sql = """
		SELECT st.*, p.first_name, p.last_name, p.human_id
		FROM legacy_pathway_migration_staging st
		JOIN people p ON p.id = st.source_person_id
	"""
	var args = []
	var wheres = []
	if status_filter != "all":
		wheres.append("st.review_status = ?")
		args.append(status_filter)
	if batch_id != "":
		wheres.append("st.migration_batch_id = ?")
		args.append(batch_id)

	if wheres.size() > 0:
		sql += " WHERE " + " AND ".join(wheres)

	sql += " ORDER BY p.last_name ASC, p.first_name ASC;"
	var res = db.execute(sql, args)
	return res["data"] if res["success"] else []

func get_staging_summary() -> Dictionary:
	if not db: return {}
	var sql = """
		SELECT 
			COUNT(*) as total_staged,
			SUM(CASE WHEN review_status = 'pending_review' THEN 1 ELSE 0 END) as pending_review,
			SUM(CASE WHEN review_status = 'ready_to_convert' THEN 1 ELSE 0 END) as ready_to_convert,
			SUM(CASE WHEN review_status = 'converted' THEN 1 ELSE 0 END) as converted,
			SUM(CASE WHEN review_status = 'conflict' THEN 1 ELSE 0 END) as conflicts,
			SUM(CASE WHEN review_status = 'archived' THEN 1 ELSE 0 END) as archived,
			SUM(CASE WHEN review_status = 'rolled_back' THEN 1 ELSE 0 END) as rolled_back
		FROM legacy_pathway_migration_staging;
	"""
	var res = db.execute(sql)
	return res["data"][0] if (res["success"] and res["data"].size() > 0) else {}

func authorize_admin_operation(acting_user: String, permission_key: String = "CAP_PATHWAYS_MIGRATION") -> Dictionary:
	if not db:
		return {"authorized": false, "error": "Database engine not initialized."}

	var clean_caller = acting_user.strip_edges()
	if clean_caller == "":
		return {"authorized": false, "error": "Unauthenticated access rejected: acting user ID is required."}

	# Check app_settings for active session user (Impersonation Protection)
	var id_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CURRENT_USER_ID';")
	var active_user_id = str(id_res["data"][0]["setting_value"]).strip_edges() if (id_res["success"] and id_res["data"].size() > 0) else ""

	if active_user_id != "" and active_user_id != clean_caller:
		return {"authorized": false, "error": "Impersonation rejected: caller '%s' does not match authenticated session user '%s'." % [clean_caller, active_user_id]}

	var target_user = active_user_id if active_user_id != "" else clean_caller

	# Check canonical capability setting from app_settings
	var cap_key = permission_key + "_SUPERVISOR"
	var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = ?;", [cap_key])
	var cap_allowed = true
	if setting_res["success"] and setting_res["data"].size() > 0:
		var val = str(setting_res["data"][0].get("setting_value", "true")).to_lower()
		if val == "false":
			cap_allowed = false

	# Query canonical role from people directory table
	var user_res = db.execute("SELECT primary_role FROM people WHERE person_uuid = ? OR human_id = ? OR id = ? LIMIT 1;", [target_user, target_user, int(target_user) if target_user.is_valid_int() else 0])
	
	if user_res["success"] and user_res["data"].size() > 0:
		var role = str(user_res["data"][0].get("primary_role", "")).to_lower()
		if role == "administrator" and cap_allowed:
			return {"authorized": true, "error": "", "actor_id": target_user}

	return {"authorized": false, "error": "User '%s' lacks administrative capability '%s' for migration operations." % [target_user, permission_key]}

func convert_staging_record(staging_id: int, academic_year: String, convert_fellows: bool, convert_lead: bool, override_track: String = "", override_standing: String = "", acting_user: String = "Admin", force_fail_step: bool = false) -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var auth = authorize_admin_operation(acting_user)
	if not auth["authorized"]:
		return {"success": false, "error": auth["error"]}

	if academic_year.strip_edges() == "":
		return {"success": false, "error": "Academic year is required for conversion."}
	if not convert_fellows and not convert_lead:
		return {"success": false, "error": "At least one program (Fellows or LEAD) must be selected for conversion."}

	var st_q = db.execute("SELECT * FROM legacy_pathway_migration_staging WHERE id = ? LIMIT 1;", [staging_id])
	if not st_q["success"] or st_q["data"].size() == 0:
		return {"success": false, "error": "Staged record not found."}

	var st = st_q["data"][0]
	var person_id = int(st["source_person_id"])
	var batch_id = str(st["migration_batch_id"])

	var created_ppids = []
	var stmts = []

	# 1. Fellows Conversion
	if convert_fellows:
		var tr = override_track if override_track != "" else ("certification" if str(st["selected_fellows_action"]) == "convert_certification" or int(st["fellows_certificate"]) == 1 else "standard")
		var st_val = override_standing if override_standing != "" else "year_1"

		# Check existing
		var chk = db.execute("SELECT id FROM person_pathways WHERE person_id = ? AND pathway_id = (SELECT id FROM pathways WHERE pathway_key = 'fellows') LIMIT 1;", [person_id])
		if chk["success"] and chk["data"].size() > 0:
			db.execute("UPDATE legacy_pathway_migration_staging SET review_status = 'conflict', validation_warnings = 'Fellows modern enrollment already exists for this constituent.' WHERE id = ?;", [staging_id])
			return {"success": false, "error": "Fellows modern enrollment already exists for this constituent."}

		var pp_res = enroll_person_pathway(person_id, "fellows", academic_year, tr, st_val, null, "Imported from legacy_pathway_tracks")
		if not pp_res["success"]: return {"success": false, "error": pp_res["error"]}
		var ppid = int(pp_res["person_pathway_id"])
		created_ppids.append(ppid)

		stmts.append({
			"sql": "UPDATE person_pathways SET migration_batch_id = ?, source_staging_id = ? WHERE id = ?;",
			"args": [batch_id, staging_id, ppid]
		})
		stmts.append({
			"sql": "UPDATE person_pathway_program_years SET migration_batch_id = ? WHERE person_pathway_id = ?;",
			"args": [batch_id, ppid]
		})

	# 2. LEAD Conversion
	if convert_lead:
		var tr = override_track if override_track != "" else ("certification" if str(st["selected_lead_action"]) == "convert_certification" or int(st["lead_certificate"]) == 1 else "standard")
		var st_val = override_standing if override_standing != "" else (_map_lead_year_to_standing(str(st["lead_current_year"])))

		# Check existing
		var chk = db.execute("SELECT id FROM person_pathways WHERE person_id = ? AND pathway_id = (SELECT id FROM pathways WHERE pathway_key = 'lead') LIMIT 1;", [person_id])
		if chk["success"] and chk["data"].size() > 0:
			# Roll back created Fellows if LEAD failed check
			_cleanup_created_ppids(created_ppids)
			db.execute("UPDATE legacy_pathway_migration_staging SET review_status = 'conflict', validation_warnings = 'LEAD modern enrollment already exists for this constituent.' WHERE id = ?;", [staging_id])
			return {"success": false, "error": "LEAD modern enrollment already exists for this constituent."}

		var pp_res = enroll_person_pathway(person_id, "lead", academic_year, tr, st_val, null, "Imported from legacy_pathway_tracks")
		if not pp_res["success"]:
			_cleanup_created_ppids(created_ppids)
			return {"success": false, "error": pp_res["error"]}
		var ppid = int(pp_res["person_pathway_id"])
		created_ppids.append(ppid)

		stmts.append({
			"sql": "UPDATE person_pathways SET migration_batch_id = ?, source_staging_id = ? WHERE id = ?;",
			"args": [batch_id, staging_id, ppid]
		})
		stmts.append({
			"sql": "UPDATE person_pathway_program_years SET migration_batch_id = ? WHERE person_pathway_id = ?;",
			"args": [batch_id, ppid]
		})

	# 3. Update Staging Record Status
	stmts.append({
		"sql": "UPDATE legacy_pathway_migration_staging SET review_status = 'converted', reviewed_by = ?, reviewed_at = datetime('now'), selected_academic_year = ?, updated_at = datetime('now') WHERE id = ?;",
		"args": [acting_user, academic_year, staging_id]
	})

	if force_fail_step:
		stmts.append({"sql": "INSERT INTO non_existent_table_for_forced_failure VALUES (1);", "args": []})

	var res = db.execute_transaction(stmts)
	if not res["success"]:
		_cleanup_created_ppids(created_ppids)
		return {"success": false, "error": "Conversion transaction failed: " + res["error"]}

	return {"success": true}

func rollback_migration_batch(migration_batch_id: String, acting_user: String = "Admin") -> Dictionary:
	if not db: return {"success": false, "error": "Database reference is null."}

	var auth = authorize_admin_operation(acting_user)
	if not auth["authorized"]:
		return {"success": false, "error": auth["error"]}

	var pp_q = db.execute("SELECT id FROM person_pathways WHERE migration_batch_id = ?;", [migration_batch_id])
	if not pp_q["success"]: return {"success": false, "error": pp_q["error"]}

	var pp_ids = []
	var skipped_cnt = 0
	for row in pp_q["data"]:
		var ppid = int(row["id"])

		# Check downstream edit safety: requirement created/completed or standing history
		var req_check = db.execute("""
			SELECT COUNT(*) as cnt FROM person_pathway_requirements pr
			JOIN person_pathway_program_years ppy ON ppy.id = pr.person_pathway_program_year_id
			WHERE ppy.person_pathway_id = ?;
		""", [ppid])

		var cnt = req_check["data"][0]["cnt"] if (req_check["success"] and req_check["data"].size() > 0) else 0
		if cnt > 0:
			skipped_cnt += 1
			continue
		pp_ids.append(ppid)

	var stmts = []
	for ppid in pp_ids:
		stmts.append({"sql": "DELETE FROM person_pathway_program_years WHERE person_pathway_id = ?;", "args": [ppid]})
		stmts.append({"sql": "DELETE FROM person_pathway_track_history WHERE person_pathway_id = ?;", "args": [ppid]})
		stmts.append({"sql": "DELETE FROM person_pathway_standing_history WHERE person_pathway_id = ?;", "args": [ppid]})
		stmts.append({"sql": "DELETE FROM person_pathways WHERE id = ?;", "args": [ppid]})

	stmts.append({
		"sql": "UPDATE legacy_pathway_migration_staging SET review_status = 'rolled_back', reviewed_by = ?, reviewed_at = datetime('now'), updated_at = datetime('now') WHERE migration_batch_id = ? AND review_status = 'converted';",
		"args": [acting_user, migration_batch_id]
	})

	var res = db.execute_transaction(stmts)
	if not res["success"]: return {"success": false, "error": res["error"]}
	return {
		"success": true,
		"rolled_back_count": pp_ids.size(),
		"skipped_due_to_downstream_activity": skipped_cnt
	}

func dry_run_migration(migration_batch_id: String = "") -> Dictionary:
	var staging = get_staging_records("all", migration_batch_id)
	var report = {
		"total_staged": staging.size(),
		"proposed_fellows": 0,
		"proposed_lead": 0,
		"real_life_historical": 0,
		"conflicts": 0,
		"ready_to_convert": 0
	}

	for s in staging:
		if int(s.get("real_life_enrolled", 0)) == 1: report["real_life_historical"] += 1
		if str(s.get("selected_fellows_action")) != "none": report["proposed_fellows"] += 1
		if str(s.get("selected_lead_action")) != "none": report["proposed_lead"] += 1

		if str(s.get("review_status")) == "conflict": report["conflicts"] += 1
		else: report["ready_to_convert"] += 1

	return report

func _cleanup_created_ppids(ppids: Array) -> void:
	if not db or ppids.size() == 0: return
	for ppid in ppids:
		db.execute("DELETE FROM person_pathway_program_years WHERE person_pathway_id = ?;", [ppid])
		db.execute("DELETE FROM person_pathway_track_history WHERE person_pathway_id = ?;", [ppid])
		db.execute("DELETE FROM person_pathway_standing_history WHERE person_pathway_id = ?;", [ppid])
		db.execute("DELETE FROM person_pathways WHERE id = ?;", [ppid])

func _map_lead_year_to_standing(lead_year_str: String) -> String:
	match lead_year_str:
		"Year 1": return "year_1"
		"Year 2": return "year_2"
		"Year 3": return "year_3"
		"Year 4": return "year_4"
		_: return "year_1"

func _generate_uuid(prefix: String) -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	return (prefix + "_" + b1 + "-" + b2).to_lower()

