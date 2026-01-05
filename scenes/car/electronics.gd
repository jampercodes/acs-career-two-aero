# electronics.gd
extends Node
class_name Electronics

# ABS
var abs_present: int = 0
var abs_active: int = 0
var abs_slip_ratio_limit: float = 0.0
var abs_rate_hz: float = 0.0
var abs_curve_file: String = ""
var abs_curve: Array = []  # Array of [int level, float slip]

# Traction Control
var tc_present: int = 0
var tc_active: int = 0
var tc_slip_ratio_limit: float = 0.0
var tc_rate_hz: float = 0.0
var tc_min_speed_kmh: float = 0.0
var tc_curve_file: String = ""
var tc_curve: Array = []  # Array of [int level, float slip]

# Stock (from parent/original)
var stock_abs_present: int = 0
var stock_abs_active: int = 0
var stock_abs_slip_ratio_limit: float = 0.0
var stock_abs_rate_hz: float = 0.0
var stock_abs_curve_file: String = ""

var stock_tc_present: int = 0
var stock_tc_active: int = 0
var stock_tc_slip_ratio_limit: float = 0.0
var stock_tc_rate_hz: float = 0.0
var stock_tc_min_speed_kmh: float = 0.0
var stock_tc_curve_file: String = ""

var proposed_abs_present: int = 0
var proposed_abs_active: int = 0
var proposed_tc_present: int = 0
var proposed_tc_active: int = 0

# ECU/FUEL SYSTEM PARTS
const ECU_PARTS = [
	# Stage 1 - Street upgrades
	{"id": 201, "name": "Fuel Pressure Regulator", "stage": 1, "super_type": 201, "mult": 1.14, "cost": 250, "desc": "Medium Engine Torque Increase"},
	{"id": 202, "name": "Fuel Rail", "stage": 1, "super_type": 202, "mult": 1.04, "cost": 250, "desc": "Small Engine Torque Increase"},
	{"id": 203, "name": "Fuel Filter", "stage": 1, "super_type": 203, "mult": 1.04, "cost": 250, "desc": "Small Engine Torque Increase"},
	
	# Stage 2 - Sport upgrades
	{"id": 204, "name": "Performance Chip", "stage": 2, "super_type": 204, "mult": 1.20, "cost": 1000, "desc": "Large Engine Torque Increase"},
	{"id": 205, "name": "High Flow Fuel Pump", "stage": 2, "super_type": 205, "mult": 1.055, "cost": 500, "desc": "Small Engine Torque Increase"},
	
	# Stage 3 - Race upgrades
	{"id": 206, "name": "Engine Management Unit", "stage": 3, "super_type": 204, "mult": 1.28, "cost": 3500, "desc": "Extreme Engine Torque Increase"},
	{"id": 207, "name": "Fuel Injectors", "stage": 3, "super_type": 206, "mult": 1.06, "cost": 1000, "desc": "Medium Engine Torque Increase"},
]

# Currently installed ECU/fuel parts (by super_type)
var installed_parts: Dictionary = {}  # super_type -> part_id

# Stock ECU power baseline
var stock_ecu_power: float = 0.0


func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/electronics.ini")

	# ABS
	if ini.has("ABS"):
		var a = ini["ABS"]
		abs_slip_ratio_limit = IniParser.get_float(a, "SLIP_RATIO_LIMIT", 0.0)
		abs_present = IniParser.get_int(a, "PRESENT", 0)
		abs_active = IniParser.get_int(a, "ACTIVE", 0)
		abs_rate_hz = IniParser.get_float(a, "RATE_HZ", 0.0)
		abs_curve_file = IniParser.get_str(a, "CURVE", "")

	# TC
	if ini.has("TRACTION_CONTROL"):
		var t = ini["TRACTION_CONTROL"]
		tc_slip_ratio_limit = IniParser.get_float(t, "SLIP_RATIO_LIMIT", 0.0)
		tc_present = IniParser.get_int(t, "PRESENT", 0)
		tc_active = IniParser.get_int(t, "ACTIVE", 0)
		tc_rate_hz = IniParser.get_float(t, "RATE_HZ", 0.0)
		tc_min_speed_kmh = IniParser.get_float(t, "MIN_SPEED_KMH", 0.0)
		tc_curve_file = IniParser.get_str(t, "CURVE", "")

	# Try to load LUTs if referenced and present
	abs_curve = _load_lut_if_exists(data_dir, abs_curve_file)
	tc_curve = _load_lut_if_exists(data_dir, tc_curve_file)

	# Clear previews
	clear_preview()
	
	# Load tuner metadata (for ECU parts)
	var car_dir := data_dir.get_base_dir()
	_load_tuner_metadata(car_dir)


func clear_preview() -> void:
	proposed_abs_present = abs_present
	proposed_abs_active = abs_active
	proposed_tc_present = tc_present
	proposed_tc_active = tc_active


func _load_lut_if_exists(data_dir: String, curve_file: String) -> Array:
	var arr: Array = []
	if curve_file == "":
		return arr

	var lut_path := data_dir.path_join(curve_file)
	if not FileAccess.file_exists(lut_path):
		return arr

	var f := FileAccess.open(lut_path, FileAccess.READ)
	if f == null:
		return arr

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with(";"):
			continue
		var parts := line.split("|", false)
		if parts.size() < 2:
			continue
		var level := int(parts[0])
		var slip := float(parts[1])
		arr.append([level, slip])

	f.close()
	return arr


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

	var oe := orig_car.get_node_or_null("Electronics") as Electronics
	if oe == null:
		return

	# Store ABS/TC stock values
	stock_abs_present = oe.abs_present
	stock_abs_active = oe.abs_active
	stock_abs_slip_ratio_limit = oe.abs_slip_ratio_limit
	stock_abs_rate_hz = oe.abs_rate_hz
	stock_abs_curve_file = oe.abs_curve_file

	stock_tc_present = oe.tc_present
	stock_tc_active = oe.tc_active
	stock_tc_slip_ratio_limit = oe.tc_slip_ratio_limit
	stock_tc_rate_hz = oe.tc_rate_hz
	stock_tc_min_speed_kmh = oe.tc_min_speed_kmh
	stock_tc_curve_file = oe.tc_curve_file
	
	# Store stock ECU power from engine
	var engine := parent_car.get_node_or_null("Engine") as CarEngine
	if engine:
		stock_ecu_power = engine.stock_hp


# ============================================================================
# ABS/TC TOGGLES (old system)
# ============================================================================

func has_abs() -> bool:
	return abs_present == 1 and abs_active == 1


func has_tc() -> bool:
	return tc_present == 1 and tc_active == 1


func preview_toggle(id: String) -> void:
	clear_preview()

	match id:
		"abs":
			if has_abs():
				proposed_abs_present = 0
				proposed_abs_active = 0
			else:
				proposed_abs_present = 1
				proposed_abs_active = 1
		"tc":
			if has_tc():
				proposed_tc_present = 0
				proposed_tc_active = 0
			else:
				proposed_tc_present = 1
				proposed_tc_active = 1


func apply_toggle(id: String) -> void:
	match id:
		"abs":
			if has_abs():
				abs_present = 0
				abs_active = 0
			else:
				abs_present = 1
				abs_active = 1
		"tc":
			if has_tc():
				tc_present = 0
				tc_active = 0
			else:
				tc_present = 1
				tc_active = 1

	clear_preview()


func revert_to_stock() -> void:
	# Revert ABS/TC
	abs_present = stock_abs_present
	abs_active = stock_abs_active
	abs_slip_ratio_limit = stock_abs_slip_ratio_limit
	abs_rate_hz = stock_abs_rate_hz
	abs_curve_file = stock_abs_curve_file

	tc_present = stock_tc_present
	tc_active = stock_tc_active
	tc_slip_ratio_limit = stock_tc_slip_ratio_limit
	tc_rate_hz = stock_tc_rate_hz
	tc_min_speed_kmh = stock_tc_min_speed_kmh
	tc_curve_file = stock_tc_curve_file
	
	# Revert ECU parts
	installed_parts.clear()
	
	# Reset engine power to stock
	_apply_ecu_power_to_engine()

	clear_preview()


# ============================================================================
# ECU/FUEL SYSTEM PARTS (new system)
# ============================================================================

# Get part definition by ID
func _get_part_by_id(part_id: int) -> Dictionary:
	for part in ECU_PARTS:
		if part["id"] == part_id:
			return part
	return {}


# Get currently installed part in a specific upgrade line
func _get_installed_part_in_line(super_type: int) -> Dictionary:
	if installed_parts.has(super_type):
		return _get_part_by_id(installed_parts[super_type])
	return {}


# Calculate total power multiplier from all installed ECU parts
func _calculate_total_multiplier() -> float:
	var total_mult := 1.0
	
	for super_type in installed_parts.keys():
		var part_id = installed_parts[super_type]
		var part = _get_part_by_id(part_id)
		if part.is_empty():
			continue
		
		total_mult *= part["mult"]
	
	return total_mult


# Get current ECU power contribution
func get_ecu_power_multiplier() -> float:
	return _calculate_total_multiplier()


# Check if a part is currently installed
func is_part_installed(part_id: int) -> bool:
	return installed_parts.values().has(part_id)


# Check if any part in the same upgrade line is installed
func has_part_in_line(super_type: int) -> bool:
	return installed_parts.has(super_type)


# Get all available upgrade options (combines ABS/TC toggles + ECU parts)
func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	# ABS/TC toggles (old system)
	options.append({
		"id": "abs",
		"display_name": "ABS",
		"action": "remove" if has_abs() else "add",
		"cost": 0 if has_abs() else 2500,
		"is_toggle": true,
	})

	options.append({
		"id": "tc",
		"display_name": "Traction Control",
		"action": "remove" if has_tc() else "add",
		"cost": 0 if has_tc() else 3000,
		"is_toggle": true,
	})
	
	# ECU/Fuel parts (new system)
	for part in ECU_PARTS:
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
			"replaces_id": current_in_line.get("id", 0),
			"is_toggle": false,
		})

	return options


# Apply an ECU part upgrade
func apply_ecu_upgrade(part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		printerr("Invalid ECU part ID: ", part_id)
		return false
	
	var super_type: int = part["super_type"]
	
	# Install part (replacing any existing part in the same line)
	installed_parts[super_type] = part_id
	
	print("Installed ECU part: %s (ID %d)" % [part["name"], part_id])
	
	# Update engine power
	_apply_ecu_power_to_engine()
	
	return true


# Remove a specific ECU upgrade
func remove_ecu_upgrade(part_id: int) -> bool:
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
	
	print("Removed ECU part: %s (ID %d)" % [part["name"], part_id])
	
	# Update engine power
	_apply_ecu_power_to_engine()
	
	return true


# Can we remove any ECU upgrades?
func can_remove_ecu_upgrades() -> bool:
	return not installed_parts.is_empty()


# Apply ECU power multiplier to engine
func _apply_ecu_power_to_engine() -> void:
	var parent_car: Car = get_parent() as Car
	if parent_car == null:
		return
	
	var engine := parent_car.get_node_or_null("Engine") as CarEngine
	if engine == null:
		return
	
	var ecu_mult := _calculate_total_multiplier()
	
	# ECU parts modify the engine's base power
	# This is applied on top of engine's own upgrades
	if stock_ecu_power > 0.0:
		var new_base = stock_ecu_power * ecu_mult
		# Note: Engine will recalculate its current_hp based on this
		engine.stock_hp = new_base
		engine.current_hp = engine.get_current_hp()
		engine.estimated_hp = engine.current_hp
		
		var driveline_efficiency := 0.85
		engine.estimated_whp = engine.estimated_hp * driveline_efficiency


# Preview what power multiplier would be with a specific upgrade
func get_preview_multiplier(part_id: int) -> float:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return _calculate_total_multiplier()
	
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
	
	return total_mult


# Get tuner metadata for saving
func get_tuner_metadata() -> Dictionary:
	return {
		"installed_parts": installed_parts,
		"stock_ecu_power": stock_ecu_power,
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
	
	if not root.has("js_tuner_electronics"):
		return
	
	var jt_elec = root["js_tuner_electronics"]
	if typeof(jt_elec) != TYPE_DICTIONARY:
		return
	
	# Load installed ECU parts
	if jt_elec.has("installed_parts") and typeof(jt_elec["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in jt_elec["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(jt_elec["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if jt_elec.has("stock_ecu_power"):
		stock_ecu_power = float(jt_elec["stock_ecu_power"])
	
	# Apply ECU power to engine
	_apply_ecu_power_to_engine()


# Load tuner metadata (public version for external calls)
func load_tuner_metadata(meta: Dictionary) -> void:
	if meta.has("installed_parts") and typeof(meta["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in meta["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(meta["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if meta.has("stock_ecu_power"):
		stock_ecu_power = float(meta["stock_ecu_power"])
	
	# Apply ECU power to engine
	_apply_ecu_power_to_engine()


func get_summary_lines() -> Array[String]:
	var lines: Array[String] = []

	# ABS/TC status
	var abs_state := "Enabled" if has_abs() else "Disabled"
	lines.append("ABS: %s" % abs_state)
	if abs_curve_file != "":
		lines.append("  Curve: %s" % abs_curve_file)
	lines.append("  Slip limit: %.2f" % abs_slip_ratio_limit)

	var tc_state := "Enabled" if has_tc() else "Disabled"
	lines.append("TC: %s" % tc_state)
	if tc_curve_file != "":
		lines.append("  Curve: %s" % tc_curve_file)
	lines.append("  Slip limit: %.2f" % tc_slip_ratio_limit)
	
	# ECU/Fuel parts
	if not installed_parts.is_empty():
		lines.append("\nECU/Fuel Upgrades:")
		
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
				lines.append("  • %s (+%.1f%%)" % [
					part["name"],
					(part["mult"] - 1.0) * 100.0
				])
		
		var total_mult := _calculate_total_multiplier()
		lines.append("  Total ECU gain: +%.1f%%" % [(total_mult - 1.0) * 100.0])

	return lines
