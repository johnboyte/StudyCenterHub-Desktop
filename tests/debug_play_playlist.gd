@tool
extends SceneTree

func _init():
	print("==================================================")
	print("DEBUGGING PLAY PLAYLIST ACTION")
	print("==================================================")
	
	var PlaylistsViewScript = load("res://app/scenes/playlists_view.gd")
	var PlaybackSvcScript = load("res://src/domain/playlists/playback_session_service.gd")
	var MacPlayerScript = load("res://src/infrastructure/native/mac_wkwebview_player.gd")
	
	var view = PlaylistsViewScript.new()
	var player = MacPlayerScript.new()
	var svc = PlaybackSvcScript.new()
	svc.attach_native_player(player)
	
	# Simulate view binding
	view.playback_svc = svc
	view.current_playlist_id = "pl-test-1"
	view.items_list = [
		{"id": "it-1", "title": "Test Song", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"}
	]
	
	print("Calling _on_play_playlist_pressed()...")
	view._on_play_playlist_pressed()
	
	print("Playback state after press: ", svc.playback_state)
	print("Active playlist ID: ", svc.active_playlist_id)
	print("Active playlist name: ", svc.active_playlist_name)
	print("Current queue index: ", svc.current_queue_index)
	print("Loaded video ID in player: ", player._loaded_video_id)
	
	view.free()
	player.free()
	quit()
