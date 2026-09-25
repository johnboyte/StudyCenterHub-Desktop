@tool
extends SceneTree

func _init():
	print("==================================================")
	print("SEARCHING FOR ALL DB FILES AND PLAYLIST COUNTS")
	print("==================================================")
	
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	
	var paths = [
		"/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/studycenterhub_development.db",
		"/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/studycenterhub_staging.db",
		"/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db",
		"/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_staging.db"
	]
	
	for p in paths:
		if FileAccess.file_exists(p):
			var db = SQLiteScript.new(p)
			var res = db.execute("SELECT id, name, sort_order FROM playlists ORDER BY sort_order ASC")
			var playlists = res.get("rows", [])
			print("DB file at ", p, " exists! Playlists count: ", playlists.size())
			for pl in playlists:
				print("  - Playlist: ID=", pl.get("id"), " Name='", pl.get("name"), "'")
				var items_res = db.execute("SELECT id, title, url FROM playlist_items WHERE playlist_id = ?", [pl.get("id")])
				var items = items_res.get("rows", [])
				print("    Items count: ", items.size())
				for it in items:
					print("      * Item Title='", it.get("title"), "' URL='", it.get("url"), "'")
		else:
			print("DB file at ", p, " does NOT exist.")
			
	quit()
