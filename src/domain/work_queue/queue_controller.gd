class_name QueueController
extends RefCounted

## Lightweight Singleton Manager for Action Center Work Queues.
## Handles query execution, queue item navigation, status completion, and count tracking.

const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

signal count_updated(queue_id: String, new_count: int)
signal item_completed(queue_id: String, item_id: Variant, remaining_count: int)

var db = null
var active_queue_id: String = ""
var active_items: Array = []
var current_index: int = -1

func _init(db_instance = null) -> void:
	if db_instance:
		db = db_instance
	else:
		db = SQLiteDatabaseScript.new()

func get_queue_count(queue_id: String) -> int:
	if queue_id == "uncovered_center_hours":
		return fetch_queue_records("uncovered_center_hours").size()
	var def = QueueRegistryScript.get_definition(queue_id)
	if def.is_empty() or not db:
		return 0

	var res = db.execute(def["count_sql"])
	if res.get("success", false) and res.get("data", []).size() > 0:
		return int(res["data"][0].get("cnt", 0))
	return 0

func fetch_queue_records(queue_id: String) -> Array:
	if queue_id == "uncovered_center_hours":
		return QueueRegistryScript.get_uncovered_center_hours_records(db)
	var def = QueueRegistryScript.get_definition(queue_id)
	if def.is_empty() or not db:
		return []

	var res = db.execute(def["record_sql"])
	if res.get("success", false):
		return res.get("data", [])
	return []

func start_queue(queue_id: String) -> bool:
	if not QueueRegistryScript.has_definition(queue_id):
		return false
	
	active_queue_id = queue_id
	active_items = fetch_queue_records(queue_id)
	if active_items.size() > 0:
		current_index = 0
	else:
		current_index = -1
	return true

func get_current_item() -> Dictionary:
	if active_items.size() > 0 and current_index >= 0 and current_index < active_items.size():
		return active_items[current_index]
	return {}

func get_remaining_count() -> int:
	return active_items.size()

func next_item() -> Dictionary:
	if active_items.size() == 0:
		current_index = -1
		return {}
	current_index = (current_index + 1) % active_items.size()
	return get_current_item()

func prev_item() -> Dictionary:
	if active_items.size() == 0:
		current_index = -1
		return {}
	current_index = (current_index - 1 + active_items.size()) % active_items.size()
	return get_current_item()

func complete_current_item(bind_params: Array = []) -> bool:
	if active_queue_id.is_empty() or active_items.size() == 0 or current_index < 0:
		return false
	
	var item = get_current_item()
	var def = QueueRegistryScript.get_definition(active_queue_id)
	if item.is_empty() or def.is_empty():
		return false
	
	var item_id = item.get("id", null)
	var params = bind_params.duplicate()
	if params.is_empty() and item_id != null:
		params = [item_id]
	
	var res = db.execute(def["completion_sql"], params)
	if res.get("success", false):
		active_items.remove_at(current_index)
		if active_items.size() == 0:
			current_index = -1
		elif current_index >= active_items.size():
			current_index = 0
		
		var new_count = get_queue_count(active_queue_id)
		item_completed.emit(active_queue_id, item_id, active_items.size())
		count_updated.emit(active_queue_id, new_count)
		return true
	return false

func end_session() -> void:
	active_queue_id = ""
	active_items.clear()
	current_index = -1
