class_name UpdateBanner
extends PanelContainer
## Tells the player about a newer build, with a button to get it: the store
## page on Android/iOS (the server's update URL), or a page reload on the web
## so the browser fetches the new build instead of a cached one.

var _url := ""

@onready var _message: Label = %Message
@onready var _button: Button = %UpdateButton


func _ready() -> void:
	hide()
	_button.pressed.connect(_on_update_pressed)


## `info` as in `Network.update_info`; empty hides the banner.
func show_info(info: Dictionary) -> void:
	if info.is_empty():
		hide()
		return
	_url = info.get("url", "")
	var latest: String = info.get("latest_version", "")
	if info.get("required", false):
		_message.text = "Version %s is too old to play online. Please update%s." \
				% [GameVersion.current(), " to %s" % latest if latest else ""]
	else:
		_message.text = "Version %s is available (you have %s)." % [latest, GameVersion.current()]
	var is_web := OS.has_feature("web")
	_button.text = "Reload" if is_web and not _url else "Update"
	_button.visible = is_web or not _url.is_empty()
	show()


func _on_update_pressed() -> void:
	if _url:
		OS.shell_open(_url)
	elif OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
