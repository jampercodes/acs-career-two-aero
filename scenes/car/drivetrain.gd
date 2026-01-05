# drivetrain.gd
extends Node
class_name Drivetrain

var traction_type: String = ""   # RWD / FWD / AWD

var gear_count: int = 0
var gear_r: float = 0.0
var gears: Array[float] = []     # forward gears
var final_drive: float = 0.0

# DIFFERENTIAL
var diff_power: float = 0.0
var diff_coast: float = 0.0
var diff_preload: float = 0.0

# GEARBOX
var change_up_time: float = 0.0
var change_dn_time: float = 0.0
var auto_cutoff_time: float = 0.0
var supports_shifter: int = 0
var valid_shift_rpm_window: float = 0.0
var controls_window_gain: float = 0.0
var gearbox_inertia: float = 0.0

# CLUTCH
var clutch_max_torque: float = 0.0

# AUTOCLUTCH
var autoclutch_upshift_profile: String = ""
var autoclutch_downshift_profile: String = ""
var autoclutch_use_on_changes: int = 0
var autoclutch_min_rpm: int = 0
var autoclutch_max_rpm: int = 0
var autoclutch_forced_on: int = 0

# DOWNSHIFT_PROFILE
var downshift_point_0: float = 0.0
var downshift_point_1: float = 0.0
var downshift_point_2: float = 0.0

# AUTOBLIP
var autoblip_electronic: int = 0
var autoblip_point_0: float = 0.0
var autoblip_point_1: float = 0.0
var autoblip_point_2: float = 0.0
var autoblip_level: float = 0.0

# DAMAGE
var rpm_window_k: float = 0.0

# AUTO_SHIFTER
var auto_shifter_up: float = 0.0
var auto_shifter_down: float = 0.0
var auto_shifter_slip_threshold: float = 0.0
var auto_shifter_gas_cutoff_time: float = 0.0

#  UPGRADE TRACKING
var stock_traction_type: String = ""
var current_archetype: String = ""  # e.g., "rwd_race", "fwd_sport", ""
var stock_archetype: String = ""    # Track original for reversion

func store_stock_values():
	stock_traction_type = traction_type
	# Stock archetype is set externally after classification

func load_from_data_dir(data_dir: String) -> void:
	var ini := IniParser.parse_file(data_dir + "/drivetrain.ini")

	if ini.has("TRACTION"):
		var t = ini["TRACTION"]
		traction_type = IniParser.get_str(t, "TYPE", "")

	if ini.has("GEARS"):
		var g = ini["GEARS"]
		gear_count = IniParser.get_int(g, "COUNT", 0)
		gear_r = IniParser.get_float(g, "GEAR_R", 0.0)
		gears.clear()
		for i in range(1, gear_count + 1):
			var key := "GEAR_%d" % i
			if g.has(key):
				gears.append(IniParser.get_float(g, key, 0.0))
		final_drive = IniParser.get_float(g, "FINAL", 0.0)

	if ini.has("DIFFERENTIAL"):
		var d = ini["DIFFERENTIAL"]
		diff_power = IniParser.get_float(d, "POWER", 0.0)
		diff_coast = IniParser.get_float(d, "COAST", 0.0)
		diff_preload = IniParser.get_float(d, "PRELOAD", 0.0)

	if ini.has("GEARBOX"):
		var gb = ini["GEARBOX"]
		change_up_time = IniParser.get_float(gb, "CHANGE_UP_TIME", 0.0)
		change_dn_time = IniParser.get_float(gb, "CHANGE_DN_TIME", 0.0)
		auto_cutoff_time = IniParser.get_float(gb, "AUTO_CUTOFF_TIME", 0.0)
		supports_shifter = IniParser.get_int(gb, "SUPPORTS_SHIFTER", 0)
		valid_shift_rpm_window = IniParser.get_float(gb, "VALID_SHIFT_RPM_WINDOW", 0.0)
		controls_window_gain = IniParser.get_float(gb, "CONTROLS_WINDOW_GAIN", 0.0)
		gearbox_inertia = IniParser.get_float(gb, "INERTIA", 0.0)

	if ini.has("CLUTCH"):
		var c = ini["CLUTCH"]
		clutch_max_torque = IniParser.get_float(c, "MAX_TORQUE", 0.0)

	if ini.has("AUTOCLUTCH"):
		var ac = ini["AUTOCLUTCH"]
		autoclutch_upshift_profile = IniParser.get_str(ac, "UPSHIFT_PROFILE", "")
		autoclutch_downshift_profile = IniParser.get_str(ac, "DOWNSHIFT_PROFILE", "")
		autoclutch_use_on_changes = IniParser.get_int(ac, "USE_ON_CHANGES", 0)
		autoclutch_min_rpm = IniParser.get_int(ac, "MIN_RPM", 0)
		autoclutch_max_rpm = IniParser.get_int(ac, "MAX_RPM", 0)
		autoclutch_forced_on = IniParser.get_int(ac, "FORCED_ON", 0)

	if ini.has("DOWNSHIFT_PROFILE"):
		var dp = ini["DOWNSHIFT_PROFILE"]
		downshift_point_0 = IniParser.get_float(dp, "POINT_0", 0.0)
		downshift_point_1 = IniParser.get_float(dp, "POINT_1", 0.0)
		downshift_point_2 = IniParser.get_float(dp, "POINT_2", 0.0)

	if ini.has("AUTOBLIP"):
		var ab = ini["AUTOBLIP"]
		autoblip_electronic = IniParser.get_int(ab, "ELECTRONIC", 0)
		autoblip_point_0 = IniParser.get_float(ab, "POINT_0", 0.0)
		autoblip_point_1 = IniParser.get_float(ab, "POINT_1", 0.0)
		autoblip_point_2 = IniParser.get_float(ab, "POINT_2", 0.0)
		autoblip_level = IniParser.get_float(ab, "LEVEL", 0.0)

	if ini.has("DAMAGE"):
		var dmg = ini["DAMAGE"]
		rpm_window_k = IniParser.get_float(dmg, "RPM_WINDOW_K", 0.0)

	if ini.has("AUTO_SHIFTER"):
		var autoshift = ini["AUTO_SHIFTER"]
		auto_shifter_up = IniParser.get_float(autoshift, "UP", 0.0)
		auto_shifter_down = IniParser.get_float(autoshift, "DOWN", 0.0)
		auto_shifter_slip_threshold = IniParser.get_float(autoshift, "SLIP_THRESHOLD", 0.0)
		auto_shifter_gas_cutoff_time = IniParser.get_float(autoshift, "GAS_CUTOFF_TIME", 0.0)


func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	
	# Get carloader from scene tree
	var carloader = null
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop is SceneTree:
		var root = main_loop.root
		if root:
			carloader = root.get_node_or_null("Carloader")
	
	if carloader == null or not carloader.has_method("get_drivetrain_archetypes"):
		return options
	
	var archetypes: Dictionary = carloader.get_drivetrain_archetypes()
	
	for archetype_id in archetypes.keys():
		var archetype = archetypes[archetype_id]
		
		# DON'T skip current archetype - let UI show it with checkmark
		
		options.append({
			"archetype_id": archetype_id,
			"display_name": archetype["display_name"],
			"cost": archetype["cost"],
			"traction_type": archetype["traction_type"],
			"tier": archetype["tier"],
		})
	
	return options


func can_remove_drivetrain_upgrade() -> bool:
	# Can remove if we have an applied archetype that differs from stock
	return current_archetype != "" and current_archetype != stock_archetype


func apply_drivetrain_upgrade(archetype_id: String) -> void:
	current_archetype = archetype_id


func remove_drivetrain_upgrade() -> void:
	if stock_archetype != "":
		current_archetype = stock_archetype
	else:
		current_archetype = ""
