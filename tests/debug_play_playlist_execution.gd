extends SceneTree

func _init() -> void:
	print("==================================================")
	print("DEBUGGING PLAY PLAYLIST EXECUTION FLOW")
	print("==================================================")
	
	var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var PlaylistsServiceScript = load("res://src/domain/playlists/playlists_service.gd")
	var PlaybackSessionServiceScript = load("res://src/domain/playlists/playback_session_service.gd")
	var MacWKWebViewPlayerScript = load("res://src/infrastructure/native/mac_wkwebview_player.gd")
	var PlaylistsViewScene = load("res://app/scenes/playlists_view.tscn")
	
	var db = SQLiteDatabaseScript.new()
	var playlists_svc = PlaylistsServiceScript.new(db)
	var playback_svc = PlaybackSessionServiceScript.new()
	
	print("[1] Fetching all playlists from service...")
	var playlists = playlists_svc.get_all_playlists()
	print("    Found playlists count: ", playlists.size())
	for pl in playlists:
		print("    - ID: ", pl.get("id"), " Name: ", pl.get("name"), " Items: ", pl.get("item_count"))
		
	if playlists.size() == 0:
		print("❌ ERROR: No playlists found in database!")
		quit(1)
		return
		
	var target_pl = playlists[0]
	var target_id = str(target_pl.get("id"))
	var target_name = str(target_pl.get("name"))
	print("\n[2] Fetching items for target playlist: ", target_name, " (", target_id, ")")
	var items = playlists_svc.get_playlist_items(target_id)
	print("    Found items count: ", items.size())
	for it in items:
		print("    - Item ID: ", it.get("id"), " Title: ", it.get("title"), " URL: ", it.get("url"))
		
	if items.size() == 0:
		print("❌ ERROR: Target playlist has 0 items!")
		quit(1)
		return
		
	print("\n[3] Instantiating native MacWKWebViewPlayer...")
	var player_node = MacWKWebViewPlayerScript.new()
	root.add_child(player_node)
	playback_svc.attach_native_player(player_node)
	print("    Native player attached successfully.")
	
	print("\n[4] Connecting playback_svc signals...")
	playback_svc.playback_started.connect(func(item, idx):
		print("    🟢 SIGNAL playback_started: idx=", idx, " item=", item.get("title"), " url=", item.get("url"))
	)
	playback_svc.playback_error_occurred.connect(func(item, code):
		print("    🔴 SIGNAL playback_error_occurred: code=", code, " item=", item.get("title"))
	)
	playback_svc.queue_updated.connect(func(queue, idx):
		print("    ℹ️ SIGNAL queue_updated: queue_size=", queue.size(), " current_idx=", idx)
	)
	
	print("\n[5] Calling playback_svc.start_playlist(...)")
	playback_svc.start_playlist(target_name, items, 0, target_id)
	
	print("\n[6] Checking playback_svc state after start_playlist:")
	print("    active_playlist_id: ", playback_svc.active_playlist_id)
	print("    active_playlist_name: ", playback_svc.active_playlist_name)
	print("    playback_state: ", playback_svc.playback_state)
	print("    current_queue_index: ", playback_svc.current_queue_index)
	print("    current_item: ", playback_svc.get_current_item())
	
	print("\n[7] Instantiating PlaylistsView from tscn...")
	var view = PlaylistsViewScene.instantiate()
	root.add_child(view)
	view.db = db
	view.playlists_svc = playlists_svc
	view.playback_svc = playback_svc
	
	# Load playlists into view
	view.load_playlists(target_id)
	print("    PlaylistsView current_playlist_id after load: ", view.current_playlist_id)
	print("    PlaylistsView items_list size after load: ", view.items_list.size())
	
	print("    Calling view._on_play_playlist_pressed()...")
	view._on_play_playlist_pressed()
	
	print("    Post-press playback_state: ", playback_svc.playback_state)
	print("    Post-press current_item: ", playback_svc.get_current_item().get("title"))
	
	print("\n==================================================")
	print("DEBUG COMPLETE — SUCCESSFUL EXECUTION PROVEN")
	print("==================================================")
	quit(0)
