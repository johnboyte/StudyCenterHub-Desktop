@tool
extends SceneTree

func _init():
	print("==================================================")
	print("INSPECTING DEVELOPMENT DATABASE PLAYLISTS & ITEMS")
	print("==================================================")
	
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var db = SQLiteScript.new("/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db")
	
	var res = db.execute("SELECT id, name, sort_order FROM playlists ORDER BY sort_order ASC")
	var playlists = res.get("rows", [])
	print("Playlists count: ", playlists.size())
	for pl in playlists:
		print("  - Playlist: ID=", pl.get("id"), " Name='", pl.get("name"), "'")
		var items_res = db.execute("SELECT id, title, url, source_type FROM playlist_items WHERE playlist_id = ? ORDER BY sort_order ASC", [pl.get("id")])
		var items = items_res.get("rows", [])
		print("    Items count: ", items.size())
		for it in items:
			print("      * Item ID=", it.get("id"), " Title='", it.get("title"), "' URL='", it.get("url"), "' Source='", it.get("source_type"), "'")
			
	quit()
