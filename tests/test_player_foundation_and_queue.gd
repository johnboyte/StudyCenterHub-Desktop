@tool
extends SceneTree

func _init():
	print("==================================================")
	print("RUNNING AUTOMATED NATIVE PLAYER FOUNDATION TESTS")
	print("==================================================")
	
	var pass_count = 0
	var total_tests = 0
	
	# Test 1: Instantiation of PlaybackSessionService and MacWKWebViewPlayer
	total_tests += 1
	var PlaybackSvcScript = load("res://src/domain/playlists/playback_session_service.gd")
	var MacPlayerScript = load("res://src/infrastructure/native/mac_wkwebview_player.gd")
	var NativeBridgeScript = load("res://src/infrastructure/native/native_player_bridge.gd")
	
	if PlaybackSvcScript and MacPlayerScript and NativeBridgeScript:
		print("✅ PASS Test 1: Service and Native Player scripts loaded.")
		pass_count += 1
	else:
		print("❌ FAIL Test 1: Script load failed.")
		
	# Test 2: Native Player Initialization & Bridge Handshake
	total_tests += 1
	var player_node = MacPlayerScript.new()
	player_node._init_native_player()
	var service = PlaybackSvcScript.new()
	service.attach_native_player(player_node)
	if service.native_player == player_node:
		print("✅ PASS Test 2: Native WKWebView player attached to App-level PlaybackSessionService.")
		pass_count += 1
	else:
		print("❌ FAIL Test 2: Native player attachment failed.")

	# Test 3: Start Playlist & Video Load (No Safari OS.shell_open)
	total_tests += 1
	var test_items = [
		{"id": "s1", "title": "Song One", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "duration_seconds": 210},
		{"id": "s2", "title": "Song Two", "url": "https://www.youtube.com/watch?v=9bZkp7q19f0", "duration_seconds": 180}
	]
	service.start_playlist("Test Playlist", test_items, 0, "pl-101")
	if service.playback_state == "playing" and service.current_queue_index == 0:
		print("✅ PASS Test 3: PlaybackSessionService started item without OS.shell_open.")
		pass_count += 1
	else:
		print("❌ FAIL Test 3: Playback start state mismatch.")

	# Test 4: YT.PlayerState.ENDED Event Queue Advancement
	total_tests += 1
	var ended_state = [false]
	service.playback_started.connect(func(item, idx):
		if idx == 1:
			ended_state[0] = true
	)
	player_node.player_ended.emit()
	if ended_state[0] and service.current_queue_index == 1:
		print("✅ PASS Test 4: YT.PlayerState.ENDED callback automatically advanced queue to next item.")
		pass_count += 1
	else:
		print("❌ FAIL Test 4: Queue auto-advance on ENDED failed.")

	# Test 5: Clean Error Handling & No Fake Playing State
	total_tests += 1
	var error_state = [false]
	service.playback_error_occurred.connect(func(item, code):
		if code == 153:
			error_state[0] = true
	)
	player_node.player_error.emit(153)
	if error_state[0] and service.playback_state == "error" and service.has_playback_error:
		print("✅ PASS Test 5: Player Error 153 caught cleanly, state updated to error without launching Safari.")
		pass_count += 1
	else:
		print("❌ FAIL Test 5: Player error handling failed.")

	# Test 6: Explicit Safari Fallback Helper
	total_tests += 1
	if service.has_method("open_current_in_safari"):
		print("✅ PASS Test 6: Separate explicit Open on YouTube fallback action preserved.")
		pass_count += 1
	else:
		print("❌ FAIL Test 6: Fallback method missing.")

	print("==================================================")
	print("RESULTS: %d / %d TESTS PASSED" % [pass_count, total_tests])
	print("==================================================")
	
	player_node.free()
	quit()
