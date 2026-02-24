class_name World
extends Node3D

const chunk_scene = preload("res://scenes/chunk/chunk.tscn")

@onready var chunks_root:Node3D = $ChunksRoot
@onready var environment:WorldEnvironment = $WorldEnvironment


@export var world_seed:String = ""
var noise:FastNoiseLite

const MAX_CHUNKS_PER_FRAME = 8
const MAX_CHUNKS_UNLOAD_PER_FRAME = 8

var chunks_loading = 0
var chunks_unloading = 0

var last_player_queue = 0 # Index of the player in Players
var chunk_queues = {}
var unload_queue = []
var next_player = null
var next_player_idx = -1
var loaded_chunks = {}
var unloader_collecting = false

func _ready() -> void:
	#RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	setup_noise()
	set_fog()

func _process(_delta: float) -> void:
	load_chunks()
	unload_chunks()
	update_debug_info()

func set_queue(player: Player, new_chunks: Array[Vector2i]):
	chunk_queues[player] = new_chunks

func load_chunks():
	if chunks_loading >= MAX_CHUNKS_PER_FRAME: return
	if next_player == null:
		get_next_player()
		return
	if not chunk_queues.has(next_player): return
	var current_queue = chunk_queues[next_player]
	if current_queue.is_empty(): return
	sort_chunks(next_player, current_queue)
	var chunk = current_queue.pop_front()
	if loaded_chunks.has(chunk): return
	chunks_loading += 1
	var new_chunk = chunk_scene.instantiate()
	new_chunk.init_chunk(noise, chunk.x, chunk.y)
	new_chunk.position = Vector3(chunk.x * Chunk.CHUNK_SIZE, 0, chunk.y * Chunk.CHUNK_SIZE)
	new_chunk.loaded.connect(_on_chunk_loaded)
	chunks_root.add_child(new_chunk)
	loaded_chunks[chunk] = new_chunk
	get_next_player()

func _on_chunk_loaded():
	chunks_loading = max(0, chunks_loading - 1)

func _on_chunk_unloaded():
	chunks_unloading = max(0, chunks_unloading - 1)

func unload_chunks():
	#print("Trying to unload chunks. (" + str(chunks_unloading) + " unloading now)")
	while chunks_unloading < MAX_CHUNKS_UNLOAD_PER_FRAME and not unload_queue.is_empty():
		var chunk_pos = unload_queue.pop_front()
		if loaded_chunks.has(chunk_pos):
			var chunk = loaded_chunks[chunk_pos]
			chunk.unloaded.connect(_on_chunk_unloaded)
			chunk.mark_for_unload()
			loaded_chunks.erase(chunk_pos)
			chunks_unloading += 1

func collect_chunks_to_unload():
	if Players.players.is_empty():
		return
	unloader_collecting = true
	var render_distance = Settings.get_setting(Settings.Setting.RenderDistance)
	var rd_squared = render_distance * render_distance
	for chunk_pos in loaded_chunks.keys():
		var should_unload = true
		for player in Players.players:
			var player_chunk = Chunk.coordinates_2_chunk(int(player.position.x), int(player.position.z))
			var dx = chunk_pos.x - player_chunk.x
			var dy = chunk_pos.y - player_chunk.y
			var dist_squared = (dx * dx) + (dy * dy)
			if dist_squared <= rd_squared:
				should_unload = false
				break
		if should_unload:
			unload_queue.append(chunk_pos)
	unloader_collecting = false

func sort_chunks(player:Player, queue:Array):
	var p_chunk = Chunk.coordinates_2_chunk(int(player.position.x), int(player.position.z))
	queue.sort_custom(func(a: Vector2i, b:Vector2i):
			var dist_a = (a.x - p_chunk.x) ** 2 + (a.y - p_chunk.y) ** 2
			var dist_b = (b.x - p_chunk.x) ** 2 + (b.y - p_chunk.y) ** 2
			return dist_a < dist_b
			)

func get_next_player():
	if next_player == null:
		if Players.players.size() > 0:
			next_player = Players.players[0]
			next_player_idx = 0
		return
	next_player_idx = (next_player_idx + 1) % Players.players.size()
	next_player = Players.players[next_player_idx]

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
	%ChunkQueueLabel.text = str(total_chunks) + " (" + str(loaded_chunks.size()) + " loaded)"
	%UnloadQueueLabel.text = str(len(unload_queue))
	if Client.client_player.position != null:
		var pl = Client.client_player
		%CoordsLabel.text = str(pl.position)
		%ChunkLabel.text = str(Chunk.coordinates_2_chunk(int(pl.position.x), int(pl.position.z)))

func get_loaded_chunks_positions():
	return loaded_chunks.keys()


func _on_chunk_unload_timer_timeout() -> void:
	collect_chunks_to_unload()
