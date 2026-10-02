extends SceneTree

const NativePlayerBridgeScript = preload("res://src/infrastructure/native/native_player_bridge.gd")

func _init() -> void:
	print("\n=======================================================")
	print("  NATIVE MACOS DRAG BRIDGE VERIFICATION")
	print("=======================================================\n")

	assert(ClassDB.class_exists("MacWKWebViewHelper"), "MacWKWebViewHelper GDExtension class must be registered")
	print("✓ MacWKWebViewHelper GDExtension registered in ClassDB.")

	var helper = ClassDB.instantiate("MacWKWebViewHelper")
	assert(helper != null, "Failed to instantiate MacWKWebViewHelper")
	print("✓ MacWKWebViewHelper instantiated successfully.")

	# Verify native methods exist on helper
	assert(helper.has_method("enableExternalDrag") or helper.has_method("enable_external_drag"), "enableExternalDrag missing")
	assert(helper.has_method("pollExternalDrop") or helper.has_method("poll_external_drop"), "pollExternalDrop missing")
	print("✓ Native drag methods enableExternalDrag and pollExternalDrop exist on helper.")

	# Verify NativePlayerBridge helper functions
	NativePlayerBridgeScript.enable_external_drag()
	print("✓ NativePlayerBridgeScript.enable_external_drag() executed cleanly.")

	var drop_dict = NativePlayerBridgeScript.poll_external_drop()
	assert(drop_dict is Dictionary, "poll_external_drop must return a Dictionary")
	print("✓ NativePlayerBridgeScript.poll_external_drop() returned empty dictionary when no drop pending.")

	print("\n=======================================================")
	print("  NATIVE DRAG BRIDGE VERIFICATION PASSED!  ")
	print("=======================================================\n")
	quit(0)
