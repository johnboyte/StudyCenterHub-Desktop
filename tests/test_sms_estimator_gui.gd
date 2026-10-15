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

				# Test 3: Perform optimize action and verify ConfirmationDialog
				comms._on_btn_optimize_sms_pressed()
				var modal_found = false
				for child in comms.get_children():
					if child is ConfirmationDialog:
						modal_found = true
						print("✓ Test 3: Optimizer Preview ConfirmationDialog successfully created: ", child.title)
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

				print("\n==========================================================================")
				print("ALL SMS ESTIMATOR & OPTIMIZER GUI INTEGRATION TESTS PASSED CLEANLY!")
				print("==========================================================================")
				quit(0)
			)
		)
	)
