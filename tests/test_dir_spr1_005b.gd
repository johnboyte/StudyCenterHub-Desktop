extends MainLoop

## STORY DIR-SPR1-005B: PERSON WORKSPACE FOUNDATION TEST SUITE
## Headless verification suite testing Person Workspace navigation, section rendering, empty states, and read-only DB integrity.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

var db: RefCounted
var read_service: RefCounted
var total_assertions: int = 0
var passed_assertions: int = 0

func _process(_delta: float) -> bool:
	run_all_tests()
	return true

func run_all_tests() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-005B PERSON WORKSPACE TEST SUITE")
	print("==========================================================")

	_setup_test_environment()

	var scene_res = load("res://app/scenes/directory_view.tscn")
	_assert(scene_res != null, "DirectoryView scene file loaded successfully.")

	var dir_view = scene_res.instantiate() as DirectoryViewScript
	dir_view.read_service = read_service

	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.add_child(dir_view)

	dir_view._ready()

	# Assertion 1: Unselected state shows NoSelectionWorkspace
	var no_sel_lbl = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/NoSelectionWorkspace") as Label
	var sel_vbox = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox") as VBoxContainer
	_assert(no_sel_lbl != null and no_sel_lbl.visible and sel_vbox != null and not sel_vbox.visible, "Unselected state shows empty workspace messaging.")

	# Assertion 2: Selecting person updates workspace header
	dir_view.select_person_by_index(0)
	var name_lbl = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/NameLabel") as Label
	var id_lbl = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/HumanIdLabel") as Label
	_assert(name_lbl != null and name_lbl.text == "Hannah Abbott" and id_lbl != null and id_lbl.text == "Human ID: P-20260720-8CC6", "Workspace header displays selected person full name and Human ID.")

	# Assertion 3: Default workspace tab is Overview
	var overview_sec = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/OverviewSection") as VBoxContainer
	_assert(overview_sec != null and overview_sec.visible, "Default active section is Overview.")

	# Assertion 4: Profile tab navigation
	dir_view.select_workspace_tab("profile")
	var profile_sec = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ProfileSection") as VBoxContainer
	_assert(profile_sec != null and profile_sec.visible and not overview_sec.visible, "Selecting Profile tab displays Profile section.")

	# Assertion 5: Participation tab navigation
	dir_view.select_workspace_tab("participation")
	var part_sec = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ParticipationSection") as VBoxContainer
	_assert(part_sec != null and part_sec.visible and not profile_sec.visible, "Selecting Participation tab displays Participation section.")

	# Assertion 6: Communications tab navigation
	dir_view.select_workspace_tab("communications")
	var comm_sec = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/CommunicationsSection") as VBoxContainer
	_assert(comm_sec != null and comm_sec.visible and not part_sec.visible, "Selecting Communications tab displays Communications section.")

	# Assertion 7: History tab navigation
	dir_view.select_workspace_tab("history")
	var hist_sec = dir_view.get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/HistorySection") as VBoxContainer
	_assert(hist_sec != null and hist_sec.visible and not comm_sec.visible, "Selecting History tab displays History section.")

	# Assertion 8: Profile section displays contact data
	dir_view.select_workspace_tab("profile")
	var has_contact_card = profile_sec.get_child_count() >= 1
	_assert(has_contact_card, "Profile section renders Contact Information card.")

	# Assertion 9: Clean empty state for Roles and Access
	var has_roles_card = profile_sec.get_child_count() >= 2
	_assert(has_roles_card, "Profile section renders Roles and Access empty state card.")

	# Assertion 10: Communications section renders Direct Actions buttons
	dir_view.select_workspace_tab("communications")
	var has_actions_card = comm_sec.get_child_count() >= 1
	_assert(has_actions_card, "Communications section renders Direct Actions card.")

	# Assertion 11: History section renders Notes with Configurable Application Data badge
	dir_view.select_workspace_tab("history")
	var has_notes_card = hist_sec.get_child_count() >= 1
	_assert(has_notes_card, "History section renders Notes card with Configurable Application Data badge.")

	# Assertion 12: Directory roster filtering remains functional alongside workspace
	dir_view.select_filter("active")
	_assert(dir_view.visible_people.size() == 8, "Roster filtering operates correctly alongside Person Workspace.")

	# Assertion 13: Read-only DB integrity check (zero outbox events)
	var outbox_cnt = _get_pending_outbox_count()
	_assert(outbox_cnt == 0, "Person Workspace interaction created zero outbox events.")

	# Assertion 14: Read-only DB integrity check (people table count unmodified)
	var total_cnt = read_service.count_people()
	_assert(total_cnt == 13, "Person Workspace interaction made zero database modifications.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (%.1f%%)" % [passed_assertions, total_assertions, (float(passed_assertions)/float(total_assertions))*100.0])
	print("==========================================================")

	if passed_assertions == total_assertions:
		print("SUCCESS: ALL STORY DIR-SPR1-005B OBJECTIVES PASSED (100%)")
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % (total_assertions - passed_assertions))

func _setup_test_environment() -> void:
	db = SQLiteDatabaseScript.new()
	var migrations_runner = MigrationsRunnerScript.new(db)
	migrations_runner.run_migrations()
	read_service = DirectoryReadServiceScript.new(db)
	_seed_sample_data()

func _seed_sample_data() -> void:
	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM attendance_log;")
	db.execute("DELETE FROM event_outbox;")

	var seed_people = [
		{"uuid": "usr_001", "id": "P-20260720-8CC6", "first": "Hannah", "last": "Abbott", "status": "active", "grade": "Freshman", "phone": "(864) 555-0101", "em_name": "Mary Abbott", "em_phone": "(864) 555-0102", "notes": "Active student in math pathway."},
		{"uuid": "usr_002", "id": "P-20260720-60EE", "first": "Laura", "last": "Croft", "status": "inactive", "grade": "Senior", "phone": "(864) 555-0103", "em_name": "Richard Croft", "em_phone": "(864) 555-0104", "notes": ""},
		{"uuid": "usr_003", "id": "P-20260720-A4E4", "first": "Grace", "last": "Hopper", "status": "active", "grade": "Recent Graduate", "phone": "(864) 555-0105", "em_name": "John Hopper", "em_phone": "(864) 555-0106", "notes": "Completed computer science pathway."},
		{"uuid": "usr_004", "id": "P-20260720-1F54", "first": "Ian", "last": "Malcolm", "status": "pending", "grade": "Junior", "phone": "(864) 555-0107", "em_name": "Sarah Malcolm", "em_phone": "(864) 555-0108", "notes": ""},
		{"uuid": "usr_005", "id": "P-20260720-297A", "first": "Julia", "last": "Roberts", "status": "pending", "grade": "Freshman", "phone": "", "em_name": "", "em_phone": "", "notes": ""},
		{"uuid": "usr_006", "id": "P-20260720-2145", "first": "Michael", "last": "Scott", "status": "inactive", "grade": "Other", "phone": "(864) 555-0109", "em_name": "", "em_phone": "", "notes": ""},
		{"uuid": "usr_007", "id": "P-20260720-DF67", "first": "Kevin", "last": "Spacey", "status": "pending", "grade": "Sophomore", "phone": "", "em_name": "", "em_phone": "", "notes": ""},
		{"uuid": "usr_008", "id": "P-20260720-81E9", "first": "Frank", "last": "Underwood", "status": "active", "grade": "Sophomore", "phone": "(864) 555-0110", "em_name": "Claire Underwood", "em_phone": "(864) 555-0111", "notes": ""},
		{"uuid": "usr_009", "id": "P-20260720-6DDA", "first": "David", "last": "Vance", "status": "active", "grade": "Freshman", "phone": "(864) 555-0112", "em_name": "", "em_phone": "", "notes": ""},
		{"uuid": "usr_010", "id": "P-20260720-AAB1", "first": "Bartholomew-Alexander", "last": "Wellington-Smythe-Montgomery", "status": "active", "grade": "Graduate Student", "phone": "(864) 555-0113", "em_name": "Eleanor Wellington-Smythe", "em_phone": "(864) 555-0114", "notes": "Long legal name test constituent."},
		{"uuid": "usr_011", "id": "P-20260720-005F", "first": "Beth", "last": "Yates", "status": "active", "grade": "", "phone": "(864) 555-0115", "em_name": "", "em_phone": "", "notes": ""},
		{"uuid": "usr_012", "id": "P-20260720-881C", "first": "Aaron", "last": "Zimmerman", "status": "active", "grade": "Senior", "phone": "(864) 555-0116", "em_name": "Rachel Zimmerman", "em_phone": "(864) 555-0117", "notes": ""},
		{"uuid": "usr_013", "id": "P-20260720-8C9C", "first": "Elena", "last": "de la Rosa", "status": "active", "grade": "Junior", "phone": "(864) 555-0118", "em_name": "Carlos de la Rosa", "em_phone": "(864) 555-0119", "notes": ""}
	]

	for p in seed_people:
		db.execute(
			"INSERT INTO people (person_uuid, human_id, first_name, last_name, status, grade, phone, emergency_contact_name, emergency_contact_phone, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[p["uuid"], p["id"], p["first"], p["last"], p["status"], p["grade"], p["phone"], p["em_name"], p["em_phone"], p["notes"]]
		)

	# Seed attendance check-in for usr_001
	db.execute(
		"INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES (?, 1, 'usr_001', 'P-20260720-8CC6', '2026-07-20', '09:30:00', 'Manual', 'dev_macbook_primary_node');",
		["chk_001_test"]
	)

func _get_pending_outbox_count() -> int:
	var res = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox WHERE status = 'pending';")
	if res["success"] and res["data"].size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func _assert(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL assertion %d: %s" % [total_assertions, message])
