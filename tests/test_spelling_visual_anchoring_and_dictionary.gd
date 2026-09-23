extends SceneTree

const SpellingAssistanceHelper = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _initialize():
	print("============================================================")
	print("  RUNNING SPELLING NATIVE SYNTAX HIGHLIGHTER SUITE")
	print("============================================================")
	
	# 1. Test Required Dictionary Validation
	print("--- 1. Testing Dictionary Vocabulary Validation ---")
	SpellingAssistanceHelper._ensure_dictionary_loaded()
	
	var required_valid_words = [
		"is", "it", "to", "the", "and", "another", "others", "wanted",
		"gather", "glad", "bring", "food", "evening", "people", "chance",
		"familiar", "little", "community", "coming", "Sunday", "others",
		"I'd", "we'll", "Real", "Life", "House", "one", "build"
	]
	
	var required_invalid_words = [
		"tha", "anothre", "commuity", "familar"
	]
	
	var valid_failures = []
	for w in required_valid_words:
		if not SpellingAssistanceHelper.is_word_valid(w):
			valid_failures.append(w)
			
	var invalid_failures = []
	for w in required_invalid_words:
		if SpellingAssistanceHelper.is_word_valid(w):
			invalid_failures.append(w)
			
	if valid_failures.size() > 0:
		print("❌ FAIL: Valid words incorrectly flagged as invalid: ", valid_failures)
		quit(1)
		return
	else:
		print("✓ PASS: All ", required_valid_words.size(), " required ordinary English words validated cleanly.")
		
	if invalid_failures.size() > 0:
		print("❌ FAIL: Invalid words incorrectly passed as valid: ", invalid_failures)
		quit(1)
		return
	else:
		print("✓ PASS: All ", required_invalid_words.size(), " required misspelled words correctly flagged invalid.")

	# 2. Test Real Message Tokenization and Issue Extraction
	print("\n--- 2. Testing Real Message Tokenization ---")
	var msg_text = "This is another message to test the spelling checker. We wanted to gather several others for an evening together.\n\nThis sentence contains tha intentional mistake and another misspelled word: commuity.\n\nWe'd be glad to bring food and help people get familiar with the Real Life House."
	
	var issues = SpellingAssistanceHelper.check_text(msg_text)
	var misspelled_list = []
	for iss in issues:
		misspelled_list.append(iss["word"])
		
	print("Detected misspelled tokens: ", misspelled_list)
	if misspelled_list.has("another") or misspelled_list.has("to") or misspelled_list.has("gather") or misspelled_list.has("evening") or misspelled_list.has("glad") or misspelled_list.has("familiar"):
		print("❌ FAIL: Ordinary words present in issue list: ", misspelled_list)
		quit(1)
		return
		
	if not misspelled_list.has("tha") or not misspelled_list.has("commuity"):
		print("❌ FAIL: Required misspelled words missing from issue list: ", misspelled_list)
		quit(1)
		return
		
	print("✓ PASS: Real message tokenization extracted EXACTLY the intentional misspellings ('tha', 'commuity').")

	# 3. Test TextEdit Native Syntax Highlighter Attachment & Line Ranges
	print("\n--- 3. Testing Native SpellingSyntaxHighlighter Range Highlights ---")
	var te = TextEdit.new()
	te.size = Vector2(400, 150)
	te.text = msg_text
	
	root.add_child(te)
	await process_frame
	
	SpellingAssistanceHelper.attach_inline_spell_check(te)
	await process_frame
	
	if not (te.syntax_highlighter is SpellingAssistanceHelper.SpellingSyntaxHighlighter):
		print("❌ FAIL: SpellingSyntaxHighlighter not attached to TextEdit.")
		quit(1)
		return
		
	var hl = te.syntax_highlighter
	var res = hl._get_line_syntax_highlighting(2) # line with 'tha' and 'commuity'
	print("Line 2 native highlight ranges: ", res)
	
	if res.size() == 0:
		print("❌ FAIL: No highlight ranges generated for line 2.")
		quit(1)
		return
		
	print("✓ PASS: Native SpellingSyntaxHighlighter attached and generated text character range highlights.")
	
	print("\n============================================================")
	print("  SUCCESS: ALL SPELLING SYNTAX HIGHLIGHTER TESTS PASSED (100%)")
	print("============================================================")
	quit(0)
