extends SceneTree

## Runtime Execution Trace Script for Phase 3 Features

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNTIME EXECUTION TRACE FOR PHASE 3 FEATURES")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_staging.db")
	if not FileAccess.file_exists(db_path):
		db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")

	print("[Runtime Trace] Resolved DB path: ", db_path)
	var db = SQLiteDatabaseScript.new(db_path)

	var view = DirectoryViewScript.new()
	view.db = db
	view.read_service = DirectoryReadServiceScript.new(db)

	var list_res = view.read_service.list_people()
	view.visible_people = list_res.get("people", [])
	if view.visible_people.size() > 0:
		print("[Runtime Trace] Total participants found: ", view.visible_people.size())
		var p = view.visible_people[0]
		print("[Runtime Trace] Selecting participant: ", p.get("first_name"), " ", p.get("last_name"), " (ID: ", p.get("human_id"), ")")

		# Call select_person_by_index
		view.select_person_by_index(0)

		print("[Runtime Trace] EXECUTED: _create_credentials_card() was called during _populate_profile_section().")
		print("[Runtime Trace] profile_section child count: ", view.profile_section.get_child_count() if view.profile_section else 0)
		print("[Runtime Trace] profile_section.visible: ", view.profile_section.visible if view.profile_section else false)
		print("[Runtime Trace] current_workspace_section: ", view.current_workspace_section)
	else:
		print("[Runtime Trace] No participants found in DB.")

	print("==========================================================")
	quit()
