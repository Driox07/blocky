extends Node3D

const CHUNKS_RADIUS = 8

@onready var chunks_root:Node3D = $ChunksRoot
@onready var environment:WorldEnvironment = $WorldEnvironment
const chunk_scene = preload("res://scenes/chunk_drawer/chunk.tscn")

@export var chunk_loaders:Array[Node3D]
@export var world_seed:String = ""
var noise:FastNoiseLite
var loaded_chunks:Dictionary = {}

var loader_positions = {} # In which chunk is each loader (player)
var loader_chunks = {} # Which chunks needs each loader to load

var chunks_queue:Array[Vector2i] = []
var is_generating_chunk:bool = false

var are_chunks_updating = false

func _ready() -> void:
	setup_noise()
	reload_chunks()

func set_fog():
	var fog_distance = 1.0 * CHUNKS_RADIUS / 2 * Chunk.CHUNK_SIZE
	environment.environment.fog_depth_begin = fog_distance - Chunk.CHUNK_SIZE * 2
	environment.environment.fog_depth_begin = fog_distance - Chunk.CHUNK_SIZE

func reload_chunks():
	var chunks_to_keep = {}
	for chunk_id in loaded_chunks:
		var chunk_node = loaded_chunks[chunk_id]
		var chunk_pos = Vector2i(chunk_node.chunk_x, chunk_node.chunk_y)
		for loader in loader_chunks:
			var chunk_list = loader_chunks[loader]
			if chunk_pos in chunk_list:
				chunks_to_keep[chunk_id] = chunk_node
				break
		if not chunks_to_keep.has(chunk_id):
			chunk_node.mark_for_unload()
	
	loaded_chunks = chunks_to_keep
	
	for chunk_loader in loader_chunks:
		loader_chunks[chunk_loader].sort_custom(func(a: Vector2i, b:Vector2i):
			var dist_a = (a.x - loader_positions[chunk_loader].x) ** 2 + (a.y - loader_positions[chunk_loader].y) ** 2
			var dist_b = (b.x - loader_positions[chunk_loader].x) ** 2 + (b.y - loader_positions[chunk_loader].y) ** 2
			return dist_a < dist_b
			)
	
	var final_chunk_list = []
	var loader_chunks_copy = loader_chunks.duplicate(true)
	while true:
		var count = 0
		for chunk_loader in loader_chunks_copy:
			if len(loader_chunks_copy[chunk_loader]) > 0:
				count += 1
				final_chunk_list.append(loader_chunks_copy[chunk_loader].pop_front())
		if count == 0: break

	for chunk_pos in final_chunk_list:
		var chunk_id = Chunk.get_chunk_id(chunk_pos.x, chunk_pos.y)
		if not loaded_chunks.has(chunk_id) and not chunks_queue.has(chunk_pos):
			chunks_queue.append(chunk_pos)
	are_chunks_updating = false

func _process(_delta: float) -> void:
	print_debug_info()
	if check_for_chunk_updates(): reload_chunks()
	if chunks_queue.size() > 0 and not is_generating_chunk:
		var next_chunk_pos = chunks_queue.pop_front()
		var chunk_id = Chunk.get_chunk_id(next_chunk_pos.x, next_chunk_pos.y)
		# Verificar que no se haya cargado mientras esperaba en cola
		if not loaded_chunks.has(chunk_id):
			is_generating_chunk = true
			spawn_chunk(next_chunk_pos)

func print_debug_info():
	%FPSLabel.text = "FPS: " + str(Engine.get_frames_per_second())
	%ChunkQueueLabel.text = str(len(chunks_queue))
	%CoordsLabel.text = str(chunk_loaders[0].position)
	%ChunkLabel.text = str(coordinates_2_chunk(int(chunk_loaders[0].position.x), int(chunk_loaders[0].position.z)))
	

func check_for_chunk_updates():
	if are_chunks_updating: return false
	var needed_update = false
	for loader in chunk_loaders:
		if not loader_positions.has(loader):
			loader_positions[loader] = coordinates_2_chunk(int(loader.position.x), int(loader.position.z))
			var loader_position = loader_positions[loader]
			loader_chunks[loader] = get_chunks_in_radius(loader_position.x, loader_position.y, CHUNKS_RADIUS)
			needed_update = true
			continue
		var current_pos = coordinates_2_chunk(int(loader.position.x), int(loader.position.z))
		if loader_positions[loader] != current_pos:
			loader_chunks[loader] = get_chunks_in_radius(current_pos.x, current_pos.y, CHUNKS_RADIUS)
			loader_positions[loader] = current_pos
			needed_update = true
	are_chunks_updating = needed_update
	return needed_update

func coordinates_2_chunk(x:int, z:int) -> Vector2i:
	return Vector2i(floor(x*1.0/Chunk.CHUNK_SIZE), floor(z*1.0/Chunk.CHUNK_SIZE))

func spawn_chunk(chunk_pos: Vector2i):
	var new_chunk = chunk_scene.instantiate()
	var chunk_id = Chunk.get_chunk_id(chunk_pos.x, chunk_pos.y)
	new_chunk.init_chunk(noise, chunk_pos.x, chunk_pos.y)
	new_chunk.position = Vector3(chunk_pos.x * Chunk.CHUNK_SIZE, 0, chunk_pos.y * Chunk.CHUNK_SIZE)
	new_chunk.chunk_loaded.connect(_on_chunk_loaded.bind(chunk_id))
	chunks_root.add_child(new_chunk)
	loaded_chunks[chunk_id] = new_chunk

func _on_chunk_loaded(chunk_id: String):
	is_generating_chunk = false
	# Verificar que el chunk sigue siendo válido
	if loaded_chunks.has(chunk_id):
		var chunk = loaded_chunks[chunk_id]
		if not is_instance_valid(chunk):
			loaded_chunks.erase(chunk_id)

func setup_noise():
	noise = FastNoiseLite.new()
	noise.seed = calculate_seed(world_seed)
	noise.noise_type = FastNoiseLite.TYPE_PERLIN 
	noise.frequency = 0.01 
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4 

func calculate_seed(s:String):
	if s.strip_edges() == "":
		return randi()
	if s.is_valid_int():
		return s.to_int()
	return s.hash()

func get_chunks_in_radius(center_x: int, center_y: int, radius: int) -> Array[Vector2i]:
	var chunk_list: Array[Vector2i] = []
	var radius_squared = radius * radius
	for x in range(center_x - radius, center_x + radius + 1):
		for y in range(center_y - radius, center_y + radius + 1):
			var dx = x - center_x
			var dy = y - center_y
			if (dx * dx) + (dy * dy) <= radius_squared:
				chunk_list.append(Vector2i(x, y))
	return chunk_list
