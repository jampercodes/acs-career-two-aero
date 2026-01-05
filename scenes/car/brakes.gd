extends Node
class_name Brakes

#  brakes.ini

var max_torque: float = 0.0
var front_share: float = 0.0
var handbrake_torque: float = 0.0
var cockpit_adjustable: int = 0
var adjust_step: float = 0.0

# Disc graphics
var disc_lf: String = ""
var disc_rf: String = ""
var disc_lr: String = ""
var disc_rr: String = ""
var front_max_glow: float = 0.0
var rear_max_glow: float = 0.0
var lag_hot: float = 0.0
var lag_cool: float = 0.0

#  BRAKE RATIO TIERS (Nm/kg targets) - OLD SYSTEM
const STREET_RATIOS = [1.10, 1.20, 1.40, 1.60, 1.80, 2.00]
const SPORT_RATIOS  = [2.10, 2.30, 2.50, 2.70, 2.90, 3.10]
const RACE_RATIOS   = [3.20, 3.50, 3.90, 4.30, 4.80, 5.40]

const TIER_TABLE = {
	"street": STREET_RATIOS,
	"sport":  SPORT_RATIOS,
	"race":   RACE_RATIOS,
}

#  CURRENT CLASSIFICATION - OLD SYSTEM
var current_tier: String = ""      # "street", "sport", "race"
var current_level: int = -1        # 1–6 (1-based)
var current_target_ratio: float = 0.0

# Stock (parent car) classification - OLD SYSTEM
var stock_tier: String = ""
var stock_level: int = -1
var stock_target_ratio: float = 0.0

# Keep stock values (from parent, not modified clone)
var stock_max_torque: float = 0.0
var stock_front_share: float = 0.0
var stock_handbrake_torque: float = 0.0
var stock_cockpit_adjustable: int = 0
var stock_adjust_step: float = 0.0

var proposed_max_torque: float = 0.0
var proposed_front_share: float = 0.0
var proposed_handbrake_torque: float = 0.0
var proposed_cockpit_adjustable: int = 0
var proposed_adjust_step: float = 0.0

var proposed_tier: String = ""
var proposed_level: int = -1
var proposed_target_ratio: float = 0.0

# BRAKE PART DEFINITIONS
const BRAKE_PARTS = [
	# Stage 1 - Street upgrades
	{"id": 601, "name": "Street Compound Brake Pads", "stage": 1, "super_type": 601, "mult": 1.015, "cost": 250, "desc": "Small Brake Torque Increase"},
	{"id": 602, "name": "Steel Braided Brake Lines", "stage": 1, "super_type": 602, "mult": 1.02, "cost": 250, "desc": "Small Brake Torque Increase"},
	{"id": 603, "name": "Cross Drilled Rotors", "stage": 1, "super_type": 603, "mult": 1.025, "cost": 500, "desc": "Medium Brake Torque Increase"},
	
	# Stage 2 - Sport upgrades
	{"id": 604, "name": "Large Diameter Rotors", "stage": 2, "super_type": 603, "mult": 1.05, "cost": 1500, "desc": "Large Brake Torque Increase"},
	{"id": 605, "name": "Race Compound Brake Pads", "stage": 2, "super_type": 601, "mult": 1.08, "cost": 1000, "desc": "Large Brake Torque Increase"},
	
	# Stage 3 - Race upgrades
	{"id": 606, "name": "Cross Drilled And Slotted Rotors", "stage": 3, "super_type": 603, "mult": 1.10, "cost": 2000, "desc": "Extreme Brake Torque Increase"},
	{"id": 607, "name": "6 Piston Racing Calipers", "stage": 3, "super_type": 604, "mult": 1.10, "cost": 2000, "desc": "Extreme Brake Torque Increase"},
]

# Currently installed parts
var installed_parts: Dictionary = {}  # super_type -> part_id


#  BASIC BRAKE DATA

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/brakes.ini")

	# Physics data
	if ini.has("DATA"):
		var d = ini["DATA"]
		max_torque = IniParser.get_float(d, "MAX_TORQUE", 0.0)
		front_share = IniParser.get_float(d, "FRONT_SHARE", 0.0)
		handbrake_torque = IniParser.get_float(d, "HANDBRAKE_TORQUE", 0.0)
		cockpit_adjustable = IniParser.get_int(d, "COCKPIT_ADJUSTABLE", 0)
		adjust_step = IniParser.get_float(d, "ADJUST_STEP", 0.0)

	# Graphics data
	if ini.has("DISCS_GRAPHICS"):
		var g = ini["DISCS_GRAPHICS"]
		disc_lf = IniParser.get_str(g, "DISC_LF", "")
		disc_rf = IniParser.get_str(g, "DISC_RF", "")
		disc_lr = IniParser.get_str(g, "DISC_LR", "")
		disc_rr = IniParser.get_str(g, "DISC_RR", "")
		front_max_glow = IniParser.get_float(g, "FRONT_MAX_GLOW", 0.0)
		rear_max_glow = IniParser.get_float(g, "REAR_MAX_GLOW", 0.0)
		lag_hot = IniParser.get_float(g, "LAG_HOT", 0.0)
		lag_cool = IniParser.get_float(g, "LAG_COOL", 0.0)
	
	# Load tuner metadata (for part-based system)
	var car_dir := data_dir.get_base_dir()
	_load_tuner_metadata(car_dir)


# Call this on the custom car after classified the original one.
func store_stock_values():
	var parent_car: Car = get_parent() as Car
	if parent_car == null:
		return

	var orig_id = parent_car.original_id
	if orig_id == "":
		return

	# Get the Carloader node from the scene tree
	var carloader = get_tree().root.get_node("Carloader")
	if carloader == null or not carloader.has_method("get_car"):
		return

	var orig_car = carloader.get_car(orig_id)
	if orig_car == null:
		return

	var ob := orig_car.get_node("Brakes") as Brakes
	if ob == null:
		return

	# Store old system values
	stock_tier = ob.current_tier
	stock_level = ob.current_level
	stock_target_ratio = ob.current_target_ratio
	
	# Store base values
	stock_max_torque = ob.max_torque
	stock_front_share = ob.front_share
	stock_handbrake_torque = ob.handbrake_torque
	stock_cockpit_adjustable = ob.cockpit_adjustable
	stock_adjust_step = ob.adjust_step


#  COMPUTE CURRENT BRAKE RATIO (Nm/kg)
func get_brake_ratio(car: Car) -> float:
	if car.total_mass <= 0.0:
		return 0.0
	return max_torque / car.total_mass


#  CLASSIFY EXISTING BRAKES INTO STREET/SPORT/RACE LEVEL
func classify_brakes(car: Car) -> void:
	var br := get_brake_ratio(car)

	var best_diff := INF
	var best_tier := ""
	var best_level := -1
	var best_ratio := 0.0

	for tier in TIER_TABLE.keys():
		var arr: Array = TIER_TABLE[tier]
		for i in range(arr.size()):
			var r: float = arr[i]
			var diff = abs(br - r)
			if diff < best_diff:
				best_diff = diff
				best_tier = tier
				best_level = i + 1
				best_ratio = r

	current_tier = best_tier
	current_level = best_level
	current_target_ratio = best_ratio


func get_classification_dict() -> Dictionary:
	return {
		"tier": current_tier,
		"level": current_level,
		"target_ratio": current_target_ratio,
	}


# Get part definition by ID
func _get_part_by_id(part_id: int) -> Dictionary:
	for part in BRAKE_PARTS:
		if part["id"] == part_id:
			return part
	return {}


# Get currently installed part in a specific upgrade line (super_type)
func _get_installed_part_in_line(super_type: int) -> Dictionary:
	if installed_parts.has(super_type):
		return _get_part_by_id(installed_parts[super_type])
	return {}


# Calculate total torque multiplier from all installed parts
func _calculate_total_multiplier() -> float:
	var total_mult := 1.0
	
	for super_type in installed_parts.keys():
		var part_id = installed_parts[super_type]
		var part = _get_part_by_id(part_id)
		if part.is_empty():
			continue
		
		total_mult *= part["mult"]
	
	return total_mult


# Get current brake torque (stock + all multipliers)
func get_current_torque() -> float:
	if stock_max_torque <= 0.0:
		return max_torque
	
	return stock_max_torque * _calculate_total_multiplier()


# Check if a part is currently installed
func is_part_installed(part_id: int) -> bool:
	return installed_parts.values().has(part_id)


# Check if any part in the same upgrade line is installed
func has_part_in_line(super_type: int) -> bool:
	return installed_parts.has(super_type)


# Get all available upgrade options (NEW SYSTEM)
func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	
	for part in BRAKE_PARTS:
		var part_id: int = part["id"]
		var super_type: int = part["super_type"]
		var installed = is_part_installed(part_id)
		var current_in_line = _get_installed_part_in_line(super_type)
		
		# Build display name
		var display_name := "[Stage %d] %s" % [part["stage"], part["name"]]
		
		# Add status indicators
		if installed:
			display_name = "✓ " + display_name
		elif not current_in_line.is_empty():
			# Show what it replaces
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


# Apply a brake upgrade
func apply_brake_upgrade(car: Car, part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		printerr("Invalid brake part ID: ", part_id)
		return false
	
	var super_type: int = part["super_type"]
	
	# Install part (replacing any existing part in the same line)
	installed_parts[super_type] = part_id
	
	# Recalculate max_torque
	max_torque = get_current_torque()
	
	print("Installed brake part: %s (ID %d)" % [part["name"], part_id])
	if part.has("replaces_id") and part["replaces_id"] > 0:
		var old_part = _get_part_by_id(part["replaces_id"])
		if not old_part.is_empty():
			print("  Replaced: %s" % old_part["name"])
	
	return true


# Remove a specific brake upgrade (NEW SYSTEM)
func remove_brake_upgrade(part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return false
	
	var super_type: int = part["super_type"]
	
	if not installed_parts.has(super_type):
		return false
	
	if installed_parts[super_type] != part_id:
		return false
	
	# Remove this part from the installed list
	installed_parts.erase(super_type)
	
	# Recalculate max_torque
	max_torque = get_current_torque()
	
	print("Removed brake part: %s (ID %d)" % [part["name"], part_id])
	return true


# Remove all upgrades in a specific line
func remove_upgrade_line(super_type: int) -> bool:
	if not installed_parts.has(super_type):
		return false
	
	var part_id = installed_parts[super_type]
	return remove_brake_upgrade(part_id)


# Revert to stock brakes (remove all upgrades)
func revert_to_stock() -> void:
	installed_parts.clear()
	max_torque = stock_max_torque
	front_share = stock_front_share
	handbrake_torque = stock_handbrake_torque
	cockpit_adjustable = stock_cockpit_adjustable
	adjust_step = stock_adjust_step
	
	print("Reverted brakes to stock configuration")


# Can we remove any upgrades?
func can_remove_upgrades() -> bool:
	return not installed_parts.is_empty()


# Preview what torque would be with a specific upgrade
func get_preview_torque(car: Car, part_id: int) -> float:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		return get_current_torque()
	
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
	
	return stock_max_torque * total_mult


# Get tuner metadata for saving
func get_tuner_metadata() -> Dictionary:
	return {
		"installed_parts": installed_parts,
		"stock_max_torque": stock_max_torque,
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
	
	if not root.has("js_tuner_brakes"):
		return
	
	var jt_brakes = root["js_tuner_brakes"]
	if typeof(jt_brakes) != TYPE_DICTIONARY:
		return
	
	# Load installed parts
	if jt_brakes.has("installed_parts") and typeof(jt_brakes["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in jt_brakes["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(jt_brakes["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if jt_brakes.has("stock_max_torque"):
		stock_max_torque = float(jt_brakes["stock_max_torque"])
	
	# Recalculate current torque based on installed parts
	max_torque = get_current_torque()


# Load tuner metadata
func load_tuner_metadata(meta: Dictionary) -> void:
	if meta.has("installed_parts") and typeof(meta["installed_parts"]) == TYPE_DICTIONARY:
		installed_parts.clear()
		for k in meta["installed_parts"].keys():
			var super_type = int(k)
			var part_id = int(meta["installed_parts"][k])
			installed_parts[super_type] = part_id
	
	if meta.has("stock_max_torque"):
		stock_max_torque = float(meta["stock_max_torque"])
	
	# Recalculate current torque based on installed parts
	max_torque = get_current_torque()


# ============================================================================
# OLD TIER-BASED SYSTEM (kept for compatibility)
# ============================================================================

#  COSTS (progressive across tiers)
func get_upgrade_cost(tier: String, level: int) -> int:
	# Base costs per level within each tier
	var street_base := 500
	var sport_base := 2000
	var race_base := 5000
	
	match tier:
		"street":
			# Street: 500, 750, 1000, 1250, 1500, 1750
			return street_base + (level - 1) * 250
		"sport":
			# Sport: 2000, 2500, 3000, 3500, 4000, 4500
			return sport_base + (level - 1) * 500
		"race":
			# Race: 5000, 6500, 8000, 10000, 12500, 15000
			return race_base + (level - 1) * 1500
		_:
			return 0


#  UPGRADE PREVIEW - 
func get_upgrade_torque(car: Car, tier: String, level: int) -> float:
	if not TIER_TABLE.has(tier):
		return 0.0
	
	var ratios: Array = TIER_TABLE[tier]
	if level < 1 or level > ratios.size():
		return 0.0
	
	var target_ratio = ratios[level - 1]
	return target_ratio * car.total_mass


func _tier_label(tier: String) -> String:
	match tier:
		"street":
			return "Street Brakes"
		"sport":
			return "Sport Brakes"
		"race":
			return "Race Brakes"
		_:
			return tier


# Get summary lines for UI 
func get_summary_lines(car: Car) -> Array[String]:
	var lines: Array[String] = []
	
	var current_torque := get_current_torque()
	var ratio := get_brake_ratio(car)
	
	lines.append("Brake torque: %.0f Nm (%.2f Nm/kg)" % [current_torque, ratio])
	
	if stock_max_torque > 0.0:
		var stock_ratio := stock_max_torque / car.total_mass if car.total_mass > 0.0 else 0.0
		lines.append("Stock: %.0f Nm (%.2f Nm/kg)" % [stock_max_torque, stock_ratio])
	
	# Show OLD system classification if available
	if stock_tier != "":
		lines.append(
			"Stock class: %s L%d (%.2f Nm/kg)" %
			[_tier_label(stock_tier), stock_level, stock_target_ratio]
		)
	
	if current_tier != "":
		lines.append(
			"Current class: %s L%d (%.2f Nm/kg)" %
			[_tier_label(current_tier), current_level, current_target_ratio]
		)
	
	# List NEW system installed upgrades
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
				lines.append("  • %s (+%.1f%%)" % [
					part["name"],
					(part["mult"] - 1.0) * 100.0
				])
	
	return lines
