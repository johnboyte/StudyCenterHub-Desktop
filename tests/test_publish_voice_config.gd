extends SceneTree

func _init():
	call_deferred("_start")

func _start():
	print("\n==========================================================")
	print("PUBLISHING UPDATED NEURAL VOICE CONFIG TO SITEGROUND RELAY")
	print("==========================================================\n")
	
	var user_dir = OS.get_user_data_dir()
	var db_path = user_dir + "/studycenterhub_production.db"
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var db = SQLiteScript.new(db_path)
	
	var root_node = Node.new()
	get_root().add_child(root_node)

	var SyncScript = load("res://src/domain/sync/gateway_sync_service.gd")
	var sync_svc = SyncScript.new(db, root_node)
	
	sync_svc.publish_ivr_config(func(res: Dictionary):
		print("[Publish Result]: ", res)
		if res.get("success", false) == true:
			print("\n==========================================================")
			print("PASS: NEURAL VOICE CONFIG PUBLISHED TO SITEGROUND")
			print("==========================================================\n")
		else:
			print("FAIL: Config publish failed.")
		quit()
	)
