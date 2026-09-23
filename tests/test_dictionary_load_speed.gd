extends SceneTree

func _initialize():
	var start_t = Time.get_ticks_msec()
	var file_path = "res://src/ui/components/english_dictionary.txt"
	var f = FileAccess.open(file_path, FileAccess.READ)
	var words_set = {}
	var count = 0
	if f:
		while not f.eof_reached():
			var line = f.get_line().strip_edges()
			if line != "":
				words_set[line] = true
				count += 1
		f.close()
	var elapsed = Time.get_ticks_msec() - start_t
	print("Loaded ", count, " words into Godot Dictionary in ", elapsed, " ms.")
	
	# Test required words
	var check_list = ["is", "it", "to", "the", "and", "another", "others", "wanted", "gather", "glad", "bring", "food", "evening", "people", "chance", "familiar", "little", "community", "commuity", "tha"]
	for w in check_list:
		print("Word '", w, "' valid in full dict? ", words_set.has(w.to_lower()))
		
	quit()
