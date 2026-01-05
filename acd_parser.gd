extends Node
class_name AcdExtractor
#cribbed from Content Manager and ACD parser on github

func extract_acd_to_data(car_dir: String) -> void:
	car_dir = car_dir.replace("\\", "/")

	var data_acd_path := _join_path(car_dir, "data.acd")
	var data_dir_path := _join_path(car_dir, "data")

	if not DirAccess.dir_exists_absolute(car_dir):
		push_error("Car directory does not exist: %s" % car_dir)
		return

	if not FileAccess.file_exists(data_acd_path):
		push_warning("No data.acd in %s (nothing to extract)" % car_dir)
		return

	# Read whole file into memory
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(data_acd_path)
	if bytes.is_empty():
		push_error("Failed to read file or file is empty: %s" % data_acd_path)
		return

	# Handle header 
	var pos := 0
	var result := _read_le_i32(bytes, pos)
	var first_int = result.value
	pos = result.pos

	if first_int == -1111:
		# Skip the next int (header field)
		result = _read_le_i32(bytes, pos)
		pos = result.pos
	else:
		# rewind
		pos = 0

	# Build encryption key from car folder name
	var folder_name := _get_last_path_segment(car_dir)
	var key := _build_encryption_key(folder_name)

	# Make sure output directory exists
	DirAccess.make_dir_recursive_absolute(data_dir_path)

	var extracted_files: Array[String] = []
	var skipped_files: Array[String] = []

	# Main loop: read entries until EOF
	while pos < bytes.size():
		# Read entry name
		result = _read_string(bytes, pos)
		var entry_name: String = result.value
		pos = result.pos

		if entry_name.is_empty():
			# probably padding I guess
			break

		# Read original data length
		result = _read_le_i32(bytes, pos)
		var data_len: int = result.value
		pos = result.pos

		if data_len < 0:
			# Negative length is corrupt, skip this entry but continue
			print("[AcdExtractor] Skipping entry '%s' with invalid length: %d" % [entry_name, data_len])
			skipped_files.append(entry_name)
			continue

		# Handle zero-length files
		if data_len == 0:
			# Create empty file
			var empty_normalized_name := entry_name.replace("\\", "/")
			var empty_out_path := _join_path(data_dir_path, empty_normalized_name)
			var empty_out_dir := empty_out_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(empty_out_dir)
			
			var empty_fa := FileAccess.open(empty_out_path, FileAccess.WRITE)
			if empty_fa:
				empty_fa.close()
				extracted_files.append(empty_normalized_name)
			else:
				push_error("Failed to create empty file: %s" % empty_out_path)
				skipped_files.append(empty_normalized_name)
			continue

		# Check if we have enough bytes remaining
		var bytes_needed := data_len * 4  # Each byte + 3 padding
		if pos + bytes_needed > bytes.size():
			print("[AcdExtractor] Not enough bytes for entry '%s': need %d, have %d remaining" % [
				entry_name, bytes_needed, bytes.size() - pos
			])
			skipped_files.append(entry_name)
			break  # Can't continue if we don't have enough data

		# Read encrypted bytes (one useful byte, skip 3 padding bytes)
		var enc_buf := PackedByteArray()
		enc_buf.resize(data_len)

		for i in data_len:
			if pos >= bytes.size():
				print("[AcdExtractor] Unexpected EOF while reading entry '%s' at byte %d/%d" % [entry_name, i, data_len])
				break
			enc_buf[i] = bytes[pos]
			pos += 1
			# Skip padding
			pos += 3

		# Decrypt in-place
		_decrypt_in_place(enc_buf, key)

		# Determine output path
		var normalized_name := entry_name.replace("\\", "/")
		var out_path := _join_path(data_dir_path, normalized_name)
		var out_dir := out_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(out_dir)

		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(enc_buf)
			fa.close()
			extracted_files.append(normalized_name)
		else:
			push_error("Failed to open for write: %s" % out_path)
			skipped_files.append(normalized_name)

	print("[AcdExtractor] Extracted %d files from: %s" % [extracted_files.size(), folder_name])
	if skipped_files.size() > 0:
		print("[AcdExtractor] Skipped %d files due to errors" % skipped_files.size())
	
	# Show all files
	var by_ext := {}
	for f in extracted_files:
		var ext := f.get_extension().to_lower()
		if not by_ext.has(ext):
			by_ext[ext] = []
		by_ext[ext].append(f)
	
	for ext in by_ext.keys():
		var files = by_ext[ext]
		print("[AcdExtractor]   .%s files (%d): %s" % [ext, files.size(), ", ".join(files.slice(0, min(3, files.size())))])


class ReadResult:
	var value
	var pos: int

func _read_le_i32(bytes: PackedByteArray, pos: int) -> ReadResult:
	var r := ReadResult.new()
	if pos + 4 > bytes.size():
		r.value = 0
		r.pos = bytes.size()
		return r

	var b0 = int(bytes[pos])
	var b1 = int(bytes[pos + 1])
	var b2 = int(bytes[pos + 2])
	var b3 = int(bytes[pos + 3])

	var unsigned_val: int = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
	# Convert to signed 32-bit if needed
	if unsigned_val & 0x80000000 != 0:
		unsigned_val -= 4294967296

	r.value = unsigned_val
	r.pos = pos + 4
	return r

func _read_string(bytes: PackedByteArray, pos: int) -> ReadResult:
	var r := ReadResult.new()

	var len_res := _read_le_i32(bytes, pos)
	var length: int = len_res.value
	pos = len_res.pos

	if length <= 0:
		# Empty or invalid string
		r.value = ""
		r.pos = pos
		return r
	
	if pos + length > bytes.size():
		# Not enough data for this string
		r.value = ""
		r.pos = pos
		return r

	var slice := bytes.slice(pos, pos + length)
	var s := slice.get_string_from_ascii()
	r.value = s
	r.pos = pos + length
	return r


func _int_to_byte(value: int) -> int:
	# (value % 256 + 256) % 256 safe wrap
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
		# % folderName[n] – integer modulo
		if chars[n_idx] != 0:
			num6 %= chars[n_idx]
		n_idx += 2
	var octet7 := _int_to_byte(num6)

	# Octet 8
	var num7 := 171
	var p := 0
	while p < n - 1:
		# num7 = num7 / folderName[p] + folderName[p + 1]
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
	# print("ACD key for %s: %s" % [folder_name, key])
	return key

func _decrypt_in_place(data: PackedByteArray, key: String) -> void:
	if key.is_empty():
		return

	var key_len := key.length()
	var key_index := 0

	var size := data.size()
	for i in size:
		var b := int(data[i])
		var k_char_code := key.unicode_at(key_index)
		var num4 := b - k_char_code
		if num4 < 0:
			num4 += 256
		data[i] = num4

		key_index += 1
		if key_index >= key_len:
			key_index = 0


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
