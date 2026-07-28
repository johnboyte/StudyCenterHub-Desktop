extends ConfirmationDialog

## Session Staff Assignment Dialog (Stage 10 Reusable Component)
## Allows selecting real eligible constituents and valid shift roles for uncovered sessions.

signal staff_assigned(assignment_data: Dictionary)
signal assignment_cancelled()

var db: RefCounted
var session_data: Dictionary = {}
var eligible_people: Array = []

var person_dropdown: OptionButton
var role_dropdown: OptionButton
var warning_label: Label
var assign_button: Button

const VALID_ROLES = [
	"Shift Supervisor (Staff)",
	"Study Tutor (Intern)",
	"Check-In Host (Vol)",
	"AV Tech (Staff)"
]

func _init(database: RefCounted = null) -> void:
	db = database
	title = "Assign Session Staffing Coverage"
	size = Vector2i(520, 340)
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

	# Role Selection
	var r_hdr = Label.new()
	r_hdr.text = "Select Shift Role:"
	r_hdr.add_theme_font_size_override("font_size", 13)
	vbox.add_child(r_hdr)

	role_dropdown = OptionButton.new()
	role_dropdown.name = "RoleDropdown"
	role_dropdown.custom_minimum_size = Vector2(0, 36)
	for r in VALID_ROLES:
		role_dropdown.add_item(r)
	role_dropdown.item_selected.connect(_on_selection_changed)
	vbox.add_child(role_dropdown)

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

func _load_people() -> void:
	if not person_dropdown: return
	person_dropdown.clear()
	eligible_people.clear()
	person_dropdown.add_item("-- Select Real Staff / Volunteer --", 0)

	if not db: return

	var res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, primary_role FROM people ORDER BY last_name ASC, first_name ASC;")
	if res.get("success", false):
		var rows = res.get("data", [])
		for r in rows:
			var fn = str(r.get("first_name", ""))
			var ln = str(r.get("last_name", ""))
			var name = (fn + " " + ln).strip_edges()
			if name == "": name = "Unnamed (" + str(r.get("human_id", "")) + ")"
			var pid = int(r.get("id", 0))
			var role = str(r.get("primary_role", "Participant"))

			eligible_people.append({
				"id": pid,
				"name": name,
				"role": role,
				"person_uuid": str(r.get("person_uuid", ""))
			})
			person_dropdown.add_item(name + " [" + role + "]", eligible_people.size())

	_validate_form()

func _update_session_details() -> void:
	var det_lbl = get_node_or_null("MarginContainer/VBoxContainer/DetailsLabel") as Label
	if det_lbl and not session_data.is_empty():
		var stitle = str(session_data.get("title", "Session"))
		var sdate = str(session_data.get("date_text", ""))
		var stime = str(session_data.get("start_time", ""))
		var sloc = str(session_data.get("room_location", ""))
		det_lbl.text = "Session: " + stitle + "\nDate: " + sdate + " at " + stime + "\nLocation: " + sloc
	_validate_form()

var selected_person_idx: int = 0

func _on_selection_changed(idx: int) -> void:
	selected_person_idx = idx
	if person_dropdown:
		person_dropdown.selected = idx
	_validate_form()

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

	# Duplicate Prevention Check
	if db and s_date != "" and s_loc != "":
		var dup_chk = db.execute("SELECT COUNT(*) AS cnt FROM schedule_entries WHERE person_name = ? AND shift_date = ? AND area = ?;", [p_name, s_date, s_loc])
		if dup_chk.get("success", false) and int(dup_chk["data"][0].get("cnt", 0)) > 0:
			ok_btn.disabled = true
			warning_label.text = "⚠️ " + p_name + " is already assigned to " + s_loc + " on " + s_date + "."
			return

	ok_btn.disabled = false

func _on_confirmed() -> void:
	var p_idx = selected_person_idx if selected_person_idx > 0 else (person_dropdown.selected if person_dropdown else 0)
	if p_idx <= 0 or p_idx > eligible_people.size():
		return

	var sel_person = eligible_people[p_idx - 1]
	var sel_role = VALID_ROLES[role_dropdown.selected] if (role_dropdown and role_dropdown.selected >= 0 and role_dropdown.selected < VALID_ROLES.size()) else "Shift Supervisor (Staff)"

	var payload = {
		"person_id": sel_person["id"],
		"person_name": sel_person["name"],
		"person_uuid": sel_person["person_uuid"],
		"shift_role": sel_role,
		"shift_date": str(session_data.get("date_text", "")),
		"start_time": str(session_data.get("start_time", "03:00 PM")),
		"end_time": str(session_data.get("end_time", "08:00 PM")),
		"area": str(session_data.get("room_location", "Study Center")),
		"notes": "Assigned via Uncovered Sessions Queue"
	}
	staff_assigned.emit(payload)

func _on_canceled() -> void:
	assignment_cancelled.emit()
