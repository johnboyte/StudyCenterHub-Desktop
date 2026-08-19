extends RefCounted

## Spelling Assistance Helper for StudyCenterHub
## Provides real-time spelling detection, misspelling suggestions,
## and 1-click auto-fix capability for TextEdit and LineEdit controls.

const COMMON_DICTIONARY = {
	"recieve": "receive",
	"recieved": "received",
	"recieving": "receiving",
	"definately": "definitely",
	"seperate": "separate",
	"seperated": "separated",
	"seperating": "separating",
	"calender": "calendar",
	"teh": "the",
	"taht": "that",
	"wiht": "with",
	"hvae": "have",
	"accommodate": "accommodate",
	"acommodate": "accommodate",
	"occured": "occurred",
	"occurance": "occurrence",
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
	"wierd": "weird",
	"achive": "achieve",
	"beleive": "believe",
	"goverment": "government",
	"enviroment": "environment",
	"independant": "independent",
	"succesful": "successful",
	"superintendant": "superintendent"
}

static func check_text(text: String) -> Array:
	var issues = []
	if text.strip_edges() == "":
		return issues

	var regex = RegEx.new()
	regex.compile("\\b[a-zA-Z']+\\b")

	var matches = regex.search_all(text)
	for m in matches:
		var word = m.get_string()
		var lower_word = word.to_lower()
		if COMMON_DICTIONARY.has(lower_word):
			var correct = COMMON_DICTIONARY[lower_word]
			if word.length() > 0 and word[0] == word[0].to_upper():
				correct = correct.capitalize()
			if word == word.to_upper() and word.length() > 1:
				correct = correct.to_upper()
			issues.append({
				"word": word,
				"suggestion": correct,
				"start": m.get_start(),
				"end": m.get_end()
			})

	return issues

static func attach_to_text_edit(text_edit: TextEdit, parent_container: Container) -> Control:
	var spell_card = PanelContainer.new()
	spell_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_card.custom_minimum_size = Vector2(0, 36)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.18, 0.26, 0.90) # Dark high-contrast panel
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

	var status_icon = Label.new()
	status_icon.text = "✨"
	status_icon.add_theme_font_size_override("font_size", 14)
	hbox.add_child(status_icon)

	var msg_lbl = Label.new()
	msg_lbl.text = "Real-time Spelling Assistance Active"
	msg_lbl.add_theme_font_size_override("font_size", 14)
	msg_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1.0))
	msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(msg_lbl)

	var btn_fix = Button.new()
	btn_fix.text = "⚡ Fix Spelling"
	btn_fix.custom_minimum_size = Vector2(130, 30)
	btn_fix.add_theme_font_size_override("font_size", 13)
	btn_fix.visible = false

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.95, 0.75, 0.20, 1.0) # Gold button
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	btn_fix.add_theme_stylebox_override("normal", btn_style)
	btn_fix.add_theme_color_override("font_color", Color(0.10, 0.14, 0.20, 1.0))
	btn_fix.add_theme_color_override("font_hover_color", Color(0.0, 0.0, 0.0, 1.0))
	btn_fix.add_theme_color_override("font_focus_color", Color(0.10, 0.14, 0.20, 1.0))
	hbox.add_child(btn_fix)

	spell_card.add_child(hbox)
	parent_container.add_child(spell_card)

	var current_issues = []

	var _update_spelling_bar = func():
		var txt = text_edit.text
		current_issues = check_text(txt)
		if current_issues.size() > 0:
			var first = current_issues[0]
			status_icon.text = "⚠️"
			msg_lbl.text = "Spelling Suggestion: \"%s\" → \"%s\" (%d issue%s detected)" % [
				first["word"], first["suggestion"], current_issues.size(), "s" if current_issues.size() > 1 else ""
			]
			msg_lbl.add_theme_color_override("font_color", Color(0.98, 0.85, 0.30, 1.0))
			card_style.border_color = Color(0.95, 0.75, 0.20, 1.0)
			btn_fix.text = "⚡ Fix All (%d)" % current_issues.size()
			btn_fix.visible = true
		else:
			status_icon.text = "✨"
			msg_lbl.text = "Real-time Spelling Assistance Active"
			msg_lbl.add_theme_color_override("font_color", Color(0.60, 0.80, 1.0, 1.0))
			card_style.border_color = Color(0.25, 0.40, 0.60, 0.8)
			btn_fix.visible = false

	text_edit.text_changed.connect(func():
		_update_spelling_bar.call()
	)

	btn_fix.pressed.connect(func():
		if current_issues.size() > 0:
			var txt = text_edit.text
			for issue in current_issues:
				var target_word = issue["word"]
				var replacement = issue["suggestion"]
				txt = txt.replace(target_word, replacement)
			text_edit.text = txt
			_update_spelling_bar.call()
	)

	_update_spelling_bar.call()
	return spell_card
