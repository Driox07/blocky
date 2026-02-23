class_name World
extends Node3D

const chunk_scene = preload("res://scenes/chunk/chunk.tscn")

@onready var chunks_root:Node3D = $ChunksRoot
@onready var environment:WorldEnvironment = $WorldEnvironment


@export var world_seed:String = ""
var noise:FastNoiseLite

var is_chunk_generating = false

var last_player_queue = 0 # Index of the player in Players
var chunk_queues = {}
var next_player = null
var next_player_idx = -1
var loaded_chunks = {}

func _ready() -> void:
	setup_noise()
	set_fog()

func _process(_delta: float) -> void:
	load_chunks()
	update_debug_info()
	pass

func add_chunks_to_queue(player: Player, new_chunks: Array[Vector2i]):
	if not chunk_queues.has(player):
		chunk_queues[player] = []
	var current_queue = chunk_queues[player]
	for c in new_chunks:
		if not loaded_chunks.has(c) and not current_queue.has(c):
			current_queue.append(c)
	sort_player_queue(player, current_queue)

func load_chunks():
	if is_chunk_generating: return
	if next_player == null:
		get_next_player()
		return
	if not chunk_queues.has(next_player): return
	var current_queue = chunk_queues[next_player]
	if current_queue.is_empty(): return
	var chunk = current_queue.pop_front()
	if loaded_chunks.has(chunk): return
	is_chunk_generating = true
	var new_chunk = chunk_scene.instantiate()
	new_chunk.init_chunk(noise, chunk.x, chunk.y)
	new_chunk.position = Vector3(chunk.x * Chunk.CHUNK_SIZE, 0, chunk.y * Chunk.CHUNK_SIZE)
	new_chunk.loaded.connect(_on_chunk_loaded)
	chunks_root.add_child(new_chunk)
	loaded_chunks[chunk] = new_chunk
	get_next_player()

func _on_chunk_loaded():
	is_chunk_generating = false

func get_next_player():
	if next_player == null:
		if Players.players.size() > 0:
			next_player = Players.players[0]
			next_player_idx = 0
		return
	next_player_idx = (next_player_idx + 1) % Players.players.size()
	next_player = Players.players[next_player_idx]

func sort_player_queue(player:Player, queue:Array):
	var p_chunk = Chunk.coordinates_2_chunk(int(player.position.x), int(player.position.z))
	queue.sort_custom(func(a: Vector2i, b:Vector2i):
			var dist_a = (a.x - p_chunk.x) ** 2 + (a.y - p_chunk.y) ** 2
			var dist_b = (b.x - p_chunk.x) ** 2 + (b.y - p_chunk.y) ** 2
			return dist_a < dist_b
			)

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

func set_fog():
	var chunk_radius = Settings.get_setting(Settings.Setting.RenderDistance)
	var fog_distance = 1.0 * chunk_radius / 2 * Chunk.CHUNK_SIZE
	environment.environment.fog_depth_begin = fog_distance - Chunk.CHUNK_SIZE * 2
	environment.environment.fog_depth_begin = fog_distance - Chunk.CHUNK_SIZE

func update_debug_info():
	%FPSLabel.text = str(Engine.get_frames_per_second())
	var total_chunks = 0
	for p in chunk_queues:
		total_chunks += chunk_queues[p].size()
	%ChunkQueueLabel.text = str(total_chunks)
	if Client.client_player.position != null:
		var pl = Client.client_player
		%CoordsLabel.text = str(pl.position)
		%ChunkLabel.text = str(Chunk.coordinates_2_chunk(int(pl.position.x), int(pl.position.z)))
	 
