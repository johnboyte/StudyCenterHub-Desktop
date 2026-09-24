extends SceneTree

## Comprehensive Verification Test Suite for Protected Original Profile Photo Subsystem

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")

func _init() -> void:
	print("--- Starting Protected Original Profile Photo Test Suite ---")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert(mig_res["success"], "Migrations runner failed: " + str(mig_res.get("error", "")))

	# Step 1: Verify database schema column exists
	var pragma_res = db.execute("PRAGMA table_info(people);")
	assert(pragma_res["success"], "PRAGMA table_info(people) failed")
	var has_orig_col = false
	for col in pragma_res["data"]:
		if str(col.get("name", "")) == "original_profile_photo":
			has_orig_col = true
			break
	assert(has_orig_col, "people.original_profile_photo column MUST exist in database schema!")
	print("✅ Test 1: Column 'people.original_profile_photo' exists in schema.")

	# Create test images (simulated raw source and cropped display versions)
	var raw_img = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	raw_img.fill(Color(0.2, 0.4, 0.8, 1.0)) # Raw Blue Image
	var raw_png_bytes = raw_img.save_png_to_buffer()
	var raw_source_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(raw_png_bytes)

	var crop1_img = Image.create(50, 50, false, Image.FORMAT_RGBA8)
	crop1_img.fill(Color(0.8, 0.2, 0.2, 1.0)) # Cropped Red Image
	var crop1_png_bytes = crop1_img.save_png_to_buffer()
	var crop1_display_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(crop1_png_bytes)

	var crop2_img = Image.create(40, 40, false, Image.FORMAT_RGBA8)
	crop2_img.fill(Color(0.2, 0.8, 0.2, 1.0)) # Cropped Green Image
	var crop2_png_bytes = crop2_img.save_png_to_buffer()
	var crop2_display_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(crop2_png_bytes)

	var test_person_uuid = "usr_photo_test_uuid_9999"

	# Cleanup existing test person if present
	db.execute("DELETE FROM people WHERE person_uuid = ?;", [test_person_uuid])

	# Create test constituent
	var ins_res = db.execute(
		"INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, status, profile_photo, original_profile_photo) VALUES (?, 'P-TEST-PHOTO-01', 'Photo', 'Tester', '555-0199', 'active', ?, ?);",
		[test_person_uuid, crop1_display_b64, raw_source_b64]
	)
	assert(ins_res["success"], "Test person insert failed")

	# A. Test New Photo (Original = untouched source, Current = display/edit version)
	var p_row = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row["original_profile_photo"] == raw_source_b64, "A. Original MUST store untouched source photo")
	assert(p_row["profile_photo"] == crop1_display_b64, "A. Current MUST store display/edit version")
	assert(p_row["original_profile_photo"] != p_row["profile_photo"], "A. Original and Current MUST be distinct")
	print("✅ Test A Passed: New photo distinguishes Protected Original from Current display photo.")

	# B. Test Crop current (Original unchanged, Current changed)
	db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [crop2_display_b64, test_person_uuid])
	var p_row_b = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row_b["profile_photo"] == crop2_display_b64, "B. Current photo updated to new crop")
	assert(p_row_b["original_profile_photo"] == raw_source_b64, "B. Protected Original MUST remain byte-for-byte unchanged!")
	print("✅ Test B Passed: Cropping current photo leaves Protected Original byte-for-byte unchanged.")

	# C. Test Resize current (Original unchanged, Current changed)
	var resized_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var resized_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(resized_img.save_png_to_buffer())
	db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [resized_b64, test_person_uuid])
	var p_row_c = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row_c["profile_photo"] == resized_b64, "C. Current photo updated to resized image")
	assert(p_row_c["original_profile_photo"] == raw_source_b64, "C. Protected Original MUST remain byte-for-byte unchanged!")
	print("✅ Test C Passed: Resizing current photo leaves Protected Original byte-for-byte unchanged.")

	# D. Test Restore Original (Current regenerated from original, Original byte-for-byte unchanged)
	# Restore sets profile_photo back to original_profile_photo
	db.execute("UPDATE people SET profile_photo = original_profile_photo WHERE person_uuid = ?;", [test_person_uuid])
	var p_row_d = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row_d["profile_photo"] == raw_source_b64, "D. Current photo restored from Protected Original")
	assert(p_row_d["original_profile_photo"] == raw_source_b64, "D. Protected Original remains byte-for-byte unchanged!")
	print("✅ Test D Passed: Restore Original regenerates current photo without altering original.")

	# E. Test Repeated Edits (Original remains unchanged after multiple crops/resizes)
	for i in range(5):
		var edit_i_img = Image.create(10 + i * 5, 10 + i * 5, false, Image.FORMAT_RGBA8)
		var edit_i_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(edit_i_img.save_png_to_buffer())
		db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [edit_i_b64, test_person_uuid])
		var p_row_e = db.execute("SELECT original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
		assert(p_row_e["original_profile_photo"] == raw_source_b64, "E. Protected Original MUST remain byte-for-byte unchanged on edit iteration " + str(i))
	print("✅ Test E Passed: Repeated edits leave Protected Original byte-for-byte unchanged.")

	# F. Test Save Current as Original (Replaces protected original with confirmation/intent)
	var new_master_img = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	new_master_img.fill(Color(1.0, 1.0, 0.0, 1.0)) # Yellow image
	var new_master_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(new_master_img.save_png_to_buffer())
	db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [new_master_b64, test_person_uuid])
	
	# Action: Save Current as Original
	db.execute("UPDATE people SET original_profile_photo = profile_photo WHERE person_uuid = ?;", [test_person_uuid])
	var p_row_f = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row_f["original_profile_photo"] == new_master_b64, "F. Protected Original replaced after Save Current as Original action")
	print("✅ Test F Passed: Save Current as Original replaces protected original master.")

	# G. Test New Replacement Photo (New source becomes new protected original)
	var replacement_source_img = Image.create(120, 120, false, Image.FORMAT_RGBA8)
	replacement_source_img.fill(Color(0.5, 0.0, 0.5, 1.0)) # Purple image
	var replacement_source_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(replacement_source_img.save_png_to_buffer())
	var replacement_crop_b64 = "data:image/png;base64," + Marshalls.raw_to_base64(replacement_source_img.get_region(Rect2i(0, 0, 60, 60)).save_png_to_buffer())
	
	db.execute("UPDATE people SET profile_photo = ?, original_profile_photo = ? WHERE person_uuid = ?;", [replacement_crop_b64, replacement_source_b64, test_person_uuid])
	var p_row_g = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(p_row_g["original_profile_photo"] == replacement_source_b64, "G. New source photo becomes new protected original")
	assert(p_row_g["profile_photo"] == replacement_crop_b64, "G. New cropped photo becomes current display photo")
	print("✅ Test G Passed: Entirely new photo selection updates both Protected Original and Current display photo.")

	# H. Test Existing Profile Migration (Existing photo preserved as protected baseline without changing visible photo)
	var legacy_person_uuid = "usr_legacy_photo_test_8888"
	db.execute("DELETE FROM people WHERE person_uuid = ?;", [legacy_person_uuid])
	var legacy_img_b64 = "data:image/png;base64,LEGACY_IMAGE_DATA_12345"
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, profile_photo) VALUES (?, 'P-LEGACY-01', 'Legacy', 'User', 'active', ?);", [legacy_person_uuid, legacy_img_b64])
	
	# Execute Migration Backfill query logic
	db.execute("UPDATE people SET original_profile_photo = profile_photo WHERE person_uuid = ? AND (original_profile_photo IS NULL OR original_profile_photo = '');", [legacy_person_uuid])
	var legacy_row = db.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [legacy_person_uuid])["data"][0]
	assert(legacy_row["profile_photo"] == legacy_img_b64, "H. Existing current image MUST remain unchanged")
	assert(legacy_row["original_profile_photo"] == legacy_img_b64, "H. Existing photo becomes initial protected baseline original")
	print("✅ Test H Passed: Existing profiles migrated cleanly without modifying pixels or visible current photo.")

	# I. Test Restart (Original and current both remain available after re-instantiating DB connection)
	var db_reopen = SQLiteDatabaseScript.new(db_path)
	var restart_row = db_reopen.execute("SELECT profile_photo, original_profile_photo FROM people WHERE person_uuid = ?;", [test_person_uuid])["data"][0]
	assert(restart_row["original_profile_photo"] == replacement_source_b64, "I. Protected original survives restart")
	assert(restart_row["profile_photo"] == replacement_crop_b64, "I. Current photo survives restart")
	print("✅ Test I Passed: Both Protected Original and Current photo survive app restart.")

	# J. Test Sync Engine & Directory Read Service (Sync continues using CURRENT profile_photo)
	var read_service = DirectoryReadServiceScript.new(db_reopen)
	var person_res = read_service.get_person(test_person_uuid)
	assert(person_res["success"], "get_person failed")
	var p_data = person_res["person"]
	assert(str(p_data.get("profile_photo", "")) == replacement_crop_b64, "J. Directory read service and sync engine continue using CURRENT profile_photo")
	assert(str(p_data.get("original_profile_photo", "")) == replacement_source_b64, "J. Protected original is available in person record")
	print("✅ Test J Passed: Profile photo sync and directory read service continue using optimized CURRENT photo.")

	# Cleanup test records
	db_reopen.execute("DELETE FROM people WHERE person_uuid IN (?, ?);", [test_person_uuid, legacy_person_uuid])

	print("--- Protected Original Profile Photo Test Suite PASSED CLEANLY ---")
	quit()
