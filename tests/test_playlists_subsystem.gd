extends SceneTree

## Comprehensive Verification Test Suite for Playlists Subsystem
## Runs on ISOLATED test database so Development DB is never cluttered with test records.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PlaylistsServiceScript = preload("res://src/domain/playlists/playlists_service.gd")

func _init() -> void:
	print("--- Starting Playlists Subsystem Test Suite ---")

	# Step 1: Isolated Test Database Path (Leaves Development DB untouched!)
	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_isolated.db")
	print("Running tests on Isolated Test database: ", db_path)

	# Clean isolated test database file if exists
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)
	
	var prod_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	var prod_file_existed_before = FileAccess.file_exists(prod_path)
	var prod_size_before = 0
	if prod_file_existed_before:
		var f = FileAccess.open(prod_path, FileAccess.READ)
		if f:
			prod_size_before = f.get_length()
			f.close()

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert(mig_res["success"], "Migrations runner failed: " + str(mig_res.get("error", "")))
	print("✅ Test 1: Migrations applied successfully.")

	# Step 2: Verify Schema Tables
	var pragma_pl = db.execute("PRAGMA table_info(playlists);")
	assert(pragma_pl["success"] and pragma_pl["data"].size() > 0, "playlists table MUST exist")
	var pragma_items = db.execute("PRAGMA table_info(playlist_items);")
	assert(pragma_items["success"] and pragma_items["data"].size() > 0, "playlist_items table MUST exist")
	print("✅ Test 2: Schema tables 'playlists' and 'playlist_items' verified.")

	var playlists_svc = PlaylistsServiceScript.new(db)

	# Step 3: Create Playlist
	var pl1_res = playlists_svc.create_playlist("Sunday Gathering", "Worship set for Sunday morning")
	assert(pl1_res["success"], "Create playlist 1 failed")
	var pl1 = pl1_res["playlist"]
	var pl1_id = str(pl1["id"])

	var pl2_res = playlists_svc.create_playlist("College Study", "Background music for study hours")
	assert(pl2_res["success"], "Create playlist 2 failed")
	var pl2 = pl2_res["playlist"]
	var pl2_id = str(pl2["id"])

	print("✅ Test 3: Created Playlists successfully.")

	# Step 4: Rename Playlist
	var update_res = playlists_svc.update_playlist(pl1_id, "Sunday Morning Gathering", "Updated notes")
	assert(update_res, "Rename playlist failed")
	var fetched_pl1 = playlists_svc.get_playlist_by_id(pl1_id)
	assert(fetched_pl1.get("name") == "Sunday Morning Gathering", "Name update mismatch")
	print("✅ Test 4: Renamed Playlist successfully.")

	# Step 5: Reorder Playlists & Restart Persistence
	playlists_svc.reorder_playlists([pl2_id, pl1_id])
	var ordered_pls = playlists_svc.get_all_playlists()
	assert(ordered_pls.size() == 2, "Playlists size mismatch")
	assert(str(ordered_pls[0].get("id")) == pl2_id, "Reorder mismatch: pl2 should be first")

	# Simulate Restart by creating new db & service instance
	var db_restart = SQLiteDatabaseScript.new(db_path)
	var svc_restart = PlaylistsServiceScript.new(db_restart)
	var restarted_pls = svc_restart.get_all_playlists()
	assert(restarted_pls.size() == 2, "Restarted playlists size mismatch")
	assert(str(restarted_pls[0].get("id")) == pl2_id, "Playlist order did not persist across restart!")
	print("✅ Test 5: Playlist reordering survived app restart.")

	# Step 6: YouTube & Non-YouTube URL Recognition
	var yt_url = "https://www.youtube.com/watch?v=0k123456789"
	var meta_yt = playlists_svc.detect_url_metadata(yt_url)
	assert(meta_yt["source_type"] == "youtube", "YouTube source_type detection failed")
	assert(meta_yt["video_id"] == "0k123456789", "YouTube video_id parsing failed")
	assert("hqdefault.jpg" in meta_yt["thumbnail_url"], "YouTube thumbnail URL generation failed")

	var sp_url = "https://open.spotify.com/track/12345"
	var meta_sp = playlists_svc.detect_url_metadata(sp_url)
	assert(meta_sp["source_type"] == "spotify", "Spotify source_type detection failed")

	var file_url = "/Users/johnboyte/Music/acoustic_guitar.mp3"
	var meta_file = playlists_svc.detect_url_metadata(file_url)
	assert(meta_file["source_type"] == "local_file", "Local file source_type detection failed")
	assert(meta_file["title"] == "Acoustic Guitar", "Local file title parsing failed")

	print("✅ Test 6: YouTube and Non-YouTube URL recognition verified.")

	# Step 7: Add Items & Edit Item
	var item1_res = playlists_svc.add_playlist_item(
		pl1_id,
		"Yet Not I But Through Christ In Me",
		"CityAlight",
		"youtube",
		yt_url,
		320,
		"Key of C",
		meta_yt["thumbnail_url"]
	)
	assert(item1_res["success"], "Add item 1 failed")
	var item1_id = str(item1_res["item"]["id"])

	var item2_res = playlists_svc.add_playlist_item(
		pl1_id,
		"Christ Our Hope In Life And Death",
		"Keith & Kristyn Getty",
		"youtube",
		"https://youtu.be/OibIi1feihU",
		280,
		"Key of G",
		""
	)
	assert(item2_res["success"], "Add item 2 failed")
	var item2_id = str(item2_res["item"]["id"])

	var edit_item_res = playlists_svc.update_playlist_item(
		item1_id,
		"Yet Not I But Through Christ In Me (Live)",
		"CityAlight Worship",
		"youtube",
		yt_url,
		"Key of C - Modified Arrangement",
		330,
		meta_yt["thumbnail_url"]
	)
	assert(edit_item_res, "Edit item failed")
	var updated_item1 = playlists_svc.get_item_by_id(item1_id)
	assert(updated_item1.get("title") == "Yet Not I But Through Christ In Me (Live)", "Item title edit failed")
	print("✅ Test 7: Added and Edited playlist items successfully.")

	# Step 8: Item Reordering & Restart Persistence
	playlists_svc.reorder_playlist_items(pl1_id, [item2_id, item1_id])
	var items_ordered = playlists_svc.get_playlist_items(pl1_id)
	assert(str(items_ordered[0].get("id")) == item2_id, "Item reorder failed")

	# Verify restart persistence for items
	var svc_restart2 = PlaylistsServiceScript.new(SQLiteDatabaseScript.new(db_path))
	var items_restarted = svc_restart2.get_playlist_items(pl1_id)
	assert(str(items_restarted[0].get("id")) == item2_id, "Item order did not survive restart!")
	print("✅ Test 8: Playlist item reordering survived app restart.")

	# Step 9: SELECT-AND-DRAG PLAYLIST & SONG REORDERING SPECIFIC TESTS
	var pl_a = str(playlists_svc.create_playlist("pl_test_A")["playlist"]["id"])
	var pl_b = str(playlists_svc.create_playlist("pl_test_B")["playlist"]["id"])
	var pl_c = str(playlists_svc.create_playlist("pl_test_C")["playlist"]["id"])

	# Find index of A
	var pls_before = playlists_svc.get_all_playlists()
	var idx_a = -1
	for idx in range(pls_before.size()):
		if str(pls_before[idx].get("id")) == pl_a:
			idx_a = idx
			break

	playlists_svc.reorder_playlist_to_index(pl_c, idx_a)
	var pls_dragged = playlists_svc.get_all_playlists()
	var idx_c_after = -1
	var idx_a_after = -1
	var idx_b_after = -1
	for idx in range(pls_dragged.size()):
		var pid = str(pls_dragged[idx].get("id"))
		if pid == pl_c: idx_c_after = idx
		elif pid == pl_a: idx_a_after = idx
		elif pid == pl_b: idx_b_after = idx

	assert(idx_c_after < idx_a_after and idx_a_after < idx_b_after, "Playlist drag reorder (C above A) failed!")

	# Songs: Create items 1, 2, 3, 4 -> drag 4 between 1 and 2 -> order becomes 1, 4, 2, 3 -> restart -> remains 1, 4, 2, 3
	var drag_pl_id = str(playlists_svc.create_playlist("pl_test_drag_songs")["playlist"]["id"])
	var i1_id = str(playlists_svc.add_playlist_item(drag_pl_id, "Song 1")["item"]["id"])
	var i2_id = str(playlists_svc.add_playlist_item(drag_pl_id, "Song 2")["item"]["id"])
	var i3_id = str(playlists_svc.add_playlist_item(drag_pl_id, "Song 3")["item"]["id"])
	var i4_id = str(playlists_svc.add_playlist_item(drag_pl_id, "Song 4")["item"]["id"])

	# Drag 4 between 1 and 2 (target_index = 1)
	playlists_svc.reorder_song_to_index(i4_id, 1)
	var dragged_songs = playlists_svc.get_playlist_items(drag_pl_id)
	assert(str(dragged_songs[0].get("id")) == i1_id, "Song index 1 should be Song 1")
	assert(str(dragged_songs[1].get("id")) == i4_id, "Song index 2 should be Song 4")
	assert(str(dragged_songs[2].get("id")) == i2_id, "Song index 3 should be Song 2")
	assert(str(dragged_songs[3].get("id")) == i3_id, "Song index 4 should be Song 3")

	# Verify drag reorder survived restart
	var svc_restart3 = PlaylistsServiceScript.new(SQLiteDatabaseScript.new(db_path))
	var restarted_songs = svc_restart3.get_playlist_items(drag_pl_id)
	assert(str(restarted_songs[0].get("id")) == i1_id, "Restarted Song 1 mismatch")
	assert(str(restarted_songs[1].get("id")) == i4_id, "Restarted Song 4 mismatch")
	assert(str(restarted_songs[2].get("id")) == i2_id, "Restarted Song 2 mismatch")
	assert(str(restarted_songs[3].get("id")) == i3_id, "Restarted Song 3 mismatch")
	print("✅ Test 9: Select-and-Drag index calculations & restart persistence verified.")

	# Step 10: Position Insertion & Duplicate Video ID Detection
	var param_yt_url = "https://www.youtube.com/watch?v=24Vzw77em7M&list=RD24Vzw77em7M&start_radio=1"
	var is_dup = playlists_svc.check_duplicate_in_playlist(pl1_id, param_yt_url, "Different Title")
	# Add item with plain video ID
	playlists_svc.add_playlist_item(pl1_id, "It Is Well", "Parkway Worship", "youtube", "https://www.youtube.com/watch?v=24Vzw77em7M")
	var is_dup2 = playlists_svc.check_duplicate_in_playlist(pl1_id, param_yt_url, "Different Title")
	assert(is_dup2, "Duplicate video ID detection with extra URL parameters failed!")

	# Insert at specific index 1
	var ins_res = playlists_svc.insert_playlist_item_at_index(pl1_id, 1, "Inserted Middle Song", "Artist X", "youtube", "https://youtu.be/99999999999")
	assert(ins_res["success"], "insert_playlist_item_at_index failed")
	var items_after_ins = playlists_svc.get_playlist_items(pl1_id)
	assert(str(items_after_ins[1].get("title")) == "Inserted Middle Song", "Inserted item should be at index 1")

	# Delete item
	var del_item_id = str(items_after_ins[1].get("id"))
	var del_res = playlists_svc.delete_playlist_item(del_item_id)
	assert(del_res, "delete_playlist_item failed")
	var items_after_del = playlists_svc.get_playlist_items(pl1_id)
	assert(items_after_del.size() == items_after_ins.size() - 1, "Item count should drop by 1 after deletion")
	print("✅ Test 10: Position insertion, URL parameter duplicate detection, and item deletion verified.")

	# Step 11: Strict URL Validation & Arbitrary Prompt Rejection Verification
	var bad_prompt_text = "Improve ADD MUSIC / MEDIA for YouTube URLs in the Playlists feature.\nDEVELOPMENT ONLY.\nDo not deploy Production..."
	var val_prompt = playlists_svc.validate_and_extract_url(bad_prompt_text)
	assert(not val_prompt["is_valid"], "Prompt text MUST be rejected by validate_and_extract_url!")

	var add_bad_res = playlists_svc.add_playlist_item(pl1_id, "Untitled Media", "", "youtube", bad_prompt_text)
	assert(not add_bad_res["success"], "add_playlist_item MUST fail when given arbitrary prompt text!")

	var param_url = "https://www.youtube.com/watch?v=24Vzw77em7M&list=RD24Vzw77em7M&start_radio=1"
	var val_param = playlists_svc.validate_and_extract_url(param_url)
	assert(val_param["is_valid"], "YouTube URL with parameters MUST be valid!")
	assert(val_param["video_id"] == "24Vzw77em7M", "Video ID extraction failed for parameter URL")
	assert(val_param["canonical_url"] == "https://www.youtube.com/watch?v=24Vzw77em7M", "Canonical URL extraction failed")

	var val_prose = playlists_svc.validate_and_extract_url("Just random prose text with no link")
	assert(not val_prose["is_valid"], "Arbitrary prose text without URL MUST be rejected!")

	# Test .webloc file simulation (macOS Safari drag/drop format)
	var webloc_path = ProjectSettings.globalize_path("user://test_safari_drop.webloc")
	var f_webloc = FileAccess.open(webloc_path, FileAccess.WRITE)
	if f_webloc:
		f_webloc.store_string('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>URL</key><string>https://www.youtube.com/watch?v=24Vzw77em7M</string></dict></plist>')
		f_webloc.close()
	var val_webloc = playlists_svc.validate_and_extract_url(webloc_path)
	assert(val_webloc["is_valid"], "macOS .webloc drop parsing failed!")
	assert(val_webloc["video_id"] == "24Vzw77em7M", "macOS .webloc video ID extraction failed!")
	if FileAccess.file_exists(webloc_path):
		DirAccess.remove_absolute(webloc_path)

	print("✅ Test 11: Strict URL validation, macOS .webloc parsing, and prompt rejection verified.")

	# Clean up isolated DB file
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	# Step 12: Production Database Protection Check
	if prod_file_existed_before:
		var f_after = FileAccess.open(prod_path, FileAccess.READ)
		if f_after:
			var prod_size_after = f_after.get_length()
			f_after.close()
			assert(prod_size_after == prod_size_before, "CRITICAL ERROR: Production database file size changed during tests!")
	else:
		assert(not FileAccess.file_exists(prod_path), "CRITICAL ERROR: Production database file was created during development test run!")
	print("✅ Test 12: Production database verified untouched.")

	print("\n--- Playlists Subsystem Test Suite PASSED CLEANLY ---")
	quit(0)
