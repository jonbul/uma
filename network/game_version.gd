class_name GameVersion
extends RefCounted
## This build's version and platform, as the server checks them.
##
## The version lives in Project Settings > Application > Config > Version
## (`application/config/version`). Keep the Android and iOS export presets'
## version fields in step with it.

## Tests set this to pretend to be another version.
static var override := ""


static func current() -> String:
	if override:
		return override
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "web", "android", "ios", "linux", "windows", "macos"…
static func platform() -> String:
	return OS.get_name().to_lower()


## Compares "major.minor.patch" versions: -1, 0 or 1. Same rules as the Go
## server: missing parts are 0, anything after '-' or '+' is ignored, and a
## part that isn't a number counts as 0.
static func compare(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0


static func _parts(version: String) -> Array[int]:
	var v := version.strip_edges().trim_prefix("v")
	for separator in ["-", "+"]:
		if v.contains(separator):
			v = v.get_slice(separator, 0)
	var parts: Array[int] = [0, 0, 0]
	var pieces := v.split(".")
	for i in mini(pieces.size(), 3):
		parts[i] = maxi(pieces[i].to_int(), 0) if pieces[i].is_valid_int() else 0
	return parts
