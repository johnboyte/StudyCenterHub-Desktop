extends RefCounted

## Operational Reports & Analytics Domain Service (REP-SPR1-001)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func get_summary_kpis() -> Dictionary:
	var today_date = Time.get_date_string_from_system()

	var att_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE check_in_date = ?;", [today_date])
	var checkins_today = att_res["data"][0]["cnt"] if att_res["success"] and att_res["data"].size() > 0 else 0

	var people_res = db.execute("SELECT COUNT(*) as cnt FROM people WHERE status = 'active';")
	var active_people = people_res["data"][0]["cnt"] if people_res["success"] and people_res["data"].size() > 0 else 0

	var total_people_res = db.execute("SELECT COUNT(*) as cnt FROM people;")
	var total_people = total_people_res["data"][0]["cnt"] if total_people_res["success"] and total_people_res["data"].size() > 0 else 0

	var pw_res = db.execute("""
		SELECT AVG(CASE 
			WHEN req_stats.total_reqs > 0 THEN (req_stats.completed_reqs * 100.0 / req_stats.total_reqs)
			ELSE 0.0
		END) as avg_prog
		FROM person_pathways pp
		JOIN (
			SELECT ppy.person_pathway_id,
			       COUNT(*) as total_reqs,
			       SUM(CASE WHEN pr.status = 'completed' THEN 1 ELSE 0 END) as completed_reqs
			FROM person_pathway_requirements pr
			JOIN person_pathway_program_years ppy ON ppy.id = pr.person_pathway_program_year_id
			GROUP BY ppy.person_pathway_id
		) req_stats ON req_stats.person_pathway_id = pp.id
		WHERE pp.enrollment_status != 'withdrawn';
	""")
	var avg_progress = int(pw_res["data"][0]["avg_prog"]) if pw_res["success"] and pw_res["data"].size() > 0 and pw_res["data"][0]["avg_prog"] != null else 0

	return {
		"checkins_today": checkins_today,
		"active_people": active_people,
		"total_people": total_people,
		"avg_pathway_progress": avg_progress
	}

func get_grade_distribution() -> Array:
	var res = db.execute("SELECT grade, COUNT(*) as count FROM people GROUP BY grade ORDER BY count DESC;")
	if res["success"]:
		return res["data"]
	return []

func get_participants_by_institution() -> Array:
	var res = db.execute("SELECT COALESCE(i.name, NULLIF(p.institution_other_name, ''), 'Unspecified / None') AS institution_name, COUNT(*) AS count FROM people p LEFT JOIN institutions i ON p.institution_id = i.id WHERE p.status = 'active' GROUP BY institution_name ORDER BY count DESC;")
	return res["data"] if res["success"] else []

func get_participants_by_academic_year() -> Array:
	var res = db.execute("SELECT COALESCE(NULLIF(academic_year, ''), 'Unspecified') AS ay_name, COUNT(*) AS count FROM people WHERE status = 'active' GROUP BY ay_name ORDER BY count DESC;")
	return res["data"] if res["success"] else []

func get_participants_by_major() -> Array:
	var res = db.execute("SELECT COALESCE(NULLIF(major, ''), 'Unspecified') AS major_name, COUNT(*) AS count FROM people WHERE status = 'active' AND major IS NOT NULL AND major != '' GROUP BY major_name ORDER BY count DESC LIMIT 10;")
	return res["data"] if res["success"] else []

func get_alumni_by_institution() -> Array:
	var res = db.execute("SELECT COALESCE(i.name, 'Unspecified') AS institution_name, COUNT(*) AS count FROM people p LEFT JOIN institutions i ON p.institution_id = i.id WHERE p.relationship = 'Alumni' GROUP BY institution_name ORDER BY count DESC;")
	return res["data"] if res["success"] else []

func get_campus_vs_community_stats() -> Dictionary:
	var res = db.execute("""
		SELECT 
			SUM(CASE WHEN i.institution_type IN ('college_university', 'high_school') THEN 1 ELSE 0 END) AS campus_count,
			SUM(CASE WHEN i.institution_type = 'community' OR p.relationship = 'Community Member' THEN 1 ELSE 0 END) AS community_count,
			SUM(CASE WHEN p.institution_id IS NULL AND (p.relationship IS NULL OR p.relationship != 'Community Member') THEN 1 ELSE 0 END) AS unassigned_count
		FROM people p
		LEFT JOIN institutions i ON p.institution_id = i.id
		WHERE p.status = 'active';
	""")
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {"campus_count": 0, "community_count": 0, "unassigned_count": 0}

func get_expected_graduates_breakdown() -> Array:
	var res = db.execute("SELECT expected_grad_year, expected_grad_term, COUNT(*) AS count FROM people WHERE expected_grad_year IS NOT NULL GROUP BY expected_grad_year, expected_grad_term ORDER BY expected_grad_year ASC, expected_grad_term ASC;")
	return res["data"] if res["success"] else []

func generate_csv_report(include_campus_community: bool = false) -> String:
	if not include_campus_community:
		var csv = "Human_ID,First_Name,Last_Name,Grade,Status,Phone\n"
		var res = db.execute("SELECT human_id, first_name, last_name, grade, status, phone FROM people ORDER BY last_name ASC, first_name ASC;")
		if res["success"] and res["data"].size() > 0:
			for r in res["data"]:
				var hid = str(r.get("human_id", ""))
				var fn = str(r.get("first_name", ""))
				var ln = str(r.get("last_name", ""))
				var gr = str(r.get("grade", ""))
				var st = str(r.get("status", ""))
				var ph = str(r.get("phone", ""))
				csv += "%s,%s,%s,%s,%s,%s\n" % [hid, fn, ln, gr, st, ph]
		return csv
	else:
		var csv = "Human_ID,First_Name,Last_Name,Institution,Relationship,Academic_Year,Major,Residence,Expected_Graduation,Status,Phone\n"
		var res = db.execute("SELECT p.human_id, p.first_name, p.last_name, COALESCE(i.name, p.institution_other_name, '') AS inst_name, p.relationship, p.academic_year, p.major, p.residence, p.expected_grad_term, p.expected_grad_year, p.status, p.phone FROM people p LEFT JOIN institutions i ON p.institution_id = i.id ORDER BY p.last_name ASC, p.first_name ASC;")
		if res["success"] and res["data"].size() > 0:
			for r in res["data"]:
				var hid = str(r.get("human_id", ""))
				var fn = str(r.get("first_name", ""))
				var ln = str(r.get("last_name", ""))
				var inst = str(r.get("inst_name", ""))
				var rel = str(r.get("relationship", ""))
				var ay = str(r.get("academic_year", ""))
				var mj = str(r.get("major", ""))
				var res_type = str(r.get("residence", ""))
				var gt = str(r.get("expected_grad_term", ""))
				var gy = str(r.get("expected_grad_year", ""))
				var grad_str = (gt + " " + gy).strip_edges()
				var st = str(r.get("status", ""))
				var ph = str(r.get("phone", ""))
				csv += "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" % [hid, fn, ln, inst, rel, ay, mj, res_type, grad_str, st, ph]
		return csv
