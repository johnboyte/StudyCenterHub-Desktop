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

	var pw_res = db.execute("SELECT AVG(progress_percent) as avg_prog FROM person_pathways WHERE status = 'active';")
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

func generate_csv_report() -> String:
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
