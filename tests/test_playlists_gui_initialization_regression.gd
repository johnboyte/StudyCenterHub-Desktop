extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")

func _init() -> void:
	print("\n=======================================================")
	print("  TESTING PLAYLISTS GUI INITIALIZATION REGRESSION")
	print("=======================================================\n")

	# Use isolated test database
	var test_db_path = "user://test_playlists_gui_init.db"
	var db = SQLiteDatabaseScript.new(test_db_path)

	# Run schema migrations for test DB
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# Seed 2 test playlists
	var pl_svc = PlaylistsServiceScript.new(db)
	var res1 = pl_svc.create_playlist("Test Focus Playlist 1", "Description 1")
	var res2 = pl_svc.create_playlist("Test Focus Playlist 2", "Description 2")

	var pl1_id = str(res1.get("playlist", {}).get("id", "")) if typeof(res1) == TYPE_DICTIONARY else str(res1)
	var pl2_id = str(res2.get("playlist", {}).get("id", "")) if typeof(res2) == TYPE_DICTIONARY else str(res2)

	print("Created test playlist IDs: ", pl1_id, ", ", pl2_id)

	# Instantiate PlaylistsView, set db, and add to tree
	var scene_res = load("res://app/scenes/playlists_view.tscn")
	if not scene_res:
		print("❌ Failed to load playlists_view.tscn")
		quit(1)
		return

	var view_node = scene_res.instantiate()
	view_node.db = db
	root.add_child(view_node)

	# Process frame notifications so _ready() completes
	await create_timer(0.1).timeout

	print("PlaylistsView loaded in tree and ready processed.")
	print("Playlists count in view struct: ", view_node.playlists_list.size())
	print("Selected playlist ID: ", view_node.current_playlist_id)

	if view_node.playlists_list.size() < 2:
		print("❌ FAIL: Expected at least 2 playlists in view_node struct, got ", view_node.playlists_list.size())
		quit(1)
		return

	var vbox = view_node.playlists_vbox
	if not vbox or vbox.get_child_count() < 2:
		print("❌ FAIL: Playlist library vbox is empty or missing cards! Child count: ", vbox.get_child_count() if vbox else 0)
		quit(1)
		return

	print("✅ Playlists library vbox child count: ", vbox.get_child_count())

	# Cleanup test DB
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("test_playlists_gui_init.db"):
		dir.remove("test_playlists_gui_init.db")

	print("✅ GUI INITIALIZATION REGRESSION TEST PASSED 100% CLEANLY.\n")
	quit(0)
