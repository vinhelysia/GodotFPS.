extends RefCounted

## Two generations: a manifest publishes a complete set of checksummed resources.
## An interrupted write only damages the inactive generation, not the current save.
const GENERATIONS := ["commit_0", "commit_1"]
const MANIFEST := "manifest.json"


static func current_directory(slot_directory: String) -> String:
	var current := _current(slot_directory)
	return current.get("directory", slot_directory)


static func commit(temp_directory: String, slot_directory: String, player_filename: String) -> bool:
	if not DirAccess.dir_exists_absolute(temp_directory):
		return false
	if FileAccess.file_exists(slot_directory):
		return false
	var current := _current(slot_directory)
	var revision := int(current.get("revision", 0)) + 1
	var destination := slot_directory.path_join(GENERATIONS[revision % 2])
	if FileAccess.file_exists(destination) or destination == current.get("directory", ""):
		return false
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	var manifest_path := destination.path_join(MANIFEST)
	if FileAccess.file_exists(manifest_path) and DirAccess.remove_absolute(manifest_path) != OK:
		return false
	# Keep untouched scene states, then overlay this session's staged resources.
	var sources: Dictionary = {}
	var previous_directory: String = current.get("directory", slot_directory)
	# A generation may contain leftovers from failed writes; only its manifest owns committed files.
	var previous_files: Array = current["files"].keys() if not current.is_empty() \
		else Array(DirAccess.get_files_at(previous_directory))
	for filename: String in previous_files:
		if _safe_filename(filename):
			sources[filename] = previous_directory.path_join(filename)
	for filename in DirAccess.get_files_at(temp_directory):
		if _safe_filename(filename):
			sources[filename] = temp_directory.path_join(filename)
	if not sources.has(player_filename):
		return false
	var hashes: Dictionary = {}
	for filename: String in sources:
		var target := destination.path_join(filename)
		if DirAccess.copy_absolute(sources[filename], target) != OK:
			return false
		var expected := FileAccess.get_sha256(sources[filename])
		if expected.is_empty() or FileAccess.get_sha256(target) != expected:
			return false
		hashes[filename] = expected
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		return false
	manifest.store_string(JSON.stringify({"revision": revision, "player": player_filename, "files": hashes}))
	manifest.flush()
	var error := manifest.get_error()
	manifest.close()
	if error != OK or int(_read_manifest(destination).get("revision", 0)) != revision:
		DirAccess.remove_absolute(manifest_path)
		return false
	# ponytail: FileAccess flush is not an OS fsync guarantee; power-loss durability needs platform-specific verification.
	return true


static func _current(slot_directory: String) -> Dictionary:
	var current: Dictionary = {}
	for generation in GENERATIONS:
		var directory := slot_directory.path_join(generation)
		var candidate := _read_manifest(directory)
		if int(candidate.get("revision", 0)) > int(current.get("revision", 0)):
			current = candidate
			current["directory"] = directory
	return current


static func _read_manifest(directory: String) -> Dictionary:
	var path := directory.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("files") is Dictionary:
		return {}
	if not parsed.get("revision") is float and not parsed.get("revision") is int:
		return {}
	if parsed["revision"] < 1 or parsed["revision"] != int(parsed["revision"]):
		return {}
	var player: Variant = parsed.get("player")
	if not player is String or not _safe_filename(player) or not parsed["files"].has(player):
		return {}
	for filename: Variant in parsed["files"]:
		var hash: Variant = parsed["files"][filename]
		if not filename is String or not _safe_filename(filename) or not hash is String or hash.length() != 64:
			return {}
		if not FileAccess.file_exists(directory.path_join(filename)) or FileAccess.get_sha256(directory.path_join(filename)) != hash:
			return {}
	return parsed


static func _safe_filename(filename: String) -> bool:
	return filename.ends_with(".res") and filename == filename.get_file() \
		and not filename.contains("..") and not filename.contains(":") and not filename.contains("\\")
