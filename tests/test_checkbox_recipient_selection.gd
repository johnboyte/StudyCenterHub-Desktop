@tool
extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING FOCUSED VERIFICATION: CHECKBOX RECIPIENT SELECTION")
	print("==========================================================")
	
	var user_dir = OS.get_user_data_dir()
	var test_db_path = user_dir.path_join("test_checkbox_recipient_selection.db")
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

	# Insert 30 test constituents
	for i in range(1, 31):
		var fn = "TestUser%d" % i if i <= 15 else "OtherMember%d" % i
		var ln = "Alpha%d" % i if i % 2 == 0 else "Beta%d" % i
		var hid = "P-%03d" % i
		var em = "user%d@example.org" % i
		var ph = "(864) 555-%04d" % (1000 + i)
		db.execute("INSERT OR REPLACE INTO people (id, human_id, person_uuid, first_name, last_name, email, phone, sms_consent, status) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 'active');", [i, hid, "uuid_" + str(i), fn, ln, em, ph])

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
	var chips_vbox = comm_view.individual_chips_container
	var search_input = comm_view.recipient_search_input
	var btn_all = comm_view.btn_select_all_shown
	var btn_clear = comm_view.btn_clear_selection
	var initial_total = comm_view.person_list.size()
	
	# 1. Checkbox list renders
	assert(cb_vbox != null, "checkbox_list_vbox must exist")
	assert(cb_vbox.get_child_count() == initial_total, "Should render all matching checkbox rows")
	print("✓ PASS 1: Checkbox list renders all matching constituents (%d total)." % initial_total)
	
	# 2. Check one person -> selected exactly once
	var cb1 = _find_checkbox(cb_vbox, 1)
	assert(cb1 != null, "Checkbox for ID 1 must exist")
	cb1.toggled.emit(true)
	cb1.button_pressed = true
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 1, "Selected count should be 1")
	assert(chips_vbox.get_child_count() == 1, "Should render 1 chip")
	print("✓ PASS 2: Checking one person adds to selected_individual_ids exactly once and renders chip.")
	
	# 3. Check multiple people -> each selected exactly once
	var cb2 = _find_checkbox(cb_vbox, 2)
	assert(cb2 != null, "Checkbox for ID 2 must exist")
	cb2.toggled.emit(true)
	cb2.button_pressed = true
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 2, "Selected count should be 2")
	assert(chips_vbox.get_child_count() == 2, "Should render 2 chips")
	print("✓ PASS 3: Checking multiple people updates selected_individual_ids cleanly with zero duplicates.")
	
	# 4. Uncheck -> recipient removed
	cb1.toggled.emit(false)
	cb1.button_pressed = false
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 1, "Selected count should decrease to 1")
	assert(chips_vbox.get_child_count() == 1, "Should render 1 chip after unchecking")
	print("✓ PASS 4: Unchecking checkbox removes recipient and updates chips.")
	
	# 5. Chip X -> corresponding checkbox becomes unchecked
	var chip_panel = chips_vbox.get_child(0) as PanelContainer
	var chip_hbox = chip_panel.get_child(0) as HBoxContainer
	var btn_rem = chip_hbox.get_child(1) as Button
	btn_rem.pressed.emit()
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 0, "Selected count should be 0 after chip removal")
	var cb2_active = _find_checkbox(cb_vbox, 2)
	assert(cb2_active != null and cb2_active.button_pressed == false, "Active checkbox 2 should become unchecked")
	print("✓ PASS 5: Chip X removal unchecks corresponding visible checkbox.")
	
	# 6. Search filters list & selections persist
	var cb1_cur = _find_checkbox(cb_vbox, 1)
	var cb2_cur = _find_checkbox(cb_vbox, 2)
	cb1_cur.toggled.emit(true); cb1_cur.button_pressed = true
	cb2_cur.toggled.emit(true); cb2_cur.button_pressed = true
	await create_timer(0.1).timeout
	
	search_input.text = "TestUser2 Alpha2" # exact filter for TestUser2
	comm_view._refresh_checkbox_list()
	await create_timer(0.1).timeout
	
	assert(cb_vbox.get_child_count() == 1, "Filtered count should be 1 matching row")
	assert(comm_view.selected_individual_ids.size() == 2, "Selections persist across search filter change")
	print("✓ PASS 6: Search filters list while preserving existing selections intact.")
	
	# 7. Selected person reappears -> checkbox remains checked
	search_input.text = "" # Clear filter
	comm_view._refresh_checkbox_list()
	await create_timer(0.1).timeout
	
	assert(cb_vbox.get_child_count() == initial_total, "List restored to full total")
	var cb1_new = _find_checkbox(cb_vbox, 1)
	assert(cb1_new != null and cb1_new.button_pressed == true, "Reappeared person remains checked")
	print("✓ PASS 7: Reappeared constituents retain checked checkbox state.")
	
	# 8. Select All Shown selects only filtered results
	btn_clear.pressed.emit()
	await create_timer(0.1).timeout
	assert(comm_view.selected_individual_ids.size() == 0, "Cleared")
	
	search_input.text = "OtherMember" # matches items 16 to 30 (15 items)
	comm_view._refresh_checkbox_list()
	await create_timer(0.1).timeout
	
	btn_all.pressed.emit()
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 15, "Select All Shown should select exactly 15 filtered people")
	print("✓ PASS 8: Select All Shown selects ONLY currently filtered matching constituents.")
	
	# 9. Clear Selection clears everything
	btn_clear.pressed.emit()
	await create_timer(0.1).timeout
	
	assert(comm_view.selected_individual_ids.size() == 0, "Selected count should be 0 after Clear Selection")
	assert(chips_vbox.get_child_count() == 0, "Chips count should be 0")
	print("✓ PASS 9: Clear Selection clears all selections and chips.")
	
	# 10. 15+ recipients wrap without horizontal page expansion
	search_input.text = ""
	comm_view._refresh_checkbox_list()
	btn_all.pressed.emit() # Select all matching
	await create_timer(0.2).timeout
	
	assert(comm_view.selected_individual_ids.size() == initial_total, "All constituents selected")
	assert(chips_vbox.get_child_count() == initial_total, "All chips rendered")
	assert(comm_view.chips_scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Horizontal scroll mode disabled")
	print("✓ PASS 10: 15+ recipients wrap cleanly in HFlowContainer without horizontal page expansion.")
	
	# 11. Eligible / Excluded counts updated
	comm_view._update_audience_resolution()
	assert(comm_view.aud_count_label.text.contains("Eligible Recipients"), "Audience resolution count label active")
	print("✓ PASS 11: Eligible / Excluded recipient count summary updated.")
	
	print("==========================================================")
	print("ALL CHECKBOX RECIPIENT SELECTION ASSERTIONS PASSED CLEANLY")
	print("==========================================================")
	
	comm_view.queue_free()
	quit(0)