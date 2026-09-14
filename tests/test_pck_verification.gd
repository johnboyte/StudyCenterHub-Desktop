extends SceneTree

func _init() -> void:
	print("--- VERIFYING INSTALLED PCK RESOURCE PACK ---")
	var AdminScript = load("res://app/scenes/administration_view.gd")
	if not AdminScript:
		print("FAIL: Could not load administration_view.gd from PCK")
		quit(1)
		return
		
	var inst = AdminScript.new()
	print("Inst created: ", inst)
	print("selected_ivr_day val: ", inst.get("selected_ivr_day"))
	print("_create_selectable_label has_method: ", inst.has_method("_create_selectable_label"))
	quit(0)
