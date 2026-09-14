extends SceneTree

## Automated Verification Test for Multi-Individual & Real Life Communications Redesign

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("--- Starting Communications Multi-Individual & Real Life Test ---")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	var com_scene = load("res://app/scenes/communications_view.tscn").instantiate()
	com_scene.db = db
	root.add_child(com_scene)

	# Ensure _ready() completed
	com_scene._ready()

	# 1. Verify Audience Types list
	var aud_dropdown = com_scene.audience_type_dropdown
	assert(aud_dropdown != null, "Audience type dropdown should exist")
	var aud_items = []
	for i in range(aud_dropdown.item_count):
		aud_items.append(aud_dropdown.get_item_text(i))

	print("Audience Types found: ", aud_items)
	assert(aud_items.has("Individual"), "Should contain Individual")
	assert(aud_items.has("Real Life"), "Should contain Real Life")
	assert(aud_items.has("Pathway"), "Should contain Pathway")
	assert(aud_items.has("Session"), "Should contain Session")
	assert(aud_items.has("Volunteers"), "Should contain Volunteers")
	assert(aud_items.has("Checked In Today"), "Should contain Checked In Today")
	assert(aud_items.has("All Active People"), "Should contain All Active People")

	# 2. Verify Pathway dropdown exclusions
	var pw_dropdown = com_scene.pathway_dropdown
	com_scene._on_audience_type_selected(2) # Pathway
	var pw_items = []
	for i in range(pw_dropdown.item_count):
		pw_items.append(pw_dropdown.get_item_text(i))
	print("Pathway options found: ", pw_items)
	assert(pw_items.has("Fellows"), "Pathways should contain Fellows")
	assert(pw_items.has("LEAD"), "Pathways should contain LEAD")
	assert(not pw_items.has("Academic Mastery"), "Pathways MUST NOT contain Academic Mastery")
	assert(not pw_items.has("Discipleship Track"), "Pathways MUST NOT contain Discipleship Track")

	# 3. Test Multi-Individual Selection
	com_scene._on_audience_type_selected(0) # Individual
	assert(com_scene.selected_individual_ids.size() > 0, "Default selection should have 1 person")
	assert(com_scene.channel_dropdown.item_count == 3, "Single individual should have 3 channels (SMS, Email, Phone Call)")
	var single_channels = []
	for i in range(com_scene.channel_dropdown.item_count):
		single_channels.append(com_scene.channel_dropdown.get_item_text(i))
	assert(single_channels.has("Phone Call"), "Single individual MUST allow Phone Call")

	# Add a second person
	if com_scene.person_list.size() >= 2:
		var second_p = com_scene.person_list[1]
		var p2_id = int(second_p.get("id"))
		com_scene._on_individual_selected(2) # Select second person from dropdown
		assert(com_scene.selected_individual_ids.has(p2_id), "Second person should be added to selected_individual_ids")
		assert(com_scene.selected_individual_ids.size() == 2, "Should have 2 selected individuals")

		# Test duplicate prevention
		com_scene._on_individual_selected(2) # Select second person again
		assert(com_scene.selected_individual_ids.size() == 2, "Duplicate selection MUST NOT increase size")

		# Verify multi-individual channel options
		var multi_channels = []
		for i in range(com_scene.channel_dropdown.item_count):
			multi_channels.append(com_scene.channel_dropdown.get_item_text(i))
		print("Multi-individual channels: ", multi_channels)
		assert(not multi_channels.has("Phone Call"), "Multi-individual MUST NOT allow Phone Call")
		assert(multi_channels.has("Both (SMS + Email)"), "Multi-individual should allow Both")

	print("--- Communications Multi-Individual & Real Life Test PASSED CLEANLY ---")
	quit()
