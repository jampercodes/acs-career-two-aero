# generalupgrades.gd
extends Node
class_name GeneralUpgrades

# Stock weight (from parent car)
var stock_total_mass: float = 0.0

# WEIGHT REDUCTION PARTS
const WEIGHT_PARTS = [
	# Stage 1 - Street upgrades
	{"id": 801, "name": "Lightweight Carpets", "stage": 1, "super_type": 801, "mult": 0.990, "cost": 100, "desc": "Small Weight Reduction"},
	{"id": 802, "name": "Lightweight Interior Panels", "stage": 1, "super_type": 802, "mult": 0.990, "cost": 250, "desc": "Small Weight Reduction"},
	
	# Stage 2 - Sport upgrades
	{"id": 803, "name": "Lightweight Windows", "stage": 2, "super_type": 803, "mult": 0.985, "cost": 1000, "desc": "Medium Weight Reduction"},
	{"id": 804, "name": "Lightweight Seats", "stage": 2, "super_type": 804, "mult": 0.985, "cost": 1000, "desc": "Medium Weight Reduction"},
	
	# Stage 3 - Race upgrades
	{"id": 805, "name": "Lightweight Doors", "stage": 3, "super_type": 805, "mult": 0.975, "cost": 2500, "desc": "Large Weight Reduction"},
	{"id": 806, "name": "Foam Filled Interior", "stage": 3, "super_type": 806, "mult": 0.985, "cost": 1000, "desc": "Medium Weight Reduction"},
]

# Currently installed weight reduction parts (by super_type)
var installed_parts: Dictionary = {}  # super_type -> part_id


func load_from_data_dir(data_dir: String) -> void:
	# Weight reduction doesn't have its own INI file
	# It reads from car.ini [BASIC] TOTALMASS which is already loaded in Car.gd
	
	# Load tuner metadata (for weight reduction parts)
	var car_dir := data_dir.get_base_dir()
	_load_tuner_metadata(car_dir)


func store_stock_values():
	var parent_car: Car = get_parent() as Car
	if parent_car == null:
		return

	var orig_id = parent_car.original_id
	if orig_id == "":
		return

	var carloader = get_tree().root.get_node("Carloader")
	if carloader == null or not carloader.has_method("get_car"):
		return

	var orig_car = carloader.get_car(orig_id)
	if orig_car == null:
		return

	# Store stock weight from original car
	stock_total_mass = orig_car.total_mass


# ============================================================================
# WEIGHT REDUCTION PARTS
# ============================================================================

# Get part definition by ID
func _get_part_by_id(part_id: int) -> Dictionary:
	for part in WEIGHT_PARTS:
		if part["id"] == part_id:
			return part
	return {}


# Get currently installed part in a specific upgrade line
func _get_installed_part_in_line(super_type: int) -> Dictionary:
	if installed_parts.has(super_type):
		return _get_part_by_id(installed_parts[super_type])
	return {}


# Calculate total weight multiplier from all installed parts
func _calculate_total_multiplier() -> float:
	var total_mult := 1.0
	
	for super_type in installed_parts.keys():
		var part_id = installed_parts[super_type]
		var part = _get_part_by_id(part_id)
		if part.is_empty():
			continue
		
		total_mult *= part["mult"]
	
	return total_mult


# Get current weight (stock × all multipliers)
func get_current_weight() -> float:
	if stock_total_mass <= 0.0:
		var parent_car: Car = get_parent() as Car
		if parent_car:
			return parent_car.total_mass
		return 0.0
	
	return stock_total_mass * _calculate_total_multiplier()


# Check if a part is currently installed
func is_part_installed(part_id: int) -> bool:
	return installed_parts.values().has(part_id)


# Check if any part in the same upgrade line is installed
func has_part_in_line(super_type: int) -> bool:
	return installed_parts.has(super_type)


# Get all available upgrade options
func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	
	for part in WEIGHT_PARTS:
		var part_id: int = part["id"]
		var super_type: int = part["super_type"]
		var installed = is_part_installed(part_id)
		var current_in_line = _get_installed_part_in_line(super_type)
		
		var display_name := "[Stage %d] %s" % [part["stage"], part["name"]]
		
		if installed:
			display_name = "✓ " + display_name
		elif not current_in_line.is_empty():
			display_name += " (replaces %s)" % current_in_line["name"]
		
		options.append({
			"id": part_id,
			"name": part["name"],
			"stage": part["stage"],
			"super_type": super_type,
			"mult": part["mult"],
			"cost": part["cost"],
			"desc": part["desc"],
			"display_name": display_name,
			"installed": installed,
			"replaces_id": current_in_line.get("id", 0)
		})
	
	return options


# Apply a weight reduction upgrade
func apply_weight_upgrade(part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		printerr("Invalid weight reduction part ID: ", part_id)
		return false
	
	var super_type: int = part["super_type"]
	
	# Install part (replacing any existing part in the same line)
	installed_parts[super_type] = part_id
	
	# Update car's total_mass
	_apply_weight_to_car()
	
	print("Installed weight reduction part: %s (ID %d)" % [part["name"], part_id])
	
	return true


# Remove a specific weight reduction upgrade
func remove_weight_upgrade(part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return false
	
	var super_type: int = part["super_type"]
	
	if not installed_parts.has(super_type):
		return false
	
	if installed_parts[super_type] != part_id:
		return false
	
	# Remove this part
	installed_parts.erase(super_type)
	
	# Update car's total_mass
	_apply_weight_to_car()
	
	print("Removed weight reduction part: %s (ID %d)" % [part["name"], part_id])
	return true


# Revert to stock weight (remove all upgrades)
func revert_to_stock() -> void:
	installed_parts.clear()
	
	# Reset car weight to stock
	_apply_weight_to_car()
	
	print("Reverted weight to stock configuration")


# Can we remove any upgrades?
func can_remove_upgrades() -> bool:
	return not installed_parts.is_empty()


# Apply weight to car's total_mass
func _apply_weight_to_car() -> void:
	var parent_car: Car = get_parent() as Car
	if parent_car == null:
		return
	
	if stock_total_mass <= 0.0:
		return
	
	var new_weight := get_current_weight()
	parent_car.total_mass = new_weight


# Preview what weight would be with a specific upgrade
func get_preview_weight(part_id: int) -> float:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return get_current_weight()
	
	var super_type: int = part["super_type"]
	
	# Create temporary installed_parts dict with this upgrade
	var temp_parts := installed_parts.duplicate()
	temp_parts[super_type] = part_id
	
	# Calculate multiplier
	var total_mult := 1.0
	for st in temp_parts.keys():
		var pid = temp_parts[st]
		var p = _get_part_by_id(pid)
		if p.is_empty():
			continue
		total_mult *= p["mult"]
	
	return stock_total_mass * total_mult


# Get tuner metadata for saving
func get_tuner_metadata() -> Dictionary:
	return {
		"installed_parts": installed_parts,
		"stock_total_mass": stock_total_mass,
	}


# Load tuner metadata from ui_car.json
func _load_tuner_metadata(car_dir: String) -> void:
	var ui_path := car_dir + "/ui/ui_car.json"
	if not FileAccess.file_exists(ui_path):
		return
	
	var f := FileAccess.open(ui_path, FileAccess.READ)
	if f == null:
		return
	
	var text := f.get_as_text()
	f.close()
	
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return
	
	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return
	
	if not root.has("js_tuner_weight"):
		return
	
	var jt_weight = root["js_tuner_weight"]
	if typeof(jt_weight) != TYPE_DICTIONARY:
		return
	
	# Load installed parts
	if jt_weight.has("installed_parts") and typeof(jt_weight["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in jt_weight["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(jt_weight["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if jt_weight.has("stock_total_mass"):
		stock_total_mass = float(jt_weight["stock_total_mass"])
	
	# Apply weight to car
	_apply_weight_to_car()


# Load tuner metadata (public version for external calls)
func load_tuner_metadata(meta: Dictionary) -> void:
	if meta.has("installed_parts") and typeof(meta["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in meta["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(meta["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if meta.has("stock_total_mass"):
		stock_total_mass = float(meta["stock_total_mass"])
	
	# Apply weight to car
	_apply_weight_to_car()


func get_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	
	var current_weight := get_current_weight()
	
	lines.append("Current weight: %.0f kg" % current_weight)
	
	if stock_total_mass > 0.0:
		lines.append("Stock weight: %.0f kg" % stock_total_mass)
		
		var weight_saved := stock_total_mass - current_weight
		if weight_saved > 0.0:
			var percent_reduction := (weight_saved / stock_total_mass) * 100.0
			lines.append("Weight saved: %.0f kg (-%.1f%%)" % [weight_saved, percent_reduction])
	
	# List installed upgrades
	if not installed_parts.is_empty():
		lines.append("\nInstalled Weight Reduction:")
		
		# Group by stage
		var by_stage: Dictionary = {}
		for super_type in installed_parts.keys():
			var part_id = installed_parts[super_type]
			var part = _get_part_by_id(part_id)
			if part.is_empty():
				continue
			
			var stage: int = part["stage"]
			if not by_stage.has(stage):
				by_stage[stage] = []
			by_stage[stage].append(part)
		
		# Display by stage
		for stage in [1, 2, 3]:
			if not by_stage.has(stage):
				continue
			
			for part in by_stage[stage]:
				lines.append("  • %s (-%.1f%%)" % [
					part["name"],
					(1.0 - part["mult"]) * 100.0
				])
		
		var total_mult := _calculate_total_multiplier()
		lines.append("  Total reduction: -%.1f%%" % [(1.0 - total_mult) * 100.0])
	
	return lines
