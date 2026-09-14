extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	print("==========================================================")
	print("REPUBLISHING REAL PRODUCTION IVR CONFIGURATION")
	print("==========================================================")
	
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	var db = SQLiteDatabaseScript.new(prod_db_path)
	
	var root_node = Node.new()
	get_root().add_child(root_node)
	
	var sync_svc = GatewaySyncServiceScript.new(db, root_node)
	sync_svc.publish_ivr_config(func(res: Dictionary):
		if res.get("success", false):
			print("✅ SUCCESS: Successfully republished real Production IVR configuration!")
			quit(0)
		else:
			print("❌ FAIL: Republishing IVR config failed: ", res.get("error", ""))
			quit(1)
	)
