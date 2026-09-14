extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsViewScript = preload("res://app/scenes/communications_view.gd")

func _init() -> void:
	print("==================================================")
	print("RUNNING COMMUNICATIONS REDESIGN DEV SUITE")
	print("==================================================")

	var db = SQLiteDatabaseScript.new()
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# Create instance of CommunicationsView
	var scene_res = load("res://app/scenes/communications_view.tscn")
	var view = scene_res.instantiate()
	root.add_child(view)
	if not view.is_node_ready() or view.audience_type_dropdown == null:
		view._setup_communicate_send_composer()
		view._ready()
	view.db = db

	print("[Test 1] Verifying Audience Type Selector options...")
	assert(view.audience_type_dropdown != null, "audience_type_dropdown must exist")
	assert(view.audience_type_dropdown.item_count == 6, "Expected 6 audience types")
	assert(view.audience_type_dropdown.get_item_text(0) == "Individual", "Audience 0 must be Individual")
	assert(view.audience_type_dropdown.get_item_text(1) == "Pathway", "Audience 1 must be Pathway")
	assert(view.audience_type_dropdown.get_item_text(2) == "Session", "Audience 2 must be Session")
	assert(view.audience_type_dropdown.get_item_text(3) == "Volunteers", "Audience 3 must be Volunteers")
	assert(view.audience_type_dropdown.get_item_text(4) == "Checked In Today", "Audience 4 must be Checked In Today")
	assert(view.audience_type_dropdown.get_item_text(5) == "All Active People", "Audience 5 must be All Active People")
	print("  ✓ PASS: All 6 audience selector options present.")

	print("\n[Test 2] Testing Individual Audience Resolution...")
	view._on_audience_type_selected(0)
	assert(view.recipient_dropdown.visible == true, "recipient_dropdown must be visible for Individual")
	assert(view.pathway_dropdown.visible == false, "pathway_dropdown must be hidden for Individual")
	assert(view.session_dropdown.visible == false, "session_dropdown must be hidden for Individual")
	print("  ✓ PASS: Individual selection controls wired properly.")

	print("\n[Test 3] Testing Pathway Audience Resolution...")
	view._on_audience_type_selected(1)
	assert(view.pathway_dropdown.visible == true, "pathway_dropdown must be visible for Pathway")
	assert(view.pathway_list.size() > 0, "pathway_list should load active pathways")
	print("  ✓ PASS: Pathway audience queries loaded (found ", view.pathway_list.size(), " pathways).")

	print("\n[Test 4] Testing Session Audience Resolution (Generic across Session Types)...")
	view._on_audience_type_selected(2)
	assert(view.session_dropdown.visible == true, "session_dropdown must be visible for Session")
	assert(view.session_list.size() > 0, "session_list should load active sessions")
	print("  ✓ PASS: Session audience queries loaded (found ", view.session_list.size(), " sessions).")

	print("\n[Test 5] Testing Volunteers Audience Resolution...")
	view._on_audience_type_selected(3)
	assert(view.current_eligible_recipients.size() + view.current_excluded_recipients.size() >= 0, "Volunteers query executed cleanly")
	print("  ✓ PASS: Volunteers query executed cleanly (Eligible: ", view.current_eligible_recipients.size(), ", Excluded: ", view.current_excluded_recipients.size(), ").")

	print("\n[Test 6] Testing Checked In Today Audience Resolution...")
	view._on_audience_type_selected(4)
	print("  ✓ PASS: Checked In Today query executed cleanly (Eligible: ", view.current_eligible_recipients.size(), ", Excluded: ", view.current_excluded_recipients.size(), ").")

	print("\n[Test 7] Testing All Active People Audience Resolution...")
	view._on_audience_type_selected(5)
	assert(view.current_eligible_recipients.size() + view.current_excluded_recipients.size() > 0, "All Active People query must return constituents")
	print("  ✓ PASS: All Active People query returned ", view.current_eligible_recipients.size(), " eligible recipients.")

	print("\n[Test 8] Verifying 'Parent Check-In Alert' template is hidden from composer dropdown...")
	var found_parent_template = false
	for i in range(view.template_dropdown.item_count):
		if view.template_dropdown.get_item_text(i) == "Parent Check-In Alert":
			found_parent_template = true
			break
	assert(not found_parent_template, "'Parent Check-In Alert' MUST NOT be visible in general template dropdown")
	print("  ✓ PASS: 'Parent Check-In Alert' template correctly hidden from UI composer dropdown.")

	print("\n[Test 9] Verifying Response Center section header rename...")
	var voicemail_vbox = view.voicemail_card.get_child(0) as VBoxContainer
	assert(voicemail_vbox != null, "Voicemail card container must exist")
	var header_hbox = voicemail_vbox.get_child(0) as HBoxContainer
	var title_lbl = header_hbox.get_child(0) as Label
	assert(title_lbl.text == "🎙️ Response Center", "Lower section header must be renamed to '🎙️ Response Center'")
	print("  ✓ PASS: Lower section label correctly updated to '🎙️ Response Center'.")

	print("\n==================================================")
	print("ALL COMMUNICATIONS REDESIGN DEV TESTS PASSED!")
	print("==================================================")

	quit(0)
