extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")
const YouTubePlaylistSyncServiceScript = preload("res://src/domain/playlists/youtube_playlist_sync_service.gd")

func _init() -> void:
	print("\n--- Starting YouTube Playlist Provider & Synchronization Test Suite ---")
	
	# Use isolated test database to protect John's Development database
	var user_data_dir = OS.get_user_data_dir()
	var test_db_path = user_data_dir.path_join("studycenterhub_test_provider_sync.db")
	
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
		
	var db = SQLiteDatabaseScript.new(test_db_path)
	
	# Apply migrations manually for test DB
	var mig1 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0060_playlists_subsystem.sql")
	if not mig1.is_empty():
		db.execute(mig1)
	var mig2 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0061_playlist_providers.sql")
	if not mig2.is_empty():
		db.execute(mig2)
		
	var playlists_svc = PlaylistsServiceScript.new(db)
	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	var sync_svc = YouTubePlaylistSyncServiceScript.new(playlists_svc, oauth_svc)
	
	# Test 1: Existing & New General Playlists
	var gen_pl_res = playlists_svc.create_playlist("General Gathering", "Mixed media items", "general")
	assert(gen_pl_res["success"], "Test 1 Failed: Create General playlist")
	var gen_pl = gen_pl_res["playlist"]
	var gen_id = str(gen_pl["id"])
	assert(str(gen_pl["provider_type"]) == "general", "Test 1 Failed: Provider type general")
	print("✅ Test 1: Created General / Mixed Media playlist successfully.")
	
	# Test 2: YouTube Playlist Creation & Provider Link
	var yt_pl_res = playlists_svc.create_playlist("Sunday Morning Gathering", "Worship songs", "youtube")
	assert(yt_pl_res["success"], "Test 2 Failed: Create YouTube playlist")
	var yt_pl = yt_pl_res["playlist"]
	var yt_id = str(yt_pl["id"])
	assert(str(yt_pl["provider_type"]) == "youtube", "Test 2 Failed: Provider type youtube")
	print("✅ Test 2: Created YouTube playlist with provider_type = youtube.")
	
	# Test 3: Add Items & Canonical Video ID Parsing
	var item1_res = playlists_svc.add_playlist_item(yt_id, "Yet Not I But Through Christ In Me", "CityAlight", "youtube", "https://www.youtube.com/watch?v=zpuV8vvACTs&t=10s")
	assert(item1_res["success"], "Test 3 Failed: Add YouTube item 1")
	var item1_id = str(item1_res["item"]["id"])
	var item1_vid = playlists_svc.extract_youtube_video_id("https://www.youtube.com/watch?v=zpuV8vvACTs&t=10s")
	assert(item1_vid == "zpuV8vvACTs", "Test 3 Failed: Clean video ID parsing")
	
	var item2_res = playlists_svc.add_playlist_item(yt_id, "Christ Our Hope In Life And Death", "Keith & Kristyn Getty", "youtube", "https://youtu.be/OibIi1feihU?si=abc12345")
	assert(item2_res["success"], "Test 3 Failed: Add YouTube item 2")
	var item2_id = str(item2_res["item"]["id"])
	var item2_vid = playlists_svc.extract_youtube_video_id("https://youtu.be/OibIi1feihU?si=abc12345")
	assert(item2_vid == "OibIi1feihU", "Test 3 Failed: Short URL video ID parsing")
	print("✅ Test 3: Canonical YouTube video ID parsing verified cleanly without tracking parameters.")
	
	# Test 4: OAuth Service Status & Mock Authorization
	oauth_svc.set_mock_credentials_for_testing("mock_access_token_123", "Study Center Worship")
	var auth_status = oauth_svc.get_account_status()
	assert(auth_status["connected"] == true, "Test 4 Failed: Mock OAuth connected status")
	assert(str(auth_status["channel_title"]) == "Study Center Worship", "Test 4 Failed: Channel title")
	print("✅ Test 4: OAuth service authorization status & credential boundary verified.")
	
	# Test 5: External YouTube Playlist Synchronization
	var sync_res = sync_svc.sync_playlist(yt_id)
	assert(sync_res["success"], "Test 5 Failed: External YouTube sync")
	var ext_pid = str(sync_res["external_playlist_id"])
	assert(ext_pid.begins_with("PL_SCH_"), "Test 5 Failed: External playlist ID format")
	
	var pl_link = playlists_svc.get_playlist_provider_link(yt_id, "youtube")
	assert(str(pl_link["external_playlist_id"]) == ext_pid, "Test 5 Failed: Provider link mapping")
	assert(str(pl_link["sync_status"]) == "synced", "Test 5 Failed: Sync status synced")
	print("✅ Test 5: External YouTube playlist creation and provider links verified.")
	
	# Test 6: External Item Identity Mapping & URLs
	var item1_link = playlists_svc.get_item_provider_link(item1_id, "youtube")
	assert(not item1_link.is_empty(), "Test 6 Failed: Item 1 provider link")
	assert(str(item1_link["external_media_id"]) == "zpuV8vvACTs", "Test 6 Failed: Item 1 video ID link")
	
	var ext_pl_url = sync_svc.get_external_playlist_url(ext_pid)
	assert(ext_pl_url == "https://www.youtube.com/playlist?list=" + ext_pid, "Test 6 Failed: External playlist URL")
	
	var play_from_here_url = sync_svc.get_play_from_here_url("zpuV8vvACTs", ext_pid)
	assert(play_from_here_url == "https://www.youtube.com/watch?v=zpuV8vvACTs&list=" + ext_pid, "Test 6 Failed: Play From Here URL")
	print("✅ Test 6: External item mapping, playlist URL, and Play From Here URL generation verified.")
	
	# Test 7: Playlist Conversion (General -> YouTube)
	var conv_res = playlists_svc.convert_playlist_provider(gen_id, "youtube")
	assert(conv_res["success"], "Test 7 Failed: Convert General to YouTube")
	var conv_pl = playlists_svc.get_playlist_by_id(gen_id)
	assert(str(conv_pl["provider_type"]) == "youtube", "Test 7 Failed: Converted provider type")
	print("✅ Test 7: Converted General playlist to YouTube playlist successfully.")
	
	# Clean up test DB
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
		
	print("\n🎉 ALL YOUTUBE PLAYLIST PROVIDER & SYNC TESTS PASSED SUCCESSFULLY!\n")
	quit(0)
