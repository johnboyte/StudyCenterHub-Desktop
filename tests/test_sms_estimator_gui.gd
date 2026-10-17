extends SceneTree

const AppShellScene = preload("res://app/scenes/app_shell.tscn")

func _init() -> void:
	print("==========================================================================")
	print("RUNNING FOCUSED TEST: SMS ESTIMATOR & OPTIMIZER GUI INTEGRATION")
	print("==========================================================================")

	create_timer(0.2).timeout.connect(func():
		var shell = AppShellScene.instantiate()
		root.add_child(shell)

		create_timer(0.3).timeout.connect(func():
			shell.switch_view("communications")

			create_timer(0.5).timeout.connect(func():
				var comms = shell.current_view_node
				if not comms:
					print("❌ ERROR: current_view_node is NULL!")
					quit(1)
					return

				print("✓ View loaded: ", comms.name)

				# Check estimator card
				assert(comms.sms_estimator_card != null, "sms_estimator_card must not be null")
				assert(comms.btn_optimize_sms != null, "btn_optimize_sms must not be null")
				print("✓ Estimator card and optimize button nodes exist.")

				# Test 1: Standard GSM text
				comms.message_body_edit.text = "Hello students, study session tomorrow at 6 PM!"
				comms._update_character_count()
				print("✓ Test 1 GSM Text - Char count label: ", comms.char_count_label.text)
				print("  - Encoding: ", comms.lbl_est_encoding_val.text)
				print("  - Total: ", comms.lbl_est_total_segs_val.text)
				print("  - Cost: ", comms.lbl_est_cost_val.text)
				assert("GSM-7" in comms.lbl_est_encoding_val.text, "Encoding must be GSM-7")
				assert(comms.lbl_est_alert_banner.visible == false, "Banner should not be visible for clean GSM text")

				# Test 2: Unicode multi-segment text with smart quotes and em dash
				comms.message_body_edit.text = "Important Reminder — Our weekly “Real Life” Study Center session is tonight at 6:30 PM! Please bring your books and notes. We’re excited to see all of you there, and snacks will be provided for everyone who attends! Don’t forget to check in when you arrive."
				comms._update_character_count()
				print("\n✓ Test 2 Unicode Text - Char count label: ", comms.char_count_label.text)
				print("  - Encoding: ", comms.lbl_est_encoding_val.text)
				print("  - Total: ", comms.lbl_est_total_segs_val.text)
				print("  - Cost: ", comms.lbl_est_cost_val.text)
				print("  - Alert banner visible: ", comms.lbl_est_alert_banner.visible)
				assert("Unicode" in comms.lbl_est_encoding_val.text, "Encoding must be Unicode")
				assert(comms.btn_optimize_sms.visible == true, "Optimize button must be visible for Unicode text")
				assert(comms.lbl_est_alert_banner.visible == true, "Banner should be visible for multi-segment Unicode text")

				# Test 3: Perform optimize action and verify ConfirmationDialog & Readability Styling
				comms._on_btn_optimize_sms_pressed()
				var modal_found = false
				for child in comms.get_children():
					if child is ConfirmationDialog:
						modal_found = true
						print("✓ Test 3: Optimizer Preview ConfirmationDialog successfully created: ", child.title)
						var prev_edit: TextEdit = null
						for node in child.find_children("*", "TextEdit", true, false):
							prev_edit = node
							break
						assert(prev_edit != null, "TextEdit for optimized preview must exist in modal")
						var f_col = prev_edit.get_theme_color("font_color")
						var ro_col = prev_edit.get_theme_color("font_readonly_color")
						var sel_col = prev_edit.get_theme_color("font_selected_color")
						print("  - Preview font color: ", f_col, " (White: ", f_col == Color(1, 1, 1, 1), ")")
						print("  - Preview readonly color: ", ro_col, " (White: ", ro_col == Color(1, 1, 1, 1), ")")
						print("  - Preview selected color: ", sel_col, " (White: ", sel_col == Color(1, 1, 1, 1), ")")
						assert(f_col == Color(1, 1, 1, 1), "Preview text font_color must be white (#FFFFFF)")
						assert(ro_col == Color(1, 1, 1, 1), "Preview text font_readonly_color must be white (#FFFFFF)")
						assert(sel_col == Color(1, 1, 1, 1), "Preview text font_selected_color must be white (#FFFFFF)")
						var sb_norm = prev_edit.get_theme_stylebox("normal")
						assert(sb_norm is StyleBoxFlat, "Preview text background must be StyleBoxFlat")
						assert(sb_norm.bg_color.v < 0.35, "Preview text background must remain dark")
						print("  - Preview dark background verified: ", sb_norm.bg_color)
						child.queue_free()
						break
				assert(modal_found, "Optimizer modal should be created")

				# Test 4: Verify SMS-friendly direct replacement
				var opt_res = comms.SMSEncodingHelperScript.get_optimized_text(comms.message_body_edit.text, 27)
				comms.message_body_edit.text = opt_res["optimized_text"]
				comms._update_character_count()
				print("\n✓ Test 4 After Optimization:")
				print("  - Cleaned text: ", comms.message_body_edit.text)
				print("  - Encoding: ", comms.lbl_est_encoding_val.text)
				print("  - Total: ", comms.lbl_est_total_segs_val.text)
				assert("GSM-7" in comms.lbl_est_encoding_val.text, "Post-optimization encoding must be GSM-7")
				assert(comms.lbl_est_alert_banner.visible == false, "Alert banner must be hidden after optimization")

				# Test 5: Verify Individual Send Confirmation Dialog shows estimated cost & segments
				var test_recip = {"id": 1, "first_name": "Alex", "last_name": "Smith", "phone": "8645551234"}
				comms._show_individual_send_confirmation_dialog(test_recip, "SMS Text", "Reminder: Session tomorrow!")
				var ind_backdrop = null
				for child in comms.get_children():
					if child is ColorRect:
						ind_backdrop = child
						break
				assert(ind_backdrop != null, "Individual send confirmation backdrop must exist")
				var found_ind_cost_label = false
				for lbl in ind_backdrop.find_children("*", "Label", true, false):
					if "Est. SMS Segments" in lbl.text and "Est. Cost:" in lbl.text:
						found_ind_cost_label = true
						print("\n✓ Test 5 Individual Send Confirmation Dialog verified:")
						print("  - Found Cost Label: ", lbl.text)
						break
				assert(found_ind_cost_label, "Individual confirmation dialog must display estimated segments and cost")
				ind_backdrop.free()

				# Test 6: Verify Group Send Confirmation Dialog shows estimated cost & segments
				comms._show_group_send_confirmation_dialog("SMS Text", "Group Announcement: Session tonight!")
				var grp_backdrop = null
				for child in comms.get_children():
					if child is ColorRect:
						grp_backdrop = child
						break
				assert(grp_backdrop != null, "Group send confirmation backdrop must exist")
				var found_grp_cost_label = false
				for lbl in grp_backdrop.find_children("*", "Label", true, false):
					if "Est. Segments" in lbl.text and "Est. Cost:" in lbl.text:
						found_grp_cost_label = true
						print("\n✓ Test 6 Group Send Confirmation Dialog verified:")
						print("  - Found Cost Label: ", lbl.text)
						break
				assert(found_grp_cost_label, "Group confirmation dialog must display estimated segments and cost")
				grp_backdrop.free()

				# Test 7: Verify Drag-and-Drop Image attachment handling
				var img_path = "/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/scratch/khalil_cur.png"
				if FileAccess.file_exists(img_path):
					comms._set_attached_image(img_path)
					assert(comms.current_attachment_path == img_path, "Attachment path must be updated")
					assert(comms.attachment_preview_box.visible == true, "Attachment preview must be visible")
					print("\n✓ Test 7 Image Attachment Drag-and-Drop verified:")
					print("  - Attached file: ", comms.current_attachment_path)
					print("  - Preview box visible: ", comms.attachment_preview_box.visible)
					comms._clear_attached_image()
					assert(comms.current_attachment_path == "", "Attachment path must be cleared")
					assert(comms.attachment_preview_box.visible == false, "Attachment preview must be hidden")
					print("  - Attachment cleared successfully.")

				# Test 8: Verify 0 recipients display & dynamic recipient selection updates
				comms.selected_individual_ids.clear()
				comms.current_eligible_recipients.clear()
				comms.message_body_edit.text = "Hello reminder message!"
				comms._update_character_count()
				print("\n✓ Test 8 Zero Recipients Display:")
				print("  - Recipients Label: ", comms.lbl_est_recipients_val.text)
				print("  - Total Segments Label: ", comms.lbl_est_total_segs_val.text)
				print("  - Cost Label: ", comms.lbl_est_cost_val.text)
				print("  - Per Recip Label: ", comms.lbl_est_segs_per_recip_val.text)
				assert("Recipients: 0" in comms.lbl_est_recipients_val.text, "Must show Recipients: 0 when 0 recipients")
				assert("Total: 0 segments" in comms.lbl_est_total_segs_val.text, "Must show Total: 0 segments when 0 recipients")
				assert("Est. Cost: $0.00" in comms.lbl_est_cost_val.text, "Must show Est. Cost: $0.00 when 0 recipients")
				assert("Per Recip: 1 seg" in comms.lbl_est_segs_per_recip_val.text, "Per-recipient estimate must remain visible")

				# Select 1 individual recipient
				var mock_elig = {"id": 1, "first_name": "Test", "last_name": "User", "phone": "8645551234", "eval": {"sms_ok": true}}
				comms.current_eligible_recipients.append(mock_elig)
				comms._update_character_count()
				print("\n✓ Test 8 After Selecting 1 Recipient:")
				print("  - Recipients Label: ", comms.lbl_est_recipients_val.text)
				print("  - Total Segments Label: ", comms.lbl_est_total_segs_val.text)
				print("  - Cost Label: ", comms.lbl_est_cost_val.text)
				assert("Recipients: 1" in comms.lbl_est_recipients_val.text, "Must show Recipients: 1")
				assert("Total: 1 segment" in comms.lbl_est_total_segs_val.text, "Must show Total: 1 segment")
				assert(not "Est. Cost: $0.00" in comms.lbl_est_cost_val.text, "Cost must be > $0.00")

				# Deselect back to 0
				comms.current_eligible_recipients.clear()
				comms._update_character_count()
				print("\n✓ Test 8 After Deselecting to 0:")
				print("  - Recipients Label: ", comms.lbl_est_recipients_val.text)
				print("  - Total Segments Label: ", comms.lbl_est_total_segs_val.text)
				print("  - Cost Label: ", comms.lbl_est_cost_val.text)
				assert("Recipients: 0" in comms.lbl_est_recipients_val.text, "Must return to Recipients: 0")
				assert("Total: 0 segments" in comms.lbl_est_total_segs_val.text, "Must return to Total: 0 segments")
				assert("Est. Cost: $0.00" in comms.lbl_est_cost_val.text, "Must return to Est. Cost: $0.00")

				print("\n==========================================================================")
				print("ALL SMS ESTIMATOR & OPTIMIZER GUI INTEGRATION TESTS PASSED CLEANLY!")
				print("==========================================================================")
				quit(0)
			)
		)
	)
