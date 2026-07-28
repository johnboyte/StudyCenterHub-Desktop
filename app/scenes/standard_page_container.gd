extends MarginContainer
class_name StandardPageContainer

const PAGE_OUTER_MARGIN = 16.0

func _ready() -> void:
	add_theme_constant_override("margin_top", int(PAGE_OUTER_MARGIN))
	add_theme_constant_override("margin_bottom", int(PAGE_OUTER_MARGIN))
	add_theme_constant_override("margin_left", int(PAGE_OUTER_MARGIN))
	add_theme_constant_override("margin_right", int(PAGE_OUTER_MARGIN))
