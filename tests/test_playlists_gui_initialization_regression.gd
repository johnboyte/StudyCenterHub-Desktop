extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")

func _init() -> void:
	print("\n=======================================================")
	print("  PLAYLISTS GUI INITIALIZATION REGRESSION TEST")
	print("=======================================================\n")

	var user_data_dir = OS.get_user_data_dir()
	var test_db_path = user_data_dir.path_join("studycenterhub_test_gui_init.db")

	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)

	var mig1 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0060_playlists_subsystem.sql")
	if not mig1.is_empty():
		db.execute(mig1)
	var mig2 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0061_playlist_providers.sql")
	if not mig2.is_empty():
		db.execute(mig2)

	var playlists_svc = PlaylistsServiceScript.new(db)
	var p1 = playlists_svc.create_playlist("Sunday Morning Gathering", "Main Worship", "youtube")
	var p2 = playlists_svc.create_playlist("College Study", "Midweek Worship", "youtube")
	assert(p1["success"] and p2["success"], "Failed creating test playlists")

	var scene_res = load("res://app/scenes/playlists_view.tscn")
	assert(scene_res != null, "Failed loading playlists_view.tscn")

	var view = scene_res.instantiate()
	assert(view != null, "Failed instantiating playlists_view")

	# Pass DB before ready / entering tree
	view.db = db

	root.add_child(view)
	await process_frame

	assert(view.playlists_list.size() == 2, "Expected 2 playlists loaded in view, got: " + str(view.playlists_list.size()))
	print("✓ Playlists loaded into view.playlists_list: ", view.playlists_list.size())

	assert(view.current_playlist_id != "", "Current playlist ID must not be empty")
	print("✓ Current playlist ID selected: ", view.current_playlist_id)

	var diag = NativePlayerBridge.get_native_diagnostics()
	print("✓ Native diagnostics: ", diag)

	view.queue_free()

	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n=======================================================")
	print("  PLAYLISTS GUI INITIALIZATION TEST PASSED!")
	print("=======================================================\n")
	quit(0)
