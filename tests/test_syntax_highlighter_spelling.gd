extends SceneTree

class SpellingHighlighter extends SyntaxHighlighter:
	var SpellingAssistanceHelper = preload("res://src/ui/components/spelling_assistance_helper.gd")

	func _get_line_syntax_highlighting(line_idx: int) -> Dictionary:
		var text_edit = get_text_edit()
		if not text_edit:
			return {}

		var line_str = text_edit.get_line(line_idx)
		if line_str.strip_edges() == "":
			return {}

		var issues = SpellingAssistanceHelper.check_text(line_str)
		if issues.size() == 0:
			return {}

		var format_map = {}
		var default_color = text_edit.get_theme_color("font_color")
		if default_color == Color(0,0,0,0):
			default_color = Color(0.12, 0.16, 0.22, 1.0)

		# Set initial style at column 0 if needed
		format_map[0] = { "color": default_color }

		for iss in issues:
			var start_col = int(iss["start"])
			var end_col = int(iss["end"])

			# Highlight misspelled word in crisp high-contrast crimson red text with underline or background tint
			format_map[start_col] = {
				"color": Color(0.85, 0.15, 0.15, 1.0),
				"background_color": Color(1.0, 0.90, 0.90, 1.0)
			}
			format_map[end_col] = {
				"color": default_color
			}

		return format_map

func _initialize():
	print("--- TESTING SPELLING SYNTAX HIGHLIGHTER ON REAL TEXT ---")
	var te = TextEdit.new()
	te.size = Vector2(400, 150)
	te.text = "This sentence contains tha intentional mistake and another misspelled word: commuity."
	
	var hl = SpellingHighlighter.new()
	te.syntax_highlighter = hl
	
	root.add_child(te)
	await process_frame
	
	var res = hl._get_line_syntax_highlighting(0)
	print("Line 0 syntax highlight result: ", res)
	
	# Simulate editing text before 'tha'
	te.text = "HELLO WORLD " + te.text
	await process_frame
	
	var res2 = hl._get_line_syntax_highlighting(0)
	print("Line 0 syntax highlight after typing: ", res2)
	
	quit()
