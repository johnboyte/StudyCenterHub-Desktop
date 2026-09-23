extends SceneTree

func _initialize():
	var te = TextEdit.new()
	te.size = Vector2(300, 100)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.text = "Line 1: This is another message to test the spelling checker. We wanted to gather several others for an evening together. This sentence contains tha intentional mistake and another misspelled word: commuity.\nLine 2: another test to see commuity here."
	
	root.add_child(te)
	await process_frame
	
	print("--- SCROLL V = 0 ---")
	print("Line 0 'another': ", te.get_rect_at_line_column(0, 8))
	print("Line 0 'commuity': ", te.get_rect_at_line_column(0, 190))
	print("Line 1 'commuity': ", te.get_rect_at_line_column(1, 23))
	
	te.scroll_vertical = 50.0
	await process_frame
	print("--- SCROLL V = 50 ---")
	print("Line 0 'another': ", te.get_rect_at_line_column(0, 8))
	print("Line 0 'commuity': ", te.get_rect_at_line_column(0, 190))
	print("Line 1 'commuity': ", te.get_rect_at_line_column(1, 23))

	quit()
