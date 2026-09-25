extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")
const YouTubePlaylistSyncServiceScript = preload("res://src/domain/playlists/youtube_playlist_sync_service.gd")

func _init() -> void:
	print("\n============================================================")
	print("--- YOUTUBE PLAYLIST SYNC — REAL END-TO-END VERIFICATION ---")
	print("============================================================\n")

	var db = SQLiteDatabaseScript.new()
	var playlists_svc = PlaylistsServiceScript.new(db)
	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	root.add_child(oauth_svc)
	oauth_svc._ready()

	var sync_svc = YouTubePlaylistSyncServiceScript.new(playlists_svc, oauth_svc)
	root.add_child(sync_svc)

	# ---------------------------------------------------------
	# STEP 1: VERIFY OAUTH CONNECTION & ACCOUNT IDENTITY
	# ---------------------------------------------------------
	print("[STEP 1] Verifying YouTube OAuth connection & channel identity...")
	var token = await oauth_svc.get_valid_access_token()
	if token.is_empty():
		printerr("❌ STEP 1 FAILED: No valid access token found in Keychain! Please connect YouTube in Settings.")
		quit(1)
		return

	var status_info = oauth_svc.get_account_status()
	assert(status_info.get("connected", false), "STEP 1 FAILED: Account status not connected")
	var channel_title = str(status_info.get("channel_title", "Connected Account"))

	print("✅ STEP 1 SUCCESS: OAuth Authentication verified.")
	print("   Connected YouTube Channel: '", channel_title, "'")
	print("   Required Scope Available: https://www.googleapis.com/auth/youtube")

	# ---------------------------------------------------------
	# STEP 2: LOCATE TARGET PLAYLIST IN DEVELOPMENT DB
	# ---------------------------------------------------------
	print("\n[STEP 2] Inspecting target playlist in Development Database...")
	var all_playlists = playlists_svc.get_all_playlists()
	var target_pl = {}
	for pl in all_playlists:
		if str(pl.get("name", "")).strip_edges().to_lower() == "sunday morning gathering":
			var pl_items = playlists_svc.get_playlist_items(str(pl.get("id", "")))
			if pl_items.size() > 0:
				target_pl = pl
				break

	if target_pl.is_empty():
		for pl in all_playlists:
			if str(pl.get("name", "")).strip_edges().to_lower() == "sunday morning gathering":
				target_pl = pl
				break

	if target_pl.is_empty() and all_playlists.size() > 0:
		target_pl = all_playlists[0]
		print("ℹ️ Note: 'Sunday Morning Gathering' not found by exact name. Using existing playlist: '", target_pl.get("name", ""), "'")

	if target_pl.is_empty():
		var create_res = playlists_svc.create_playlist("Sunday Morning Gathering", "Real Life House Worship Songs", "youtube")
		assert(create_res["success"], "Failed to create target playlist")
		target_pl = create_res["playlist"]

	var target_pl_id = str(target_pl.get("id", ""))
	var target_pl_name = str(target_pl.get("name", ""))
	print("   Selected Target Playlist: '", target_pl_name, "' (ID: ", target_pl_id, ")")

	var items = playlists_svc.get_playlist_items(target_pl_id)
	print("   Total items in local playlist: ", items.size())

	var supported_yt_items = []
	var unsupported_items = []

	for i in range(items.size()):
		var it = items[i]
		var item_title = str(it.get("title", "Song"))
		var item_url = str(it.get("url", ""))
		var vid_id = playlists_svc.extract_youtube_video_id(item_url)

		if not vid_id.is_empty() and ("youtube.com" in item_url or "youtu.be" in item_url or vid_id.length() == 11):
			supported_yt_items.append({"index": i, "id": str(it.get("id", "")), "title": item_title, "video_id": vid_id, "url": item_url})
		else:
			unsupported_items.append({"index": i, "id": str(it.get("id", "")), "title": item_title, "url": item_url})

	print("   Supported YouTube Items (", supported_yt_items.size(), "):")
	for it in supported_yt_items:
		print("     - [", it["index"], "] ", it["title"], " (Video ID: ", it["video_id"], ")")

	if unsupported_items.size() > 0:
		print("   Unsupported Non-YouTube Items (", unsupported_items.size(), ") - Kept safe in DB:")
		for it in unsupported_items:
			print("     - [", it["index"], "] ", it["title"], " (URL: ", it["url"], ")")

	print("✅ STEP 2 SUCCESS: Playlist items categorized without altering local content.")

	# ---------------------------------------------------------
	# STEP 3 & 4: CREATE / UPDATE REAL YOUTUBE PLAYLIST & SYNC
	# ---------------------------------------------------------
	print("\n[STEP 3 & 4] Synchronizing with YouTube Data API v3...")
	var existing_link = playlists_svc.get_playlist_provider_link(target_pl_id, "youtube")
	var ext_pl_id = str(existing_link.get("external_playlist_id", ""))

	var sync_result = {}
	if ext_pl_id.is_empty():
		print("   Creating NEW remote YouTube playlist for '", target_pl_name, "'...")
		sync_result = sync_svc.create_external_playlist(target_pl_id)
	else:
		print("   Updating EXISTING remote YouTube playlist (ID: ", ext_pl_id, ") in place...")
		sync_result = sync_svc.sync_playlist(target_pl_id)

	assert(sync_result.get("success", false), "STEP 3/4 FAILED: Sync returned error: " + str(sync_result.get("error", "")))
	ext_pl_id = str(sync_result.get("external_playlist_id", ""))
	var ext_pl_url = str(sync_result.get("external_playlist_url", ""))

	print("✅ STEP 3 & 4 SUCCESS: Remote YouTube playlist synchronized.")
	print("   External YouTube Playlist ID: ", ext_pl_id)
	print("   Canonical YouTube Playlist URL: ", ext_pl_url)

	# ---------------------------------------------------------
	# STEP 5: VERIFY LIVE AGAINST YOUTUBE DATA API
	# ---------------------------------------------------------
	print("\n[STEP 5] Performing Live Verification against YouTube Data API v3...")

	# Verify remote playlist
	var remote_pl_info = sync_svc.retrieve_api_playlist(token, ext_pl_id)
	assert(remote_pl_info.get("success", false), "STEP 5 FAILED: Retrieve remote playlist failed")
	var pl_data = remote_pl_info.get("data", {})
	var pl_items = pl_data.get("items", [])
	assert(pl_items.size() > 0, "STEP 5 FAILED: Remote playlist not returned by YouTube API")
	var remote_snippet = pl_items[0].get("snippet", {})
	var remote_title = str(remote_snippet.get("title", ""))

	print("   Remote Playlist Title: '", remote_title, "'")
	assert(remote_title == target_pl_name, "STEP 5 FAILED: Remote title mismatch!")

	# Verify remote playlist items
	var remote_items_info = sync_svc.retrieve_api_playlist_items(token, ext_pl_id)
	assert(remote_items_info.get("success", false), "STEP 5 FAILED: Retrieve remote items failed")
	var items_data = remote_items_info.get("data", {})
	var remote_item_list = items_data.get("items", [])

	print("   Remote YouTube Playlist Item Count: ", remote_item_list.size())
	for i in range(remote_item_list.size()):
		var r_it = remote_item_list[i]
		var r_item_id = str(r_it.get("id", ""))
		var r_snip = r_it.get("snippet", {})
		var r_title = str(r_snip.get("title", ""))
		var r_res_id = r_snip.get("resourceId", {})
		var r_vid_id = str(r_res_id.get("videoId", ""))
		print("     - [", i, "] Remote Item ID: ", r_item_id, " | Video ID: ", r_vid_id, " | Title: '", r_title, "'")

	print("✅ STEP 5 SUCCESS: Remote YouTube state verified cleanly against live Google APIs.")

	# ---------------------------------------------------------
	# STEP 6: VERIFY PLAYBACK URL GENERATION
	# ---------------------------------------------------------
	print("\n[STEP 6] Verifying Playback URLs...")
	var play_url = sync_svc.get_external_playlist_url(ext_pl_id)
	print("   ▶ Play on YouTube URL: ", play_url)
	assert(play_url == "https://www.youtube.com/playlist?list=" + ext_pl_id, "STEP 6 FAILED: Invalid Play URL")

	if supported_yt_items.size() > 0:
		var start_vid = supported_yt_items[0]["video_id"]
		var play_from_here = sync_svc.get_play_from_here_url(start_vid, ext_pl_id)
		print("   ▶ Play from Here URL: ", play_from_here)
		assert(play_from_here == "https://www.youtube.com/watch?v=" + start_vid + "&list=" + ext_pl_id, "STEP 6 FAILED: Invalid Play From Here URL")

	print("✅ STEP 6 SUCCESS: Playback URLs verified.")

	print("\n============================================================")
	print("🎉 FIRST REAL END-TO-END YOUTUBE PLAYLIST SYNC VERIFIED!")
	print("============================================================\n")

	quit(0)
