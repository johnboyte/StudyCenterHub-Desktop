@tool
extends SceneTree

func _init():
	print("Testing NativePlayerBridge call execution...")
	var PlaybackSvcScript = load("res://src/domain/playlists/playback_session_service.gd")
	var MacPlayerScript = load("res://src/infrastructure/native/mac_wkwebview_player.gd")
	
	var player = MacPlayerScript.new()
	var svc = PlaybackSvcScript.new()
	svc.attach_native_player(player)
	
	print("Attached native player. Now starting playlist...")
	var test_items = [
		{"id": "s1", "title": "Test YouTube Song", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "duration_seconds": 210}
	]
	svc.start_playlist("Test Playlist", test_items, 0, "pl-1")
	print("Playback state after start: ", svc.playback_state)
	print("Current queue index: ", svc.current_queue_index)
	print("Native player _loaded_video_id: ", player._loaded_video_id)
	
	player.free()
	quit()
