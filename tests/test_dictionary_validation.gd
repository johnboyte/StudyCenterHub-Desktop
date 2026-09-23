extends SceneTree

const SpellingAssistanceHelper = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _initialize():
	print("--- TESTING REFINED COMPREHENSIVE DICTIONARY VALIDATION ---")
	
	# Load dictionary in helper
	SpellingAssistanceHelper._ensure_dictionary_loaded()
	
	var valid_words = [
		"is", "it", "to", "the", "and", "another", "others", "wanted",
		"gather", "glad", "bring", "food", "evening", "people", "chance",
		"familiar", "little", "community", "coming", "Sunday", "others",
		"I'd", "we'll", "Real", "Life", "House", "one", "test", "spelling",
		"checker", "message", "sentence", "contains", "intentional", "mistake",
		"misspelled", "word", "help", "build"
	]
	
	var invalid_words = [
		"tha", "anothre", "commuity", "familar"
	]
	
	var valid_failures = []
	for w in valid_words:
		if not SpellingAssistanceHelper.is_word_valid(w):
			valid_failures.append(w)
			
	var invalid_failures = []
	for w in invalid_words:
		if SpellingAssistanceHelper.is_word_valid(w):
			invalid_failures.append(w)
			
	print("Valid word test failures (should be empty): ", valid_failures)
	print("Invalid word test failures (should be empty): ", invalid_failures)
	
	var sample_text = "This is another message to test the spelling checker. We wanted to gather several others for an evening together.\n\nThis sentence contains tha intentional mistake and another misspelled word: commuity.\n\nWe'd be glad to bring food and help people get familiar with the Real Life House."
	
	var issues = SpellingAssistanceHelper.check_text(sample_text)
	print("\nIssues found in sample text:")
	var found_words = []
	for iss in issues:
		found_words.append(iss["word"])
		print("  Misspelled word: '", iss["word"], "' at cols ", iss["start"], "..", iss["end"], " suggestions: ", iss["suggestions"])
		
	print("Found misspelled words: ", found_words)
	quit()
