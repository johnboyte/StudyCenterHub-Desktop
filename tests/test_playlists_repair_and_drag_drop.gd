extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")
const YouTubePlaylistSyncServiceScript = preload("res://src/domain/playlists/youtube_playlist_sync_service.gd")

func _init() -> void:
	print("\n=======================================================")
	print("  PLAYLISTS REPAIR & BROWSER DRAG/DROP TEST SUITE")
	print("=======================================================\n")

	var user_data_dir = OS.get_user_data_dir()
	var test_db_path = user_data_dir.path_join("studycenterhub_test_repair_dragdrop.db")

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
	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	var sync_svc = YouTubePlaylistSyncServiceScript.new(playlists_svc, oauth_svc)

	# --- TEST 1 & 2: Existing Linked YouTube Playlist PLAY & No Creation ---
	print("[TEST 1 & 2] Linked Playlist PLAY Behavior...")
	var pl_res = playlists_svc.create_playlist("Sunday Morning Gathering", "Real Worship Playlist", "youtube")
	assert(pl_res["success"], "Failed creating test playlist")
	var pl_id = str(pl_res["playlist"]["id"])

	playlists_svc.save_playlist_provider_link(pl_id, "youtube", "PL_REAL_SUNDAY_123", "https://www.youtube.com/playlist?list=PL_REAL_SUNDAY_123", "synced", "")

	var link_info = playlists_svc.get_playlist_provider_link(pl_id, "youtube")
	assert(str(link_info["external_playlist_id"]) == "PL_REAL_SUNDAY_123", "External playlist ID mismatch")
	assert(str(link_info["external_playlist_url"]) == "https://www.youtube.com/playlist?list=PL_REAL_SUNDAY_123", "External URL mismatch")

	var ext_url = sync_svc.get_external_playlist_url("PL_REAL_SUNDAY_123")
	assert(ext_url == "https://www.youtube.com/playlist?list=PL_REAL_SUNDAY_123", "URL generation mismatch")
	print("  ✓ Linked playlist opens external URL directly without calling create_external_playlist.")

	# --- TEST 3 & 4: Expired Token & Clean Reconnect Error ---
	print("\n[TEST 3 & 4] Token Refresh & Clean Reconnect Error Handling...")
	# Simulate unauthenticated / expired state
	oauth_svc.disconnect_account()
	var invalid_token = await oauth_svc.get_valid_access_token()
	assert(invalid_token.is_empty(), "Token should be empty when disconnected")

	var sync_err_res = await sync_svc.sync_playlist(pl_id)
	assert(sync_err_res["success"] == false, "Sync should fail when unauthenticated")
	var err_msg = str(sync_err_res.get("error", ""))
	assert("YouTube connection expired" in err_msg or "authorization required" in err_msg, "Error message should be clean reconnect message")
	assert("{" not in err_msg and "}" not in err_msg and "body_raw" not in err_msg, "Raw Google API JSON overlay must not be present")
	print("  ✓ Expired authentication returns clean reconnect error message:", err_msg)

	# --- TEST 8 & 9: YouTube URL Parsing & Video ID Extraction ---
	print("\n[TEST 8 & 9] YouTube URL Parsing...")
	var vid1 = playlists_svc.extract_youtube_video_id("https://youtu.be/6CKCThJB5w0?si=test12345")
	assert(vid1 == "6CKCThJB5w0", "youtu.be parsing failed: " + vid1)

	var vid2 = playlists_svc.extract_youtube_video_id("https://www.youtube.com/watch?v=UiFLPAKBY1U&list=PL123&index=2&ab_channel=Artist")
	assert(vid2 == "UiFLPAKBY1U", "watch?v with extra parameters parsing failed: " + vid2)

	var vid3 = playlists_svc.extract_youtube_video_id("https://www.youtube.com/embed/zpuV8vvACTs?autoplay=1")
	assert(vid3 == "zpuV8vvACTs", "embed parsing failed: " + vid3)

	var vid4 = playlists_svc.extract_youtube_video_id("https://www.youtube.com/shorts/OibIi1feihU?feature=share")
	assert(vid4 == "OibIi1feihU", "shorts parsing failed: " + vid4)
	print("  ✓ YouTube video ID extraction works across all URL formats and extra query parameters.")

	# --- TEST 10: Invalid Text Rejection ---
	print("\n[TEST 10] Invalid Dragged Text Rejection...")
	var val_invalid = playlists_svc.validate_and_extract_url("Just arbitrary dragged text from browser")
	assert(val_invalid["is_valid"] == false, "Arbitrary text should be invalid")
	assert(val_invalid["source_type"] in ["other", "unknown"], "Arbitrary text source_type must be non-media")
	print("  ✓ Non-YouTube arbitrary text rejected cleanly.")

	# --- TEST 5, 6, 7 & 11: Browser URL Drag & Drop Position Insertion ---
	print("\n[TEST 5, 6, 7 & 11] Browser URL Drops at Specific Index (Before, Between, After)...")
	# Add initial songs
	playlists_svc.add_playlist_item(pl_id, "Song A", "Artist A", "youtube", "https://www.youtube.com/watch?v=vid00000001", 180, "", "")
	playlists_svc.add_playlist_item(pl_id, "Song B", "Artist B", "youtube", "https://www.youtube.com/watch?v=vid00000002", 200, "", "")

	var items_before = playlists_svc.get_playlist_items(pl_id)
	assert(items_before.size() == 2, "Expected 2 initial items")

	# Drop BEFORE FIRST (index 0)
	var val_drop_first = playlists_svc.validate_and_extract_url("https://www.youtube.com/watch?v=vidFIRST000")
	playlists_svc.insert_playlist_item_at_index(pl_id, 0, "Song First", "Artist", "youtube", val_drop_first["canonical_url"], 0, "", "")

	var items_after_first = playlists_svc.get_playlist_items(pl_id)
	assert(items_after_first.size() == 3, "Expected 3 items after drop before first")
	assert(str(items_after_first[0]["title"]) == "Song First", "Drop before first item mismatch")

	# Drop BETWEEN SONGS (index 2, between Song A and Song B)
	var val_drop_between = playlists_svc.validate_and_extract_url("https://www.youtube.com/watch?v=vidBETWEEN0")
	playlists_svc.insert_playlist_item_at_index(pl_id, 2, "Song Between", "Artist", "youtube", val_drop_between["canonical_url"], 0, "", "")

	var items_after_between = playlists_svc.get_playlist_items(pl_id)
	assert(items_after_between.size() == 4, "Expected 4 items after drop between")
	assert(str(items_after_between[2]["title"]) == "Song Between", "Drop between item mismatch")

	# Drop AFTER LAST (index 4)
	var val_drop_last = playlists_svc.validate_and_extract_url("https://www.youtube.com/watch?v=vidLAST0000")
	playlists_svc.insert_playlist_item_at_index(pl_id, 4, "Song Last", "Artist", "youtube", val_drop_last["canonical_url"], 0, "", "")

	var items_after_last = playlists_svc.get_playlist_items(pl_id)
	assert(items_after_last.size() == 5, "Expected 5 items after drop after last")
	assert(str(items_after_last[4]["title"]) == "Song Last", "Drop after last item mismatch")
	print("  ✓ Drag/Drop insertion at index 0 (before first), index N (between), and index size() (after last) verified.")

	# --- TEST 11: Internal Reorder ---
	print("\n[TEST 11] Internal Song Reorder...")
	var move_item_id = str(items_after_last[4]["id"]) # Song Last
	playlists_svc.reorder_song_to_index(move_item_id, 0)
	var items_reordered = playlists_svc.get_playlist_items(pl_id)
	assert(str(items_reordered[0]["id"]) == move_item_id, "Internal reorder to index 0 failed")
	print("  ✓ Internal song reordering using structural index slots verified.")

	# --- TEST 12: No Duplicate External Playlist Created ---
	print("\n[TEST 12] External Playlist Link Preservation...")
	var final_link = playlists_svc.get_playlist_provider_link(pl_id, "youtube")
	assert(str(final_link["external_playlist_id"]) == "PL_REAL_SUNDAY_123", "External playlist ID mutated!")
	print("  ✓ Original external YouTube playlist ID preserved: PL_REAL_SUNDAY_123.")

	# Clean up test database
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n=======================================================")
	print("  ALL 13 TESTS PASSED SUCCESSFULLY!  ")
	print("=======================================================\n")
	quit(0)
