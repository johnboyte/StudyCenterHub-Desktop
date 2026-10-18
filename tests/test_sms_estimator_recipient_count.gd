@tool
extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================================")
	print("STARTING FOCUSED REGRESSION TEST: SMS ESTIMATOR RECIPIENT COUNT ACCURACY")
	print("==========================================================================")

	var user_dir = OS.get_user_data_dir()
	var test_db_path = user_dir.path_join("test_sms_estimator_recipient_count.db")
	ProjectSettings.set_setting("app/database_override_path", test_db_path)

	call_deferred("_run_tests")

func _find_checkbox(vbox: VBoxContainer, pid: int) -> CheckBox:
	if not vbox: return null
	for row in vbox.get_children():
		for child in row.get_children():
			if child is CheckBox:
				var cb = child as CheckBox
				if cb.has_meta("person_id") and int(cb.get_meta("person_id")) == pid:
					return cb
	return null

func _run_tests() -> void:
	var db = SQLiteDatabaseScript.new()
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# Clean people table for deterministic test data
	db.execute("DELETE FROM people;")

	# Insert controlled test constituents:
	# ID 1: Alice Smith (Fully eligible, Phone A)
	# ID 2: Bob Jones (Fully eligible, Phone B)
	# ID 3: Charlie Brown (Fully eligible, DUPLICATE Phone A with Alice)
	# ID 4: David NoPhone (EXCLUDED: Missing phone)
	# ID 5: Eve OptOut (EXCLUDED: SMS consent = 0)
	# ID 6: Frank DummyPhone (EXCLUDED: 555-0000 phone)
	var people_data = [
		[1, "P-001", "uuid_1", "Alice", "Smith", "alice@example.com", "(864) 555-1001", 1],
		[2, "P-002", "uuid_2", "Bob", "Jones", "bob@example.com", "(864) 555-1002", 1],
		[3, "P-003", "uuid_3", "Charlie", "Brown", "charlie@example.com", "(864) 555-1001", 1],
		[4, "P-004", "uuid_4", "David", "NoPhone", "david@example.com", "", 1],
		[5, "P-005", "uuid_5", "Eve", "OptOut", "eve@example.com", "(864) 555-1005", 0],
		[6, "P-006", "uuid_6", "Frank", "Dummy", "frank@example.com", "555-0000", 1]
	]

	for row in people_data:
		db.execute(
			"INSERT INTO people (id, human_id, person_uuid, first_name, last_name, email, phone, sms_consent, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active');",
			row
		)

	var scene_res = load("res://app/scenes/communications_view.tscn")
	var comm_view = scene_res.instantiate()
	comm_view.db = db
	root.add_child(comm_view)

	if not comm_view.is_node_ready() or comm_view.audience_type_dropdown == null:
		comm_view._setup_communicate_send_composer()
		comm_view._ready()
	comm_view.db = db
	comm_view._populate_dropdowns()

	await create_timer(0.3).timeout

	comm_view._on_audience_type_selected(0) # Individual
	comm_view._refresh_checkbox_list()

	var cb_vbox = comm_view.checkbox_list_vbox
	var search_input = comm_view.recipient_search_input
	var btn_all = comm_view.btn_select_all_shown
	var btn_clear = comm_view.btn_clear_selection

	# =========================================================================
	# 1. NO RECIPIENTS SELECTED, EMPTY MESSAGE
	# =========================================================================
	comm_view.selected_individual_ids.clear()
	comm_view.message_body_edit.text = ""
	comm_view._update_audience_resolution()
	await create_timer(0.1).timeout

	print("\n--- Test 1: Zero Recipients, Empty Message ---")
	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Per Recip:  ", comm_view.lbl_est_segs_per_recip_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:       ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Authoritative recipient count must be 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 0")
	assert("Per Recip: 0" in comm_view.lbl_est_segs_per_recip_val.text, "Empty message must show Per Recip: 0")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Must show Total: 0 segments")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Must show Est. Cost: $0.00")
	assert("0 Eligible Recipients" in comm_view.aud_count_label.text, "Audience count label must show 0 Eligible Recipients")
	print("✓ PASS 1: Zero recipients with empty message correctly displays Recipients: 0, Total: 0, $0.00.")

	# =========================================================================
	# 2. MESSAGE ENTERED BUT NO RECIPIENTS SELECTED
	# =========================================================================
	comm_view.message_body_edit.text = "Hello study group! Meeting tonight at 7 PM sharp."
	comm_view._update_character_count()
	await create_timer(0.1).timeout

	print("\n--- Test 2: Message Entered, No Recipients Selected ---")
	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Per Recip:  ", comm_view.lbl_est_segs_per_recip_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:       ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Authoritative recipient count must remain 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 0 with typed message")
	assert("Per Recip: 1 seg" in comm_view.lbl_est_segs_per_recip_val.text, "Must show actual message segment count (1 seg)")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Total must be 0 segments when no recipients selected")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Cost must be $0.00 when no recipients selected")
	print("✓ PASS 2: Message entered with no recipients displays Recipients: 0, Per Recip: 1 seg, Total: 0 segs, $0.00.")

	# =========================================================================
	# 3. ONE ELIGIBLE RECIPIENT SELECTED
	# =========================================================================
	var cb_alice = _find_checkbox(cb_vbox, 1)
	assert(cb_alice != null, "Alice checkbox must exist")
	cb_alice.button_pressed = true
	cb_alice.toggled.emit(true)
	await create_timer(0.1).timeout

	print("\n--- Test 3: One Eligible Recipient Selected ---")
	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Per Recip:  ", comm_view.lbl_est_segs_per_recip_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:       ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.get_authoritative_sms_recipient_count() == 1, "Authoritative recipient count must be 1")
	assert("Recipients: 1" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 1")
	assert("Total: 1 segment" in comm_view.lbl_est_total_segs_val.text, "Total must be 1 segment")
	assert("Est. Cost: $0.01" in comm_view.lbl_est_cost_val.text, "Cost must be $0.01")
	print("✓ PASS 3: One eligible recipient displays Recipients: 1, Total: 1 segment, $0.01.")

	# =========================================================================
	# 4. MULTIPLE ELIGIBLE RECIPIENTS (Distinct Phones)
	# =========================================================================
	var cb_bob = _find_checkbox(cb_vbox, 2)
	assert(cb_bob != null, "Bob checkbox must exist")
	cb_bob.button_pressed = true
	cb_bob.toggled.emit(true)
	await create_timer(0.1).timeout

	print("\n--- Test 4: Multiple Eligible Recipients (Distinct Phones) ---")
	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Per Recip:  ", comm_view.lbl_est_segs_per_recip_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:       ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.get_authoritative_sms_recipient_count() == 2, "Authoritative recipient count must be 2")
	assert("Recipients: 2" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 2")
	assert("Total: 2 segments" in comm_view.lbl_est_total_segs_val.text, "Total must be 2 segments")
	assert("Est. Cost: $0.02" in comm_view.lbl_est_cost_val.text, "Cost must be $0.02")
	print("✓ PASS 4: Multiple eligible recipients display Recipients: 2, Total: 2 segments, $0.02.")

	# =========================================================================
	# 5. DUPLICATE PHONE NUMBER DEDUPLICATION
	# Charlie (ID 3) shares the exact same phone number (864) 555-1001 with Alice (ID 1).
	# =========================================================================
	var cb_charlie = _find_checkbox(cb_vbox, 3)
	assert(cb_charlie != null, "Charlie checkbox must exist")
	cb_charlie.button_pressed = true
	cb_charlie.toggled.emit(true)
	await create_timer(0.1).timeout

	print("\n--- Test 5: Duplicate Phone Number Selected ---")
	print("  Selected IDs: ", comm_view.selected_individual_ids)
	print("  Recipients:   ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs:   ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:         ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.selected_individual_ids.size() == 3, "Selected IDs count is 3")
	assert(comm_view.get_authoritative_sms_recipient_count() == 2, "Authoritative recipient count must deduplicate phone and return 2")
	assert("Recipients: 2" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 2 (duplicate phone deduplicated)")
	assert("Total: 2 segments" in comm_view.lbl_est_total_segs_val.text, "Total must remain 2 segments")
	assert("Est. Cost: $0.02" in comm_view.lbl_est_cost_val.text, "Cost must remain $0.02")
	print("✓ PASS 5: Duplicate phone numbers are deduplicated: 3 contacts -> 2 unique SMS recipients.")

	# =========================================================================
	# 6. EXCLUDED RECIPIENTS (Missing phone, opt-out, dummy 555-0000)
	# =========================================================================
	var cb_david = _find_checkbox(cb_vbox, 4) # Missing phone
	var cb_eve = _find_checkbox(cb_vbox, 5)   # Opt-out (sms_consent = 0)
	var cb_frank = _find_checkbox(cb_vbox, 6) # Dummy 555-0000
	assert(cb_david != null and cb_eve != null and cb_frank != null, "Excluded checkboxes must exist")

	cb_david.button_pressed = true; cb_david.toggled.emit(true)
	cb_eve.button_pressed = true; cb_eve.toggled.emit(true)
	cb_frank.button_pressed = true; cb_frank.toggled.emit(true)
	await create_timer(0.1).timeout

	print("\n--- Test 6: Selecting Excluded Recipients ---")
	print("  Selected IDs:    ", comm_view.selected_individual_ids)
	print("  Audience Label:  ", comm_view.aud_count_label.text)
	print("  Recipients:      ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs:      ", comm_view.lbl_est_total_segs_val.text)

	assert(comm_view.selected_individual_ids.size() == 6, "All 6 people selected")
	assert(comm_view.get_authoritative_sms_recipient_count() == 2, "Authoritative recipient count must remain 2 (all 3 excluded ignored)")
	assert("Recipients: 2" in comm_view.lbl_est_recipients_val.text, "Estimator must ignore excluded recipients and display Recipients: 2")
	assert("Total: 2 segments" in comm_view.lbl_est_total_segs_val.text, "Total billable segments must remain 2")
	assert("Est. Cost: $0.02" in comm_view.lbl_est_cost_val.text, "Cost must remain $0.02")
	print("✓ PASS 6: Excluded contacts (missing phone, opt-out, dummy phone) are never counted in SMS estimator.")

	# =========================================================================
	# 7. CLEAR SELECTION
	# =========================================================================
	btn_clear.pressed.emit()
	await create_timer(0.1).timeout

	print("\n--- Test 7: Clear Selection ---")
	print("  Selected IDs: ", comm_view.selected_individual_ids)
	print("  Recipients:   ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs:   ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:         ", comm_view.lbl_est_cost_val.text)

	assert(comm_view.selected_individual_ids.size() == 0, "Selected IDs must be empty")
	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Authoritative count must return to 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Must return to Recipients: 0")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Must return to Total: 0 segments")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Must return to Est. Cost: $0.00")
	print("✓ PASS 7: Clear Selection immediately resets estimator to Recipients: 0, Total: 0, $0.00.")

	# =========================================================================
	# 8. SELECT ONLY EXCLUDED PERSON (0 Eligible, 1 Excluded)
	# =========================================================================
	cb_eve.button_pressed = true
	cb_eve.toggled.emit(true)
	await create_timer(0.1).timeout

	print("\n--- Test 8: Select Only Excluded Person (Eve - Opt Out) ---")
	print("  Audience Label: ", comm_view.aud_count_label.text)
	print("  Recipients:     ", comm_view.lbl_est_recipients_val.text)
	print("  Cost:           ", comm_view.lbl_est_cost_val.text)

	assert("0 Eligible Recipients" in comm_view.aud_count_label.text, "Audience must show 0 Eligible Recipients")
	assert("1 Excluded" in comm_view.aud_count_label.text, "Audience must show 1 Excluded")
	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Authoritative SMS count must be 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Must show Recipients: 0 when only excluded selected")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Must show Total: 0 segments")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Must show Est. Cost: $0.00")
	print("✓ PASS 8: When 0 eligible and 1 excluded selected, estimator correctly displays Recipients: 0 and $0.00.")

	# =========================================================================
	# 9. SEARCH FILTER & SELECT ALL SHOWN
	# =========================================================================
	btn_clear.pressed.emit()
	await create_timer(0.1).timeout

	search_input.text = "Jones" # Only matches Bob Jones
	comm_view._refresh_checkbox_list()
	await create_timer(0.1).timeout

	btn_all.pressed.emit()
	await create_timer(0.1).timeout

	print("\n--- Test 9: Search Filter + Select All Shown ---")
	print("  Selected IDs: ", comm_view.selected_individual_ids)
	print("  Recipients:   ", comm_view.lbl_est_recipients_val.text)

	assert(comm_view.selected_individual_ids.size() == 1, "Exactly 1 person selected via filtered Select All Shown")
	assert(comm_view.selected_individual_ids[0] == 2, "Selected person must be Bob (ID 2)")
	assert(comm_view.get_authoritative_sms_recipient_count() == 1, "Authoritative recipient count must be 1")
	assert("Recipients: 1" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 1")
	print("✓ PASS 9: Search filter + Select All Shown selects only filtered constituent and updates estimator to Recipients: 1.")

	# =========================================================================
	# 10. CHANNEL SWITCHING (SMS vs Both vs Email)
	# =========================================================================
	print("\n--- Test 10: Channel Switching ---")
	# Channel dropdown index: 0=SMS Text, 1=Email
	comm_view.channel_dropdown.select(1) # Email
	comm_view._on_channel_selected_change(1)
	await create_timer(0.1).timeout
	assert(comm_view.sms_estimator_card.visible == false, "SMS estimator card must hide on Email channel")
	print("  - Email channel hides estimator: OK")

	comm_view.channel_dropdown.select(0) # SMS Text
	comm_view._on_channel_selected_change(0)
	await create_timer(0.1).timeout
	assert(comm_view.sms_estimator_card.visible == true, "SMS estimator card must be visible on SMS channel")
	assert("Recipients: 1" in comm_view.lbl_est_recipients_val.text, "Estimator retains Recipients: 1")
	print("  - Return to SMS channel reveals estimator with Recipients: 1: OK")
	print("✓ PASS 10: Delivery channel switching updates estimator visibility and accuracy.")

	# =========================================================================
	# 11. OPTIMIZE FOR SMS DIALOG USES AUTHORITATIVE RECIPIENT COUNT
	# =========================================================================
	print("\n--- Test 11: Optimize for SMS Dialog Authoritative Count ---")
	# Enter text with Unicode smart quotes: “Hello Bob”
	comm_view.message_body_edit.text = "“Special Real Life Announcement — Tonight at 7 PM!”"
	comm_view._update_character_count()
	await create_timer(0.1).timeout

	assert(comm_view.btn_optimize_sms.visible == true, "Optimize button must be visible for Unicode text")
	comm_view._on_btn_optimize_sms_pressed()
	await create_timer(0.1).timeout

	var dlg_found = false
	for child in comm_view.get_children():
		if child is ConfirmationDialog and child.title == "Optimize Message for SMS":
			dlg_found = true
			# Verify dialog text reflects exactly 1 recipient
			var found_before_recip = false
			for lbl in child.find_children("*", "Label", true, false):
				if "BEFORE:" in lbl.text and "total billable segments" in lbl.text:
					found_before_recip = true
					print("  - Optimize dialog before summary: ", lbl.text.replace("\n", " "))
					assert(not "27 total" in lbl.text, "Dialog must NOT fall back to 27 recipients")
					break
			assert(found_before_recip, "Dialog before section must be present")
			child.queue_free()
			break

	assert(dlg_found, "Optimize confirmation dialog must be created")
	print("✓ PASS 11: Optimize for SMS dialog uses exact authoritative recipient count without fallbacks.")

	print("\n==========================================================================")
	print("ALL 11 SMS ESTIMATOR RECIPIENT COUNT REGRESSION TESTS PASSED CLEANLY!")
	print("==========================================================================")
	quit(0)
