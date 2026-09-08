extends Node
## Prints stamped application/config/version and quits.
## Usage: crash_reporter --headless --app-version --quit

var active: bool = false


func _ready() -> void:
	active = cmdline_has_app_version()
	if not active:
		return
	var ver := str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	print("CRASH_REPORTER_VERSION=%s" % ver)
	get_tree().quit()


static func cmdline_has_app_version(args: PackedStringArray = PackedStringArray()) -> bool:
	if args.is_empty():
		for a in OS.get_cmdline_user_args():
			if str(a) == "--app-version":
				return true
		for a in OS.get_cmdline_args():
			if str(a) == "--app-version":
				return true
		return false
	for a in args:
		if str(a) == "--app-version":
			return true
	return false
