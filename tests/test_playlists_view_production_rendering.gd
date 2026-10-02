extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")

func _init() -> void:
	print("\n=======================================================")
	print("  TESTING PLAYLISTS VIEW PRODUCTION RENDERING")
	print("=======================================================\n")

	var prod_db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
	var db = SQLiteDatabaseScript.new(prod_db_path)

	var direct_res = db.execute("SELECT * FROM playlists ORDER BY sort_order ASC, created_at ASC;")
	print("DIRECT DB EXECUTE RESULT success: ", direct_res.get("success"), " error: '", direct_res.get("error"), "' data count: ", direct_res.get("data", []).size())

	var svc = PlaylistsServiceScript.new(db)
	var pls = svc.get_all_playlists()
	print("SVC GET_ALL_PLAYLISTS COUNT: ", pls.size())

	quit(0)
