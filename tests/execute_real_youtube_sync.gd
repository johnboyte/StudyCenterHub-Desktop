extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")
const YouTubePlaylistSyncServiceScript = preload("res://src/domain/playlists/youtube_playlist_sync_service.gd")

func _initialize() -> void:
	print("\n============================================================")
	print("--- EXECUTE REAL YOUTUBE PLAYLIST SYNC (DEVELOPMENT) ---")
	print("============================================================\n")

	var user_data_dir = OS.get_user_data_dir()
	var dev_db_path = user_data_dir.path_join("studycenterhub_development.db")

	var db = SQLiteDatabaseScript.new(dev_db_path)
	var playlists_svc = PlaylistsServiceScript.new(db)
	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	root.add_child(oauth_svc)
	oauth_svc._ready()

	var sync_svc = YouTubePlaylistSyncServiceScript.new(playlists_svc, oauth_svc)
	root.add_child(sync_svc)

	# ---------------------------------------------------------
	# STEP 1: VERIFY AUTHENTICATION & CHANNEL IDENTITY
	# ---------------------------------------------------------
	print("[STEP 1] Verifying OAuth authentication & retrieving channel identity...")
	assert(oauth_svc.is_account_connected() == true, "Step 1 Failed: Account is not connected!")

	await oauth_svc._refresh_access_token_sync()
	var token = await oauth_svc.get_valid_access_token()
	assert(not token.is_empty(), "Step 1 Failed: OAuth access token is empty!")

	await oauth_svc._fetch_youtube_channel_identity()
	var status = oauth_svc.get_account_status()
	var channel_title = str(status.get("channel_title", "Connected Account"))
	print("✅ Step 1 PASSED: Connected to channel: '" + channel_title + "'")

	# ---------------------------------------------------------
	# STEP 2: READ EXISTING LOCAL PLAYLIST
	# ---------------------------------------------------------
	print("\n[STEP 2] Reading local playlist 'Sunday Morning Gathering'...")
	var pl_res = db.execute("SELECT id, name, description FROM playlists WHERE name = 'Sunday Morning Gathering' ORDER BY created_at ASC LIMIT 1;")
	assert(pl_res["success"] and pl_res["data"].size() > 0, "Step 2 Failed: 'Sunday Morning Gathering' playlist not found in DB")

	var target_pl = pl_res["data"][0]
	var playlist_id = str(target_pl["id"])
	print("  Local Playlist ID: " + playlist_id)

	var items = playlists_svc.get_playlist_items(playlist_id)
	var total_local_items = items.size()
	var yt_eligible_count = 0
	var video_ids = []

	for item in items:
		var url = str(item.get("url", ""))
		var vid_id = playlists_svc.extract_youtube_video_id(url)
		if not vid_id.is_empty():
			yt_eligible_count += 1
			video_ids.append(vid_id)

	print("  Total Local Items: " + str(total_local_items))
	print("  YouTube-Eligible Items: " + str(yt_eligible_count))
	assert(yt_eligible_count > 0, "Step 2 Failed: Zero YouTube-eligible items found!")
	print("✅ Step 2 PASSED: Local items read successfully.")

	# ---------------------------------------------------------
	# STEP 3: CREATE OR REUSE REAL YOUTUBE PLAYLIST
	# ---------------------------------------------------------
	print("\n[STEP 3] Checking or creating external YouTube playlist...")
	var link = playlists_svc.get_playlist_provider_link(playlist_id, "youtube")
	var ext_playlist_id = str(link.get("external_playlist_id", ""))
	var ext_playlist_url = str(link.get("external_playlist_url", ""))

	if ext_playlist_id.is_empty():
		print("  No existing external YouTube playlist ID found. Creating new remote playlist on YouTube...")
		var create_res = await sync_svc.create_api_playlist(token, "Sunday Morning Gathering", str(target_pl.get("description", "Worship Songs")), "unlisted")
		assert(create_res.get("success", false) == true, "Step 3 Failed to create remote playlist: " + str(create_res.get("error", "")))
		ext_playlist_id = str(create_res.get("id", ""))
		ext_playlist_url = str(create_res.get("url", ""))
		playlists_svc.save_playlist_provider_link(playlist_id, "youtube", ext_playlist_id, ext_playlist_url, "synced", "")
		print("  Created remote YouTube Playlist ID: " + ext_playlist_id)
	else:
		print("  Reusing existing remote YouTube Playlist ID: " + ext_playlist_id)

	assert(not ext_playlist_id.is_empty(), "Step 3 Failed: external_playlist_id is empty")
	print("  External Playlist URL: " + ext_playlist_url)
	print("✅ Step 3 PASSED: External YouTube Playlist confirmed.")

	# ---------------------------------------------------------
	# STEP 4: SYNCHRONIZE ITEMS
	# ---------------------------------------------------------
	print("\n[STEP 4] Synchronizing songs to YouTube playlist...")
	# Fetch remote playlist items to avoid duplicates
	var remote_items_res = await sync_svc.retrieve_api_playlist_items(token, ext_playlist_id)
	var remote_video_map = {}
	if remote_items_res.get("success", false):
		var r_data = remote_items_res.get("data", {})
		var r_items = r_data.get("items", [])
		for r_item in r_items:
			var r_snippet = r_item.get("snippet", {})
			var r_resource = r_snippet.get("resourceId", {})
			var r_vid = str(r_resource.get("videoId", ""))
			var r_item_id = str(r_item.get("id", ""))
			if not r_vid.is_empty():
				remote_video_map[r_vid] = r_item_id

	for i in range(items.size()):
		var item = items[i]
		var item_id = str(item.get("id", ""))
		var vid_id = playlists_svc.extract_youtube_video_id(str(item.get("url", "")))
		if not vid_id.is_empty():
			if remote_video_map.has(vid_id):
				var existing_r_item_id = remote_video_map[vid_id]
				playlists_svc.save_item_provider_link(item_id, "youtube", existing_r_item_id, vid_id, "synced", "")
				print("  Song #" + str(i + 1) + " (Video ID: " + vid_id + ") already on remote playlist (Item ID: " + existing_r_item_id + ")")
			else:
				var add_res = await sync_svc.add_api_playlist_item(token, ext_playlist_id, vid_id, i)
				assert(add_res.get("success", false) == true, "Step 4 Failed to add video " + vid_id + " to playlist: " + str(add_res.get("error", "")))
				var yt_item_id = str(add_res.get("playlist_item_id", ""))
				playlists_svc.save_item_provider_link(item_id, "youtube", yt_item_id, vid_id, "synced", "")
				print("  Added song #" + str(i + 1) + " (Video ID: " + vid_id + ") to remote playlist (Item ID: " + yt_item_id + ")")

	playlists_svc.update_playlist_sync_status(playlist_id, "youtube", "synced", "")
	print("✅ Step 4 PASSED: Items synchronized.")

	# ---------------------------------------------------------
	# STEP 5: VERIFY FROM YOUTUBE
	# ---------------------------------------------------------
	print("\n[STEP 5] Verifying remote playlist state via GET from YouTube Data API...")
	var fetch_pl_res = await sync_svc.retrieve_api_playlist(token, ext_playlist_id)
	assert(fetch_pl_res.get("success", false) == true, "Step 5 Failed: Could not retrieve playlist from YouTube")

	var privacy_status = "unlisted"
	var pl_data = fetch_pl_res.get("data", {})
	var pl_items_arr = pl_data.get("items", [])
	if pl_items_arr.size() > 0:
		privacy_status = str(pl_items_arr[0].get("status", {}).get("privacyStatus", "unlisted"))

	var fetch_items_res = await sync_svc.retrieve_api_playlist_items(token, ext_playlist_id)
	assert(fetch_items_res.get("success", false) == true, "Step 5 Failed: Could not retrieve playlist items from YouTube")

	var fetched_items_data = fetch_items_res.get("data", {}).get("items", [])
	var remote_item_count = fetched_items_data.size()
	print("  Remote Playlist Items Verified: " + str(remote_item_count))

	var remote_order_matched = true
	if remote_item_count == yt_eligible_count:
		for idx in range(fetched_items_data.size()):
			var f_snip = fetched_items_data[idx].get("snippet", {})
			var f_vid = str(f_snip.get("resourceId", {}).get("videoId", ""))
			var expected_vid = video_ids[idx]
			if f_vid != expected_vid:
				remote_order_matched = false
				print("  Mismatch at index " + str(idx) + ": expected " + expected_vid + ", got " + f_vid)
	else:
		remote_order_matched = false

	print("  Remote Order Verified: " + ("yes" if remote_order_matched else "no"))
	assert(remote_order_matched == true, "Step 5 Failed: Remote order does not match local order!")
	print("✅ Step 5 PASSED: Remote state verified via GET from YouTube Data API.")

	print("\n============================================================")
	print("🎉 REAL YOUTUBE PLAYLIST SYNC COMPLETED SUCCESSFULLY!")
	print("============================================================\n")

	print("CHANNEL: " + channel_title)
	print("LOCAL PLAYLIST: Sunday Morning Gathering")
	print("REMOTE PLAYLIST CREATED: " + ("yes" if link.get("external_playlist_id", "").is_empty() else "no (reused)"))
	print("YOUTUBE PLAYLIST ID: " + ext_playlist_id)
	print("YOUTUBE PLAYLIST URL: " + ext_playlist_url)
	print("PRIVACY: " + privacy_status)
	print("LOCAL ITEM COUNT: " + str(total_local_items))
	print("REMOTE ITEM COUNT: " + str(remote_item_count))
	print("ORDER MATCH: " + ("yes" if remote_order_matched else "no"))

	print("\nSYNCHRONIZED ITEMS:")
	for idx in range(fetched_items_data.size()):
		var f_snip = fetched_items_data[idx].get("snippet", {})
		var title = str(f_snip.get("title", ""))
		var vid = str(f_snip.get("resourceId", {}).get("videoId", ""))
		var res_item_id = str(fetched_items_data[idx].get("id", ""))
		print("  " + str(idx + 1) + ". " + title + " (Video ID: " + vid + ", Item ID: " + res_item_id + ")")

	quit(0)
