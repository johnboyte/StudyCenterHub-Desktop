@tool
extends SceneTree

func _init():
	print("--- TRACING SESSION ASSISTANT RE-RENDER LOGIC ---")
	var sch_scene = load("res://app/scenes/schedules_view.tscn")
	if not sch_scene:
		print("ERROR: Failed to load schedules_view.tscn")
		quit()
		return
	
	var inst = sch_scene.instantiate()
	root.add_child(inst)
	
	# Create test DB
	var SQLiteScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var MigrationsScript = load("res://src/infrastructure/database/migrations_runner.gd")
	var test_db_path = "user://test_assistant_trace.db"
	var db = SQLiteScript.new(test_db_path)
	var mig = MigrationsScript.new(db)
	mig.run_migrations()
	
	inst.db = db
	
	# Open session assistant
	var dummy_sess = {"id": 1, "title": "Test Study", "date_text": "2026-08-16", "start_time": "09:00 AM", "end_time": "10:30 AM", "session_type_name": "Special Event", "session_uuid": "sess_123"}
	inst.call("open_session_assistant_placeholder", dummy_sess)
	print("Session Assistant opened. is_session_assistant_open =", inst.get("is_session_assistant_open"))
	print("Content card children count:", inst.get("content_card").get_child_count())
	
	# Simulate 3 sync timer ticks
	for i in range(3):
		inst.call("on_inbound_events_processed", 1)
		# Process deferred calls
		await create_timer(0.1).timeout
		print("Tick", i+1, "- is_session_assistant_open:", inst.get("is_session_assistant_open"), "children:", inst.get("content_card").get_child_count())
	
	inst.queue_free()
	print("--- TRACE COMPLETED ---")
	quit()
