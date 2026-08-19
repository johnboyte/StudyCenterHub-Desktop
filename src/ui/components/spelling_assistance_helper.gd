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
	"calender": "calendar",
	"maintanance": "maintenance",
	"tommorrow": "tomorrow",
	"tomorow": "tomorrow",
	"untill": "until",
	"truely": "truly",
	"wierd": "weird",
	"achive": "achieve",
	"beleive": "believe",
	"goverment": "government",
	"enviroment": "environment"
}

static func check_text(text: String) -> Array:
	var issues = []
	if text.strip_edges() == "":
		return issues

	# Split words preserving index
	var regex = RegEx.new()
	regex.compile("\\b[a-zA-Z']+\\b")

	var matches = regex.search_all(text)
	for m in matches:
		var word = m.get_string()
		var lower_word = word.to_lower()
		if COMMON_DICTIONARY.has(lower_word):
			var correct = COMMON_DICTIONARY[lower_word]
			# Match original capitalization if capitalized
			if word.length() > 0 and word[0] == word[0].to_upper():
				correct = correct.capitalize()
			issues.append({
				"word": word,
				"suggestion": correct,
				"start": m.get_start(),
				"end": m.get_end()
			})

	return issues

static func attach_to_text_edit(text_edit: TextEdit, parent_container: Container) -> Control:
	var banner = HBoxContainer.new()
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.visible = false
	banner.add_theme_constant_override("separation", 8)

	var icon_lbl = Label.new()
	icon_lbl.text = "⚠️ Spelling Assistance:"
	icon_lbl.add_theme_font_size_override("font_size", 13)
	icon_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20, 1.0))
	banner.add_child(icon_lbl)

	var msg_lbl = Label.new()
	msg_lbl.text = ""
	msg_lbl.add_theme_font_size_override("font_size", 13)
	msg_lbl.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 1.0))
	msg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.add_child(msg_lbl)

	var btn_fix = Button.new()
	btn_fix.text = "Auto-Fix Spelling"
	btn_fix.custom_minimum_size = Vector2(130, 28)
	btn_fix.add_theme_font_size_override("font_size", 12)
	btn_fix.add_theme_color_override("font_color", Color(0.10, 0.14, 0.20, 1.0))
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.95, 0.75, 0.20, 1.0)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	btn_fix.add_theme_stylebox_override("normal", style_normal)
	banner.add_child(btn_fix)

	parent_container.add_child(banner)

	var current_issues = []

	var _update_banner = func():
		var txt = text_edit.text
		current_issues = check_text(txt)
		if current_issues.size() > 0:
			var first = current_issues[0]
			msg_lbl.text = "\"%s\" → \"%s\"" % [first["word"], first["suggestion"]]
			banner.visible = true
		else:
			banner.visible = false

	text_edit.text_changed.connect(func():
		_update_banner.call()
	)

	btn_fix.pressed.connect(func():
		if current_issues.size() > 0:
			var txt = text_edit.text
			for issue in current_issues:
				var target_word = issue["word"]
				var replacement = issue["suggestion"]
				txt = txt.replace(target_word, replacement)
			text_edit.text = txt
			_update_banner.call()
	)

	_update_banner.call()
	return banner
