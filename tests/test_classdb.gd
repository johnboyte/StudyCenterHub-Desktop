@tool
extends SceneTree

func _init():
	print("Checking if MacWKWebViewHelper is in ClassDB...")
	print("ClassDB.class_exists('MacWKWebViewHelper'): ", ClassDB.class_exists("MacWKWebViewHelper"))
	print("ClassDB.class_exists('MacWKWebViewNative'): ", ClassDB.class_exists("MacWKWebViewNative"))
	quit()
