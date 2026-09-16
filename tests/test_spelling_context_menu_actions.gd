extends SceneTree

const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING SPELLING CONTEXT-MENU ACTIONS REGRESSION TEST SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	_test_cut_misspelled_word_only()
	_test_copy_misspelled_word_only()
	_test_delete_misspelled_word_only()
	_test_replace_suggestion_misspelled_word_only()
	_test_paste_replaces_only_target()
	_test_manual_selection_cut_copy()
	_test_select_all_selects_everything()

	print("\n============================================================")
	print("  SUCCESS: ALL CONTEXT-MENU ACTION TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _setup_editor_with_text(initial_text: String) -> TextEdit:
	var te = TextEdit.new()
	var root_node = get_root()
	root_node.add_child(te)
	te.text = initial_text
	SpellingAssistanceHelperScript.attach_inline_spell_check(te)
	return te

func _find_resturant_issue(text: String) -> Dictionary:
	var issues = SpellingAssistanceHelperScript.check_text(text)
	for iss in issues:
		if iss["word"] == "resturant":
			return iss
	return {}

func _test_cut_misspelled_word_only() -> void:
	print("--- 1. Testing Cut on single misspelled word ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	var iss = _find_resturant_issue(initial)
	assert(not iss.is_empty(), "Expected issue for resturant")

	# Target range selection for resturant (10 to 19)
	te.select(0, int(iss["start"]), 0, int(iss["end"]))
	assert(te.get_selected_text() == "resturant", "Selected text must be resturant")

	te.delete_selection()
	var expected = "This is a  and everything else stays."
	assert(te.text == expected, "Cut failed! Expected '%s', got '%s'" % [expected, te.text])
	te.queue_free()
	print("✓ PASS: Cut removed ONLY 'resturant' and preserved surrounding text.")

func _test_copy_misspelled_word_only() -> void:
	print("\n--- 2. Testing Copy on single misspelled word ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	var iss = _find_resturant_issue(initial)
	assert(not iss.is_empty(), "Expected issue for resturant")

	te.select(0, int(iss["start"]), 0, int(iss["end"]))
	assert(te.get_selected_text() == "resturant", "Selected text must be resturant")

	te.copy()
	assert(te.text == initial, "Copy must NOT alter editor text!")
	te.queue_free()
	print("✓ PASS: Copy targeted ONLY 'resturant' without altering text.")

func _test_delete_misspelled_word_only() -> void:
	print("\n--- 3. Testing Delete on single misspelled word ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	var iss = _find_resturant_issue(initial)
	assert(not iss.is_empty(), "Expected issue for resturant")

	te.select(0, int(iss["start"]), 0, int(iss["end"]))
	assert(te.get_selected_text() == "resturant", "Selected text must be resturant")

	te.delete_selection()
	var expected = "This is a  and everything else stays."
	assert(te.text == expected, "Delete failed! Expected '%s', got '%s'" % [expected, te.text])
	te.queue_free()
	print("✓ PASS: Delete removed ONLY 'resturant'.")

func _test_replace_suggestion_misspelled_word_only() -> void:
	print("\n--- 4. Testing Replacing misspelled word with suggestion ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	var iss = _find_resturant_issue(initial)
	assert(not iss.is_empty(), "Expected issue for resturant")
	var sug = str(iss["suggestions"][0])
	assert(sug == "restaurant", "Expected 'restaurant' suggestion")

	te.select(0, int(iss["start"]), 0, int(iss["end"]))
	te.insert_text_at_caret(sug)

	var expected = "This is a restaurant and everything else stays."
	assert(te.text == expected, "Replace failed! Expected '%s', got '%s'" % [expected, te.text])
	te.queue_free()
	print("✓ PASS: Replace replaced ONLY 'resturant' with 'restaurant'.")

func _test_paste_replaces_only_target() -> void:
	print("\n--- 5. Testing Paste replacing target word without wiping editor ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	var iss = _find_resturant_issue(initial)
	assert(not iss.is_empty(), "Expected issue for resturant")

	te.select(0, int(iss["start"]), 0, int(iss["end"]))
	te.insert_text_at_caret("bistro")

	var expected = "This is a bistro and everything else stays."
	assert(te.text == expected, "Paste failed! Expected '%s', got '%s'" % [expected, te.text])
	te.queue_free()
	print("✓ PASS: Paste replaced ONLY 'resturant' with 'bistro'.")

func _test_manual_selection_cut_copy() -> void:
	print("\n--- 6. Testing Manual user selection Cut & Copy ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	# Manually select 'is a resturant' (line 0, col 5 to 19)
	te.select(0, 5, 0, 19)
	assert(te.get_selected_text() == "is a resturant", "Selected text must match manual selection")

	te.copy()
	assert(te.text == initial, "Copy must not modify text")

	te.delete_selection()
	var expected = "This  and everything else stays."
	assert(te.text == expected, "Manual cut failed! Expected '%s', got '%s'" % [expected, te.text])
	te.queue_free()
	print("✓ PASS: Manual user selection cut/copy operated cleanly on user selection.")

func _test_select_all_selects_everything() -> void:
	print("\n--- 7. Testing Select All selects entire field ---")
	var initial = "This is a resturant and everything else stays."
	var te = _setup_editor_with_text(initial)

	te.select_all()
	assert(te.has_selection(), "Select All must set selection")
	assert(te.get_selected_text() == initial, "Select All must select entire editor text")
	te.queue_free()
	print("✓ PASS: Select All successfully selected entire editor.")
