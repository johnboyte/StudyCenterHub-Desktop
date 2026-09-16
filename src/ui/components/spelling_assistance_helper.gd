class_name SpellingAssistanceHelper
extends RefCounted

## Useful Spelling Correction Assistance Helper for StudyCenterHub
## Uses Damerau-Levenshtein edit distance, dictionary candidate ranking,
## interactive clickable suggestion pills, and session word ignoring.

static var _valid_word_set: Dictionary = {}
static var _candidate_word_list: Array = []
static var _ignored_words: Dictionary = {}
static var _is_dict_loaded: bool = false

const SUGGESTION_MAP = {
	"recieve": "receive",
	"recieved": "received",
	"recieving": "receiving",
	"definately": "definitely",
	"seperate": "separate",
	"seperated": "separated",
	"seperating": "separating",
	"calender": "calendar",
	"adress": "address",
	"wierd": "weird",
	"occured": "occurred",
	"occurance": "occurrence",
	"beleive": "believe",
	"helt": "help",
	"teh": "the",
	"taht": "that",
	"wiht": "with",
	"hvae": "have",
	"accommodate": "accommodate",
	"acommodate": "accommodate",
	"recomended": "recommended",
	"recomend": "recommend",
	"embarass": "embarrass",
	"privlege": "privilege",
	"privelege": "privilege",
	"maintanance": "maintenance",
	"tommorrow": "tomorrow",
	"tomorow": "tomorrow",
	"untill": "until",
	"truely": "truly",
	"achive": "achieve",
	"goverment": "government",
	"enviroment": "environment",
	"independant": "independent",
	"succesful": "successful",
	"superintendant": "superintendent"
}

static func _ensure_dictionary_loaded() -> void:
	if _is_dict_loaded:
		return
	_is_dict_loaded = true

	# Core common English words for candidate search
	var core_words = [
		"the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with",
		"he", "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her",
		"she", "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up",
		"out", "if", "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time",
		"no", "just", "him", "know", "take", "people", "into", "year", "your", "good", "some", "could",
		"them", "see", "other", "than", "then", "now", "look", "only", "come", "its", "over", "think",
		"also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
		"new", "want", "because", "any", "these", "give", "day", "most", "us", "receive", "receiver",
		"received", "definitely", "separate", "calendar", "address", "weird", "occurred", "believe",
		"help", "held", "here", "hash", "hates", "has", "huge", "home", "hope", "hand", "head", "hear"
	]
	for w in core_words:
		_valid_word_set[w] = true
		if not _candidate_word_list.has(w):
			_candidate_word_list.append(w)

	# Load system dictionary if available (/usr/share/dict/words)
	if FileAccess.file_exists("/usr/share/dict/words"):
		var f = FileAccess.open("/usr/share/dict/words", FileAccess.READ)
		if f:
			var loaded_count = 0
			while not f.eof_reached() and loaded_count < 25000:
				var line = f.get_line().strip_edges().to_lower()
				if line.length() >= 2 and line.is_valid_identifier():
					_valid_word_set[line] = true
					if loaded_count < 3000 and not _candidate_word_list.has(line):
						_candidate_word_list.append(line)
					loaded_count += 1

static func damerau_levenshtein(s1: String, s2: String) -> int:
	var len1 = s1.length()
	var len2 = s2.length()
	if len1 == 0: return len2
	if len2 == 0: return len1

	var d = []
	for i in range(len1 + 1):
		var row = []
		row.resize(len2 + 1)
		d.append(row)

	for i in range(len1 + 1):
		d[i][0] = i
	for j in range(len2 + 1):
		d[0][j] = j

	for i in range(1, len1 + 1):
		var char1 = s1[i - 1]
		for j in range(1, len2 + 1):
			var char2 = s2[j - 1]
			var cost = 0 if char1 == char2 else 1

			d[i][j] = min(d[i - 1][j] + 1, min(d[i][j - 1] + 1, d[i - 1][j - 1] + cost))

			if i > 1 and j > 1 and char1 == s2[j - 2] and s1[i - 2] == char2:
				d[i][j] = min(d[i][j], d[i - 2][j - 2] + cost)

	return d[len1][len2]

static func find_suggestions(word: String) -> Array:
	_ensure_dictionary_loaded()
	var lower = word.to_lower()

	# 1. Direct explicit map match
	if SUGGESTION_MAP.has(lower):
		var explicit_sug = SUGGESTION_MAP[lower]
		if word.length() > 0 and word[0] == word[0].to_upper():
			explicit_sug = explicit_sug.capitalize()
		return [explicit_sug]

	# 2. Dynamic Damerau-Levenshtein search over candidate vocabulary
	var scored_candidates = []
	for dict_word in _candidate_word_list:
		if abs(dict_word.length() - lower.length()) > 2:
			continue
		var dist = damerau_levenshtein(lower, dict_word)
		if dist <= 2:
			scored_candidates.append({
				"word": dict_word,
				"dist": dist,
				"len_diff": abs(dict_word.length() - lower.length())
			})

	# Sort by lowest edit distance first, then length difference
	scored_candidates.sort_custom(func(a, b):
		if a["dist"] != b["dist"]:
			return a["dist"] < b["dist"]
		return a["len_diff"] < b["len_diff"]
	)

	var suggestions = []
	for item in scored_candidates:
		var sug = item["word"]
		if word.length() > 0 and word[0] == word[0].to_upper():
			sug = sug.capitalize()
		if not suggestions.has(sug):
			suggestions.append(sug)
		if suggestions.size() >= 3:
			break

	return suggestions

static func check_text(text: String) -> Array:
	_ensure_dictionary_loaded()

	var issues = []
	if text.strip_edges() == "":
		return issues

	var regex = RegEx.new()
	regex.compile("\\b[a-zA-Z']+\\b")

	var matches = regex.search_all(text)
	for m in matches:
		var word = m.get_string()
		var lower = word.to_lower()

		# Ignore valid single-character pronouns/articles 'a' and 'I'
		if lower == "a" or lower == "i":
			continue

		# Ignore user-ignored words in session
		if _ignored_words.has(lower):
			continue

		# Ignore acronyms (ALL CAPS >= 2 chars)
		if word == word.to_upper() and word.length() >= 2:
			continue

		# Ignore proper nouns (Capitalized words in body text unless at sentence start)
		if word.length() > 1 and word[0] == word[0].to_upper() and not SUGGESTION_MAP.has(lower):
			# If word is in dictionary, skip flagging proper noun
			if _valid_word_set.has(lower):
				continue

		# Check if word is valid in dictionary set
		if _valid_word_set.has(lower):
			# Check if explicit misspelling map overrides valid word (e.g. 'calender')
			if not SUGGESTION_MAP.has(lower):
				continue

		var sugs = find_suggestions(word)
		issues.append({
			"word": word,
			"suggestions": sugs,
			"start": m.get_start(),
			"end": m.get_end()
		})

	return issues

static func ignore_word(word: String) -> void:
	_ignored_words[word.to_lower()] = true

static func add_word_to_dictionary(word: String) -> void:
	_ensure_dictionary_loaded()
	var lower = word.to_lower()
	_valid_word_set[lower] = true
	if not _candidate_word_list.has(lower):
		_candidate_word_list.append(lower)

func attach_to_text_edit(text_edit: TextEdit, parent_container: Container) -> Control:
	var spell_card = PanelContainer.new()
	spell_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_card.custom_minimum_size = Vector2(0, 40)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.18, 0.26, 0.95)
	card_style.border_color = Color(0.25, 0.40, 0.60, 0.8)
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	spell_card.add_theme_stylebox_override("panel", card_style)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)

	var status_lbl = Label.new()
	status_lbl.text = "✨ Real-time Spelling Assistance Active"
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1.0))
	hbox.add_child(status_lbl)

	var sug_container = HBoxContainer.new()
	sug_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sug_container.add_theme_constant_override("separation", 8)
	hbox.add_child(sug_container)

	spell_card.add_child(hbox)
	parent_container.add_child(spell_card)

	var current_issues = []
	var active_issue_idx = 0
	var _update_spelling_bar: Callable

	_update_spelling_bar = func():
		# Clear suggestion container
		for c in sug_container.get_children():
			c.queue_free()

		var txt = text_edit.text
		current_issues = check_text(txt)

		if current_issues.size() == 0:
			status_lbl.text = "✨ Real-time Spelling Assistance Active"
			status_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1.0))
			card_style.border_color = Color(0.25, 0.40, 0.60, 0.8)
			return

		if active_issue_idx >= current_issues.size():
			active_issue_idx = 0

		var issue = current_issues[active_issue_idx]
		var word = str(issue["word"])
		var sugs: Array = issue["suggestions"]

		status_lbl.text = "⚠️ Possible spelling: \"%s\"" % word
		if current_issues.size() > 1:
			status_lbl.text += " (%d of %d)" % [active_issue_idx + 1, current_issues.size()]

		status_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.30, 1.0))
		card_style.border_color = Color(0.95, 0.75, 0.20, 1.0)

		# Render suggestion pills
		if sugs.size() > 0:
			for sug in sugs:
				var sug_btn = Button.new()
				sug_btn.text = str(sug)
				sug_btn.custom_minimum_size = Vector2(70, 28)
				sug_btn.add_theme_font_size_override("font_size", 13)

				var btn_s = StyleBoxFlat.new()
				btn_s.bg_color = Color(0.18, 0.42, 0.70, 1.0) # Bright blue suggestion pill
				btn_s.corner_radius_top_left = 4
				btn_s.corner_radius_top_right = 4
				btn_s.corner_radius_bottom_left = 4
				btn_s.corner_radius_bottom_right = 4
				btn_s.content_margin_left = 8
				btn_s.content_margin_right = 8
				sug_btn.add_theme_stylebox_override("normal", btn_s)
				sug_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				sug_btn.add_theme_color_override("font_hover_color", Color(0.4, 0.9, 1.0, 1.0))

				sug_btn.pressed.connect(func():
					var cur_t = text_edit.text
					# Replace target word occurrence
					text_edit.text = cur_t.replace(word, str(sug))
					_update_spelling_bar.call_deferred()
				)
				sug_container.add_child(sug_btn)
		else:
			var no_sug_lbl = Label.new()
			no_sug_lbl.text = "(No confident suggestion)"
			no_sug_lbl.add_theme_font_size_override("font_size", 12)
			no_sug_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
			sug_container.add_child(no_sug_lbl)

		# Render Ignore button
		var btn_ignore = Button.new()
		btn_ignore.text = "🙈 Ignore"
		btn_ignore.custom_minimum_size = Vector2(70, 28)
		btn_ignore.add_theme_font_size_override("font_size", 12)
		var ign_s = StyleBoxFlat.new()
		ign_s.bg_color = Color(0.25, 0.30, 0.38, 1.0)
		ign_s.corner_radius_top_left = 4
		ign_s.corner_radius_top_right = 4
		ign_s.corner_radius_bottom_left = 4
		ign_s.corner_radius_bottom_right = 4
		ign_s.content_margin_left = 8
		ign_s.content_margin_right = 8
		btn_ignore.add_theme_stylebox_override("normal", ign_s)
		btn_ignore.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95, 1.0))
		btn_ignore.pressed.connect(func():
			ignore_word(word)
			_update_spelling_bar.call_deferred()
		)
		sug_container.add_child(btn_ignore)

		# Render Add to Dict button
		var btn_add_dict = Button.new()
		btn_add_dict.text = "➕ Add to Dict"
		btn_add_dict.custom_minimum_size = Vector2(90, 28)
		btn_add_dict.add_theme_font_size_override("font_size", 12)
		var add_s = StyleBoxFlat.new()
		add_s.bg_color = Color(0.18, 0.42, 0.32, 1.0)
		add_s.corner_radius_top_left = 4
		add_s.corner_radius_top_right = 4
		add_s.corner_radius_bottom_left = 4
		add_s.corner_radius_bottom_right = 4
		add_s.content_margin_left = 8
		add_s.content_margin_right = 8
		btn_add_dict.add_theme_stylebox_override("normal", add_s)
		btn_add_dict.add_theme_color_override("font_color", Color(0.85, 0.95, 0.90, 1.0))
		btn_add_dict.pressed.connect(func():
			add_word_to_dictionary(word)
			_update_spelling_bar.call_deferred()
		)
		sug_container.add_child(btn_add_dict)

		# Render Next Issue button if multiple issues exist
		if current_issues.size() > 1:
			var btn_next = Button.new()
			btn_next.text = "Next ➡️"
			btn_next.custom_minimum_size = Vector2(65, 28)
			btn_next.add_theme_font_size_override("font_size", 12)
			var nxt_s = StyleBoxFlat.new()
			nxt_s.bg_color = Color(0.20, 0.35, 0.50, 1.0)
			nxt_s.corner_radius_top_left = 4
			nxt_s.corner_radius_top_right = 4
			nxt_s.corner_radius_bottom_left = 4
			nxt_s.corner_radius_bottom_right = 4
			nxt_s.content_margin_left = 6
			nxt_s.content_margin_right = 6
			btn_next.add_theme_stylebox_override("normal", nxt_s)
			btn_next.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 1.0))
			btn_next.pressed.connect(func():
				active_issue_idx = (active_issue_idx + 1) % current_issues.size()
				_update_spelling_bar.call_deferred()
			)
			sug_container.add_child(btn_next)

	text_edit.text_changed.connect(func():
		_update_spelling_bar.call()
	)

	_update_spelling_bar.call()
	return spell_card
