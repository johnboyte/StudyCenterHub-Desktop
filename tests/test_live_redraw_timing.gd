extends SceneTree

const SpellingAssistanceHelper = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _initialize():
	print("============================================================")
	print("  TESTING LIVE REDRAW TIMING & GLYPH RECT UPDATES")
	print("============================================================")
	
	var te = TextEdit.new()
	te.size = Vector2(400, 150)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.text = "This contains tha mistake and commuity later."
	
	root.add_child(te)
	await process_frame
	
	SpellingAssistanceHelper.attach_inline_spell_check(te)
	await process_frame
	
	var r1 = te.get_rect_at_line_column(0, te.text.find("tha"))
	print("Initial rect for 'tha': ", r1)
	
	# Simulate typing "HELLO " before "tha"
	te.text = "This contains HELLO tha mistake and commuity later."
	te.text_changed.emit()
	
	# Check rect immediately in same call stack
	var r2_immediate = te.get_rect_at_line_column(0, te.text.find("tha"))
	print("Immediate rect for 'tha' during text_changed: ", r2_immediate)
	
	await process_frame
	var r2_deferred = te.get_rect_at_line_column(0, te.text.find("tha"))
	print("Deferred rect for 'tha' after process_frame: ", r2_deferred)
	
	if r2_immediate != r2_deferred:
		print("⚠️ OBSERVATION: Immediate get_rect_at_line_column during text_changed differs from post-frame rect!")
		print("   Immediate: ", r2_immediate)
		print("   Deferred:  ", r2_deferred)
	else:
		print("✓ Rect updated immediately in headless engine mode.")

	quit()
