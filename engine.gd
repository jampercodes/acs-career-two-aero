extends Node
class_name CarEngine

var power_curve_file: String = ""
var power_curve: Array[Vector2] = []
var is_swapped: bool = false
var swap_source_car_id: String = ""
var coast_curve_mode: String = ""
var coast_curve_file: String = ""
var coast_curve: Array[Vector2] = []

var altitude_sensitivity: float = 0.0
var inertia: float = 0.0
var limiter: int = 0
var limiter_hz: int = 0
var minimum_rpm: int = 0
var default_turbo_adjustment: float = 0.0

var coast_ref_rpm: float = 0.0
var coast_ref_torque: float = 0.0
var coast_ref_non_linearity: float = 0.0

var coast0: float = 0.0
var coast1: float = 0.0
var coast: float = 0.0

var turbo_boost_threshold: float = 0.0
var turbo_damage_k: float = 0.0
var rpm_threshold: float = 0.0
var rpm_damage_k: float = 0.0

var turbos: Array = []

var estimated_hp: float = 0.0
var estimated_whp: float = 0.0

# Stock values
var stock_hp: float = 0.0
var current_hp: float = 0.0
var proposed_hp: float = 0.0

# ENGINE PART DEFINITIONS (inspired by Cyberpunk mod)
# Parts are organized by SuperType (upgrade lines) and Stage (progression)

const ENGINE_PARTS = [
	# Stage 1 - Street upgrades
	{"id": 101, "name": "Cold Air Intake", "stage": 1, "super_type": 101, "mult": 1.03, "cost": 250, "desc": "Small Engine Torque Increase"},
	{"id": 102, "name": "Replace Headers", "stage": 1, "super_type": 102, "mult": 1.04, "cost": 500, "desc": "Small Engine Torque Increase"},
	{"id": 103, "name": "Mild Camshaft and Cam Gears", "stage": 1, "super_type": 103, "mult": 1.035, "cost": 250, "desc": "Small Engine Torque Increase"},
	{"id": 104, "name": "Performance Exhaust", "stage": 1, "super_type": 104, "mult": 1.035, "cost": 500, "desc": "Small Engine Torque Increase"},
	
	# Stage 2 - Sport upgrades
	{"id": 105, "name": "Cat Back Exhaust System", "stage": 2, "super_type": 104, "mult": 1.0625, "cost": 1000, "desc": "Medium Engine Torque Increase"},
	{"id": 106, "name": "High Flow Intake Manifold", "stage": 2, "super_type": 105, "mult": 1.04, "cost": 500, "desc": "Small Engine Torque Increase"},
	{"id": 107, "name": "Larger Diameter Downpipe", "stage": 2, "super_type": 106, "mult": 1.04, "cost": 500, "desc": "Small Engine Torque Increase"},
	
	# Stage 3 - Race upgrades
	{"id": 108, "name": "Racing Camshaft and Cam Gears", "stage": 3, "super_type": 103, "mult": 1.05, "cost": 500, "desc": "Medium Engine Torque Increase"},
	{"id": 109, "name": "Port and Polish Heads", "stage": 3, "super_type": 107, "mult": 1.0625, "cost": 1000, "desc": "Medium Engine Torque Increase"},
	{"id": 110, "name": "Blueprint the Block", "stage": 3, "super_type": 108, "mult": 1.075, "cost": 1500, "desc": "Medium Engine Torque Increase"},
	{"id": 111, "name": "High Flow Headers", "stage": 3, "super_type": 102, "mult": 1.06, "cost": 500, "desc": "Medium Engine Torque Increase"},
]

# Turbo parts (special SuperType 110)
const TURBO_PARTS = [
	{"id": 121, "name": "Stage 1 Turbo System", "stage": 1, "super_type": 110, "mult": 1.08, "cost": 1000, "desc": "Medium Engine Torque Increase"},
	{"id": 122, "name": "Stage 2 Turbo System", "stage": 2, "super_type": 110, "mult": 1.15, "cost": 4000, "desc": "Very Large Engine Torque Increase"},
	{"id": 123, "name": "Stage 3 Twin Turbo System", "stage": 3, "super_type": 110, "mult": 1.25, "cost": 8000, "desc": "Extreme Engine Torque Increase"},
]

# Currently installed parts (by super_type)
var installed_parts: Dictionary = {}  # super_type -> part_id

# Track if car originally had turbo
var has_stock_turbo: bool = false


func _ready() -> void:
	pass

func copy_from_engine(source_engine: CarEngine, source_car_id: String) -> void:
	# Copy all base engine properties
	altitude_sensitivity = source_engine.altitude_sensitivity
	inertia = source_engine.inertia
	limiter = source_engine.limiter
	limiter_hz = source_engine.limiter_hz
	minimum_rpm = source_engine.minimum_rpm
	
	coast_ref_rpm = source_engine.coast_ref_rpm
	coast_ref_torque = source_engine.coast_ref_torque
	coast_ref_non_linearity = source_engine.coast_ref_non_linearity
	coast0 = source_engine.coast0
	coast1 = source_engine.coast1
	coast = source_engine.coast
	
	coast_curve_mode = source_engine.coast_curve_mode
	coast_curve_file = source_engine.coast_curve_file
	coast_curve = source_engine.coast_curve.duplicate()
	
	power_curve_file = source_engine.power_curve_file
	power_curve = source_engine.power_curve.duplicate()
	
	rpm_threshold = source_engine.rpm_threshold
	rpm_damage_k = source_engine.rpm_damage_k
	turbo_boost_threshold = source_engine.turbo_boost_threshold
	turbo_damage_k = source_engine.turbo_damage_k
	
	# Copy turbo data
	has_stock_turbo = source_engine.has_stock_turbo
	turbos = source_engine.turbos.duplicate(true)
	
	# Set new stock values
	stock_hp = source_engine.stock_hp
	current_hp = source_engine.stock_hp
	estimated_hp = source_engine.stock_hp
	estimated_whp = source_engine.stock_hp * 0.85
	
	# Clear all upgrades
	installed_parts.clear()
	
	# Mark as swapped
	is_swapped = true
	swap_source_car_id = source_car_id
	
	print("Engine swapped from %s (%.0f bhp)" % [source_car_id, stock_hp])


# Get part definition by ID
func _get_part_by_id(part_id: int) -> Dictionary:
	for part in ENGINE_PARTS:
		if part["id"] == part_id:
			return part
	
	for part in TURBO_PARTS:
		if part["id"] == part_id:
			return part
	
	return {}


# Get currently installed part in a specific upgrade line
func _get_installed_part_in_line(super_type: int) -> Dictionary:
	if installed_parts.has(super_type):
		return _get_part_by_id(installed_parts[super_type])
	return {}

func get_tuner_metadata() -> Dictionary:
	return {
		"stock_hp": stock_hp,
		"current_hp": current_hp,
		"installed_parts": installed_parts,
		"is_swapped": is_swapped,
		"swap_source_car_id": swap_source_car_id,
	}


# Calculate total torque/HP multiplier from all installed parts
func _calculate_total_multiplier() -> float:
	var total_mult := 1.0
	
	for super_type in installed_parts.keys():
		var part_id = installed_parts[super_type]
		var part = _get_part_by_id(part_id)
		if part.is_empty():
			continue
		
		total_mult *= part["mult"]
	
	return total_mult


# Get current engine power
func get_current_hp() -> float:
	if stock_hp <= 0.0:
		return estimated_hp
	
	return stock_hp * _calculate_total_multiplier()


# Check if a part is currently installed
func is_part_installed(part_id: int) -> bool:
	return installed_parts.values().has(part_id)


# Check if any part in the same upgrade line is installed
func has_part_in_line(super_type: int) -> bool:
	return installed_parts.has(super_type)


# Check if car has turbo installed (stock or upgraded)
func has_turbo() -> bool:
	return has_stock_turbo or installed_parts.has(110)


# Check if turbo can be added
func can_add_turbo() -> bool:
	if has_stock_turbo:
		# Already has turbo, can upgrade it
		var current = _get_installed_part_in_line(110)
		if current.is_empty():
			return true  # Can install first turbo upgrade
		
		# Can upgrade if not at highest stage
		return current.get("stage", 0) < 3
	else:
		# NA car, can add turbo
		return true


# Check if turbo can be removed
func can_remove_turbo() -> bool:
	if has_stock_turbo:
		# Can only remove if we have an upgrade installed
		return installed_parts.has(110)
	else:
		# NA car, can remove if turbo is installed
		return installed_parts.has(110)


# Get all available upgrade options (non-turbo)
func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	
	for part in ENGINE_PARTS:
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


# Get turbo upgrade options
func get_turbo_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	
	for part in TURBO_PARTS:
		var part_id: int = part["id"]
		var installed = is_part_installed(part_id)
		var current_turbo = _get_installed_part_in_line(110)
		
		var display_name = part["name"]
		
		if installed:
			display_name = "✓ " + display_name
		elif not current_turbo.is_empty():
			display_name += " (replaces %s)" % current_turbo["name"]
		elif not has_stock_turbo:
			display_name += " (adds turbocharger)"
		
		options.append({
			"id": part_id,
			"name": part["name"],
			"stage": part["stage"],
			"super_type": 110,
			"mult": part["mult"],
			"cost": part["cost"],
			"desc": part["desc"],
			"display_name": display_name,
			"installed": installed,
			"is_turbo": true
		})
	
	return options


# Apply an engine upgrade
func apply_engine_upgrade(part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		printerr("Invalid engine part ID: ", part_id)
		return false
	
	var super_type: int = part["super_type"]
	
	# Install part (replacing any existing part in the same line)
	installed_parts[super_type] = part_id
	
	# Recalculate current HP
	current_hp = get_current_hp()
	estimated_hp = current_hp
	
	var driveline_efficiency := 0.85
	estimated_whp = estimated_hp * driveline_efficiency
	
	print("Installed engine part: %s (ID %d)" % [part["name"], part_id])
	
	return true


# Remove a specific engine upgrade
func remove_engine_upgrade(part_id: int) -> bool:
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
	
	# Recalculate current HP
	current_hp = get_current_hp()
	estimated_hp = current_hp
	
	var driveline_efficiency := 0.85
	estimated_whp = estimated_hp * driveline_efficiency
	
	print("Removed engine part: %s (ID %d)" % [part["name"], part_id])
	return true


# Remove turbo upgrade (revert to stock or NA)
func remove_turbo_upgrade() -> bool:
	if not can_remove_turbo():
		return false
	
	if installed_parts.has(110):
		var turbo_id = installed_parts[110]
		return remove_engine_upgrade(turbo_id)
	
	return false


# Revert to stock engine (remove all upgrades)
func revert_to_stock() -> void:
	installed_parts.clear()
	current_hp = stock_hp
	estimated_hp = stock_hp
	
	var driveline_efficiency := 0.85
	estimated_whp = estimated_hp * driveline_efficiency
	
	print("Reverted engine to stock configuration")


# Can we remove any upgrades?
func can_remove_upgrades() -> bool:
	return not installed_parts.is_empty()


# Preview what HP would be with a specific upgrade
func get_preview_hp(part_id: int) -> float:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return get_current_hp()
	
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
	
	return stock_hp * total_mult


# Preview with upgrade (for UI)
func preview_with_upgrade(part_id: int) -> void:
	proposed_hp = get_preview_hp(part_id)


# Clear preview
func clear_preview() -> void:
	proposed_hp = current_hp


# Get summary lines for UI
func get_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	
	var current_power := get_current_hp()
	
	lines.append("Stock power: %.0f bhp" % stock_hp)
	lines.append("Current power: %.0f bhp" % current_power)
	
	# Show aspiration status
	if has_turbo():
		var turbo_part = _get_installed_part_in_line(110)
		if not turbo_part.is_empty():
			lines.append("Aspiration: %s" % turbo_part["name"])
		elif has_stock_turbo:
			lines.append("Aspiration: Stock Turbo")
	else:
		lines.append("Aspiration: Naturally Aspirated")
	
	# List installed upgrades by stage
	if not installed_parts.is_empty():
		lines.append("\nInstalled Upgrades:")
		
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
				# Skip turbo in this list (already shown above)
				if part["super_type"] == 110:
					continue
				
				lines.append("  • %s (+%.1f%%)" % [
					part["name"],
					(part["mult"] - 1.0) * 100.0
				])
	
	return lines


# LOAD ENGINE DATA

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/engine.ini")

	if ini.has("HEADER"):
		var h = ini["HEADER"]
		power_curve_file = IniParser.get_str(h, "POWER_CURVE", "")
		coast_curve_mode = IniParser.get_str(h, "COAST_CURVE", "")

	if ini.has("ENGINE_DATA"):
		var e = ini["ENGINE_DATA"]
		altitude_sensitivity = IniParser.get_float(e, "ALTITUDE_SENSITIVITY", 0.0)
		inertia = IniParser.get_float(e, "INERTIA", 0.0)
		limiter = IniParser.get_int(e, "LIMITER", 0)
		limiter_hz = IniParser.get_int(e, "LIMITER_HZ", 0)
		minimum_rpm = IniParser.get_int(e, "MINIMUM", 0)
		default_turbo_adjustment = IniParser.get_float(e, "DEFAULT_TURBO_ADJUSTMENT", 0.0)

	if ini.has("COAST_REF"):
		var c = ini["COAST_REF"]
		coast_ref_rpm = IniParser.get_float(c, "RPM", 0.0)
		coast_ref_torque = IniParser.get_float(c, "TORQUE", 0.0)
		coast_ref_non_linearity = IniParser.get_float(c, "NON_LINEARITY", 0.0)

	if ini.has("COAST_DATA"):
		var cd = ini["COAST_DATA"]
		coast0 = IniParser.get_float(cd, "COAST0", 0.0)
		coast1 = IniParser.get_float(cd, "COAST1", 0.0)
		coast = IniParser.get_float(cd, "COAST", 0.0)

	if ini.has("COAST_CURVE"):
		var cc = ini["COAST_CURVE"]
		coast_curve_file = IniParser.get_str(cc, "FILENAME", "")

	if ini.has("DAMAGE"):
		var d = ini["DAMAGE"]
		turbo_boost_threshold = IniParser.get_float(d, "TURBO_BOOST_THRESHOLD", 0.0)
		turbo_damage_k = IniParser.get_float(d, "TURBO_DAMAGE_K", 0.0)
		rpm_threshold = IniParser.get_float(d, "RPM_THRESHOLD", 0.0)
		rpm_damage_k = IniParser.get_float(d, "RPM_DAMAGE_K", 0.0)

	# Load turbos
	turbos.clear()
	var turbo_index := 0
	while true:
		var section_name := "TURBO_%d" % turbo_index
		if not ini.has(section_name):
			break
		var t = ini[section_name]
		var turbo_data := {
			"lag_dn": IniParser.get_float(t, "LAG_DN", 0.0),
			"lag_up": IniParser.get_float(t, "LAG_UP", 0.0),
			"max_boost": IniParser.get_float(t, "MAX_BOOST", 0.0),
			"wastegate": IniParser.get_float(t, "WASTEGATE", 0.0),
			"display_max_boost": IniParser.get_float(t, "DISPLAY_MAX_BOOST", 0.0),
			"reference_rpm": IniParser.get_float(t, "REFERENCE_RPM", 0.0),
			"gamma": IniParser.get_float(t, "GAMMA", 1.0),
			"cockpit_adjustable": IniParser.get_int(t, "COCKPIT_ADJUSTABLE", 0) != 0,
		}
		turbos.append(turbo_data)
		turbo_index += 1

	# Check if stock car has turbo
	has_stock_turbo = not turbos.is_empty()

	# Load power curve
	power_curve.clear()
	if power_curve_file != "":
		power_curve_file = power_curve_file.strip_edges()
		power_curve = LutUtils.load_lut(data_dir + "/" + power_curve_file)

	# Compute estimated HP from physics
	_compute_estimated_power()
	_override_estimate_from_ui(data_dir)

	# Initialize stock HP
	stock_hp = max(estimated_hp, 0.0)
	current_hp = stock_hp
	proposed_hp = stock_hp
	
	installed_parts = {}

	# Try to load saved tuner data
	var car_dir := data_dir.get_base_dir()
	_load_tuner_metadata(car_dir)


func store_stock_values():
	# Stock values are handled in load_from_data_dir
	pass


func _compute_estimated_power() -> void:
	if power_curve.is_empty():
		estimated_hp = 0.0
		estimated_whp = 0.0
		return

	var peak_bhp := 0.0
	for p in power_curve:
		var rpm: float = p.x
		var torque_nm: float = p.y
		if rpm <= 0.0:
			continue
		var bhp := torque_nm * rpm / 7127.0
		if bhp > peak_bhp:
			peak_bhp = bhp

	var driveline_efficiency := 0.85
	estimated_hp = peak_bhp
	estimated_whp = peak_bhp * driveline_efficiency


func _override_estimate_from_ui(data_dir: String) -> void:
	var car_dir := data_dir.get_base_dir()
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
		push_warning("Engine: Failed to parse ui_car.json: %s" % ui_path)
		return

	var root = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return

	var ui_bhp: float = 0.0
	var bhp_from_curve: float = 0.0

	var specs = root.get("specs", null)
	if typeof(specs) == TYPE_DICTIONARY:
		var bhp_raw = specs.get("bhp", "")
		var bhp_str := str(bhp_raw)
		ui_bhp = _parse_bhp_string(bhp_str)

	if ui_bhp <= 0.0:
		var pcurve = root.get("powerCurve", null)
		if typeof(pcurve) == TYPE_ARRAY:
			for pt in pcurve:
				if pt is Array and pt.size() >= 2:
					var val = pt[1]
					var hp_val: float
					if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
						hp_val = float(val)
					else:
						hp_val = float(str(val))
					if hp_val > bhp_from_curve:
						bhp_from_curve = hp_val

	var final_bhp := ui_bhp
	if final_bhp <= 0.0:
		final_bhp = bhp_from_curve

	if final_bhp > 0.0:
		estimated_hp = final_bhp
		var driveline_efficiency := 0.85
		estimated_whp = estimated_hp * driveline_efficiency


func _parse_bhp_string(s: String) -> float:
	var clean := s.strip_edges().to_lower()
	if clean == "" or clean == "--" or clean == "n/a":
		return 0.0

	var num_str := ""
	var dot_seen := false

	for ch in clean:
		if ch >= "0" and ch <= "9":
			num_str += ch
		elif ch == "." and not dot_seen:
			dot_seen = true
			num_str += ch
		elif num_str != "":
			break

	if num_str == "":
		return 0.0

	return float(num_str)


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
	
	if not root.has("js_tuner"):
		return
	
	var jt = root["js_tuner"]
	if typeof(jt) != TYPE_DICTIONARY:
		return
	
	var saved_stock_hp := float(jt.get("stock_hp", 0.0))
	var saved_current_hp := float(jt.get("current_hp", 0.0))
	var saved_parts = jt.get("installed_parts", {})
	
	# ADD THESE LINES to restore swap info:
	if jt.has("is_swapped"):
		is_swapped = bool(jt["is_swapped"])
	if jt.has("swap_source_car_id"):
		swap_source_car_id = str(jt["swap_source_car_id"])
	
	if saved_current_hp <= 0.0:
		return
	
	# Restore baseline + current power
	stock_hp = saved_stock_hp if saved_stock_hp > 0.0 else saved_current_hp
	current_hp = saved_current_hp
	
	estimated_hp = current_hp
	var driveline_eff := 0.85
	estimated_whp = estimated_hp * driveline_eff
	
	# Restore installed parts
	installed_parts = {}
	if typeof(saved_parts) == TYPE_DICTIONARY:
		for k in saved_parts.keys():
			var super_type = int(k)
			var part_id = int(saved_parts[k])
			installed_parts[super_type] = part_id
	
	proposed_hp = current_hp

func get_upgrade_refund_value() -> int:
	var total := 0
	for super_type in installed_parts.keys():
		var part_id = installed_parts[super_type]
		var part = _get_part_by_id(part_id)
		if not part.is_empty():
			total += part["cost"]
	return total

func get_hp_multiplier() -> float:
	if stock_hp <= 0.0 or current_hp <= 0.0:
		return 1.0
	return current_hp / stock_hp
