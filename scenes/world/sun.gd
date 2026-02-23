extends DirectionalLight3D

@export var day_length_minutes: float = 5 

var rotation_speed: float

func _ready() -> void:
	rotation_speed = 360.0 / (day_length_minutes * 60.0)

func _process(delta: float) -> void:
	rotate_x(deg_to_rad(rotation_speed * delta))
	
	var current_pitch = rotation_degrees.x
	
	if current_pitch > 0.0 and current_pitch < 180.0:
		light_energy = 0.0
	else:
		light_energy = 1.0 
