# lut_utils.gd
class_name LutUtils

static func load_lut(path: String) -> Array[Vector2]:
	var result: Array[Vector2] = []

	# Treat empty / "empty.lut" as "no LUT"
	if path == "" or path.to_lower().ends_with("empty.lut"):
		return result

	var resolved := _resolve_lut_path(path)
	if resolved == "":
		return result

	var f := FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		printerr("LutUtils: cannot open LUT: ", resolved)
		return result

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue

		var parts_str: PackedStringArray

		# Typical AC format is "x|y"
		if line.find("|") != -1:
			parts_str = line.split("|", false)
		else:
			# Fallback: space or tab separated
			parts_str = line.split(" ", false)
			if parts_str.size() < 2:
				parts_str = line.split("\t", false)

		if parts_str.size() >= 2:
			var x := parts_str[0].to_float()
			var y := parts_str[1].to_float()
			result.append(Vector2(x, y))

	f.close()
	return result


static func eval_lut(points: Array[Vector2], x: float, default_value: float = 0.0) -> float:
	if points.is_empty():
		return default_value

	if x <= points[0].x:
		return points[0].y

	for i in range(1, points.size()):
		var p0 := points[i - 1]
		var p1 := points[i]
		if x <= p1.x and p1.x != p0.x:
			var t := (x - p0.x) / (p1.x - p0.x)
			return lerp(p0.y, p1.y, t)

	return points[points.size() - 1].y


# 2D LUTs for CSP aero maps (front RH vs rear RH)
# Returns a Dictionary with keys:
#   "x": PackedFloat32Array (front ride heights)
#   "y": PackedFloat32Array (rear ride heights)
#   "grid": Array[PackedFloat32Array] (values[y][x])
static func load_lut_2d(path: String) -> Dictionary:
	var result: Dictionary = {}

	if path == "":
		return result

	var lower := path.to_lower()
	if lower.ends_with("empty.lut") or lower.ends_with("empty.2dlut"):
		return result

	var resolved := _resolve_lut_path(path)
	if resolved == "":
		printerr("LutUtils: 2D LUT not found (even after fallback): ", path)
		return result

	var f := FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		printerr("LutUtils: cannot open 2D LUT: ", resolved)
		return result

	var rows: Array[PackedFloat32Array] = []

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue

		var tokens := line.split(" ", false)
		if tokens.size() < 2:
			tokens = line.split("\t", false)
		if tokens.size() < 1:
			continue

		var floats := PackedFloat32Array()
		for t in tokens:
			if t == "":
				continue
			floats.append(t.to_float())

		if floats.size() > 0:
			rows.append(floats)

	f.close()

	if rows.size() < 2:
		return result  # need header + at least 1 row

	# First row: x axis (front ride heights)
	var x_vals := PackedFloat32Array()
	var header := rows[0]
	for i in range(header.size()):
		x_vals.append(header[i])

	var num_x := x_vals.size()
	if num_x == 0:
		return result

	# Subsequent rows: first value = y axis (rear RH), rest = grid row
	var y_vals := PackedFloat32Array()
	var grid: Array[PackedFloat32Array] = []

	for row_i in range(1, rows.size()):
		var r := rows[row_i]
		if r.size() < 2:
			continue

		var y_val := r[0]
		y_vals.append(y_val)

		var g_row := PackedFloat32Array()
		for col in range(1, min(r.size(), num_x + 1)):
			g_row.append(r[col])

		# pad if shorter than header
		while g_row.size() < num_x:
			g_row.append(g_row[g_row.size() - 1])

		grid.append(g_row)

	if y_vals.size() == 0 or grid.size() == 0:
		return result

	result["x"] = x_vals
	result["y"] = y_vals
	result["grid"] = grid
	return result


static func eval_lut_2d(lut: Dictionary, x: float, y: float, default_value: float = 0.0) -> float:
	if lut.is_empty():
		return default_value
	if not lut.has("x") or not lut.has("y") or not lut.has("grid"):
		return default_value

	var xs: PackedFloat32Array = lut["x"]
	var ys: PackedFloat32Array = lut["y"]
	var grid: Array = lut["grid"]

	if xs.size() == 0 or ys.size() == 0 or grid.size() == 0:
		return default_value

	# Find x indices
	var ix0 := 0
	var ix1 := xs.size() - 1
	if xs.size() > 1:
		if x <= xs[0]:
			ix0 = 0
			ix1 = 1
		elif x >= xs[xs.size() - 1]:
			ix0 = xs.size() - 2
			ix1 = xs.size() - 1
		else:
			for i in range(1, xs.size()):
				if x <= xs[i]:
					ix0 = i - 1
					ix1 = i
					break

	# Find y indices
	var iy0 := 0
	var iy1 := ys.size() - 1
	if ys.size() > 1:
		if y <= ys[0]:
			iy0 = 0
			iy1 = 1
		elif y >= ys[ys.size() - 1]:
			iy0 = ys.size() - 2
			iy1 = ys.size() - 1
		else:
			for j in range(1, ys.size()):
				if y <= ys[j]:
					iy0 = j - 1
					iy1 = j
					break

	var x0 := xs[ix0]
	var x1 := xs[ix1]
	var y0 := ys[iy0]
	var y1 := ys[iy1]

	var row0: PackedFloat32Array = grid[iy0]
	var row1: PackedFloat32Array = grid[iy1]

	var q11 := row0[ix0]
	var q21 := row0[ix1]
	var q12 := row1[ix0]
	var q22 := row1[ix1]

	var tx := 0.0
	var ty := 0.0
	if x1 != x0:
		tx = (x - x0) / (x1 - x0)
	if y1 != y0:
		ty = (y - y0) / (y1 - y0)

	var a = lerp(q11, q21, tx)
	var b = lerp(q12, q22, tx)
	return lerp(a, b, ty)


# Path resolver with some mod-typo tolerance,
# e.g. height_frontwing_CL.lut → height_front_CL.lut
static func _resolve_lut_path(path: String) -> String:
	# Normalise slashes
	var norm := path.replace("\\", "/")

	# If it exists as-is, we're done
	if FileAccess.file_exists(norm):
		return norm

	var base_dir := norm.get_base_dir()
	var fname := norm.get_file()
	var lower := fname.to_lower()

	var candidates: Array[String] = []

	# Specific common typo: "frontwing" / "rearwing"
	if lower.find("frontwing") != -1:
		candidates.append(lower.replace("frontwing", "front"))
	if lower.find("rearwing") != -1:
		candidates.append(lower.replace("rearwing", "rear"))

	# More generic: drop the "wing" word
	if lower.find("wing") != -1:
		candidates.append(lower.replace("wing_", "_"))
		candidates.append(lower.replace("wing", ""))

	var dir := DirAccess.open(base_dir)
	if dir == null:
		return ""

	var files := dir.get_files()

	# Exact filename match against our candidate list
	for cand in candidates:
		for f in files:
			if f.to_lower() == cand:
				return base_dir + "/" + f

	# Fuzzy: same prefix before "wing" and same suffix (_cl.lut / _cd.lut)
	var idx := lower.find("wing")
	if idx != -1:
		var prefix := lower.substr(0, idx)  # e.g. "height_front"
		var suffix := ""
		var uscore := lower.rfind("_")
		if uscore != -1:
			suffix = lower.substr(uscore)   # e.g. "_cl.lut"

		for f in files:
			var lf := f.to_lower()
			if lf.begins_with(prefix) and (suffix == "" or lf.ends_with(suffix)):
				print("LutUtils: LUT '%s' missing, using '%s' (fuzzy match) for car : %s" % [fname, f, path])
				return base_dir + "/" + f

	# Nothing reasonable found
	return ""
