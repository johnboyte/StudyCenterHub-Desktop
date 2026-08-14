extends SceneTree

func _init():
	var db = load("res://src/infrastructure/database/sqlite_database.gd").new()
	var path = OS.get_user_data_dir() + "/studycenterhub_production.db"
	db.open_db(path)
	var res = db.execute("SELECT * FROM app_settings;")
	print("==========================================")
	print("APP SETTINGS IN PRODUCTION DB:")
	if res["success"]:
		for row in res["data"]:
			print(row["setting_key"], " => ", row["setting_value"])
	print("==========================================")
	quit()
