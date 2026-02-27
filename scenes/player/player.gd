class_name Player
extends CharacterBody3D
static var counter = 0
var SPEED = 5.0
const JUMP_VELOCITY = 5.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast:RayCast3D = $Head/RayCast3D
@onready var highlight_box:MeshInstance3D = $HighlightBox

@export var gravity: float = 9.8

var last_current_chunk = null

var world:World
var selected_block

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Players.add_player(self)
	Client.client_player = self
	get_world()

func get_world():
	if world == null:
		var tree_world = get_parent().get_parent()
		if tree_world != null and is_instance_of(tree_world, World):
			world = tree_world

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
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				hit()
	

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

func hit():
	counter+=1
	print("Called hit " + str(counter) + " times")
	if selected_block == null: return
	print("Breaking ", selected_block)
	var block_chunk = Chunk.coordinates_2_chunk(selected_block.x, selected_block.z)
	var chunk:Chunk = world.loaded_chunks.get(block_chunk)
	if chunk == null: return
	var local_x = selected_block.x - (chunk.chunk_x * Chunk.CHUNK_SIZE)
	var local_z = selected_block.z - (chunk.chunk_y * Chunk.CHUNK_SIZE)
	chunk.set_block(local_x, selected_block.y, local_z, Blocks.Block.AIR)
	chunk.reload_chunk([Chunk.y_2_section(selected_block.y)])

func check_chunk():
	var current_chunk = Chunk.coordinates_2_chunk(int(position.x), int(position.z))
	if last_current_chunk != current_chunk and world != null:
		last_current_chunk = current_chunk
		world.set_queue(self, get_chunks_in_sight())

func update_raycast():
	if not raycast.is_colliding():
		highlight_box.visible = false
		selected_block = null
		return
	highlight_box.visible = true
	var hit_pos = raycast.get_collision_point()
	var normal = raycast.get_collision_normal()
	var block_pos = hit_pos - (normal * 0.5)
	var b_x = floor(block_pos.x)
	var b_y = floor(block_pos.y)
	var b_z = floor(block_pos.z)
	highlight_box.global_position = Vector3(b_x + 0.5, b_y + 0.5, b_z + 0.5)
	selected_block = Vector3i(b_x, b_y, b_z)

func get_chunks_in_sight(exclude_loaded:bool=true):
	if world == null: return
	var excluded = world.get_loaded_chunks_positions() if exclude_loaded else []
	var chunk_coord = Chunk.coordinates_2_chunk(int(position.x), int(position.z))
	return Chunk.get_chunks_in_radius(chunk_coord.x, 
	chunk_coord.y, 
	Settings.get_setting(Settings.Setting.RenderDistance),
	excluded)
