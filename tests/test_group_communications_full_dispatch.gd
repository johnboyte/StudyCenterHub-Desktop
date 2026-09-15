extends SceneTree

## Automated Verification Test Suite for Group Communications Dispatch

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("============================================================")
	print("STARTING FULL GROUP COMMUNICATIONS DISPATCH TEST SUITE")
	print("============================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	var com_scene = load("res://app/scenes/communications_view.tscn").instantiate()
	com_scene.db = db
	root.add_child(com_scene)
	com_scene._ready()

	# 1. Test Audience Types presence
	var aud_dropdown = com_scene.audience_type_dropdown
	assert(aud_dropdown != null, "Audience dropdown must exist")
	var aud_items = []
	for i in range(aud_dropdown.item_count):
		aud_items.append(aud_dropdown.get_item_text(i))

	print("[TEST] Audiences verified: ", aud_items)
	assert(aud_items.has("Individual"), "Must have Individual")
	assert(aud_items.has("Real Life"), "Must have Real Life")
	assert(aud_items.has("Pathway"), "Must have Pathway")
	assert(aud_items.has("Session"), "Must have Session")
	assert(aud_items.has("Volunteers"), "Must have Volunteers")
	assert(aud_items.has("Checked In Today"), "Must have Checked In Today")
	assert(aud_items.has("All Active People"), "Must have All Active People")

	# 2. Test Pathway Canonical Enrollments (Fellows, LEAD only)
	com_scene.selected_audience_type = "Pathway"
	com_scene._update_audience_resolution()
	var pw_dropdown = com_scene.pathway_dropdown
	assert(pw_dropdown != null, "Pathway dropdown must exist")
	var pw_items = []
	for i in range(pw_dropdown.item_count):
		pw_items.append(pw_dropdown.get_item_text(i))
	print("[TEST] Pathway options: ", pw_items)
	assert(pw_items.has("Fellows"), "Pathways must contain Fellows")
	assert(pw_items.has("LEAD"), "Pathways must contain LEAD")
	assert(not pw_items.has("Academic Mastery"), "Pathways MUST NOT contain Academic Mastery")
	assert(not pw_items.has("Discipleship Track"), "Pathways MUST NOT contain Discipleship Track")

	# 3. Test Single Individual Channels (SMS, Email, Phone Call allowed)
	com_scene.selected_audience_type = "Individual"
	com_scene.selected_individual_ids = [1]
	com_scene._update_channel_dropdown_options()
	var single_channels = []
	for i in range(com_scene.channel_dropdown.item_count):
		single_channels.append(com_scene.channel_dropdown.get_item_text(i))
	print("[TEST] Single individual channels: ", single_channels)
	assert(single_channels.has("Phone Call"), "Single individual MUST allow Phone Call")

	# 4. Test Multi-Individual Channels (Bulk Call prevented, Both allowed)
	com_scene.selected_individual_ids = [1, 2]
	com_scene._update_channel_dropdown_options()
	var multi_channels = []
	for i in range(com_scene.channel_dropdown.item_count):
		multi_channels.append(com_scene.channel_dropdown.get_item_text(i))
	print("[TEST] Multi-individual channels: ", multi_channels)
	assert(not multi_channels.has("Phone Call"), "Multi-individual MUST NOT allow Phone Call")
	assert(multi_channels.has("Both (SMS + Email)"), "Multi-individual MUST allow Both")

	# Ensure test constituent records exist in DB to satisfy foreign keys
	db.execute("INSERT OR IGNORE INTO people (id, person_uuid, human_id, first_name, last_name, phone, email, sms_consent, status) VALUES (9901, 'uuid-9901', 'TST-9901', 'Full', 'Tester', '4345550199', 'fulltest@example.com', 1, 'active');")
	db.execute("INSERT OR IGNORE INTO people (id, person_uuid, human_id, first_name, last_name, phone, email, sms_consent, status) VALUES (9902, 'uuid-9902', 'TST-9902', 'SMS', 'Tester', '4345550198', '', 1, 'active');")
	db.execute("INSERT OR IGNORE INTO people (id, person_uuid, human_id, first_name, last_name, phone, email, sms_consent, status) VALUES (9903, 'uuid-9903', 'TST-9903', 'Email', 'Tester', '', 'emailtest@example.com', 1, 'active');")
	db.execute("INSERT OR IGNORE INTO people (id, person_uuid, human_id, first_name, last_name, phone, email, sms_consent, status) VALUES (9904, 'uuid-9904', 'TST-9904', 'Opt', 'OutTester', '4345550197', 'optout@example.com', 0, 'active');")

	var p_full = {"id": 9901, "person_uuid": "uuid-9901", "human_id": "TST-9901", "phone": "4345550199", "email": "fulltest@example.com", "sms_consent": 1}
	var p_sms_only = {"id": 9902, "person_uuid": "uuid-9902", "human_id": "TST-9902", "phone": "4345550198", "email": "", "sms_consent": 1}
	var p_email_only = {"id": 9903, "person_uuid": "uuid-9903", "human_id": "TST-9903", "phone": "", "email": "emailtest@example.com", "sms_consent": 1}
	var p_opt_out = {"id": 9904, "person_uuid": "uuid-9904", "human_id": "TST-9904", "phone": "4345550197", "email": "optout@example.com", "sms_consent": 0}

	var eval_both_full = com_scene._evaluate_person_eligibility(p_full, "Both (SMS + Email)")
	assert(eval_both_full.is_eligible == true, "Full contact person must be eligible for Both")
	assert(eval_both_full.sms_ok == true, "SMS ok should be true")
	assert(eval_both_full.email_ok == true, "Email ok should be true")

	var eval_both_sms_only = com_scene._evaluate_person_eligibility(p_sms_only, "Both (SMS + Email)")
	assert(eval_both_sms_only.is_eligible == true, "SMS-only person must be eligible for Both")
	assert(eval_both_sms_only.sms_ok == true, "SMS ok should be true for sms-only person")
	assert(eval_both_sms_only.email_ok == false, "Email ok should be false for sms-only person")

	var eval_both_email_only = com_scene._evaluate_person_eligibility(p_email_only, "Both (SMS + Email)")
	assert(eval_both_email_only.is_eligible == true, "Email-only person must be eligible for Both")
	assert(eval_both_email_only.sms_ok == false, "SMS ok should be false for email-only person")
	assert(eval_both_email_only.email_ok == true, "Email ok should be true for email-only person")

	var eval_sms_opt_out = com_scene._evaluate_person_eligibility(p_opt_out, "SMS Text")
	assert(eval_sms_opt_out.is_eligible == false, "SMS opt-out person must be excluded for SMS")

	print("[TEST] Eligibility and channel independence rules verified cleanly!")

	# 6. Test Group Broadcast Execution & Per-Person Communication Logging
	var initial_logs_res = db.execute("SELECT COUNT(*) as cnt FROM communications_log;")
	var initial_log_count = int(initial_logs_res["data"][0]["cnt"]) if initial_logs_res["success"] else 0

	com_scene.current_eligible_recipients = [
		{"id": p_full.id, "person_uuid": p_full.person_uuid, "human_id": p_full.human_id, "phone": p_full.phone, "email": p_full.email, "sms_consent": 1, "first_name": "Full", "last_name": "Tester", "eval": eval_both_full},
		{"id": p_sms_only.id, "person_uuid": p_sms_only.person_uuid, "human_id": p_sms_only.human_id, "phone": p_sms_only.phone, "email": p_sms_only.email, "sms_consent": 1, "first_name": "SMS", "last_name": "Tester", "eval": eval_both_sms_only},
		{"id": p_email_only.id, "person_uuid": p_email_only.person_uuid, "human_id": p_email_only.human_id, "phone": p_email_only.phone, "email": p_email_only.email, "sms_consent": 1, "first_name": "Email", "last_name": "Tester", "eval": eval_both_email_only}
	]
	com_scene.current_excluded_recipients = [
		{"id": p_opt_out.id, "person_uuid": p_opt_out.person_uuid, "human_id": p_opt_out.human_id, "phone": p_opt_out.phone, "email": p_opt_out.email, "sms_consent": 0, "first_name": "Opt", "last_name": "OutTester", "eval": eval_sms_opt_out}
	]

	# Test execution loop directly
	com_scene._execute_group_broadcast("Both (SMS + Email)", "Automated Group Test Message", null)

	var final_logs_res = db.execute("SELECT COUNT(*) as cnt FROM communications_log;")
	var final_log_count = int(final_logs_res["data"][0]["cnt"]) if final_logs_res["success"] else 0

	print("[TEST] Initial Log Count: ", initial_log_count, " | Final Log Count: ", final_log_count)
	assert(final_log_count - initial_log_count == 4, "Should create exactly 4 individual communication log entries")

	# Verify double-send protection resets properly
	assert(com_scene._is_sending_group_broadcast == false, "Double-send guard flag must reset to false after broadcast")

	# Clean up test constituents
	db.execute("DELETE FROM people WHERE id IN (9901, 9902, 9903, 9904);")

	print("============================================================")
	print("ALL GROUP COMMUNICATIONS DISPATCH AUTOMATED TESTS PASSED CLEANLY")
	print("============================================================")
	quit()
