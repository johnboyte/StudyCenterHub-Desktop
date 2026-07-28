extends Control

## Phase 3 Visual Capture & Automated Integration Verification Runner
## Runs native GUI captures for Digital Pass, Membership Card, Print Queue, and Public Sign.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const AppShellScript = preload("res://app/scenes/app_shell.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")
const PublicQrSignDialogScript = preload("res://app/scenes/public_qr_sign_dialog.gd")

const ARTIFACT_DIR = "/Users/johnboyte/.gemini/antigravity-ide/brain/fc5645ce-6da2-4dc9-af53-55957241878d/"

@onready var container: Control = $Container

func _ready() -> void:
	print("==========================================================")
	print("STARTING PHASE 3 VISUAL CAPTURE & INTEGRATION VERIFICATION")
	print("==========================================================")

	DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)

	# Use Staging SQLite Database for visual capture
	var db = SQLiteDatabaseScript.new()
	MigrationsRunnerScript.new(db).run_migrations()

	var scene_res = load("res://app/scenes/app_shell.tscn")
	var shell = scene_res.instantiate() as AppShellScript
	shell.db = db
	add_child(shell)

	_run_captures(shell)

func _run_captures(shell: AppShellScript) -> void:
	DisplayServer.window_set_size(Vector2i(1600, 950))
	await get_tree().create_timer(0.6).timeout

	# 1. Directory View with Digital Member Pass
	shell.switch_view("people")
	await get_tree().create_timer(0.4).timeout
	var dir_view = shell.current_view_node
	if dir_view and dir_view.has_method("select_person_by_index"):
		dir_view.select_person_by_index(0)
		dir_view.select_workspace_tab("profile")
	await _snap("phase3_01_digital_member_pass.png")

	# 2. Open Card Preview Modal from Directory
	if dir_view and dir_view.visible_people.size() > 0:
		var p = dir_view.visible_people[0]
		dir_view._open_card_preview_for_person(p)
		await _snap("phase3_02_membership_card_preview.png")

	# 3. Open Card Print Queue Dialog
	var queue_dlg = CardPrintQueueDialogScript.new(shell)
	queue_dlg.show_dialog()
	await _snap("phase3_03_card_print_queue.png")
	queue_dlg.queue_free()

	# 4. Open Public QR Sign Dialog
	var sign_dlg = PublicQrSignDialogScript.new(shell)
	sign_dlg.show_dialog()
	await _snap("phase3_04_public_checkin_qr_sign.png")
	sign_dlg.queue_free()

	# 5. Attendance View (with Public QR Sign button)
	shell.switch_view("attendance")
	await get_tree().create_timer(0.4).timeout
	await _snap("phase3_05_attendance_public_qr.png")

	# 6. Administration View (with Public QR Sign and Print Queue buttons)
	shell.switch_view("administration")
	await get_tree().create_timer(0.4).timeout
	await _snap("phase3_06_administration_tools.png")

	print("==========================================================")
	print("PHASE 3 VISUAL CAPTURE PROCESS COMPLETED SUCCESSFULLY")
	print("==========================================================")
	get_tree().quit(0)

func _snap(filename: String) -> void:
	await get_tree().create_timer(0.5).timeout
	var target_file = ARTIFACT_DIR + filename
	var output = []
	OS.execute("screencapture", ["-x", target_file], output, true)
	await get_tree().create_timer(0.3).timeout
	print("Captured screenshot: ", target_file)
