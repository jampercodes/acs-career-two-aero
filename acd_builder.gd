extends Node
class_name AcdBuilder
# cribbed from Content Manager and ACD parser on github

func build_acd_from_data(car_dir: String) -> bool:
	car_dir = car_dir.replace("\\", "/")

	var data_dir_path := _join_path(car_dir, "data")
	var data_acd_path := _join_path(car_dir, "data.acd")

	if not DirAccess.dir_exists_absolute(data_dir_path):
		push_error("Data directory does not exist: %s" % data_dir_path)
		return false

	# Build encryption key from car folder name
	var folder_name := _get_last_path_segment(car_dir)
	var key := _build_encryption_key(folder_name)

	# Collect all files from data directory
	var entries: Array[Dictionary] = []
	_collect_files_recursive(data_dir_path, data_dir_path, entries)

	if entries.is_empty():
		push_warning("No files found in data directory: %s" % data_dir_path)
		return false

	# Build the ACD file in memory
	var stream := StreamPeerBuffer.new()
	stream.big_endian = false  # Little-endian

	for entry in entries:
		var entry_name: String = entry["name"]
		var file_data: PackedByteArray = entry["data"]

		# Write entry name (length + string)
		_write_string(stream, entry_name)

		# Write original data length
		_write_int32(stream, file_data.size())

		# Encrypt the data
		var encrypted := _encrypt_data(file_data, key)

		# Write encrypted bytes (with 3-byte padding after each byte)
		for b in encrypted:
			stream.put_u8(b)
			stream.put_u8(0)  # padding
			stream.put_u8(0)  # padding
			stream.put_u8(0)  # padding

	# Write to file
	var output := stream.data_array
	var file := FileAccess.open(data_acd_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to create ACD file: %s" % data_acd_path)
		return false

	file.store_buffer(output)
	file.close()

	print("[AcdBuilder] Created data.acd for: %s (%d entries, %d bytes)" % [
		folder_name,
		entries.size(),
		output.size()
	])
	return true


func _collect_files_recursive(base_dir: String, current_dir: String, entries: Array[Dictionary]) -> void:
	var dir := DirAccess.open(current_dir)
	if dir == null:
		push_error("Failed to open directory: %s" % current_dir)
		return

	dir.list_dir_begin()
	while true:
		var item := dir.get_next()
		if item == "":
			break
		if item == "." or item == "..":
			continue

		var full_path := _join_path(current_dir, item)

		if dir.current_is_dir():
			# Recurse into subdirectory
			_collect_files_recursive(base_dir, full_path, entries)
		else:
			# Read file
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file == null:
				push_warning("Failed to read file: %s" % full_path)
				continue

			var data := file.get_buffer(file.get_length())
			file.close()

			# Calculate relative path from base_dir
			var rel_path := full_path.replace(base_dir + "/", "")
			rel_path = rel_path.replace("/", "\\")  # ACD uses backslashes

			entries.append({
				"name": rel_path,
				"data": data
			})

	dir.list_dir_end()


func _write_int32(stream: StreamPeerBuffer, value: int) -> void:
	stream.put_32(value)


func _write_string(stream: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_ascii_buffer()
	_write_int32(stream, bytes.size())
	stream.put_data(bytes)


func _encrypt_data(data: PackedByteArray, key: String) -> PackedByteArray:
	if key.is_empty():
		return data

	var encrypted := PackedByteArray()
	encrypted.resize(data.size())

	var key_len := key.length()
	var key_index := 0

	for i in data.size():
		var b := int(data[i])
		var k_char_code := key.unicode_at(key_index)
		var num4 := b + k_char_code
		if num4 >= 256:
			num4 -= 256
		encrypted[i] = num4

		key_index += 1
		if key_index >= key_len:
			key_index = 0

	return encrypted


func _int_to_byte(value: int) -> int:
	return int(((value % 256) + 256) % 256)


func _build_encryption_key(folder_name: String) -> String:
	var lower_name := folder_name.to_lower()
	var n := lower_name.length()

	if n == 0:
		return ""
	var chars: Array[int] = []
	chars.resize(n)
	for i in n:
		chars[i] = lower_name.unicode_at(i)

	# Octet 1
	var aggregate_seed := 0
	for c in chars:
		aggregate_seed += c
	var octet1 := _int_to_byte(aggregate_seed)

	# Octet 2
	var num := 0
	var i := 0
	while i < n - 1:
		num = (num * chars[i]) - chars[i + 1]
		i += 2
	var octet2 := _int_to_byte(num)

	# Octet 3
	var num2 := 0
	var j := 1
	while j < n - 3:
		num2 = ((num2 * chars[j]) / (chars[j + 1] + 27)) - 27 - chars[j - 1]
		j += 3
	var octet3 := _int_to_byte(num2)

	# Octet 4
	var num3 := 5763
	var k := 1
	while k < n:
		num3 -= chars[k]
		k += 1
	var octet4 := _int_to_byte(num3)

	# Octet 5
	var num4 := 66
	var l := 1
	while l < n - 4:
		num4 = (chars[l] + 15) * num4 * (chars[l - 1] + 15) + 22
		l += 4
	var octet5 := _int_to_byte(num4)

	# Octet 6
	var num5 := 101
	var m := 0
	while m < n - 2:
		num5 -= chars[m]
		m += 2
	var octet6 := _int_to_byte(num5)

	# Octet 7
	var num6 := 171
	var n_idx := 0
	while n_idx < n - 2:
		if chars[n_idx] != 0:
			num6 %= chars[n_idx]
		n_idx += 2
	var octet7 := _int_to_byte(num6)

	# Octet 8
	var num7 := 171
	var p := 0
	while p < n - 1:
		if chars[p] != 0:
			num7 = int(num7 / chars[p]) + chars[p + 1]
		p += 1
	var octet8 := _int_to_byte(num7)

	var parts := [
		str(octet1),
		str(octet2),
		str(octet3),
		str(octet4),
		str(octet5),
		str(octet6),
		str(octet7),
		str(octet8),
	]
	var key := "-".join(parts)
	return key


func _join_path(a: String, b: String) -> String:
	if a.ends_with("/") or a.ends_with("\\"):
		return (a + b).replace("\\", "/")
	return (a + "/" + b).replace("\\", "/")


func _get_last_path_segment(path: String) -> String:
	var normalized := path.replace("\\", "/").rstrip("/")
	var idx := normalized.rfind("/")
	if idx == -1:
		return normalized
	return normalized.substr(idx + 1, normalized.length() - idx - 1)
