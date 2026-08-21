extends RefCounted

static func upload(
	endpoint: String,
	app_id: String,
	build_id: String,
	crash_dir: String,
	report_id: String,
	include_attachments: bool,
	user_message: String,
	anonymous: bool
) -> Error:
	var dump_path := crash_dir.path_join(report_id + ".dmp")
	var dump := PackedByteArray()
	if include_attachments:
		if not FileAccess.file_exists(dump_path):
			return ERR_FILE_NOT_FOUND
		dump = FileAccess.get_file_as_bytes(dump_path)
	var metadata := "{}"
	var meta_path := crash_dir.path_join(report_id + ".json")
	if FileAccess.file_exists(meta_path):
		metadata = FileAccess.get_file_as_string(meta_path)
	metadata = _fill_report_fields(metadata, app_id, build_id, user_message, anonymous)
	var log_bytes := PackedByteArray()
	if include_attachments:
		log_bytes = _read_log_bytes(crash_dir)

	var boundary := "----BlaziumCrashBoundary"
	var body := PackedByteArray()
	body.append_array(_part_text(boundary, "metadata", "application/json", metadata))
	if include_attachments and not dump.is_empty():
		body.append_array(_part_file(boundary, "dump", report_id + ".dmp", "application/octet-stream", dump))
	if include_attachments and not log_bytes.is_empty():
		body.append_array(_part_file(boundary, "log", report_id + ".log", "text/plain", log_bytes))
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())

	var http := HTTPRequest.new()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child.call_deferred(http)
	while not http.is_inside_tree():
		await tree.process_frame
	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
		"User-Agent: BlaziumCrashReporter/official",
		"X-App-Id: %s" % app_id,
		"X-Build-Id: %s" % build_id,
	])
	var err := http.request_raw(endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return err
	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	if response_code >= 200 and response_code < 300:
		var state := FileAccess.open(crash_dir.path_join(report_id + ".state"), FileAccess.WRITE)
		if state:
			state.store_string("submitted")
		return OK
	return FAILED


static func _fill_report_fields(metadata: String, app_id: String, build_id: String, user_message: String, anonymous: bool) -> String:
	var parsed: Variant = JSON.parse_string(metadata)
	var meta: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if String(meta.get("app_id", "")).is_empty() and not app_id.is_empty():
		meta["app_id"] = app_id
	if String(meta.get("build_id", "")).is_empty() and not build_id.is_empty():
		meta["build_id"] = build_id
	meta["user_message"] = user_message
	meta["anonymous"] = anonymous
	return JSON.stringify(meta)


static func _read_log_bytes(crash_dir: String) -> PackedByteArray:
	var names := PackedStringArray(["godot.log", "blazium.log"])
	var dirs := PackedStringArray([
		crash_dir.get_base_dir().path_join("logs"),
		OS.get_user_data_dir().path_join("logs"),
	])
	for dir_path in dirs:
		for name in names:
			var log_path: String = dir_path.path_join(name)
			if FileAccess.file_exists(log_path):
				return FileAccess.get_file_as_bytes(log_path)
	return PackedByteArray()


static func _part_text(boundary: String, name: String, content_type: String, text: String) -> PackedByteArray:
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, name, content_type]
	return header.to_utf8_buffer() + text.to_utf8_buffer() + "\r\n".to_utf8_buffer()


static func _part_file(boundary: String, name: String, filename: String, content_type: String, data: PackedByteArray) -> PackedByteArray:
	var header := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [boundary, name, filename, content_type]
	return header.to_utf8_buffer() + data + "\r\n".to_utf8_buffer()
