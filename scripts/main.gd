extends Control

const Uploader := preload("res://scripts/uploader.gd")

var crash_dir := ""
var report_id := ""
var endpoint := ""
var contact_url := ""
var privacy_url := ""
var app_id := ""
var build_id := ""
var reports: Array = []

@onready var reports_list: ItemList = %Reports
@onready var user_message: TextEdit = %UserMessage
@onready var include_attachments: CheckBox = %IncludeAttachments
@onready var send_anonymous: CheckBox = %SendAnonymous
@onready var status: Label = %Status
@onready var privacy_link: LinkButton = %PrivacyLink


func _ready() -> void:
	if AppVersion != null and AppVersion.active:
		return
	DisplayServer.window_set_min_size(Vector2i(640, 480))
	_parse_args()
	privacy_link.visible = not privacy_url.is_empty()
	privacy_link.uri = privacy_url
	%Send.pressed.connect(_on_send)
	%Discard.pressed.connect(_on_discard)
	%Refresh.pressed.connect(_refresh)
	reports_list.item_selected.connect(_on_selected)
	_refresh()
	if OS.get_cmdline_args().has("--auto-send") or OS.get_cmdline_user_args().has("--auto-send"):
		user_message.text = ""
		include_attachments.button_pressed = true
		send_anonymous.button_pressed = false
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		await _on_send()
		print("SIDECAR_STATUS=%s" % status.text)
		print("SIDECAR_DETAIL_BEGIN")
		print(status.text)
		print("SIDECAR_DETAIL_END")
		get_tree().quit()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var value := ""
		if i + 1 < args.size():
			value = args[i + 1]
		match a:
			"--crash-dir":
				crash_dir = value
				i += 1
			"--report-id":
				report_id = value
				i += 1
			"--endpoint":
				endpoint = value
				i += 1
			"--app-id":
				app_id = value
				i += 1
			"--build-id":
				build_id = value
				i += 1
			"--contact-url":
				contact_url = value
				i += 1
			"--privacy-url":
				privacy_url = value
				i += 1
		i += 1
	if crash_dir.is_empty():
		crash_dir = OS.get_user_data_dir().path_join("crashes")


func _refresh() -> void:
	reports.clear()
	reports_list.clear()
	var dir := DirAccess.open(crash_dir)
	if dir == null:
		status.text = "Crash directory not found: %s" % crash_dir
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension().to_lower() == "dmp":
			var id := fname.get_basename()
			var dump_path := crash_dir.path_join(fname)
			var meta := {}
			var meta_path := crash_dir.path_join(id + ".json")
			if FileAccess.file_exists(meta_path):
				var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
				if typeof(parsed) == TYPE_DICTIONARY:
					meta = parsed
			var state := "pending"
			var state_path := crash_dir.path_join(id + ".state")
			if FileAccess.file_exists(state_path):
				state = FileAccess.get_file_as_string(state_path).strip_edges()
			if state != "submitted":
				reports.append({"id": id, "dump_path": dump_path, "metadata": meta, "state": state})
				reports_list.add_item("%s (%s)" % [id, state])
		fname = dir.get_next()
	dir.list_dir_end()
	if reports.is_empty():
		status.text = "No pending crash reports."
		return
	var select := 0
	if not report_id.is_empty():
		for idx in reports.size():
			if reports[idx]["id"] == report_id:
				select = idx
				break
	reports_list.select(select)
	_on_selected(select)
	status.text = "Found %d pending report(s)." % reports.size()


func _on_selected(_index: int) -> void:
	pass


func _selected_row() -> Dictionary:
	var selected := reports_list.get_selected_items()
	if selected.is_empty() or selected[0] >= reports.size():
		return {}
	return reports[selected[0]]


func _selected_id() -> String:
	var row := _selected_row()
	return String(row.get("id", ""))


func _resolved_identity() -> Dictionary:
	var row := _selected_row()
	var meta: Dictionary = row.get("metadata", {})
	var send_app := app_id.strip_edges()
	var send_build := build_id.strip_edges()
	var send_endpoint := endpoint.strip_edges()
	if send_app.is_empty():
		send_app = String(meta.get("app_id", "")).strip_edges()
	if send_build.is_empty():
		send_build = String(meta.get("build_id", "")).strip_edges()
	if send_endpoint.is_empty():
		send_endpoint = String(meta.get("endpoint", "")).strip_edges()
	return {"app_id": send_app, "build_id": send_build, "endpoint": send_endpoint}


func _on_discard() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	for ext in [".dmp", ".json", ".state"]:
		var path := crash_dir.path_join(id + ext)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	status.text = "Discarded report."
	_refresh()


func _on_send() -> void:
	var id := _selected_id()
	if id.is_empty():
		status.text = "Select a report first."
		return
	var identity := _resolved_identity()
	var url: String = identity["endpoint"]
	var send_app: String = identity["app_id"]
	var send_build: String = identity["build_id"]
	if url.is_empty() or send_app.is_empty() or send_build.is_empty():
		status.text = "This report cannot be sent. The application identity is missing."
		return
	status.text = "Uploading report..."
	var err := await Uploader.upload(
		url,
		send_app,
		send_build,
		crash_dir,
		id,
		include_attachments.button_pressed,
		user_message.text.strip_edges(),
		send_anonymous.button_pressed
	)
	if err == OK:
		user_message.editable = false
		_refresh()
		status.text = "Thank you. Report id: %s" % id
	else:
		_refresh()
		status.text = "Upload failed. Please try again."
