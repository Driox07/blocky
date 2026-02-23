extends Node

enum Setting {RenderDistance, CameraSensitivity}

var settings:Dictionary[Setting, Variant] = {
	Setting.RenderDistance: 8, # Render distance in chunks
	Setting.CameraSensitivity: 0.002
}

func get_setting(setting:Setting) -> Variant:
	return settings.get(setting, 0)

func set_setting(setting:Setting, value:Variant):
	settings.set(setting, value)
