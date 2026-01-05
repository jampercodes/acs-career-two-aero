# Tyres.gd
extends Node
class_name Tyres

class TyreThermal:
	var surface_transfer: float = 0.0
	var patch_transfer: float = 0.0
	var core_transfer: float = 0.0
	var internal_core_transfer: float = 0.0
	var friction_k: float = 0.0
	var rolling_k: float = 0.0
	var performance_curve_path: String = ""
	var performance_curve_points: Array[Vector2] = []
	var grain_gamma: float = 0.0
	var grain_gain: float = 0.0
	var blister_gamma: float = 0.0
	var blister_gain: float = 0.0
	var cool_factor: float = 0.0
	var surface_rolling_k: float = 0.0


class TyreCompound:
	var index: int = 0
	var axle: String = ""  # "front" / "rear"
	var name: String = ""
	var short_name: String = ""

	var width: float = 0.0
	var radius: float = 0.0
	var rim_radius: float = 0.0
	var angular_inertia: float = 0.0
	var damp: float = 0.0
	var rate: float = 0.0

	var fz0: float = 0.0
	var dy_ref: float = 0.0
	var dx_ref: float = 0.0
	var ls_expy: float = 1.0
	var ls_expx: float = 1.0
	var friction_limit_angle: float = 0.0

	var pressure_static: float = 0.0
	var pressure_ideal: float = 0.0
	var pressure_d_gain: float = 0.0
	var speed_sensitivity: float = 0.0

	var camber_gain: float = 0.0
	var dcamber_0: float = 0.0
	var dcamber_1: float = 0.0

	var flex_gain: float = 0.0
	var falloff_level: float = 0.0
	var falloff_speed: float = 0.0
	var cx_mult: float = 1.0
	var brake_dx_mod: float = 0.0

	var wear_curve_path: String = ""
	var wear_curve_points: Array[Vector2] = []

	var thermal: TyreThermal = null

	func get_peak_lateral_mu() -> float:
		return dy_ref

	func get_peak_longitudinal_mu() -> float:
		return dx_ref


# Upgrade definitions

const TYRE_COSTS := {
	"street": {1: 500, 2: 1200, 3: 2500},
	"sport":  {1: 4000, 2: 8000, 3: 14000},
	"race":   {1: 20000, 2: 35000, 3: 55000},
}

const TARGET_DY := {
	"street": {1: 1.12, 2: 1.20, 3: 1.27},
	"sport":  {1: 1.30, 2: 1.38, 3: 1.45},
	"race":   {1: 1.55, 2: 1.65, 3: 1.75},
}
const TARGET_DX := {
	"street": {1: 1.12, 2: 1.20, 3: 1.27},
	"sport":  {1: 1.30, 2: 1.38, 3: 1.45},
	"race":   {1: 1.55, 2: 1.65, 3: 1.75},
}

const TIER_DISPLAY := {
	"street": "Street Tyres",
	"sport": "Sport Semis",
	"race": "Race Slicks",
}

const TIER_SHORT := {
	"street": "ST",
	"sport": "SM",
	"race": "RC",
}


# Base compound storage

var default_compound_index: int = 0

var _front_by_index: Dictionary = {}
var _rear_by_index: Dictionary = {}
var _compound_indices: Array[int] = []

# Best compound metrics
var best_compound_index: int = 0
var best_compound_name: String = ""
var best_compound_short_name: String = ""
var best_lateral_mu: float = 0.0
var best_longitudinal_mu: float = 0.0
var best_mechanical_grip_index: float = 0.0

# Stock + upgrade state

var stock_default_index: int = 0
var stock_best_mu_lat: float = 0.0
var stock_best_mu_long: float = 0.0
var stock_tier: String = ""
var stock_level: int = 0

var current_tier: String = ""     # "", "street", "sport", "race"
var current_level: int = 0        # 0..3

var proposed_tier: String = ""
var proposed_level: int = 0

# We store original tyres.ini text so we can reconstruct cleanly
var _stock_tyres_ini_text: String = ""
var _stock_data_dir: String = ""


func store_stock_values() -> void:
	# Called after load_from_data_dir
	stock_default_index = default_compound_index
	stock_best_mu_lat = best_lateral_mu
	stock_best_mu_long = best_longitudinal_mu

	var classification = _classify_mu(stock_best_mu_lat)
	stock_tier = classification["tier"]
	stock_level = classification["level"]

	current_tier = stock_tier
	current_level = stock_level
	proposed_tier = ""
	proposed_level = 0

	# Capture raw tyres.ini
	if _stock_data_dir != "":
		var path = _stock_data_dir.path_join("tyres.ini")
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			if f:
				_stock_tyres_ini_text = f.get_as_text()
				f.close()


func load_from_data_dir(data_dir: String) -> void:
	_stock_data_dir = data_dir

	var ini := IniParser.parse_file(data_dir + "/tyres.ini")

	_front_by_index.clear()
	_rear_by_index.clear()
	_compound_indices.clear()

	best_mechanical_grip_index = 0.0
	best_lateral_mu = 0.0
	best_longitudinal_mu = 0.0
	best_compound_name = ""
	best_compound_short_name = ""
	best_compound_index = 0

	if ini.has("COMPOUND_DEFAULT"):
		var c = ini["COMPOUND_DEFAULT"]
		default_compound_index = IniParser.get_int(c, "INDEX", 0)
	else:
		default_compound_index = 0

	for section_name in ini.keys():
		if section_name.begins_with("FRONT"):
			_parse_compound(section_name, ini[section_name], true, data_dir)
		elif section_name.begins_with("REAR"):
			_parse_compound(section_name, ini[section_name], false, data_dir)
		elif section_name.begins_with("THERMAL_FRONT"):
			_parse_thermal(section_name, ini[section_name], true, data_dir)
		elif section_name.begins_with("THERMAL_REAR"):
			_parse_thermal(section_name, ini[section_name], false, data_dir)

	_compute_best_compound_metrics()


func get_all_upgrade_options() -> Array:
	var opts: Array = []
	for tier in ["street", "sport", "race"]:
		for level in [1, 2, 3]:
			var target_mu = TARGET_DY[tier][level]
			var mech_index = _mu_to_mech_index(target_mu)
			opts.append({
				"tier": tier,
				"level": level,
				"display_name": "%s L%d" % [TIER_DISPLAY[tier], level],
				"short_name": TIER_SHORT[tier],
				"cost": TYRE_COSTS[tier][level],
				"target_mu": target_mu,
				"target_mech_index": mech_index,
			})
	return opts


func preview_with_upgrade(tier: String, level: int) -> void:
	proposed_tier = tier
	proposed_level = level


func clear_preview() -> void:
	proposed_tier = ""
	proposed_level = 0


func is_upgrade_applied(tier: String, level: int) -> bool:
	return current_tier == tier and current_level == level


func apply_tyre_upgrade(tier: String, level: int) -> void:
	current_tier = tier
	current_level = level
	clear_preview()

	var mu = TARGET_DY.get(tier, {}).get(level, best_lateral_mu)
	best_lateral_mu = mu
	best_longitudinal_mu = TARGET_DX.get(tier, {}).get(level, best_longitudinal_mu)
	best_mechanical_grip_index = _mu_to_mech_index(best_lateral_mu)

	best_compound_name = "%s L%d" % [TIER_DISPLAY.get(tier, "Tyres"), level]
	best_compound_short_name = TIER_SHORT.get(tier, "TY")


func can_remove_tyre_upgrade() -> bool:
	return not (current_tier == stock_tier and current_level == stock_level)


func revert_to_stock() -> void:
	current_tier = stock_tier
	current_level = stock_level
	clear_preview()

	# Restore computed metrics
	default_compound_index = stock_default_index

	best_lateral_mu = stock_best_mu_lat
	best_longitudinal_mu = stock_best_mu_long
	best_mechanical_grip_index = _mu_to_mech_index(best_lateral_mu)

	best_compound_name = ""
	best_compound_short_name = ""


# Writer support (called by CarLoader)

func build_upgraded_tyres_ini_text() -> String:
	# If no upgrade beyond stock, just return the original file
	if not can_remove_tyre_upgrade():
		if _stock_tyres_ini_text != "":
			return _stock_tyres_ini_text

	# Baseline is stock text if available, else reconstruct minimal
	var base_text := _stock_tyres_ini_text
	if base_text == "":
		base_text = _reconstruct_minimal_ini()

	# Determine a safe new index
	var max_idx := _get_max_compound_index_from_parsed()
	var new_idx := max_idx + 1
	# After we know new_idx and before we build `out`
	# Update COMPOUND_DEFAULT to point to the new compound index
	var base_lines := base_text.split("\n", false)
	var in_cd := false
	for i in range(base_lines.size()):
		var line := base_lines[i].strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			in_cd = (line == "[COMPOUND_DEFAULT]")
			continue
		if in_cd and line.begins_with("INDEX="):
			base_lines[i] = "INDEX=%d" % new_idx
			break
	base_text = "\n".join(base_lines)
	# Use default compound as a template if possible
	var template_f: TyreCompound = null
	var template_r: TyreCompound = null
	if _front_by_index.has(stock_default_index):
		template_f = _front_by_index[stock_default_index]
	if _rear_by_index.has(stock_default_index):
		template_r = _rear_by_index[stock_default_index]

	# Fallback to any available
	if template_f == null and _front_by_index.size() > 0:
		template_f = _front_by_index[_compound_indices[0]]
	if template_r == null and _rear_by_index.size() > 0:
		template_r = _rear_by_index[_compound_indices[0]]

	# If still null, bail out with base
	if template_f == null or template_r == null:
		return base_text

	var tier := current_tier
	var level := current_level
	var dy = TARGET_DY.get(tier, {}).get(level, template_f.dy_ref)
	var dx = TARGET_DX.get(tier, {}).get(level, template_f.dx_ref)

	var tiername = "%s L%d" % [TIER_DISPLAY.get(tier, "Tyres"), level]
	var short = "%s%d" % [TIER_SHORT.get(tier, "TY"), level]

	var front_section := _compound_to_ini_section(template_f, "FRONT_%d" % new_idx, tiername, short, new_idx, dy, dx)
	var rear_section := _compound_to_ini_section(template_r, "REAR_%d" % new_idx, tiername, short, new_idx, dy, dx)

	# Add matching thermal sections if we have templates
	var thermal_front_text := ""
	var thermal_rear_text := ""
	if template_f.thermal != null:
		thermal_front_text = _thermal_to_ini_section(template_f.thermal, "THERMAL_FRONT_%d" % new_idx)
	if template_r.thermal != null:
		thermal_rear_text = _thermal_to_ini_section(template_r.thermal, "THERMAL_REAR_%d" % new_idx)

	# Append to base text
	var out := base_text.strip_edges() + "\n\n; ───────── JS TUNER TYRE UPGRADE ─────────\n"
	out += front_section + "\n\n" + rear_section + "\n"
	if thermal_front_text != "":
		out += "\n" + thermal_front_text + "\n"
	if thermal_rear_text != "":
		out += "\n" + thermal_rear_text + "\n"

	return out


func _index_from_section_name(partname: String, prefix: String) -> int:
	if partname == prefix:
		return 0
	var parts := partname.split("_", false)
	if parts.size() >= 2:
		var idx_str := parts[1]
		if idx_str.is_valid_int():
			return int(idx_str)
	return 0


func _parse_compound(section_name: String, sec: Dictionary, is_front: bool, data_dir: String) -> void:
	var comp := TyreCompound.new()
	if is_front:
		comp.index = _index_from_section_name(section_name, "FRONT")
		comp.axle = "front"
	else:
		comp.index = _index_from_section_name(section_name, "REAR")
		comp.axle = "rear"

	comp.name = IniParser.get_str(sec, "NAME", "")
	comp.short_name = IniParser.get_str(sec, "SHORT_NAME", "")

	comp.width = IniParser.get_float(sec, "WIDTH", 0.0)
	comp.radius = IniParser.get_float(sec, "RADIUS", 0.0)
	comp.rim_radius = IniParser.get_float(sec, "RIM_RADIUS", 0.0)
	comp.angular_inertia = IniParser.get_float(sec, "ANGULAR_INERTIA", 0.0)
	comp.damp = IniParser.get_float(sec, "DAMP", 0.0)
	comp.rate = IniParser.get_float(sec, "RATE", 0.0)

	comp.fz0 = IniParser.get_float(sec, "FZ0", 0.0)
	comp.dy_ref = IniParser.get_float(sec, "DY_REF", IniParser.get_float(sec, "DY0", 1.0))
	comp.dx_ref = IniParser.get_float(sec, "DX_REF", IniParser.get_float(sec, "DX0", 1.0))
	comp.ls_expy = IniParser.get_float(sec, "LS_EXPY", 1.0)
	comp.ls_expx = IniParser.get_float(sec, "LS_EXPX", 1.0)
	comp.friction_limit_angle = IniParser.get_float(sec, "FRICTION_LIMIT_ANGLE", 0.0)

	comp.pressure_static = float(IniParser.get_int(sec, "PRESSURE_STATIC", 0))
	comp.pressure_ideal = float(IniParser.get_int(sec, "PRESSURE_IDEAL", 0))
	comp.pressure_d_gain = IniParser.get_float(sec, "PRESSURE_D_GAIN", 0.0)
	comp.speed_sensitivity = IniParser.get_float(sec, "SPEED_SENSITIVITY", 0.0)

	comp.camber_gain = IniParser.get_float(sec, "CAMBER_GAIN", 0.0)
	comp.dcamber_0 = IniParser.get_float(sec, "DCAMBER_0", 0.0)
	comp.dcamber_1 = IniParser.get_float(sec, "DCAMBER_1", 0.0)

	comp.flex_gain = IniParser.get_float(sec, "FLEX_GAIN", 0.0)
	comp.falloff_level = IniParser.get_float(sec, "FALLOFF_LEVEL", 1.0)
	comp.falloff_speed = IniParser.get_float(sec, "FALLOFF_SPEED", 1.0)
	comp.cx_mult = IniParser.get_float(sec, "CX_MULT", 1.0)
	comp.brake_dx_mod = IniParser.get_float(sec, "BRAKE_DX_MOD", 0.0)

	comp.wear_curve_path = IniParser.get_str(sec, "WEAR_CURVE", "")
	if comp.wear_curve_path != "":
		comp.wear_curve_points = LutUtils.load_lut(data_dir + "/" + comp.wear_curve_path)

	if is_front:
		_front_by_index[comp.index] = comp
	else:
		_rear_by_index[comp.index] = comp

	if not _compound_indices.has(comp.index):
		_compound_indices.append(comp.index)


func _parse_thermal(section_name: String, sec: Dictionary, is_front: bool, data_dir: String) -> void:
	var idx
	if is_front:
		idx = _index_from_section_name(section_name, "THERMAL_FRONT")
	else:
		idx = _index_from_section_name(section_name, "THERMAL_REAR")

	var th := TyreThermal.new()
	th.surface_transfer = IniParser.get_float(sec, "SURFACE_TRANSFER", 0.0)
	th.patch_transfer = IniParser.get_float(sec, "PATCH_TRANSFER", 0.0)
	th.core_transfer = IniParser.get_float(sec, "CORE_TRANSFER", 0.0)
	th.internal_core_transfer = IniParser.get_float(sec, "INTERNAL_CORE_TRANSFER", 0.0)
	th.friction_k = IniParser.get_float(sec, "FRICTION_K", 0.0)
	th.rolling_k = IniParser.get_float(sec, "ROLLING_K", 0.0)
	th.performance_curve_path = IniParser.get_str(sec, "PERFORMANCE_CURVE", "")
	if th.performance_curve_path != "":
		th.performance_curve_points = LutUtils.load_lut(data_dir + "/" + th.performance_curve_path)
	th.grain_gamma = IniParser.get_float(sec, "GRAIN_GAMMA", 0.0)
	th.grain_gain = IniParser.get_float(sec, "GRAIN_GAIN", 0.0)
	th.blister_gamma = IniParser.get_float(sec, "BLISTER_GAMMA", 0.0)
	th.blister_gain = IniParser.get_float(sec, "BLISTER_GAIN", 0.0)
	th.cool_factor = IniParser.get_float(sec, "COOL_FACTOR", 0.0)
	th.surface_rolling_k = IniParser.get_float(sec, "SURFACE_ROLLING_K", 0.0)

	var dict = _front_by_index if is_front else _rear_by_index
	if dict.has(idx):
		var comp: TyreCompound = dict[idx]
		comp.thermal = th


func _compute_best_compound_metrics() -> void:
	best_lateral_mu = 0.0
	best_longitudinal_mu = 0.0
	best_mechanical_grip_index = 0.0
	best_compound_name = ""
	best_compound_short_name = ""
	best_compound_index = default_compound_index

	var chosen_mu_lat := 0.0
	var chosen_mu_long := 0.0
	var chosen_name := ""
	var chosen_short := ""
	var chosen_index := default_compound_index

	if _front_by_index.has(default_compound_index) and _rear_by_index.has(default_compound_index):
		var cf: TyreCompound = _front_by_index[default_compound_index]
		var cr: TyreCompound = _rear_by_index[default_compound_index]

		chosen_mu_lat = min(cf.get_peak_lateral_mu(), cr.get_peak_lateral_mu())
		chosen_mu_long = min(cf.get_peak_longitudinal_mu(), cr.get_peak_longitudinal_mu())
		chosen_name = cf.name
		chosen_short = cf.short_name
		chosen_index = default_compound_index
	else:
		for idx in _compound_indices:
			if not _front_by_index.has(idx) or not _rear_by_index.has(idx):
				continue

			var cf2: TyreCompound = _front_by_index[idx]
			var cr2: TyreCompound = _rear_by_index[idx]

			var mu_pair2 = min(cf2.get_peak_lateral_mu(), cr2.get_peak_lateral_mu())

			if mu_pair2 > chosen_mu_lat:
				chosen_mu_lat = mu_pair2
				chosen_mu_long = min(cf2.get_peak_longitudinal_mu(), cr2.get_peak_longitudinal_mu())
				chosen_name = cf2.name
				chosen_short = cf2.short_name
				chosen_index = idx

	best_lateral_mu = chosen_mu_lat
	best_longitudinal_mu = chosen_mu_long
	best_compound_name = chosen_name
	best_compound_short_name = chosen_short
	best_compound_index = chosen_index

	best_mechanical_grip_index = _mu_to_mech_index(best_lateral_mu)


func _mu_to_mech_index(mu_in: float) -> float:
	if mu_in <= 0.0:
		return 0.0

	var mu = clamp(mu_in, 0.95, 1.70)
	var mu_min := 0.95
	var mu_max := 1.70
	var norm_mu = (mu - mu_min) / (mu_max - mu_min)
	norm_mu = clamp(norm_mu, 0.0, 1.0)
	var gamma := 0.8
	norm_mu = pow(norm_mu, gamma)
	return clamp(1.0 + 9.0 * norm_mu, 1.0, 10.0)


func _classify_mu(mu: float) -> Dictionary:
	if mu < 1.15:
		return {"tier": "street", "level": 1}
	elif mu < 1.23:
		return {"tier": "street", "level": 2}
	elif mu < 1.28:
		return {"tier": "street", "level": 3}
	elif mu < 1.36:
		return {"tier": "sport", "level": 1}
	elif mu < 1.43:
		return {"tier": "sport", "level": 2}
	elif mu < 1.49:
		return {"tier": "sport", "level": 3}
	elif mu < 1.60:
		return {"tier": "race", "level": 1}
	elif mu < 1.68:
		return {"tier": "race", "level": 2}
	else:
		return {"tier": "race", "level": 3}


func _get_max_compound_index_from_parsed() -> int:
	var max_idx := 0
	for idx in _compound_indices:
		max_idx = max(max_idx, idx)
	return max_idx


func _compound_to_ini_section(template: TyreCompound, section_name: String, ininame: String, short: String, _idx: int, dy: float, dx: float) -> String:
	var t := ""
	t += "[%s]\n" % section_name
	t += "NAME=%s\n" % ininame
	t += "SHORT_NAME=%s\n" % short

	t += "WIDTH=%.4f\n" % template.width
	t += "RADIUS=%.5f\n" % template.radius
	t += "RIM_RADIUS=%.4f\n" % template.rim_radius
	t += "ANGULAR_INERTIA=%.4f\n" % template.angular_inertia
	t += "DAMP=%.0f\n" % template.damp
	t += "RATE=%.0f\n" % template.rate

	# Keep most handling parameters so mods stay coherent,
	# but override the headline grip.
	t += "FZ0=%.0f\n" % template.fz0
	t += "LS_EXPY=%.4f\n" % template.ls_expy
	t += "LS_EXPX=%.4f\n" % template.ls_expx
	t += "FRICTION_LIMIT_ANGLE=%.2f\n" % template.friction_limit_angle

	t += "DX_REF=%.3f\n" % dx
	t += "DY_REF=%.3f\n" % dy

	if template.wear_curve_path != "":
		t += "WEAR_CURVE=%s\n" % template.wear_curve_path

	t += "SPEED_SENSITIVITY=%.6f\n" % template.speed_sensitivity

	t += "CAMBER_GAIN=%.3f\n" % template.camber_gain
	t += "DCAMBER_0=%.2f\n" % template.dcamber_0
	t += "DCAMBER_1=%.2f\n" % template.dcamber_1

	t += "FLEX_GAIN=%.4f\n" % template.flex_gain
	t += "FALLOFF_LEVEL=%.2f\n" % template.falloff_level
	t += "FALLOFF_SPEED=%.2f\n" % template.falloff_speed
	t += "CX_MULT=%.2f\n" % template.cx_mult
	t += "BRAKE_DX_MOD=%.2f\n" % template.brake_dx_mod

	# Pressure basics
	t += "PRESSURE_STATIC=%d\n" % int(template.pressure_static)
	t += "PRESSURE_IDEAL=%d\n" % int(template.pressure_ideal)
	t += "PRESSURE_D_GAIN=%.4f\n" % template.pressure_d_gain

	return t


func _thermal_to_ini_section(th: TyreThermal, section_name: String) -> String:
	var t := ""
	t += "[%s]\n" % section_name
	t += "SURFACE_TRANSFER=%.4f\n" % th.surface_transfer
	t += "PATCH_TRANSFER=%.5f\n" % th.patch_transfer
	t += "CORE_TRANSFER=%.6f\n" % th.core_transfer
	t += "INTERNAL_CORE_TRANSFER=%.6f\n" % th.internal_core_transfer
	t += "FRICTION_K=%.5f\n" % th.friction_k
	t += "ROLLING_K=%.3f\n" % th.rolling_k
	if th.performance_curve_path != "":
		t += "PERFORMANCE_CURVE=%s\n" % th.performance_curve_path
	t += "GRAIN_GAMMA=%.3f\n" % th.grain_gamma
	t += "GRAIN_GAIN=%.3f\n" % th.grain_gain
	t += "BLISTER_GAMMA=%.3f\n" % th.blister_gamma
	t += "BLISTER_GAIN=%.3f\n" % th.blister_gain
	t += "COOL_FACTOR=%.2f\n" % th.cool_factor
	t += "SURFACE_ROLLING_K=%.5f\n" % th.surface_rolling_k
	return t


func _reconstruct_minimal_ini() -> String:
	var out := "[HEADER]\nVERSION=10\n\n"
	out += "[COMPOUND_DEFAULT]\nINDEX=%d\n\n" % default_compound_index
	return out
