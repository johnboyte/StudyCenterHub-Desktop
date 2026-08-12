extends SceneTree

func _init() -> void:
	print("Verifying new print artwork asset loading...")
	var path = "res://assets/print/real_life_remote_check_in_poster.png"
	var global_path = ProjectSettings.globalize_path(path)
	
	if FileAccess.file_exists(global_path):
		print("File exists at global path: ", global_path)
		var img = Image.load_from_file(global_path)
		if img and not img.is_empty():
			print("SUCCESS: Loaded image successfully!")
			print("Dimensions: ", img.get_width(), "x", img.get_height(), " pixels")
			print("Format: ", img.get_format())
		else:
			print("ERROR: Image loaded but is empty.")
	else:
		print("ERROR: File does not exist at path: ", global_path)
	quit(0)
