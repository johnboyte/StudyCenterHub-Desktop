@tool
extends SceneTree

func _init():
	print("Testing MacWKWebViewHelper Objective-C lookup...")
	if OS.get_name() == "macOS":
		# Test ClassDB or Native class lookup
		print("Running on macOS!")
	quit()
