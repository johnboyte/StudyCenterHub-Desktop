extends SceneTree

const CommunicationsViewScene = preload("res://app/scenes/communications_view.tscn")

func _initialize():
	print("============================================================")
	print("  RUNNING POST-SEND COMPOSER RESET REGRESSION TEST SUITE")
	print("============================================================")
	
	var cv = CommunicationsViewScene.instantiate()
	root.add_child(cv)
	await process_frame
	
	print("--- 1. Populating Communications Composer with State ---")
	cv.selected_individual_ids = [1, 2]
	cv._refresh_individual_chips()
	
	if cv.message_body_edit:
		cv.message_body_edit.text = "Test message for composer reset test"
		cv._update_character_count()
		
	cv.current_attachment_path = "/tmp/test_flyer.png"
	
	if cv.template_dropdown and cv.template_dropdown.get_item_count() > 1:
		cv.template_dropdown.selected = 1
		
	cv._update_audience_resolution()
	cv._update_composer_validation()
	
	print("Initial State:")
	print("  Recipients count: ", cv.selected_individual_ids.size())
	print("  Message text: '", cv.message_body_edit.text if cv.message_body_edit else "", "'")
	print("  Attachment path: '", cv.current_attachment_path, "'")
	print("  Can Send: ", not cv.btn_send_message.disabled if cv.btn_send_message else false)
	print("  Can Schedule: ", not cv.btn_schedule_message.disabled if cv.btn_schedule_message else false)
	
	if cv.selected_individual_ids.size() == 0:
		print("❌ FAIL: Recipients failed to populate for test.")
		quit(1)
		return
		
	print("\n--- 2. Executing Post-Send Composer Reset ---")
	cv._reset_communications_composer_after_successful_send()
	await process_frame
	
	print("Post-Reset State:")
	print("  Recipients count: ", cv.selected_individual_ids.size())
	print("  Message text: '", cv.message_body_edit.text if cv.message_body_edit else "", "'")
	print("  Attachment path: '", cv.current_attachment_path, "'")
	print("  Recipient status label: '", cv.aud_count_label.text if cv.aud_count_label else "", "'")
	print("  Send Button disabled: ", cv.btn_send_message.disabled if cv.btn_send_message else false)
	print("  Schedule Button disabled: ", cv.btn_schedule_message.disabled if cv.btn_schedule_message else false)
	
	var pass_count = 0
	if cv.selected_individual_ids.size() == 0:
		print("  ✓ PASS: Recipient chips and IDs cleared.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Recipient IDs not cleared: ", cv.selected_individual_ids)
		
	if cv.message_body_edit and cv.message_body_edit.text == "":
		print("  ✓ PASS: Message composer text cleared.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Message text not cleared.")
		
	if cv.current_attachment_path == "":
		print("  ✓ PASS: Attached flyer/image cleared.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Attachment path not cleared.")
		
	if cv.aud_count_label and cv.aud_count_label.text.begins_with("0 Eligible Recipients"):
		print("  ✓ PASS: Recipient status reset to '0 Eligible Recipients | 0 Excluded'.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Recipient status label incorrect: ", cv.aud_count_label.text if cv.aud_count_label else "")
		
	if cv.btn_send_message and cv.btn_send_message.disabled == true:
		print("  ✓ PASS: Send Message button disabled.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Send Message button not disabled.")
		
	if cv.btn_schedule_message and cv.btn_schedule_message.disabled == true:
		print("  ✓ PASS: Schedule Message button disabled.")
		pass_count += 1
	else:
		print("  ❌ FAIL: Schedule Message button not disabled.")
		
	if pass_count == 6:
		print("\n============================================================")
		print("  SUCCESS: ALL POST-SEND COMPOSER RESET TESTS PASSED (100%)")
		print("============================================================")
		quit(0)
	else:
		print("\n❌ FAIL: ", 6 - pass_count, " reset verification checks failed.")
		quit(1)
