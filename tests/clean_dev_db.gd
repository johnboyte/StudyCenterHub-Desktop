extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	db.execute("DELETE FROM playlist_items WHERE playlist_id IN (SELECT id FROM playlists WHERE id LIKE 'pl_test_%' OR name LIKE 'pl_test_%');")
	db.execute("DELETE FROM playlists WHERE id LIKE 'pl_test_%' OR name LIKE 'pl_test_%';")
	print("✅ Cleaned pl_test_* records from Development DB.")
	quit(0)
