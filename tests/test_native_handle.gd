@tool
extends SceneTree

func _init():
	print("Enums in DisplayServer:")
	var enums = ClassDB.class_get_enum_constants("DisplayServer", "HandleType")
	for e in enums:
		print("HandleType: ", e, " = ", ClassDB.class_get_integer_constant("DisplayServer", e))
	quit()
