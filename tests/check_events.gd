extends SceneTree

func _init():
	var db = load("res://src/infrastructure/database/sqlite_database.gd").new()
	var path = OS.get_user_data_dir() + "/studycenterhub_production.db"
	db.open_db(path)
	var res = db.execute("SELECT * FROM inbound_event_queue ORDER BY id DESC LIMIT 15;")
	print("==========================================")
	print("RECENT INBOUND EVENTS IN PRODUCTION DB:")
	if res["success"]:
		for r in res["data"]:
			print("ID:", r.get("id"), " Type:", r.get("event_type"), " Processed:", r.get("processed"), " Payload:", r.get("payload_json"), " Result:", r.get("result_json"))
	else:
		print("Error:", res["error"])
	print("==========================================")

	var p_res = db.execute("SELECT id, first_name, last_name, phone_e164, created_at FROM people ORDER BY id DESC LIMIT 10;")
	print("RECENT PEOPLE IN PRODUCTION DB:")
	if p_res["success"]:
		for r in p_res["data"]:
			print("ID:", r.get("id"), " Name:", r.get("first_name"), r.get("last_name"), " Phone:", r.get("phone_e164"), " Created:", r.get("created_at"))
	print("==========================================")
	quit()
