extends SceneTree

const CommunicationsViewScene = preload("res://app/scenes/communications_view.tscn")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _init() -> void:
	print("==========================================================================")
	print("RUNNING COMMUNICATIONS TYPING RESPONSIVENESS & REGRESSION TEST SUITE")
	print("==========================================================================")

	# Failsafe safety timer: quit after 30s so test can never hang indefinitely
	create_timer(30.0).timeout.connect(func():
		print("❌ ERROR: Test watchdog timeout expired (30s)")
		quit(1)
	)

	var comm_view = CommunicationsViewScene.instantiate()
	root.add_child(comm_view)
	await create_timer(0.2).timeout

	assert(comm_view.message_body_edit != null, "MessageBodyEdit must exist")
	var edit = comm_view.message_body_edit

	# =========================================================================
	# Test 0: Verify Initial Zero Recipients State
	# =========================================================================
	print("\n--- Test 0: Initial Zero Recipients State ---")
	print("  Audience:       ", comm_view.selected_audience_type)
	print("  Selected IDs:   ", comm_view.selected_individual_ids)
	print("  Audience Label: ", comm_view.aud_count_label.text if comm_view.aud_count_label else "N/A")
	print("  Recipients:     ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs:     ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:           ", comm_view.lbl_est_cost_val.text)
	print("  Send Disabled:  ", comm_view.btn_send_message.disabled)

	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Initial authoritative SMS count must be 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Estimator must display Recipients: 0 initially")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Estimator must display Total: 0 segments initially")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Estimator must display Est. Cost: $0.00 initially")
	assert(comm_view.btn_send_message.disabled == true, "Send button must be disabled when 0 recipients")
	print("✓ PASS 0: Initial zero-recipient state is completely verified (Recipients: 0, Total: 0, $0.00, Send Disabled).")

	# =========================================================================
	# Case 1: Rapidly type a 500-character message character-by-character
	# =========================================================================
	print("\n--- Case 1: Rapidly Type 500-Character Message ---")
	edit.text = ""
	var sample_words = "The quick brown fox jumps over the lazy dog and explores the beautiful study center with friends. "
	var target_text_500 = ""
	while target_text_500.length() < 500:
		target_text_500 += sample_words
	target_text_500 = target_text_500.substr(0, 500)

	var t0 = Time.get_ticks_usec()
	for i in range(target_text_500.length()):
		edit.text = target_text_500.substr(0, i + 1)
		comm_view._on_message_body_text_changed()
	var elapsed_500_us = Time.get_ticks_usec() - t0
	var avg_500_ms = (elapsed_500_us / 1000.0) / 500.0
	print("  Typed 500 chars continuously in %.2f ms (Average: %.4f ms / keystroke)" % [elapsed_500_us / 1000.0, avg_500_ms])
	assert(avg_500_ms < 2.0, "Average continuous keystroke latency must be under 2.0 ms (was %.4f ms)" % avg_500_ms)
	assert("500 characters" in comm_view.char_count_label.text or "500" in comm_view.lbl_est_chars_val.text, "Chars must update immediately to 500")

	# Await debounce timer for full analysis
	await create_timer(0.25).timeout
	print("  Post-debounce Segments: ", comm_view.lbl_est_segs_per_recip_val.text)
	assert("Per Recip: 4 segs" in comm_view.lbl_est_segs_per_recip_val.text, "500 GSM chars should be 4 segments per recipient")
	print("✓ PASS Case 1: Continuous 500-char typing latency is excellent (<2ms) and segments calculated accurately.")

	# =========================================================================
	# Case 2: Rapidly type up to 2,000 characters
	# =========================================================================
	print("\n--- Case 2: Rapidly Type Up To 2,000 Characters ---")
	var target_text_2000 = ""
	while target_text_2000.length() < 2000:
		target_text_2000 += sample_words
	target_text_2000 = target_text_2000.substr(0, 2000)

	t0 = Time.get_ticks_usec()
	for i in range(500, 2000):
		edit.text = target_text_2000.substr(0, i + 1)
		comm_view._on_message_body_text_changed()
	var elapsed_2000_us = Time.get_ticks_usec() - t0
	var avg_2000_ms = (elapsed_2000_us / 1000.0) / 1500.0
	print("  Typed 1,500 additional chars (total 2,000) in %.2f ms (Average: %.4f ms / keystroke)" % [elapsed_2000_us / 1000.0, avg_2000_ms])
	assert(avg_2000_ms < 2.0, "Average continuous keystroke latency must be under 2.0 ms (was %.4f ms)" % avg_2000_ms)

	await create_timer(0.25).timeout
	print("  Post-debounce 2000 chars Segments: ", comm_view.lbl_est_segs_per_recip_val.text)
	assert("Per Recip: 14 segs" in comm_view.lbl_est_segs_per_recip_val.text, "2000 GSM chars should be 14 segments per recipient")
	print("✓ PASS Case 2: 2,000-character typing responsiveness remains instantaneous throughout.")

	# =========================================================================
	# Case 3: Paste a long message
	# =========================================================================
	print("\n--- Case 3: Paste Long Message ---")
	var paste_text = "Announcement: Reminder that tomorrow's study session begins at 10 AM. Please arrive on time. ".repeat(15)
	t0 = Time.get_ticks_usec()
	edit.text = paste_text
	comm_view._on_message_body_text_changed()
	var paste_us = Time.get_ticks_usec() - t0
	print("  Pasted %d chars in %.3f ms" % [paste_text.length(), paste_us / 1000.0])
	assert(paste_us / 1000.0 < 5.0, "Pasting must be nearly instantaneous (< 5 ms)")
	await create_timer(0.25).timeout
	print("✓ PASS Case 3: Pasting long text operates with zero freeze.")

	# =========================================================================
	# Case 4: Insert Unicode characters and emoji
	# =========================================================================
	print("\n--- Case 4: Insert Unicode Characters and Emoji ---")
	var unicode_msg = "“Important Announcement — Our fall session tonight has special activities planned for all participants! 🎉”"
	t0 = Time.get_ticks_usec()
	for i in range(unicode_msg.length()):
		edit.text = unicode_msg.substr(0, i + 1)
		comm_view._on_message_body_text_changed()
	var unicode_type_us = Time.get_ticks_usec() - t0
	print("  Typed Unicode string in %.2f ms (Average: %.4f ms / keystroke)" % [unicode_type_us / 1000.0, (unicode_type_us / 1000.0) / unicode_msg.length()])
	assert((unicode_type_us / 1000.0) / unicode_msg.length() < 2.0, "Unicode typing must remain < 2 ms / keystroke")

	await create_timer(0.25).timeout
	print("  Encoding Detected: ", comm_view.lbl_est_encoding_val.text)
	assert("Unicode (UCS-2)" in comm_view.lbl_est_encoding_val.text, "Must detect Unicode encoding")

	# Test Unicode text with smart quotes only (>70 chars so optimization saves segments):
	var opt_unicode_text = "“Special Announcement — Fall Festival is starting soon! Please come join us tonight for our study center activities.”"
	edit.text = opt_unicode_text
	comm_view._on_message_body_text_changed()
	await create_timer(0.25).timeout
	print("  Optimizable Text Alert Banner: ", comm_view.lbl_est_alert_banner.text)
	assert(comm_view.lbl_est_alert_banner.visible == true, "Alert banner must show for optimizable Unicode text")
	assert(comm_view.btn_optimize_sms.visible == true, "Optimize button must be visible")
	print("✓ PASS Case 4: Unicode and emoji correctly detected, banner shown for optimizable Unicode, typing unhindered.")

	# =========================================================================
	# Case 5: Delete and replace text rapidly
	# =========================================================================
	print("\n--- Case 5: Delete and Replace Text Rapidly ---")
	t0 = Time.get_ticks_usec()
	var cur = edit.text
	while cur.length() > 0:
		cur = cur.substr(0, cur.length() - 1)
		edit.text = cur
		comm_view._on_message_body_text_changed()
	var del_us = Time.get_ticks_usec() - t0
	print("  Backspaced entire text in %.2f ms" % [del_us / 1000.0])
	assert(edit.text == "", "Editor must be cleared")
	await create_timer(0.25).timeout
	assert("Chars: 0" in comm_view.lbl_est_chars_val.text, "Chars must return to 0")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Total must be 0 segments")
	print("✓ PASS Case 5: Rapid deletion operates smoothly and returns counts to 0.")

	# =========================================================================
	# Case 6: Select and deselect recipients while composing
	# =========================================================================
	print("\n--- Case 6: Select and Deselect Recipients While Composing ---")
	edit.text = "Hello! Important study group update."
	comm_view._update_character_count()

	# Add 2 eligible recipients
	var p1 = {"id": 101, "first_name": "Alice", "last_name": "Smith", "phone": "8645550101", "eval": {"sms_ok": true}}
	var p2 = {"id": 102, "first_name": "Bob", "last_name": "Jones", "phone": "8645550102", "eval": {"sms_ok": true}}
	comm_view.current_eligible_recipients = [p1, p2]
	comm_view.invalidate_authoritative_sms_cache()
	comm_view._update_character_count()
	await create_timer(0.1).timeout

	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Est. Cost:  ", comm_view.lbl_est_cost_val.text)
	assert(comm_view.get_authoritative_sms_recipient_count() == 2, "Authoritative count must be 2")
	assert("Recipients: 2" in comm_view.lbl_est_recipients_val.text, "Must show Recipients: 2")
	assert("Total: 2 segments" in comm_view.lbl_est_total_segs_val.text, "Must show Total: 2 segments")
	assert("Est. Cost: $0.02" in comm_view.lbl_est_cost_val.text, "Must show Est. Cost: $0.02")
	print("✓ PASS Case 6: Selecting recipients dynamically updates estimator accurately.")

	# =========================================================================
	# Case 7: Clear all recipients
	# =========================================================================
	print("\n--- Case 7: Clear All Recipients ---")
	comm_view.current_eligible_recipients.clear()
	comm_view.invalidate_authoritative_sms_cache()
	comm_view._update_character_count()
	comm_view._update_composer_validation()
	await create_timer(0.1).timeout

	print("  Recipients: ", comm_view.lbl_est_recipients_val.text)
	print("  Total Segs: ", comm_view.lbl_est_total_segs_val.text)
	print("  Cost:       ", comm_view.lbl_est_cost_val.text)
	print("  Send Disab: ", comm_view.btn_send_message.disabled)

	assert(comm_view.get_authoritative_sms_recipient_count() == 0, "Authoritative count must be 0")
	assert("Recipients: 0" in comm_view.lbl_est_recipients_val.text, "Must show Recipients: 0")
	assert("Total: 0 segments" in comm_view.lbl_est_total_segs_val.text, "Must show Total: 0 segments")
	assert("Est. Cost: $0.00" in comm_view.lbl_est_cost_val.text, "Must show Est. Cost: $0.00")
	assert(comm_view.btn_send_message.disabled == true, "Sending must be disabled when 0 recipients")
	print("✓ PASS Case 7: Clearing recipients correctly sets Recipients: 0, Total: 0, $0.00 and disables sending.")

	# =========================================================================
	# Case 8: Switch between SMS Text, Email, and Both
	# =========================================================================
	print("\n--- Case 8: Switch Delivery Channels ---")
	if comm_view.person_list.size() > 0:
		comm_view._on_individual_selected(1)
	else:
		comm_view.person_list = [p1]
		comm_view.selected_individual_ids = [101]
		comm_view._update_audience_resolution()
	await create_timer(0.1).timeout

	# Channel 1: Email
	comm_view.channel_dropdown.select(1)
	comm_view._on_channel_selected(1)
	await create_timer(0.1).timeout
	assert(comm_view.sms_estimator_card.visible == false, "Estimator must hide on Email")

	# Channel 0: SMS Text
	comm_view.channel_dropdown.select(0)
	comm_view._on_channel_selected(0)
	await create_timer(0.1).timeout
	assert(comm_view.sms_estimator_card.visible == true, "Estimator must reappear on SMS Text")
	assert(comm_view.get_authoritative_sms_recipient_count() >= 1, "Must have authoritative recipient")
	assert("Recipients: 1" in comm_view.lbl_est_recipients_val.text, "Estimator retains accurate recipient count")
	print("✓ PASS Case 8: Switching channels updates visibility and maintains estimator accuracy.")

	# =========================================================================
	# Case 9: Open and apply SMS optimization
	# =========================================================================
	print("\n--- Case 9: Open and Apply SMS Optimization ---")
	edit.text = "“Special Announcement — Fall Festival is starting soon! Join us tonight for fellowship and activities.”"
	comm_view._update_character_count()
	await create_timer(0.1).timeout

	assert(comm_view.btn_optimize_sms.visible == true, "Optimize button must be visible for smart quotes/dash")
	comm_view._on_btn_optimize_sms_pressed()
	await create_timer(0.1).timeout

	var dlg = null
	for child in comm_view.get_children():
		if child is ConfirmationDialog and child.title == "Optimize Message for SMS":
			dlg = child
			break
	assert(dlg != null, "Optimization dialog must open")
	dlg.confirmed.emit()
	await create_timer(0.1).timeout

	print("  Optimized Text in Editor: ", edit.text)
	assert(not "“" in edit.text and not "”" in edit.text and not "—" in edit.text, "Quotes and dashes must be GSM-7 compatible")
	assert(comm_view.btn_optimize_sms.disabled == true, "Optimize button must show disabled '✓ SMS Optimized'")
	print("✓ PASS Case 9: SMS optimization preview and apply works cleanly.")

	# =========================================================================
	# Case 10: Verify spellchecking and normal editing behavior
	# =========================================================================
	print("\n--- Case 10: Verify Spellchecking and Normal Editing ---")
	edit.text = "We definately want everyone to come."
	var high = edit.syntax_highlighter
	assert(high != null, "Syntax highlighter must be attached to message_body_edit")
	var highlight_dict = high._get_line_syntax_highlighting(0)
	print("  Highlight dict keys: ", highlight_dict.keys())
	# Column 3 is the start of 'definately'
	assert(highlight_dict.has(3), "Misspelled word 'definately' must be highlighted starting at col 3")

	# Verify context menu suggestions exist on right-click
	var issues = SpellingAssistanceHelperScript.check_text(edit.text, true)
	assert(issues.size() == 1, "Must find exactly 1 issue")
	assert(issues[0]["suggestions"].has("definitely"), "Must suggest 'definitely' for 'definately'")
	print("✓ PASS Case 10: Spellchecking highlights errors natively and generates suggestions for context menu.")

	print("\n==========================================================================")
	print("SUCCESS: ALL 10 COMMUNICATIONS TYPING RESPONSIVENESS CASES PASSED CLEANLY!")
	print("==========================================================================")
	quit(0)
