extends SceneTree

## Focused Verification Suite for Communications Image Attachment Restoration

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING FOCUSED IMAGE ATTACHMENT RESTORATION TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_attachment_restoration.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var runner = MigrationsRunnerScript.new(db)
	var m_res = runner.run_migrations()
	assert(m_res.get("success", false) == true, "Database migration failed")
	print("  ✓ PASS 1/14: Database schema migrated cleanly.")

	var scene_res = load("res://app/scenes/communications_view.tscn")
	assert(scene_res != null, "Failed to load communications_view.tscn")
	var comms_view = scene_res.instantiate()
	comms_view.db = db
	root.add_child(comms_view)
	if not comms_view.message_body_edit:
		comms_view._setup_communicate_send_composer()
	print("  ✓ PASS 2/14: CommunicationsView instantiated and initialized.")

	# PASS 3: Message editor node present and configured
	assert(comms_view.message_body_edit != null, "MessageBodyEdit node missing")
	assert(comms_view.message_body_edit.custom_minimum_size.y >= 140, "MessageBodyEdit height must be at least 140px")
	print("  ✓ PASS 3/14: MessageBodyEdit present with multiline configuration.")

	# PASS 4: AttachmentCard node present
	assert(comms_view.attachment_card != null, "AttachmentCard node missing")
	print("  ✓ PASS 4/14: AttachmentCard statically declared in scene tree.")

	# PASS 5: Drop Zone visible initially when no image is attached
	assert(comms_view.attachment_drop_zone != null, "AttachmentDropZone node missing")
	assert(comms_view.attachment_drop_zone.visible == true, "AttachmentDropZone must be visible initially")
	assert(comms_view.attachment_preview_box != null, "AttachmentPreviewBox node missing")
	assert(comms_view.attachment_preview_box.visible == false, "AttachmentPreviewBox must be hidden initially")
	assert(comms_view.btn_choose_image != null, "BtnChooseImage missing")
	print("  ✓ PASS 5/14: Drop Zone & Choose Image button visible initially.")

	# Create a temporary test image
	var tmp_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var test_img_path = tmp_dir + "/test_restoration_flyer.png"
	var test_img = Image.create(640, 480, false, Image.FORMAT_RGBA8)
	test_img.fill(Color(0.88, 0.35, 0.21, 1.0))
	test_img.save_png(test_img_path)

	# PASS 6: Set attached image
	comms_view._set_attached_image(test_img_path)
	assert(comms_view.current_attachment_path == test_img_path, "current_attachment_path must match attached image")
	print("  ✓ PASS 6/14: Image attachment path updated correctly.")

	# PASS 7: Preview box visible, drop zone hidden
	assert(comms_view.attachment_drop_zone.visible == false, "AttachmentDropZone must hide when image is attached")
	assert(comms_view.attachment_preview_box.visible == true, "AttachmentPreviewBox must be visible when image is attached")
	assert(comms_view.attachment_thumbnail.texture != null, "AttachmentThumbnail texture must be populated")
	assert("640x480" in comms_view.attachment_info_label.text, "AttachmentInfoLabel must display image dimensions")
	print("  ✓ PASS 7/14: Preview box & thumbnail updated cleanly with image metadata.")

	# PASS 8: Text editing preserves attachment
	comms_view.message_body_edit.text = "Testing text editing while image is attached."
	comms_view._update_character_count()
	assert(comms_view.current_attachment_path == test_img_path, "Text editing must not alter attachment path")
	assert(comms_view.attachment_preview_box.visible == true, "Text editing must keep attachment preview visible")
	print("  ✓ PASS 8/14: Editing text preserves attached image.")

	# PASS 9: Recipient selection preserves attachment
	comms_view.selected_individual_ids.append(1)
	comms_view._refresh_individual_chips()
	assert(comms_view.current_attachment_path == test_img_path, "Recipient changes must not alter attachment path")
	print("  ✓ PASS 9/14: Recipient selection preserves attached image.")

	# PASS 10: MMS Indicator updates when channel switches
	comms_view._on_channel_selected_change(0) # SMS
	assert("MMS" in comms_view.channel_mms_indicator.text, "MMS indicator must show MMS when image attached on SMS channel")
	print("  ✓ PASS 10/14: Channel indicator displays MMS for SMS channel.")

	# PASS 11: Remove image functionality
	comms_view._clear_attached_image()
	assert(comms_view.current_attachment_path == "", "current_attachment_path must reset to empty string")
	assert(comms_view.attachment_drop_zone.visible == true, "AttachmentDropZone must be visible after clear")
	assert(comms_view.attachment_preview_box.visible == false, "AttachmentPreviewBox must be hidden after clear")
	print("  ✓ PASS 11/14: Remove image resets state and restores drop zone.")

	# PASS 12: Character count accuracy when empty
	comms_view.message_body_edit.text = ""
	comms_view._update_character_count()
	assert("0 character" in comms_view.char_count_label.text, "CharCountLabel must indicate 0 characters when text edit is empty")
	print("  ✓ PASS 12/14: Character counter accurately reads 0 when empty.")

	# PASS 13: Window files dropped handler connected
	var win = comms_view.get_window()
	if win:
		assert(win.files_dropped.is_connected(comms_view._on_window_files_dropped), "Window files_dropped signal must be connected")
	print("  ✓ PASS 13/14: Window drag-and-drop listener connected.")

	# PASS 14: Action buttons validate with attachment alone
	comms_view.current_eligible_recipients = [101]
	comms_view._set_attached_image(test_img_path)
	comms_view.message_body_edit.text = ""
	comms_view._update_composer_validation()
	assert(comms_view.btn_send_message.disabled == false, "Send Message button must be enabled when image is attached even if body is empty")
	print("  ✓ PASS 14/14: Send Message enables with image attachment alone.")

	print("==========================================================")
	print("SUMMARY: 14 / 14 ASSERTIONS PASSED (100.0%)")
	print("==========================================================")
	print("SUCCESS: FOCUSED IMAGE ATTACHMENT RESTORATION VERIFICATION PASSED (100%)")
	quit(0)
