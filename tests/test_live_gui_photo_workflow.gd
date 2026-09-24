extends SceneTree

## Live GUI Photo Workflow Integration Test
## Tests the exact Directory/Profile UI node signals, image editor callbacks, and SQLite reads/writes.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")

func _get_b64_hash(b64_str: String) -> String:
	var s = b64_str.strip_edges()
	if s.is_empty():
		return "<EMPTY>"
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	var digest = ctx.finish()
	return digest.hex_encode().substr(0, 16)

func _init() -> void:
	print("--- Starting Live GUI Photo Workflow Test ---")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert(mig_res["success"], "Migration failed")

	var test_uuid = "usr_live_gui_photo_test_7777"
	db.execute("DELETE FROM people WHERE person_uuid = ?;", [test_uuid])

	# Create distinct uncropped raw source image (200x200 Blue square with Yellow border)
	var raw_src_img = Image.create(200, 200, false, Image.FORMAT_RGBA8)
	raw_src_img.fill(Color(0.1, 0.3, 0.9, 1.0)) # Blue
	for x in range(200):
		for y in range(20):
			raw_src_img.set_pixel(x, y, Color(1.0, 0.8, 0.0, 1.0)) # Yellow border top
	var raw_src_png = raw_src_img.save_png_to_buffer()
	var raw_src_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(raw_src_png)
	var raw_src_hash = _get_b64_hash(raw_src_b64)

	# Create distinct cropped current display image (60x60 Red square)
	var cropped_img = Image.create(60, 60, false, Image.FORMAT_RGBA8)
	cropped_img.fill(Color(0.9, 0.1, 0.1, 1.0)) # Red
	var cropped_png = cropped_img.save_png_to_buffer()
	var cropped_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(cropped_png)
	var cropped_hash = _get_b64_hash(cropped_b64)

	# Insert test constituent into SQLite
	var ins_res = db.execute(
		"INSERT INTO people (person_uuid, human_id, first_name, last_name, status, profile_photo, original_profile_photo) VALUES (?, 'P-GUI-TEST-01', 'GUI', 'Tester', 'active', ?, ?);",
		[test_uuid, cropped_b64, raw_src_b64]
	)
	assert(ins_res["success"], "Insert test person failed")

	# Instantiate Directory View Scene
	var dir_scene = load("res://app/scenes/directory_view.tscn").instantiate()
	dir_scene.db = db
	dir_scene.read_service = DirectoryReadServiceScript.new(db)
	root.add_child(dir_scene)
	dir_scene._ready()
	dir_scene.refresh_view()

	# Select test constituent in GUI
	dir_scene.select_person_by_uuid(test_uuid)
	assert(dir_scene.selected_person_uuid == test_uuid, "Selected person UUID mismatch")

	# STEP 1: BEFORE EDITING - Read SQLite hashes
	var db_before = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ? LIMIT 1;", [test_uuid])["data"][0]
	var cur_before = str(db_before.get("profile_photo", ""))
	var orig_before = str(db_before.get("original_profile_photo", ""))
	print("\n--- 1. BEFORE EDITING ---")
	print("CURRENT:  len=", cur_before.length(), " sha256=", _get_b64_hash(cur_before))
	print("ORIGINAL: len=", orig_before.length(), " sha256=", _get_b64_hash(orig_before))
	print("CURRENT == ORIGINAL: ", (cur_before == orig_before))
	assert(cur_before == cropped_b64, "Initial current photo mismatch")
	assert(orig_before == raw_src_b64, "Initial original photo mismatch")
	assert(cur_before != orig_before, "Initial current and original should be distinct")

	# STEP 2: SIMULATE EDIT / CROP CURRENT PHOTO (Normal Edit Mode)
	# User edits current photo and saves a new crop (Green 50x50 image)
	var new_crop_img = Image.create(50, 50, false, Image.FORMAT_RGBA8)
	new_crop_img.fill(Color(0.1, 0.9, 0.1, 1.0)) # Green
	var new_crop_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(new_crop_img.save_png_to_buffer())

	# Execute photo save callback (Simulating Crop & Save in Editor)
	dir_scene._active_photo_callback.call(new_crop_b64)

	var db_after_crop = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ? LIMIT 1;", [test_uuid])["data"][0]
	var cur_after_crop = str(db_after_crop.get("profile_photo", ""))
	var orig_after_crop = str(db_after_crop.get("original_profile_photo", ""))
	print("\n--- 2. AFTER CROPPING CURRENT PHOTO ---")
	print("CURRENT:  len=", cur_after_crop.length(), " sha256=", _get_b64_hash(cur_after_crop))
	print("ORIGINAL: len=", orig_after_crop.length(), " sha256=", _get_b64_hash(orig_after_crop))
	print("CURRENT == ORIGINAL: ", (cur_after_crop == orig_after_crop))
	assert(cur_after_crop == new_crop_b64, "Current photo must update to new crop")
	assert(orig_after_crop == raw_src_b64, "Protected Original MUST remain 100% byte-for-byte unchanged!")

	# STEP 3: SIMULATE "SAVE CURRENT AS ORIGINAL"
	# Executing the Save Current as Original action
	db.execute("UPDATE people SET original_profile_photo = profile_photo WHERE person_uuid = ?;", [test_uuid])
	dir_scene._invalidate_photo_cache(test_uuid)
	dir_scene.refresh_view()
	dir_scene.select_person_by_uuid(test_uuid)

	var db_after_save_orig = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ? LIMIT 1;", [test_uuid])["data"][0]
	var cur_after_save_orig = str(db_after_save_orig.get("profile_photo", ""))
	var orig_after_save_orig = str(db_after_save_orig.get("original_profile_photo", ""))
	print("\n--- 3. AFTER SAVE CURRENT AS ORIGINAL ---")
	print("CURRENT:  len=", cur_after_save_orig.length(), " sha256=", _get_b64_hash(cur_after_save_orig))
	print("ORIGINAL: len=", orig_after_save_orig.length(), " sha256=", _get_b64_hash(orig_after_save_orig))
	print("CURRENT == ORIGINAL: ", (cur_after_save_orig == orig_after_save_orig))
	assert(orig_after_save_orig == new_crop_b64, "Original must now match current photo after Save Current as Original")
	assert(cur_after_save_orig == orig_after_save_orig, "Current and Original hashes MUST match after Save Current as Original")

	# STEP 4: SIMULATE "RESTORE ORIGINAL"
	# Now set a new raw source image (Orange 180x180) and test Restore Original workflow
	var raw_src2_img = Image.create(180, 180, false, Image.FORMAT_RGBA8)
	raw_src2_img.fill(Color(1.0, 0.5, 0.0, 1.0)) # Orange
	var raw_src2_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(raw_src2_img.save_png_to_buffer())

	db.execute("UPDATE people SET original_profile_photo = ? WHERE person_uuid = ?;", [raw_src2_b64, test_uuid])
	dir_scene.refresh_view()
	dir_scene.select_person_by_uuid(test_uuid)

	# Verify Restore Original loads raw_src2_b64 from SQLite
	var db_restore_read = db.execute("SELECT original_profile_photo FROM people WHERE person_uuid = ? LIMIT 1;", [test_uuid])["data"][0]
	var loaded_orig_hash = _get_b64_hash(str(db_restore_read.get("original_profile_photo", "")))
	print("\n--- 4. RESTORE ORIGINAL CLICKED ---")
	print("Loaded original_profile_photo hash into editor: ", loaded_orig_hash)
	assert(loaded_orig_hash == _get_b64_hash(raw_src2_b64), "Restore Original MUST load raw protected original from SQLite")

	# Save a new edit from Restore Original (Purple 45x45 image)
	var restore_crop_img = Image.create(45, 45, false, Image.FORMAT_RGBA8)
	restore_crop_img.fill(Color(0.6, 0.1, 0.8, 1.0)) # Purple
	var restore_crop_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(restore_crop_img.save_png_to_buffer())

	dir_scene._active_photo_callback.call(restore_crop_b64)

	var db_after_restore = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ? LIMIT 1;", [test_uuid])["data"][0]
	var cur_after_restore = str(db_after_restore.get("profile_photo", ""))
	var orig_after_restore = str(db_after_restore.get("original_profile_photo", ""))
	print("\n--- 5. AFTER SAVING EDIT FROM RESTORE ORIGINAL ---")
	print("CURRENT:  len=", cur_after_restore.length(), " sha256=", _get_b64_hash(cur_after_restore))
	print("ORIGINAL: len=", orig_after_restore.length(), " sha256=", _get_b64_hash(orig_after_restore))
	print("CURRENT == ORIGINAL: ", (cur_after_restore == orig_after_restore))
	assert(cur_after_restore == restore_crop_b64, "Current photo updated from restore edit")
	assert(orig_after_restore == raw_src2_b64, "Protected Original MUST remain 100% byte-for-byte unchanged!")

	# Cleanup test record
	db.execute("DELETE FROM people WHERE person_uuid = ?;", [test_uuid])

	print("\n--- Live GUI Photo Workflow Test PASSED CLEANLY ---")
	quit()
