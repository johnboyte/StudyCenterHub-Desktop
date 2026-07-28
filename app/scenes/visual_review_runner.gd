extends Control

## Multi-Story Visual Review Runner (DIR-SPR1-007, ADM-SPR1-001, ATT-SPR1-001)
## Captures high-resolution, full-screen native desktop views of all newly integrated modules.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AppShellScript = preload("res://app/scenes/app_shell.gd")

const SCREENSHOT_DIR = "/Users/johnboyte/Desktop/StudyCenterHub-Screenshots/"

@onready var container: Control = $Container

func _ready() -> void:
	print("==========================================================")
	print("STARTING MULTI-STORY GUI VISUAL CAPTURE PROCESS")
	print("==========================================================")

	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)

	var db_path = ProjectSettings.globalize_path("user://visual_review_gui.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	MigrationsRunnerScript.new(db).run_migrations()

	# Seed sample constituents, pathways, and sessions
	db.execute("INSERT OR IGNORE INTO people (person_uuid, human_id, first_name, last_name, status, grade) VALUES ('usr_aaron', 'P-20260720-0001', 'Aaron', 'Zimmerman', 'active', 'Senior');")
	db.execute("INSERT OR IGNORE INTO people (person_uuid, human_id, first_name, last_name, status, grade) VALUES ('usr_beth', 'P-20260720-0002', 'Beth', 'Yates', 'active', 'Junior');")
	db.execute("INSERT OR IGNORE INTO people (person_uuid, human_id, first_name, last_name, status, grade) VALUES ('usr_david', 'P-20260720-0003', 'David', 'Vance', 'active', 'Freshman');")

	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_david';")
	if p_res["success"] and p_res["data"].size() > 0:
		var pid = p_res["data"][0]["id"]
		db.execute("INSERT OR IGNORE INTO person_pathways (person_id, pathway_id, current_stage, progress_percent) VALUES (?, 1, 'Stage 2 - Discipleship', 50);", [pid])
		var pp_res = db.execute("SELECT id FROM person_pathways WHERE person_id = ?;", [pid])
		if pp_res["success"] and pp_res["data"].size() > 0:
			var ppid = pp_res["data"][0]["id"]
			db.execute("INSERT OR IGNORE INTO person_pathway_milestones (person_pathway_id, milestone_name, milestone_order, is_completed) VALUES (?, 'Orientation Completed', 1, 1);", [ppid])
			db.execute("INSERT OR IGNORE INTO person_pathway_milestones (person_pathway_id, milestone_name, milestone_order, is_completed) VALUES (?, 'Leadership Basics', 2, 0);", [ppid])
		db.execute("INSERT OR IGNORE INTO person_sessions (person_id, session_id, attendance_status) VALUES (?, 1, 'registered');", [pid])

	var scene_res = load("res://app/scenes/app_shell.tscn")
	var shell = scene_res.instantiate() as AppShellScript
	shell.db = db
	container.add_child(shell)

	_run_captures(shell)

func _run_captures(shell: AppShellScript) -> void:
	DisplayServer.window_set_size(Vector2i(1600, 950))
	await get_tree().create_timer(0.6).timeout

	# 1. Home Dashboard View
	shell.switch_view("home")
	await _snap("fullscreen_01_home_dashboard.png")

	# 2. People Directory View
	shell.switch_view("people")
	await get_tree().create_timer(0.4).timeout
	var dir_view = shell.current_view_node
	if dir_view and dir_view.has_method("select_person_by_index"):
		dir_view.select_person_by_index(0)
		dir_view.select_workspace_tab("participation")
	await _snap("fullscreen_04_pathways_participation.png")

	# 3. Administration View (White-Label & Vocabulary)
	shell.switch_view("administration")
	await get_tree().create_timer(0.4).timeout
	var admin_view = shell.current_view_node
	if admin_view and admin_view.has_method("switch_tab"):
		admin_view.switch_tab("branding")
	await _snap("fullscreen_05_administration_white_label.png")

	# 4. Attendance & Check-In View
	shell.switch_view("attendance")
	await get_tree().create_timer(0.4).timeout
	await _snap("fullscreen_06_attendance_checkin.png")

	print("==========================================================")
	print("COMPLETED MULTI-STORY CAPTURE PROCESS")
	print("==========================================================")
	get_tree().quit(0)

func _snap(filename: String) -> void:
	await get_tree().create_timer(0.4).timeout
	var target_file = SCREENSHOT_DIR + filename
	var output = []
	OS.execute("screencapture", ["-x", target_file], output, true)
	await get_tree().create_timer(0.2).timeout
	print("Captured screenshot: ", target_file)
