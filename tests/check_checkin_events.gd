extends SceneTree

func _init():
	var db = load("res://src/infrastructure/database/sqlite_database.gd").new()
	var path = OS.get_user_data_dir() + "/studycenterhub_production.db"
	db.open_db(path)

	print("==========================================")
	print("RECENT PORTAL CHECKIN EVENTS IN PRODUCTION DB:")
	var res = db.execute("SELECT * FROM inbound_event_queue WHERE event_type = 'portal.checkin' ORDER BY id DESC LIMIT 10;")
	if res["success"]:
		for r in res["data"]:
			print("ID:", r.get("id"), " Processed:", r.get("processed"), " Status:", r.get("status"), " Result:", r.get("result_json"), " Payload:", r.get("payload_json"))
	else:
		print("Error:", res["error"])

	print("==========================================")
	print("ALL RECENT INBOUND EVENTS:")
	var all_res = db.execute("SELECT id, provider_event_id, event_type, processed, status, result_json, created_at FROM inbound_event_queue ORDER BY id DESC LIMIT 15;")
	if all_res["success"]:
		for r in all_res["data"]:
			print("ID:", r.get("id"), " Type:", r.get("event_type"), " Processed:", r.get("processed"), " Status:", r.get("status"), " Result:", r.get("result_json"), " Created:", r.get("created_at"))

	print("==========================================")
	print("RECENT ATTENDANCE LOG ROWS:")
	var att = db.execute("SELECT * FROM attendance_log ORDER BY id DESC LIMIT 10;")
	if att["success"]:
		for r in att["data"]:
			print("ID:", r.get("id"), " PersonID:", r.get("person_id"), " Name:", r.get("first_name"), r.get("last_name"), " Date:", r.get("check_in_date"), " Source:", r.get("source"))

	print("==========================================")
	quit()
