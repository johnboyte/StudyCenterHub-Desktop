extends SceneTree

func _init():
	var db = load("res://src/infrastructure/database/sqlite_database.gd").new()
	var path = OS.get_user_data_dir() + "/studycenterhub_production.db"
	db.open_db(path)

	var res = db.execute("SELECT * FROM inbound_event_queue WHERE id = 4;")
	if res["success"] and res["data"].size() > 0:
		var r = res["data"][0]
		print("==========================================")
		print("EVENT ID 4 DETAILS:")
		print("ID:", r.get("id"))
		print("Provider Event ID:", r.get("provider_event_id"))
		print("Type:", r.get("event_type"))
		print("Payload JSON:", r.get("payload_json"))
		print("Processed:", r.get("processed"))
		print("Status:", r.get("status"))
		print("Result JSON:", r.get("result_json"))
		print("Created At:", r.get("created_at"))
		print("==========================================")

	quit()
