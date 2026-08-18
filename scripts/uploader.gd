extends RefCounted

static func upload(endpoint: String, api_key: String, crash_dir: String, report_id: String, include_logs: bool) -> Error:
	var dump_path := crash_dir.path_join(report_id + ".dmp")
	if not FileAccess.file_exists(dump_path):
		return ERR_FILE_NOT_FOUND
	var dump := FileAccess.get_file_as_bytes(dump_path)
	var metadata := "{}"
	var meta_path := crash_dir.path_join(report_id + ".json")
	if FileAccess.file_exists(meta_path):
		metadata = FileAccess.get_file_as_string(meta_path)
	var log_bytes := PackedByteArray()
	if include_logs:
		log_bytes = _read_log_bytes(crash_dir)

	var boundary := "----BlaziumCrashBoundary"
	var body := PackedByteArray()
	body.append_array(_part_text(boundary, "metadata", "application/json", metadata))
	body.append_array(_part_file(boundary, "dump", report_id + ".dmp", "application/octet-stream", dump))
	if not log_bytes.is_empty():
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
	])
	if not api_key.is_empty():
		headers.append("X-API-Key: %s" % api_key)
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


static func http_get(url: String, api_key: String) -> Dictionary:
	var http := HTTPRequest.new()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child.call_deferred(http)
	while not http.is_inside_tree():
		await tree.process_frame
	var headers := PackedStringArray(["User-Agent: BlaziumCrashReporter/official"])
	if not api_key.is_empty():
		headers.append("X-API-Key: %s" % api_key)
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "text": ""}
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	var body: PackedByteArray = result[3]
	return {"ok": code >= 200 and code < 300, "code": code, "text": body.get_string_from_utf8()}


static func fetch_server_detail(endpoint: String, api_key: String, report_id: String) -> String:
	var report_url := endpoint.rstrip("/") + "/" + report_id
	var stack_url := report_url + "/stack"
	var report := {}
	var stack := ""
	for _i in 5:
		var report_res: Dictionary = await http_get(report_url, api_key)
		if report_res.get("ok", false):
			var parsed: Variant = JSON.parse_string(String(report_res.get("text", "")))
			if typeof(parsed) == TYPE_DICTIONARY:
				report = parsed
		var stack_res: Dictionary = await http_get(stack_url, api_key)
		if stack_res.get("ok", false):
			stack = String(stack_res.get("text", ""))
		var analysis: Variant = report.get("analysis", {})
		var reason := ""
		if typeof(analysis) == TYPE_DICTIONARY:
			reason = String(analysis.get("crash_reason", ""))
		if not reason.is_empty() or not stack.is_empty():
			break
		await Engine.get_main_loop().create_timer(1.0).timeout
	return format_server_detail(report, stack)


static func format_server_detail(report: Dictionary, stack: String) -> String:
	var analysis: Variant = report.get("analysis", {})
	var reason := ""
	var address := ""
	if typeof(analysis) == TYPE_DICTIONARY:
		reason = String(analysis.get("crash_reason", ""))
		address = String(analysis.get("crash_address", ""))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Crash reason: %s" % (reason if not reason.is_empty() else "(pending)"))
	if not address.is_empty():
		lines.append("Crash address: %s" % address)
	if report.has("id"):
		lines.append("Report id: %s" % String(report.get("id", "")))
	lines.append("")
	if stack.is_empty():
		lines.append("(stackwalk not available yet)")
	else:
		lines.append(stack)
	return "\n".join(lines)


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
