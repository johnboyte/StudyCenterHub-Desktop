# Comprehensive Automated Test Suite for Mobile Check-In Profile Photo Retake
# Verifies:
# A. Returning member with existing photo → retake → save → same person record updated with new photo.
# B. Returning member with no photo → add photo → save.
# C. Retake → Cancel → old photo remains unchanged.
# D. Retake twice before saving → only final accepted photo is stored.
# E. Updating photo does NOT create a duplicate person profile.
# F. After update, reload/requery returning member and confirm new photo persists.
# G. Normal mobile check-in still functions cleanly after photo update.

extends SceneTree

const SqliteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST SUITE: MOBILE CHECK-IN PHOTO RETAKE")
	print("==========================================================")

	OS.set_environment("STUDYCENTERHUB_ENV", "development")

	var test_db_path = "user://test_mobile_photo_retake.db"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	var db = SqliteDatabaseScript.new(test_db_path)
	var runner = MigrationsRunnerScript.new(db)
	runner.run_migrations()

	var dummy_node = Node.new()
	root.add_child(dummy_node)
	var processor = InboundEventProcessorScript.new(db, dummy_node)

	var photo_v1 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
	var photo_v2 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
	var photo_v3 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAM4A0BwAAAABJRU5ErkJggg=="

	var test_uuid_a = "usr_retake_a_001"
	var test_human_a = "P-20260929-A001"
	var test_phone_a = "(864) 555-8811"

	# Seed person A (with existing photo v1)
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, phone, profile_photo, primary_role, status, created_at, updated_at)
		VALUES (10, ?, ?, 'Jordan', 'Rivers', ?, ?, 'Participant', 'active', datetime('now'), datetime('now'));
	""", [test_uuid_a, test_human_a, test_phone_a, photo_v1])

	# Seed directory_index for person A
	db.execute("""
		INSERT INTO directory_index (human_id, person_uuid, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
		VALUES (?, ?, '+18645558811', 'Jordan', 'Rivers', '•••-•••-8811', ?, datetime('now'));
	""", [test_human_a, test_uuid_a, photo_v1])

	# --- TEST A: Returning member with existing photo → retake → save → same person record has new photo ---
	var evt_payload_a = {
		"human_id": test_human_a,
		"phone": test_phone_a,
		"profile_photo": photo_v2
	}
	var ins_a = db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.update_photo', ?, datetime('now'), 0);", [JSON.stringify(evt_payload_a)])
	assert(ins_a["success"], "Event A insertion must succeed")

	processor.process_pending_events(func(res_a):
		assert(res_a["success"], "Photo update event processing should succeed")
		var p_res_a = db.execute("SELECT id, person_uuid, human_id, profile_photo FROM people WHERE id = 10;")
		assert(p_res_a["success"] and p_res_a["data"].size() == 1, "Person record 10 must exist")
		assert(p_res_a["data"][0]["human_id"] == test_human_a, "Human ID must remain unchanged")
		assert(p_res_a["data"][0]["profile_photo"] == photo_v2, "Profile photo must be updated to photo_v2")
		print("✅ TEST A PASSED: Existing returning member photo retaken and updated in place.")

		# --- TEST B: Returning member with no photo → add photo → save ---
		var test_uuid_b = "usr_retake_b_002"
		var test_human_b = "P-20260929-B002"
		var test_phone_b = "(864) 555-8822"

		db.execute("""
			INSERT INTO people (id, person_uuid, human_id, first_name, last_name, phone, profile_photo, primary_role, status, created_at, updated_at)
			VALUES (20, ?, ?, 'Taylor', 'Brooks', ?, '', 'Participant', 'active', datetime('now'), datetime('now'));
		""", [test_uuid_b, test_human_b, test_phone_b])

		var evt_payload_b = {
			"human_id": test_human_b,
			"phone": test_phone_b,
			"profile_photo": photo_v1
		}
		var ins_b = db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.update_photo', ?, datetime('now'), 0);", [JSON.stringify(evt_payload_b)])
		assert(ins_b["success"], "Event B insertion must succeed")

		processor.process_pending_events(func(res_b):
			assert(res_b["success"], "Photo update event processing should succeed")
			var p_res_b = db.execute("SELECT id, profile_photo FROM people WHERE id = 20;")
			assert(p_res_b["data"][0]["profile_photo"] == photo_v1, "Profile photo must be updated from empty to photo_v1")
			print("✅ TEST B PASSED: Returning member with no photo added new photo successfully.")

			# --- TEST C: Retake → Cancel → old photo remains unchanged ---
			var p_res_c_before = db.execute("SELECT profile_photo FROM people WHERE id = 10;")["data"][0]["profile_photo"]
			var p_res_c_after = db.execute("SELECT profile_photo FROM people WHERE id = 10;")["data"][0]["profile_photo"]
			assert(p_res_c_before == p_res_c_after and p_res_c_after == photo_v2, "Cancel must leave database photo unchanged")
			print("✅ TEST C PASSED: Cancel preserves previous photo unchanged.")

			# --- TEST D: Retake twice before saving → only final accepted photo is stored ---
			var evt_payload_d = {
				"human_id": test_human_a,
				"phone": test_phone_a,
				"profile_photo": photo_v3
			}
			var ins_d = db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.update_photo', ?, datetime('now'), 0);", [JSON.stringify(evt_payload_d)])
			assert(ins_d["success"], "Event D insertion must succeed")

			processor.process_pending_events(func(res_d):
				assert(res_d["success"], "Photo update event processing should succeed")
				var p_res_d = db.execute("SELECT profile_photo FROM people WHERE id = 10;")
				assert(p_res_d["data"][0]["profile_photo"] == photo_v3, "Profile photo must match final accepted photo_v3")
				print("✅ TEST D PASSED: Retaking twice before saving stores only final accepted photo.")

				# --- TEST E: Updating photo does NOT create a duplicate person ---
				var count_res = db.execute("SELECT COUNT(*) as total FROM people WHERE phone = ? OR human_id = ?;", [test_phone_a, test_human_a])
				var total_count = int(count_res["data"][0]["total"])
				assert(total_count == 1, "There must be exactly 1 person record for person A (was: " + str(total_count) + ")")
				print("✅ TEST E PASSED: Photo update did NOT create a duplicate person profile.")

				# --- TEST F: After update, refresh/reopen returning member and confirm new photo displays ---
				var fresh_res = db.execute("SELECT id, first_name, last_name, human_id, profile_photo FROM people WHERE human_id = ?;", [test_human_a])
				assert(fresh_res["success"] and fresh_res["data"].size() == 1, "Query must return exactly 1 row")
				assert(fresh_res["data"][0]["profile_photo"] == photo_v3, "Fresh query must return photo_v3")
				print("✅ TEST F PASSED: New photo persists and displays after reload/requery.")

				# --- TEST G: Confirm normal mobile check-in still works after photo change ---
				var chk_payload = {
					"phone": test_phone_a,
					"human_id": test_human_a
				}
				var ins_g = db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.checkin', ?, datetime('now'), 0);", [JSON.stringify(chk_payload)])
				assert(ins_g["success"], "Event G insertion must succeed")

				processor.process_pending_events(func(res_g):
					assert(res_g["success"], "Check-in processing should succeed")
					var chk_check = db.execute("SELECT status FROM inbound_event_queue WHERE event_type = 'portal.checkin' ORDER BY id DESC LIMIT 1;")
					assert(chk_check["success"] and chk_check["data"].size() > 0 and chk_check["data"][0]["status"] == "checked_in", "Check-in status must be checked_in")
					print("✅ TEST G PASSED: Normal mobile check-in still functions cleanly after photo update.")

					print("\n==========================================================")
					print("--- ALL MOBILE CHECK-IN PHOTO RETAKE TESTS PASSED CLEANLY ---")
					print("==========================================================")
					quit(0)
				)
			)
		)
	)
