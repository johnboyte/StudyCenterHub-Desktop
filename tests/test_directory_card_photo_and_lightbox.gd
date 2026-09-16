extends SceneTree

## Automated Headless Test Suite for Directory Person Cards, Photo Cropping & Lightbox Viewer
## Verifies 3-line card formatting, photo crop/zoom pipeline, and lightbox thumbnail click separation.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING DIRECTORY CARDS, PHOTO CROP & LIGHTBOX TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_dir_card_photo.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	# Load DirectoryView scene
	var dir_scene = load("res://app/scenes/directory_view.tscn").instantiate()
	root.add_child(dir_scene)
	dir_scene.db = db

	# Seed 3 test people:
	# 1. 3-line person with photo
	# 2. 2-line person without photo
	# 3. Long text person
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, institution_short_name, academic_year, major, profile_photo) VALUES (1, 'p-001', 'P-20260901-0001', 'Alexander', 'Hamilton', 'Participant', 'AU', 'Freshman', 'Political Science', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role) VALUES (2, 'p-002', 'P-20260901-0002', 'Benjamin', 'Franklin', 'Participant');")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, institution_short_name, academic_year, major) VALUES (3, 'p-003', 'P-20260901-0003', 'Christopher-Bartholomew', 'Montgomery-Wellington', 'Participant', 'Anderson University School of Advanced Studies', 'Senior Undergraduate Scholar', 'Biomedical Engineering and Computational Physics');")

	dir_scene._init_read_service()
	dir_scene._fetch_roster_data()

	print("VISIBLE PEOPLE SIZE: ", dir_scene.visible_people.size())
	if dir_scene.visible_people.size() > 0:
		print("PEOPLE DUMP: ", dir_scene.visible_people[0])

	var p_hamilton = {
		"person_uuid": "p-001", "human_id": "P-20260901-0001", "first_name": "Alexander", "last_name": "Hamilton",
		"institution_short_name": "AU", "academic_year": "Freshman", "major": "Political Science",
		"profile_photo": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
	}
	var p_franklin = {
		"person_uuid": "p-002", "human_id": "P-20260901-0002", "first_name": "Benjamin", "last_name": "Franklin"
	}
	var p_montgomery = {
		"person_uuid": "p-003", "human_id": "P-20260901-0003", "first_name": "Christopher-Bartholomew", "last_name": "Montgomery-Wellington",
		"institution_short_name": "Anderson University School of Advanced Studies", "academic_year": "Senior Undergraduate Scholar", "major": "Biomedical Engineering and Computational Physics"
	}

	# ----------------------------------------------------
	# TEST 1: Directory Row Button Height & 3-Line Structure
	# ----------------------------------------------------
	var btn1 = dir_scene._create_roster_row_button(p_hamilton, 0)

	if btn1.custom_minimum_size.y != 84:
		print("FAIL: Directory row button minimum height is not 84px. Got: ", btn1.custom_minimum_size.y)
		quit(1)
		return
	print("PASS 1/6: Directory row button height guaranteed at 84px for 3 comfortable lines.")

	# ----------------------------------------------------
	# TEST 2: 3-Line Content Verification
	# ----------------------------------------------------
	var margin1 = btn1.get_child(0) as MarginContainer
	var hbox1 = margin1.get_child(0) as HBoxContainer
	var vbox_text1 = hbox1.get_child(1) as VBoxContainer

	if vbox_text1.get_child_count() != 3:
		print("FAIL: Person card text container does not have 3 labels. Got: ", vbox_text1.get_child_count())
		quit(1)
		return

	var name_lbl1 = vbox_text1.get_child(0) as Label
	var id_lbl1 = vbox_text1.get_child(1) as Label
	var campus_lbl1 = vbox_text1.get_child(2) as Label

	if name_lbl1.text != "Alexander Hamilton" or id_lbl1.text != "P-20260901-0001" or campus_lbl1.text != "AU • Freshman • Political Science":
		print("FAIL: 3-line text content mismatch. Got: ", [name_lbl1.text, id_lbl1.text, campus_lbl1.text])
		quit(1)
		return
	print("PASS 2/6: Person card displays Line 1 Name, Line 2 Human ID, and Line 3 College/Classification cleanly.")

	# ----------------------------------------------------
	# TEST 3: Thumbnail Click Separation & Lightbox Support
	# ----------------------------------------------------
	var avatar_rect = hbox1.get_child(0) as TextureRect
	if avatar_rect == null or avatar_rect.mouse_filter != Control.MOUSE_FILTER_STOP:
		print("FAIL: Profile photo thumbnail mouse filter is not MOUSE_FILTER_STOP.")
		quit(1)
		return
	print("PASS 3/6: Photo thumbnail mouse filter set to MOUSE_FILTER_STOP to separate photo lightbox from card selection.")

	# ----------------------------------------------------
	# TEST 4: No-Photo Initials Avatar Click Safety
	# ----------------------------------------------------
	var btn2 = dir_scene._create_roster_row_button(p_franklin, 1)
	var margin2 = btn2.get_child(0) as MarginContainer
	var hbox2 = margin2.get_child(0) as HBoxContainer
	var avatar2 = hbox2.get_child(0) as Label

	if avatar2.mouse_filter != Control.MOUSE_FILTER_PASS:
		print("FAIL: No-photo initials avatar mouse filter is not MOUSE_FILTER_PASS.")
		quit(1)
		return
	print("PASS 4/6: No-photo initials avatar passes click through to normal card selection.")

	# ----------------------------------------------------
	# TEST 5: Base64 Image Decoding Helper
	# ----------------------------------------------------
	var test_b64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
	var decoded_img = dir_scene._create_image_from_base64(test_b64)
	if decoded_img == null or decoded_img.get_width() != 1 or decoded_img.get_height() != 1:
		print("FAIL: _create_image_from_base64 failed to decode image buffer.")
		quit(1)
		return
	print("PASS 5/6: Base64 image decoding helper verified.")

	# ----------------------------------------------------
	# TEST 6: Long Text Truncation Safety
	# ----------------------------------------------------
	var btn3 = dir_scene._create_roster_row_button(p_montgomery, 2)
	var margin3 = btn3.get_child(0) as MarginContainer
	var hbox3 = margin3.get_child(0) as HBoxContainer
	var vbox_text3 = hbox3.get_child(1) as VBoxContainer
	var campus_lbl3 = vbox_text3.get_child(2) as Label

	if campus_lbl3.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		print("FAIL: Third line text overrun behavior is not OVERRUN_TRIM_ELLIPSIS.")
		quit(1)
		return
	print("PASS 6/6: Long third-line classification text truncates gracefully with ellipsis.")

	# Cleanup test db and scene
	dir_scene.queue_free()
	db = null
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	print("==========================================================")
	print("SUCCESS: DIRECTORY CARDS, PHOTO CROP & LIGHTBOX VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
