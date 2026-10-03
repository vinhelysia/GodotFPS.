@tool
extends Node3D

## Chạy scene trong editor (Play Scene) hoặc nhấn nút bên dưới để lưu icon.
## Sau khi lưu, đặt file PNG vào trường "icon" của .tres

@export_category("Icon Capture Settings")

## Đường dẫn và tên file muốn lưu (VD: res://Scenes/Items/Icons/item_icon.png)
@export var save_path: String = "res://icon_output.png"

## Kéo thả SubViewport vào đây. Nếu để trống, script sẽ tự tìm node con tên "SubViewport"
@export var target_viewport: SubViewport

## Nhấn vào đây để chụp ngay lập tức trong Editor
@export var capture_now: bool = false:
	set(value):
		capture_now = false # Reset thành false ngay lập tức để tạo hiệu ứng nút bấm
		if value and Engine.is_editor_hint():
			_save_icon()

var _last_known_icon_modified_time: int = -1

func _ready() -> void:
	if Engine.is_editor_hint():
		_last_known_icon_modified_time = _get_icon_modified_time(_normalize_save_path())
		set_process(true)
		return
	# Khi play scene thật (không phải editor), đợi 1 frame rồi lưu
	await get_tree().process_frame
	await get_tree().process_frame
	_save_icon()
	get_tree().quit()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	var resource_path := _normalize_save_path()
	var current_modified_time := _get_icon_modified_time(resource_path)
	if current_modified_time == -1 or current_modified_time == _last_known_icon_modified_time:
		return

	_last_known_icon_modified_time = current_modified_time
	_refresh_saved_icon_in_editor(resource_path)

func _normalize_save_path() -> String:
	var normalized_path := save_path.strip_edges()
	if normalized_path.is_empty():
		normalized_path = "res://icon_output.png"

	if not normalized_path.ends_with(".png"):
		normalized_path += ".png"

	return normalized_path

func _get_icon_modified_time(resource_path: String) -> int:
	var global_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(global_path):
		return -1

	return FileAccess.get_modified_time(global_path)

func _refresh_saved_icon_in_editor(resource_path: String) -> void:
	if not Engine.is_editor_hint():
		return

	var file_system := EditorInterface.get_resource_filesystem()
	if file_system == null:
		return

	var directory_path := resource_path.get_base_dir()
	if file_system.get_filesystem_path(directory_path) == null:
		file_system.scan()
	else:
		file_system.update_file(resource_path)

	file_system.reimport_files(PackedStringArray([resource_path]))

func _save_icon() -> void:
	# Fallback an toàn nếu bạn quên gán target_viewport trong Inspector
	if target_viewport == null:
		target_viewport = get_node_or_null("SubViewport")
		if target_viewport == null:
			push_error("Không tìm thấy SubViewport. Vui lòng gán target_viewport trong Inspector.")
			return

	# Đợi viewport render xong
	await RenderingServer.frame_post_draw
	
	var img: Image = target_viewport.get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Viewport texture rỗng — kiểm tra Camera3D bên trong SubViewport")
		return

	var resource_path := _normalize_save_path()
	save_path = resource_path

	var err := img.save_png(ProjectSettings.globalize_path(resource_path))
	if err == OK:
		_last_known_icon_modified_time = _get_icon_modified_time(resource_path)
		_refresh_saved_icon_in_editor(resource_path)
		print("Icon đã lưu thành công tại: ", resource_path)
	else:
		push_error("Lỗi khi lưu hình ảnh: " + str(err))
