extends SceneTree

func _init() -> void:
	print("==========================================================")
	print("PACKING CANDIDATE PCK USING NATIVE GODOT PCKPACKER")
	print("==========================================================")
	
	var packer = PCKPacker.new()
	var pck_path = "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Candidate.pck"
	var err = packer.pck_start(pck_path)
	if err != OK:
		print("FAIL: pck_start failed with error code: ", err)
		quit(1)
		return
		
	var files_added = _add_dir(packer, "res://")
	packer.flush()
	
	print("✓ PASS: Successfully packed ", files_added, " project files into Candidate PCK: ", pck_path)
	print("==========================================================")
	quit(0)

func _add_dir(packer: PCKPacker, dir_path: String) -> int:
	var count = 0
	var dir = DirAccess.open(dir_path)
	if not dir:
		return 0
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var full_path = dir_path.path_join(file_name)
			if dir.current_is_dir():
				if file_name != ".godot" and file_name != ".git" and file_name != ".agents" and file_name != "scratch" and file_name != ".bin":
					count += _add_dir(packer, full_path)
			else:
				if not file_name.ends_with(".import") and not file_name.ends_with(".tmp") and not file_name.ends_with(".db"):
					var pck_err = packer.add_file(full_path, full_path)
					if pck_err == OK:
						count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return count
