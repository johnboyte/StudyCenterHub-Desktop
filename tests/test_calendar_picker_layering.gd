extends SceneTree

# Automated Test Suite for Calendar Picker Dialog & Window Layering
# Verifies that calendar pickers open on top of modal ConfirmationDialogs and subwindows.

func _init() -> void:
	print("\n==========================================================")
	print("STARTING CALENDAR PICKER LAYERING & MODAL TEST SUITE")
	print("==========================================================")

	call_deferred("_run_test")

func _run_test() -> void:
	var scene = load("res://app/scenes/directory_view.tscn")
	if not scene:
		print("❌ FAIL: Could not load directory_view.tscn")
		quit(1)
		return

	var dir_view = scene.instantiate()
	root.add_child(dir_view)

	# Create a modal ConfirmationDialog representing "Add Pathway Requirement"
	var dlg = ConfirmationDialog.new()
	dlg.title = "Add Pathway Requirement"

	var txt_d = LineEdit.new()
	txt_d.name = "TxtDueDate"
	txt_d.text = ""
	dlg.add_child(txt_d)

	root.add_child(dlg)

	# Assert parent window resolution
	var win = txt_d.get_window()
	if win == dlg:
		print("  ✓ PASS: LineEdit in ConfirmationDialog correctly resolves parent Window to ConfirmationDialog.")
	else:
		print("❌ FAIL: LineEdit parent Window did not resolve to ConfirmationDialog.")
		quit(1)

	# Trigger calendar picker for txt_d
	dir_view._open_calendar_picker(txt_d)

	# Verify CanvasLayer attached directly to dlg (ConfirmationDialog) with layer = 128
	var found_picker = false
	for child in dlg.get_children():
		if child is CanvasLayer:
			found_picker = true
			if child.layer == 128:
				print("  ✓ PASS: Calendar picker CanvasLayer attached directly to ConfirmationDialog with layer = 128 (renders ON TOP).")
			else:
				print("❌ FAIL: CanvasLayer layer was not 128.")
				quit(1)

	if not found_picker:
		print("❌ FAIL: Calendar picker CanvasLayer was not attached to ConfirmationDialog window.")
		quit(1)

	dlg.queue_free()
	dir_view.queue_free()

	print("\n==========================================================")
	print("ALL CALENDAR PICKER LAYERING TESTS PASSED! (1/1)")
	print("==========================================================\n")
	quit(0)
