@tool
extends SceneTree

func _init():
	print("Testing native ObjC helper call in Godot...")
	if OS.get_name() == "macOS":
		var cls_exists = ClassDB.class_exists("MacWKWebViewHelper")
		print("ClassDB.class_exists: ", cls_exists)
	quit()
