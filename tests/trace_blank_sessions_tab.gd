@tool
extends SceneTree

func _init():
	print("--- TRACING SCHEDULED SESSIONS TAB BLANK CONTENT ISSUE ---")
	var sch_scene = load("res://app/scenes/schedules_view.tscn")
	if not sch_scene:
		print("ERROR: Failed to load schedules_view.tscn")
		quit()
		return

	var inst = sch_scene.instantiate()
	root.add_child(inst)

	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var prod_db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
	var db = SQLiteScript.new(prod_db_path)
	inst.db = db

	await create_timer(0.1).timeout

	print("1. active_top_tab =", inst.get("active_top_tab"))
	print("2. is_session_assistant_open =", inst.get("is_session_assistant_open"))
	print("3. active_assistant_session_data =", inst.get("active_assistant_session_data"))
	var content_card = inst.get("content_card")
	print("4. content_card child count =", content_card.get_child_count() if content_card else "NULL")

	if content_card and content_card.get_child_count() > 0:
		for i in range(content_card.get_child_count()):
			var child = content_card.get_child(i)
			print("   Child", i, ":", child.get_class(), "name:", child.name, "visible:", child.visible, "size:", child.size, "custom_min:", child.custom_minimum_size)
			if child is Container:
				print("   Child", i, "sub-children count:", child.get_child_count())
				for j in range(child.get_child_count()):
					var sc = child.get_child(j)
					print("      Sub-child", j, ":", sc.get_class(), "name:", sc.name, "visible:", sc.visible, "size:", sc.size)

	# Test rendering sessions tab directly
	print("\n5. Testing explicit _render_sessions_tab call:")
	inst.call("_render_sessions_tab")
	print("   After explicit call, content_card child count =", content_card.get_child_count())

	inst.queue_free()
	print("--- TRACE COMPLETE ---")
	quit()
