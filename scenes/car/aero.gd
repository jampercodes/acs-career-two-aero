# aero.gd
extends Node
class_name Aero

# normal AC wings (per-element CL/CD)
class Wing:
	var index: int = -1              # WING_0, WING_1, ...
	var name: String = ""
	var chord: float = 0.0
	var span: float = 0.0
	var position: Vector3 = Vector3.ZERO

	var lut_aoa_cl: String = ""
	var lut_gh_cl: String = ""
	var cl_gain: float = 0.0

	var lut_aoa_cd: String = ""
	var lut_gh_cd: String = ""
	var cd_gain: float = 0.0

	var angle: float = 0.0

	var zone_front_cl: float = 0.0
	var zone_front_cd: float = 0.0
	var zone_rear_cl: float = 0.0
	var zone_rear_cd: float = 0.0
	var zone_left_cl: float = 0.0
	var zone_left_cd: float = 0.0
	var zone_right_cl: float = 0.0
	var zone_right_cd: float = 0.0

	# Cached LUT data
	var aoa_cl_points: Array[Vector2] = []
	var gh_cl_points: Array[Vector2] = []
	var aoa_cd_points: Array[Vector2] = []
	var gh_cd_points: Array[Vector2] = []


# CSP aero maps (2D ride-height maps etc.)
class AeroMap:
	var name: String = ""

	var cl_rh_path: String = ""
	var cd_rh_path: String = ""

	var cl_rh_lut: Dictionary = {}          # 2D: front RH vs rear RH -> CL*area
	var cd_rh_lut: Dictionary = {}          # 2D: front RH vs rear RH -> CD*area

	var speed_cl_points: Array[Vector2] = []  # kph -> multiplier
	var speed_cd_points: Array[Vector2] = []  # kph -> multiplier

	var front_rh_offset: float = 0.0
	var rear_rh_offset: float = 0.0

	var cl_mult: float = 1.0
	var cd_mult: float = 1.0


# Dynamic controllers (used by some mods, like RSS F1 2021)
# We only care about:
#   INPUT=SPEED_KMH
#   COMBINATOR=ADD
# that modify the WING's ANGLE based on speed.

class DynamicController:
	var wing_index: int = -1
	var combinator: String = ""
	var input_type: String = ""
	var lut_name: String = ""
	var lut_points: Array[Vector2] = []
	var up_limit: float = 0.0
	var down_limit: float = 0.0


var wings: Array[Wing] = []
var maps: Array[AeroMap] = []
var _dynamic_controllers: Array[DynamicController] = []

# Reference aero metrics (at some chosen speed)
var ref_speed_kmh: float = 200.0
var ref_downforce_N: float = 0.0
var ref_drag_N: float = 0.0
var ref_downforce_ratio: float = 0.0   # downforce / static weight (filled in Car)

const AERO_PARTS = [
	# Stage 3 - Race upgrades
	{"id": 901, "name": "wing", "stage": 3, "super_type": 901, "mult": 0.975, "cost": 2500, "desc": "Large wing"},
]

# Currently installed weight reduction parts (by super_type)
var installed_parts: Dictionary = {}  # super_type -> part_id

func store_stock_values():
	pass

func load_from_data_dir(data_dir: String) -> void:
	
	var ini := IniParser.parse_file(data_dir + "/aero.ini")
	wings.clear()
	maps.clear()
	_dynamic_controllers.clear()

	for section_name in ini.keys():
		var sec: Dictionary = ini[section_name]

		# Classic WING_x sections 
		if section_name.begins_with("WING_"):
			var w := Wing.new()

			# WING index from the section name ("WING_0" -> 0)
			var idx_str = section_name.substr(5)
			var idx := -1
			if idx_str.is_valid_int():
				idx = int(idx_str)
			w.index = idx

			w.name = IniParser.get_str(sec, "NAME", "")
			w.chord = IniParser.get_float(sec, "CHORD", 0.0)
			w.span = IniParser.get_float(sec, "SPAN", 0.0)
			w.position = IniParser.parse_vec3(IniParser.get_str(sec, "POSITION", "0,0,0"))

			w.lut_aoa_cl = IniParser.get_str(sec, "LUT_AOA_CL", "")
			w.lut_gh_cl = IniParser.get_str(sec, "LUT_GH_CL", "")
			w.cl_gain = IniParser.get_float(sec, "CL_GAIN", 0.0)

			w.lut_aoa_cd = IniParser.get_str(sec, "LUT_AOA_CD", "")
			w.lut_gh_cd = IniParser.get_str(sec, "LUT_GH_CD", "")
			w.cd_gain = IniParser.get_float(sec, "CD_GAIN", 0.0)

			w.angle = IniParser.get_float(sec, "ANGLE", 0.0)

			w.zone_front_cl = IniParser.get_float(sec, "ZONE_FRONT_CL", 0.0)
			w.zone_front_cd = IniParser.get_float(sec, "ZONE_FRONT_CD", 0.0)
			w.zone_rear_cl = IniParser.get_float(sec, "ZONE_REAR_CL", 0.0)
			w.zone_rear_cd = IniParser.get_float(sec, "ZONE_REAR_CD", 0.0)
			w.zone_left_cl = IniParser.get_float(sec, "ZONE_LEFT_CL", 0.0)
			w.zone_left_cd = IniParser.get_float(sec, "ZONE_LEFT_CD", 0.0)
			w.zone_right_cl = IniParser.get_float(sec, "ZONE_RIGHT_CL", 0.0)
			w.zone_right_cd = IniParser.get_float(sec, "ZONE_RIGHT_CD", 0.0)

			# Load LUTs if present
			if w.lut_aoa_cl != "":
				w.aoa_cl_points = LutUtils.load_lut(data_dir + "/" + w.lut_aoa_cl)
			if w.lut_gh_cl != "":
				w.gh_cl_points = LutUtils.load_lut(data_dir + "/" + w.lut_gh_cl)

			if w.lut_aoa_cd != "":
				w.aoa_cd_points = LutUtils.load_lut(data_dir + "/" + w.lut_aoa_cd)
			if w.lut_gh_cd != "":
				w.gh_cd_points = LutUtils.load_lut(data_dir + "/" + w.lut_gh_cd)

			wings.append(w)

		# CSP MAP_x sections 
		elif section_name.begins_with("MAP_"):
			var m := AeroMap.new()
			m.name = IniParser.get_str(sec, "NAME", section_name)

			m.cl_rh_path = IniParser.get_str(sec, "MAP_CL_RH", "")
			m.cd_rh_path = IniParser.get_str(sec, "MAP_CD_RH", "")

			if m.cl_rh_path != "":
				m.cl_rh_lut = LutUtils.load_lut_2d(data_dir + "/" + m.cl_rh_path)
			if m.cd_rh_path != "":
				m.cd_rh_lut = LutUtils.load_lut_2d(data_dir + "/" + m.cd_rh_path)

			var speed_cl_name := IniParser.get_str(sec, "MAP_SPEED_CL", "")
			if speed_cl_name != "":
				m.speed_cl_points = LutUtils.load_lut(data_dir + "/" + speed_cl_name)

			var speed_cd_name := IniParser.get_str(sec, "MAP_SPEED_CD", "")
			if speed_cd_name != "":
				m.speed_cd_points = LutUtils.load_lut(data_dir + "/" + speed_cd_name)

			m.front_rh_offset = IniParser.get_float(sec, "FRONT_RH_OFFSET", 0.0)
			m.rear_rh_offset = IniParser.get_float(sec, "REAR_RH_OFFSET", 0.0)

			m.cl_mult = IniParser.get_float(sec, "CL_MULT", 1.0)
			m.cd_mult = IniParser.get_float(sec, "CD_MULT", 1.0)

			maps.append(m)

		# DYNAMIC_CONTROLLER_x sections
		elif section_name.begins_with("DYNAMIC_CONTROLLER_"):
			var dc := DynamicController.new()
			dc.wing_index = IniParser.get_int(sec, "WING", -1)
			dc.combinator = IniParser.get_str(sec, "COMBINATOR", "").to_upper()
			dc.input_type = IniParser.get_str(sec, "INPUT", "").to_upper()

			var lut_name := IniParser.get_str(sec, "LUT", "")
			dc.lut_name = lut_name
			if lut_name != "":
				dc.lut_points = LutUtils.load_lut(data_dir + "/" + lut_name)

			dc.up_limit = IniParser.get_float(sec, "UP_LIMIT", 0.0)
			dc.down_limit = IniParser.get_float(sec, "DOWN_LIMIT", 0.0)

			_dynamic_controllers.append(dc)

	# After wings & maps are loaded, compute reference aero forces
	_compute_reference_aero()



func _compute_reference_aero() -> void:
	ref_downforce_N = 0.0
	ref_drag_N = 0.0
	ref_downforce_ratio = 0.0

	var v_ms := ref_speed_kmh / 3.6  # 200 km/h ~ 55.56 m/s
	var rho := 1.225                 # air density kg/m^3

	# Precompute dynamic angle offsets
	var wing_angle_offset := {}  # Dictionary: int wing_index -> float delta_angle_deg

	for dc in _dynamic_controllers:
		if dc.input_type != "SPEED_KMH":
			continue
		if dc.combinator != "ADD":
			continue
		if dc.wing_index < 0:
			continue
		if dc.lut_points.is_empty():
			continue

		var delta := LutUtils.eval_lut(dc.lut_points, ref_speed_kmh, 0.0)
		# Apply UP/DOWN_LIMIT 
		# (for many mods DOWN_LIMIT=0, UP_LIMIT=some_max_deg)
		if dc.down_limit != 0.0 or dc.up_limit != 0.0:
			delta = clamp(delta, dc.down_limit, dc.up_limit)

		if not wing_angle_offset.has(dc.wing_index):
			wing_angle_offset[dc.wing_index] = delta
		else:
			wing_angle_offset[dc.wing_index] += delta

	# lassic WING_x aero contributions 
	for w in wings:
		var area := w.chord * w.span
		if area <= 0.0:
			continue

		# Base AoA + any dynamic controller offset
		var aoa := w.angle
		if wing_angle_offset.has(w.index):
			aoa += float(wing_angle_offset[w.index])

		var gh_ref := 0.05    # 5 cm generic ground clearance

		# CL: area * CL_GAIN * LUT_AOA_CL * LUT_GH_CL
		var cl_aoa := 0.0
		if w.aoa_cl_points.size() > 0:
			cl_aoa = LutUtils.eval_lut(w.aoa_cl_points, aoa, 0.0)

		var cl_gh := 1.0
		if w.gh_cl_points.size() > 0:
			cl_gh = LutUtils.eval_lut(w.gh_cl_points, gh_ref, 1.0)

		var cl_area := area * w.cl_gain * cl_aoa * cl_gh

		# CD: area * CD_GAIN * LUT_AOA_CD * LUT_GH_CD
		var cd_aoa := 0.0
		if w.aoa_cd_points.size() > 0:
			cd_aoa = LutUtils.eval_lut(w.aoa_cd_points, aoa, 0.0)

		var cd_gh := 1.0
		if w.gh_cd_points.size() > 0:
			cd_gh = LutUtils.eval_lut(w.gh_cd_points, gh_ref, 1.0)

		var cd_area := area * w.cd_gain * cd_aoa * cd_gh

		var df := 0.5 * rho * v_ms * v_ms * cl_area
		var drag := 0.5 * rho * v_ms * v_ms * cd_area

		ref_downforce_N += df
		ref_drag_N += drag

	# CSP MAP_x aero maps 
	for m in maps:
		if m.cl_rh_lut.is_empty() and m.cd_rh_lut.is_empty():
			continue

		# Pick a representative (front, rear) ride height:
		# midpoint of the 2D LUT domain, plus any offsets.
		var xs: PackedFloat32Array = m.cl_rh_lut.get("x", PackedFloat32Array())
		var ys: PackedFloat32Array = m.cl_rh_lut.get("y", PackedFloat32Array())
		if xs.size() == 0 or ys.size() == 0:
			continue

		var front_rh := (xs[0] + xs[xs.size() - 1]) * 0.5 + m.front_rh_offset
		var rear_rh := (ys[0] + ys[ys.size() - 1]) * 0.5 + m.rear_rh_offset

		var cl_area_map := 0.0
		if not m.cl_rh_lut.is_empty():
			cl_area_map = LutUtils.eval_lut_2d(m.cl_rh_lut, front_rh, rear_rh, 0.0)

		var cd_area_map := 0.0
		if not m.cd_rh_lut.is_empty():
			cd_area_map = LutUtils.eval_lut_2d(m.cd_rh_lut, front_rh, rear_rh, 0.0)

		# Speed multipliers
		var speed_mul_cl := 1.0
		if m.speed_cl_points.size() > 0:
			speed_mul_cl = LutUtils.eval_lut(m.speed_cl_points, ref_speed_kmh, 1.0)

		var speed_mul_cd := 1.0
		if m.speed_cd_points.size() > 0:
			speed_mul_cd = LutUtils.eval_lut(m.speed_cd_points, ref_speed_kmh, 1.0)

		cl_area_map *= m.cl_mult * speed_mul_cl
		cd_area_map *= m.cd_mult * speed_mul_cd

		var df_map := 0.5 * rho * v_ms * v_ms * cl_area_map
		var drag_map := 0.5 * rho * v_ms * v_ms * cd_area_map

		ref_downforce_N += df_map
		ref_drag_N += drag_map

# ============================================================================
# AERO PARTS
# ============================================================================

# Get part definition by ID
func _get_part_by_id(part_id: int) -> Dictionary:
	for part in AERO_PARTS:
		if part["id"] == part_id:
			return part
	return {}

# Get currently installed part in a specific upgrade line
func _get_installed_part_in_line(super_type: int) -> Dictionary:
	if installed_parts.has(super_type):
		return _get_part_by_id(installed_parts[super_type])
	return {}

# Check if a part is currently installed
func is_part_installed(part_id: int) -> bool:
	return installed_parts.values().has(part_id)

# Check if any part in the same upgrade line is installed
func has_part_in_line(super_type: int) -> bool:
	return installed_parts.has(super_type)

# Get all available upgrade options
func get_all_upgrade_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	for part in AERO_PARTS:
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

# Apply a aero upgrade
func apply_aero_upgrade(_car: Car, part_id: int) -> bool:
	var part = _get_part_by_id(part_id)
	if part.is_empty():
		printerr("Invalid earo part ID: ", part_id)
		return false

	var super_type: int = part["super_type"]

	# Install part (replacing any existing part in the same line)
	installed_parts[super_type] = part_id

	# probebly need to do some data stuf idk

	return true
