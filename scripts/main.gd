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
@onready var detail: TextEdit = %Detail
@onready var endpoint_edit: LineEdit = %Endpoint
@onready var app_id_edit: LineEdit = %AppId
@onready var build_id_edit: LineEdit = %BuildId
@onready var include_logs: CheckBox = %IncludeLogs
@onready var status: Label = %Status
@onready var privacy_link: LinkButton = %PrivacyLink


func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(640, 480))
	_parse_args()
	endpoint_edit.text = endpoint
	app_id_edit.text = app_id
	build_id_edit.text = build_id
	privacy_link.visible = not privacy_url.is_empty()
	privacy_link.uri = privacy_url
	%Send.pressed.connect(_on_send)
	%Discard.pressed.connect(_on_discard)
	%Refresh.pressed.connect(_refresh)
	reports_list.item_selected.connect(_on_selected)
	_refresh()
	if OS.get_cmdline_args().has("--auto-send") or OS.get_cmdline_user_args().has("--auto-send"):
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		await _on_send()
		print("SIDECAR_STATUS=%s" % status.text)
		print("SIDECAR_DETAIL_BEGIN")
		print(detail.text)
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
		status.text = "No pending crash reports in %s" % crash_dir
		detail.text = ""
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


func _on_selected(index: int) -> void:
	if index < 0 or index >= reports.size():
		return
	var row: Dictionary = reports[index]
	var meta: Dictionary = row.get("metadata", {})
	detail.text = JSON.stringify(meta, "\t")
	if app_id_edit.text.strip_edges().is_empty():
		app_id_edit.text = String(meta.get("app_id", ""))
	if build_id_edit.text.strip_edges().is_empty():
		build_id_edit.text = String(meta.get("build_id", ""))


func _selected_id() -> String:
	var selected := reports_list.get_selected_items()
	if selected.is_empty() or selected[0] >= reports.size():
		return ""
	return reports[selected[0]]["id"]


func _on_discard() -> void:
	var id := _selected_id()
	if id.is_empty():
		return
	for ext in [".dmp", ".json", ".state"]:
		var path := crash_dir.path_join(id + ext)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	status.text = "Discarded %s." % id
	_refresh()


func _on_send() -> void:
	var id := _selected_id()
	if id.is_empty():
		status.text = "Select a report first."
		return
	var url := endpoint_edit.text.strip_edges()
	if url.is_empty():
		status.text = "Set an endpoint before sending."
		return
	var send_app := app_id_edit.text.strip_edges()
	var send_build := build_id_edit.text.strip_edges()
	if send_app.is_empty() or send_build.is_empty():
		status.text = "Set App ID and Build ID before sending."
		return
	status.text = "Uploading %s..." % id
	var err := await Uploader.upload(url, send_app, send_build, crash_dir, id, include_logs.button_pressed)
	if err == OK:
		status.text = "Uploaded %s. Fetching stackwalk..." % id
		var server_detail := await Uploader.fetch_server_detail(url, id)
		detail.text = server_detail
		if server_detail.contains("Crash reason:") and not server_detail.contains("(pending)"):
			status.text = "Uploaded %s. Server analysis ready." % id
		else:
			status.text = "Uploaded %s. Stackwalk still pending." % id
	else:
		status.text = "Upload failed for %s (error %s)." % [id, error_string(err)]
		_refresh()
