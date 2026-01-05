# ini_parser.gd
class_name IniParser

static func parse_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	var current_section := ""

	if not FileAccess.file_exists(path):
		printerr("IniParser: file not found: ", path)
		return result

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("IniParser: cannot open file: ", path)
		return result

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with(";"):
			continue

		# Section
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2)
			if not result.has(current_section):
				result[current_section] = {}
			continue

		# Key=Value
		var eq_idx := line.find("=")
		if eq_idx == -1:
			continue

		var key := line.substr(0, eq_idx).strip_edges()
		var value := line.substr(eq_idx + 1).strip_edges()

		# Strip trailing inline comment
		var semi := value.find(";")
		if semi != -1:
			value = value.substr(0, semi).strip_edges()

		if current_section == "":
			current_section = "GLOBAL"
			if not result.has(current_section):
				result[current_section] = {}

		result[current_section][key] = value

	f.close()
	return result

static func get_str(sec: Dictionary, key: String, default := "") -> String:
	return String(sec.get(key, default))

static func get_float(sec: Dictionary, key: String, default := 0.0) -> float:
	if not sec.has(key):
		return default
	return float(sec[key])

static func get_int(sec: Dictionary, key: String, default := 0) -> int:
	if not sec.has(key):
		return default
	return int(sec[key])

static func get_vec3(sec: Dictionary, key: String, default := Vector3.ZERO) -> Vector3:
	if not sec.has(key):
		return default
	return parse_vec3(String(sec[key]), default)

static func parse_vec3(text: String, default := Vector3.ZERO) -> Vector3:
	var parts := text.split(",", false)
	if parts.size() != 3:
		return default
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
