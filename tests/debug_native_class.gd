extends MainLoop

func _process(_delta: float) -> bool:
	print("--- DEBUG NATIVE CLASS ---")
	print("ClassDB.class_exists('MacWKWebViewHelper')=", ClassDB.class_exists("MacWKWebViewHelper"))
	if ClassDB.class_exists("MacWKWebViewHelper"):
		var helper = ClassDB.instantiate("MacWKWebViewHelper")
		print("Instantiated helper=", helper)
		if helper:
			print("has createPlayer=", helper.has_method("createPlayer"))
			print("has create_player=", helper.has_method("create_player"))
			var methods = ClassDB.class_get_method_list("MacWKWebViewHelper")
			print("Method count=", methods.size())
			for m in methods:
				print("  method=", m.name)
	return true
