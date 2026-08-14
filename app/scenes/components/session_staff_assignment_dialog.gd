extends ConfirmationDialog

## Session Staff Assignment Dialog (Enhanced for Partial Coverage & Compact Time UI)
## Allows selecting real eligible constituents and valid shift coverage bounds for uncovered sessions.

signal staff_assigned(assignment_data: Dictionary)
signal assignment_cancelled()

var db: RefCounted
var session_data: Dictionary = {}
var eligible_people: Array = []

var person_dropdown: OptionButton
var start_time_picker: HBoxContainer
var end_time_picker: HBoxContainer
var warning_label: Label
var assign_button: Button

var selected_person_idx: int = 0

func _init(database: RefCounted = null) -> void:
	db = database
	title = "Assign Session Staffing Coverage"
	size = Vector2i(540, 380)
	exclusive = true

func _ready() -> void:
	_build_ui()
	_load_people()

func configure_session(session: Dictionary) -> void:
	session_data = session.duplicate(true)
	if is_node_ready():
		_update_session_details()

func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "UNCOVERED SESSION COVERAGE"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.53, 0.90, 1.0))
	vbox.add_child(title_lbl)

	var details_lbl = Label.new()
	details_lbl.name = "DetailsLabel"
	details_lbl.text = "Session details..."
	details_lbl.add_theme_font_size_override("font_size", 13)
	details_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
	vbox.add_child(details_lbl)

	vbox.add_child(HSeparator.new())

	# Person Selection
	var p_hdr = Label.new()
	p_hdr.text = "Select Staff/Volunteer Worker:"
	p_hdr.add_theme_font_size_override("font_size", 13)
	vbox.add_child(p_hdr)

	person_dropdown = OptionButton.new()
	person_dropdown.name = "PersonDropdown"
	person_dropdown.custom_minimum_size = Vector2(0, 36)
	person_dropdown.item_selected.connect(_on_selection_changed)
	vbox.add_child(person_dropdown)

	# Partial Coverage Time Range Selectors
	var time_grid = HBoxContainer.new()
	time_grid.add_theme_constant_override("separation", 16)

	var start_vbox = VBoxContainer.new()
	var lbl_st = Label.new()
	lbl_st.text = "Coverage Start:"
	lbl_st.add_theme_font_size_override("font_size", 13)
	start_vbox.add_child(lbl_st)

	var initial_start = str(session_data.get("start_time", session_data.get("open_time", "03:00 PM")))
	start_time_picker = _create_compact_time_picker(initial_start)
	start_time_picker.get_meta("connect_changed").call(func(): _validate_form())
	start_vbox.add_child(start_time_picker)
	time_grid.add_child(start_vbox)

	var end_vbox = VBoxContainer.new()
	var lbl_end = Label.new()
	lbl_end.text = "Coverage End:"
	lbl_end.add_theme_font_size_override("font_size", 13)
	end_vbox.add_child(lbl_end)

	var initial_end = str(session_data.get("end_time", session_data.get("close_time", "08:00 PM")))
	end_time_picker = _create_compact_time_picker(initial_end)
	end_time_picker.get_meta("connect_changed").call(func(): _validate_form())
	end_vbox.add_child(end_time_picker)
	time_grid.add_child(end_vbox)

	vbox.add_child(time_grid)

	warning_label = Label.new()
	warning_label.name = "WarningLabel"
	warning_label.text = ""
	warning_label.add_theme_font_size_override("font_size", 12)
	warning_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.20, 1.0))
	vbox.add_child(warning_label)

	get_ok_button().text = "Assign Coverage"
	get_cancel_button().text = "Cancel"

	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)

	_update_session_details()

func _create_compact_time_picker(initial_time: String = "03:00 PM") -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	var parts = initial_time.strip_edges().split(" ")
	var time_part = parts[0] if parts.size() > 0 else "03:00"
	var ampm_part = parts[1].to_upper() if parts.size() > 1 else "PM"

	var sub_parts = time_part.split(":")
	var raw_h = int(sub_parts[0]) if sub_parts.size() > 0 else 3
	var raw_m = int(sub_parts[1]) if sub_parts.size() > 1 else 0

	var opt_h = OptionButton.new()
	opt_h.custom_minimum_size = Vector2(58, 34)
	for h in range(1, 13):
		opt_h.add_item("%02d" % h)
	opt_h.select(clamp(raw_h - 1, 0, 11))
	hbox.add_child(opt_h)

	var colon_lbl = Label.new()
	colon_lbl.text = ":"
	colon_lbl.add_theme_font_size_override("font_size", 14)
	colon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(colon_lbl)

	var opt_m = OptionButton.new()
	opt_m.custom_minimum_size = Vector2(58, 34)
	var standard_mins = [0, 15, 30, 45]
	if not raw_m in standard_mins:
		standard_mins.append(raw_m)
		standard_mins.sort()

	var sel_m_idx = 0
	for idx in range(standard_mins.size()):
		var m_val = standard_mins[idx]
		opt_m.add_item("%02d" % m_val)
		if m_val == raw_m:
			sel_m_idx = idx
	opt_m.select(sel_m_idx)
	hbox.add_child(opt_m)

	var opt_ampm = OptionButton.new()
	opt_ampm.custom_minimum_size = Vector2(62, 34)
	opt_ampm.add_item("AM")
	opt_ampm.add_item("PM")
	opt_ampm.select(1 if ampm_part == "PM" else 0)
	hbox.add_child(opt_ampm)

	hbox.set_meta("get_time_string", func() -> String:
		var h_str = opt_h.get_item_text(opt_h.selected)
		var m_str = opt_m.get_item_text(opt_m.selected)
		var ampm_str = opt_ampm.get_item_text(opt_ampm.selected)
		return h_str + ":" + m_str + " " + ampm_str
	)
	hbox.set_meta("set_disabled", func(dis: bool) -> void:
		opt_h.disabled = dis
		opt_m.disabled = dis
		opt_ampm.disabled = dis
	)
	hbox.set_meta("connect_changed", func(callable: Callable) -> void:
		opt_h.item_selected.connect(func(_idx): callable.call())
		opt_m.item_selected.connect(func(_idx): callable.call())
		opt_ampm.item_selected.connect(func(_idx): callable.call())
	)

	return hbox

func _load_people() -> void:
	if not person_dropdown: return
	person_dropdown.clear()
	eligible_people.clear()
	person_dropdown.add_item("-- Select Real Staff / Volunteer --", 0)

	if not db: return

	var res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, primary_role, COALESCE(staff_classification, 'Staff') as staff_classification, COALESCE(can_cover_hours, 0) as can_cover_hours FROM people WHERE (status IS NULL OR status = 'active' OR status = '') AND (staff_classification = 'Staff' OR primary_role = 'Staff' OR can_cover_hours = 1) ORDER BY last_name ASC, first_name ASC;")
	if res.get("success", false):
		var rows = res.get("data", [])
		for r in rows:
			var fn = str(r.get("first_name", ""))
			var ln = str(r.get("last_name", ""))
			var name = (fn + " " + ln).strip_edges()
			if name == "": name = "Unnamed (" + str(r.get("human_id", "")) + ")"
			var pid = int(r.get("id", 0))
			var cls_val = str(r.get("staff_classification", r.get("primary_role", "Staff")))
			if cls_val.contains("Supervisor") or cls_val == "Shift Supervisor": cls_val = "Team Leader"

			eligible_people.append({
				"id": pid,
				"name": name,
				"role": cls_val,
				"person_uuid": str(r.get("person_uuid", ""))
			})
			person_dropdown.add_item(name + " [" + cls_val + "]", eligible_people.size())

	_validate_form()

func _update_session_details() -> void:
	var det_lbl = get_node_or_null("MarginContainer/VBoxContainer/DetailsLabel") as Label
	if det_lbl and not session_data.is_empty():
		var stitle = str(session_data.get("title", "Session"))
		var sdate = str(session_data.get("date_text", ""))
		var stime = str(session_data.get("start_time", session_data.get("open_time", "03:00 PM")))
		var etime = str(session_data.get("end_time", session_data.get("close_time", "08:00 PM")))
		var sloc = str(session_data.get("room_location", ""))
		det_lbl.text = "Session: " + stitle + "\nDate: " + sdate + " (" + stime + " - " + etime + ")\nLocation: " + sloc

	_validate_form()

func _on_selection_changed(idx: int) -> void:
	selected_person_idx = idx
	if person_dropdown:
		person_dropdown.selected = idx
	_validate_form()

func _parse_time_to_minutes(time_str: String) -> int:
	var clean = time_str.strip_edges().to_upper()
	var parts = clean.split(" ")
	if parts.size() < 2: return 0
	var time_parts = parts[0].split(":")
	if time_parts.size() < 2: return 0
	var h = int(time_parts[0])
	var m = int(time_parts[1])
	var is_pm = parts[1] == "PM"
	if is_pm and h < 12: h += 12
	if not is_pm and h == 12: h = 0
	return h * 60 + m

func _validate_form() -> void:
	var ok_btn = get_ok_button()
	if not ok_btn: return

	warning_label.text = ""

	var p_idx = selected_person_idx if selected_person_idx > 0 else (person_dropdown.selected if person_dropdown else 0)
	if p_idx <= 0 or p_idx > eligible_people.size():
		ok_btn.disabled = true
		warning_label.text = "⚠️ Please select a real constituent worker."
		return

	var sel_person = eligible_people[p_idx - 1]
	var p_name = sel_person["name"]
	var s_date = str(session_data.get("date_text", ""))
	var s_loc = str(session_data.get("room_location", ""))

	# Validate Time Boundaries
	var sel_start_str = start_time_picker.get_meta("get_time_string").call() if start_time_picker else "03:00 PM"
	var sel_end_str = end_time_picker.get_meta("get_time_string").call() if end_time_picker else "08:00 PM"

	var sel_st_min = _parse_time_to_minutes(sel_start_str)
	var sel_end_min = _parse_time_to_minutes(sel_end_str)

	var unc_start_min = _parse_time_to_minutes(str(session_data.get("start_time", session_data.get("open_time", "03:00 PM"))))
	var unc_end_min = _parse_time_to_minutes(str(session_data.get("end_time", session_data.get("close_time", "08:00 PM"))))

	if sel_st_min >= sel_end_min:
		ok_btn.disabled = true
		warning_label.text = "⚠️ Coverage End Time must be after Coverage Start Time."
		return

	if sel_st_min < unc_start_min or sel_end_min > unc_end_min:
		ok_btn.disabled = true
		warning_label.text = "⚠️ Selected coverage time must stay within current uncovered interval bounds."
		return

	# Duplicate Prevention Check
	if db and s_date != "" and s_loc != "":
		var dup_chk = db.execute("SELECT COUNT(*) AS cnt FROM schedule_entries WHERE person_name = ? AND shift_date = ? AND area = ? AND NOT (end_time <= ? OR start_time >= ?);", [p_name, s_date, s_loc, sel_start_str, sel_end_str])
		if dup_chk.get("success", false) and int(dup_chk["data"][0].get("cnt", 0)) > 0:
			ok_btn.disabled = true
			warning_label.text = "⚠️ " + p_name + " is already assigned to " + s_loc + " on " + s_date + " during this time."
			return

	ok_btn.disabled = false

func _on_confirmed() -> void:
	var p_idx = selected_person_idx if selected_person_idx > 0 else (person_dropdown.selected if person_dropdown else 0)
	if p_idx <= 0 or p_idx > eligible_people.size():
		return

	var sel_person = eligible_people[p_idx - 1]
	var sel_role = sel_person.get("role", "Staff")

	var sel_start_str = start_time_picker.get_meta("get_time_string").call() if start_time_picker else str(session_data.get("start_time", "03:00 PM"))
	var sel_end_str = end_time_picker.get_meta("get_time_string").call() if end_time_picker else str(session_data.get("end_time", "08:00 PM"))

	var payload = {
		"session_id": int(session_data.get("id", 0)),
		"person_id": sel_person["id"],
		"person_name": sel_person["name"],
		"person_uuid": sel_person["person_uuid"],
		"shift_role": sel_role,
		"shift_date": str(session_data.get("date_text", "")),
		"start_time": sel_start_str,
		"end_time": sel_end_str,
		"area": str(session_data.get("room_location", "Study Center")),
		"notes": "Assigned via Uncovered Sessions Queue"
	}
	staff_assigned.emit(payload)

func _on_canceled() -> void:
	assignment_cancelled.emit()
