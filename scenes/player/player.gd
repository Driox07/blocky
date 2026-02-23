class_name Player
extends CharacterBody3D

var SPEED = 5.0
const JUMP_VELOCITY = 5.0


@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast:RayCast3D = $Head/RayCast3D
@onready var highlight_box:MeshInstance3D = $HighlightBox

@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var last_current_chunk = null
var chunks_in_sight = []

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Players.add_player(self)
	Client.client_player = self

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sensitivity = Settings.get_setting(Settings.Setting.CameraSensitivity)
		rotate_y(-event.relative.x * sensitivity)
		
		head.rotate_x(-event.relative.y * sensitivity)
		
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("move_west", "move_east", "move_north", "move_south")
	
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _process(_delta):
	check_chunk()
	update_raycast()

func check_chunk():
	var current_chunk = Chunk.coordinates_2_chunk(int(position.x), int(position.z))
	if last_current_chunk != current_chunk:
		last_current_chunk = current_chunk
		var world = get_parent().get_parent()
		if world != null and is_instance_of(world, World):
			world.add_chunks_to_queue(self, Chunk.get_chunks_in_radius(int(position.x), int(position.z), Settings.get_setting(Settings.Setting.RenderDistance)))

func update_raycast():
	if not raycast.is_colliding():
		highlight_box.visible = false
		return
	highlight_box.visible = true
	var hit_pos = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	var block_pos = hit_pos - (normal * 0.5)
	var b_x = floor(block_pos.x)
	var b_y = floor(block_pos.y)
	var b_z = floor(block_pos.z)
	highlight_box.global_position = Vector3(b_x + 0.5, b_y + 0.5, b_z + 0.5)

func get_chunks_in_sight():
	return Chunk.get_chunks_in_radius(int(position.x), int(position.z), Settings.get_setting(Settings.Setting.RenderDistance))
