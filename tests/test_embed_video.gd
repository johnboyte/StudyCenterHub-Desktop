extends MainLoop

func _process(_delta: float) -> bool:
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		print("Testing official YouTube embed video M7lc1UVf-VE...")
		var h = helper.call("createPlayer", 0, 0.0, 0.0, 640.0, 360.0)
		helper.call("loadVideo", h, "M7lc1UVf-VE")
	return true
