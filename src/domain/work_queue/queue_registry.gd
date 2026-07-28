class_name QueueRegistry
extends RefCounted

## Canonical Registry of Production V1 Work Queue Definitions.
## Provides a single, centralized source of truth for all Action Center work queues.

static func get_registry() -> Dictionary:
	return {
		"overdue_callbacks": {
			"queue_id": "overdue_callbacks",
			"title": "Overdue Callbacks",
			"description": "Voicemails and callback requests past their due date",
			"target_view": "communications",
			"required_permission": "communications.manage",
			"urgency": "critical", # Red accent
			"count_sql": "SELECT COUNT(*) AS cnt FROM voicemails WHERE status = 'new' AND due_date IS NOT NULL AND due_date != '' AND due_date < date('now', 'localtime');",
			"record_sql": "SELECT id, voicemail_uuid, caller_phone, caller_name, transcription, due_date, status, created_at FROM voicemails WHERE status = 'new' AND due_date IS NOT NULL AND due_date != '' AND due_date < date('now', 'localtime') ORDER BY due_date ASC;",
			"completion_sql": "UPDATE voicemails SET status = 'completed' WHERE id = ?;",
			"primary_button": "Start Queue",
			"queue_mode_supported": true
		},
		"unanswered_messages": {
			"queue_id": "unanswered_messages",
			"title": "Unanswered Messages (>2h)",
			"description": "Inbound voicemails older than 2 hours awaiting initial staff response",
			"target_view": "communications",
			"required_permission": "communications.view",
			"urgency": "urgent", # Amber accent
			"count_sql": "SELECT COUNT(*) AS cnt FROM voicemails WHERE status = 'new' AND created_at <= datetime('now', '-2 hours');",
			"record_sql": "SELECT id, voicemail_uuid, caller_phone, caller_name, transcription, status, created_at FROM voicemails WHERE status = 'new' AND created_at <= datetime('now', '-2 hours') ORDER BY created_at ASC;",
			"completion_sql": "UPDATE voicemails SET status = 'completed' WHERE id = ?;",
			"primary_button": "Reply to Messages",
			"queue_mode_supported": true
		},
		"registrations_awaiting_review": {
			"queue_id": "registrations_awaiting_review",
			"title": "Registrations Awaiting Review",
			"description": "Newly created constituent registrations pending administrative review",
			"target_view": "people",
			"required_permission": "people.view",
			"urgency": "normal", # Blue accent
			"count_sql": "SELECT COUNT(*) AS cnt FROM people WHERE review_status = 'pending';",
			"record_sql": "SELECT id, person_uuid, human_id, first_name, last_name, phone, email, primary_role, created_at FROM people WHERE review_status = 'pending' ORDER BY created_at ASC;",
			"completion_sql": "UPDATE people SET review_status = 'reviewed', reviewed_at = datetime('now') WHERE id = ?;",
			"primary_button": "Review Registrations",
			"queue_mode_supported": true
		},
		"uncovered_sessions": {
			"queue_id": "uncovered_sessions",
			"title": "Uncovered Sessions (Next 14d)",
			"description": "Scheduled sessions over the next 14 days lacking assigned shift coverage",
			"target_view": "schedules",
			"required_permission": "schedules.manage",
			"urgency": "resource", # Purple accent
			"count_sql": "SELECT COUNT(*) AS cnt FROM sessions s LEFT JOIN schedule_entries se ON (se.shift_date = s.date_text AND se.area = s.room_location) WHERE s.date_text BETWEEN date('now') AND date('now', '+14 days') AND s.is_active = 1 AND se.id IS NULL;",
			"record_sql": "SELECT s.id, s.title, s.date_text, s.start_time, s.end_time, s.room_location FROM sessions s LEFT JOIN schedule_entries se ON (se.shift_date = s.date_text AND se.area = s.room_location) WHERE s.date_text BETWEEN date('now') AND date('now', '+14 days') AND s.is_active = 1 AND se.id IS NULL ORDER BY s.date_text ASC, s.start_time ASC;",
			"completion_sql": "UPDATE schedule_entries SET notes = 'covered' WHERE id = ?;",
			"primary_button": "Review Staffing",
			"queue_mode_supported": true
		},
		"pending_member_cards": {
			"queue_id": "pending_member_cards",
			"title": "Pending Member Cards",
			"description": "Constituent membership cards waiting in the batch print queue",
			"target_view": "card_print_queue",
			"required_permission": "credentials.manage",
			"urgency": "normal", # Blue accent
			"count_sql": "SELECT COUNT(*) AS cnt FROM card_print_queue q WHERE q.status = 'pending';",
			"record_sql": "SELECT q.id, q.queue_uuid, q.person_id, q.person_uuid, q.status, q.added_at, p.first_name, p.last_name, p.primary_role FROM card_print_queue q JOIN people p ON (q.person_id = p.id) WHERE q.status = 'pending' ORDER BY q.added_at ASC;",
			"completion_sql": "UPDATE card_print_queue SET status = 'printed', printed_at = datetime('now') WHERE id = ?;",
			"primary_button": "Issue Passes",
			"queue_mode_supported": true
		}
	}

static func get_definition(queue_id: String) -> Dictionary:
	var reg = get_registry()
	return reg.get(queue_id, {})

static func has_definition(queue_id: String) -> bool:
	return get_registry().has(queue_id)
