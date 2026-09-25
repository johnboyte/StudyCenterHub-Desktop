@tool
extends SceneTree

func _init():
	print("==================================================")
	print("SEEDING DEVELOPMENT DATABASE IF EMPTY")
	print("==================================================")
	
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var PlaylistsSvcScript = load("res://src/domain/playlists/playlists_service.gd")
	
	var p = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"
	var db = SQLiteScript.new(p)
	var svc = PlaylistsSvcScript.new(db)
	
	var playlists = svc.get_all_playlists()
	print("Playlists count after service init: ", playlists.size())
	for pl in playlists:
		print("  - Playlist: ID=", pl.get("id"), " Name='", pl.get("name"), "'")
		var items = svc.get_playlist_items(pl.get("id"))
		print("    Items count: ", items.size())
		for it in items:
			print("      * Item Title='", it.get("title"), "' URL='", it.get("url"), "'")
			
	quit()
