extends RefCounted

## Creates a read-only, selectable single-line text control (names, phone, email, UUIDs, IDs, dates)
func create_selectable_line(text_str: String, font_size: int = 14, text_color: Color = Color(0.12, 0.18, 0.26, 1.0)) -> LineEdit:
	var le = LineEdit.new()
	le.text = text_str
	le.editable = false
	le.context_menu_enabled = true
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", font_size)
	le.add_theme_color_override("font_uneditable_color", text_color)
	le.add_theme_color_override("selection_color", Color(0.18, 0.45, 0.85, 0.35))
	
	var sb = StyleBoxEmpty.new()
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("read_only", sb)
	le.add_theme_stylebox_override("focus", sb)
	return le

## Creates a read-only, selectable multi-line text control (descriptions, notes, message bodies, scripts)
func create_selectable_text(text_str: String, font_size: int = 14, text_color: Color = Color(0.12, 0.18, 0.26, 1.0), min_lines: int = 3) -> TextEdit:
	var te = TextEdit.new()
	te.text = text_str
	te.editable = false
	te.context_menu_enabled = true
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.custom_minimum_size = Vector2(0, max(40, min_lines * (font_size + 6) + 12))
	te.add_theme_font_size_override("font_size", font_size)
	te.add_theme_color_override("font_readonly_color", text_color)
	te.add_theme_color_override("selection_color", Color(0.18, 0.45, 0.85, 0.35))
	
	var sb = StyleBoxEmpty.new()
	te.add_theme_stylebox_override("normal", sb)
	te.add_theme_stylebox_override("read_only", sb)
	te.add_theme_stylebox_override("focus", sb)
	return te
