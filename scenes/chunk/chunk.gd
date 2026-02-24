class_name Chunk
extends Node3D


"""====================================
-------- SIGNALS DECLARATIONS ---------
===================================="""
signal loaded
signal unloaded

"""====================================
-------- STATIC VARS AND FUNCS --------
===================================="""
static var CHUNK_SIZE = 16
static var CHUNK_HEIGHT = 64
static var CHUNK_GEN_HEIGHT_MARGIN = 10
static var CHUNK_GEN_MIN_BASE = 5
static var LAYER_STONE_HEIGHT = 20
static var texture
static var material

# Utilities
static func coordinate_2_index(x:int, y:int, z:int) -> int:
	return x + (y * CHUNK_SIZE) + (z * CHUNK_SIZE * CHUNK_HEIGHT)

static func coordinates_2_chunk(x:int, z:int) -> Vector2i:
	return Vector2i(floor(x*1.0/Chunk.CHUNK_SIZE), floor(z*1.0/Chunk.CHUNK_SIZE))

static func get_chunks_in_radius(center_x: int, center_y: int, radius: int, to_exclude: Array = []) -> Array[Vector2i]:
	var chunk_list: Array[Vector2i] = []
	var radius_squared = radius * radius
	for x in range(center_x - radius, center_x + radius + 1):
		for y in range(center_y - radius, center_y + radius + 1):
			var dx = x - center_x
			var dy = y - center_y
			if (dx * dx) + (dy * dy) <= radius_squared:
				if not to_exclude.has(Vector2i(x, y)):
					chunk_list.append(Vector2i(x, y))
	return chunk_list

static func setup_material():
	if texture == null and material == null:
		texture = preload("res://assets/block_textures.png")
		material = StandardMaterial3D.new()
		material.albedo_texture = texture
		#material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.roughness = 1.0

"""====================================
----------- INSTANCE LOGIC ------------
===================================="""
@onready var chunk_mesh: MeshInstance3D = $ChunkMesh
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

var noise:FastNoiseLite
var chunk_x:int
var chunk_y:int
var blocks_data:PackedByteArray
var finished_loading:bool = false
var marked_for_unload:bool = false

# Establish noise and chunk coordinates
func init_chunk(n:FastNoiseLite, cx:int=0, cy:int=0):
	self.noise = n
	self.chunk_x = cx
	self.chunk_y = cy

# Load material if it is not, and air box
func _ready():
	setup_material()
	blocks_data.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT)
	blocks_data.fill(Blocks.Block.AIR)
	load_chunk()

func _process(_delta: float) -> void:
	if marked_for_unload and finished_loading:
		unload()

func load_chunk(data:PackedByteArray=[]):
	var chunk_load_process = Callable(self, "_load_process").bind(data)
	WorkerThreadPool.add_task(chunk_load_process, true)

func _load_process(data:PackedByteArray=[]):
	if noise != null and data.is_empty():
		generate_from_noise(noise)
	elif data.size() == CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT:
		print("Chunk load from data is not implemented yet. Ignoring...")
		finished_loading = true
		loaded.emit()
		return
	#var mesh = build_mesh()
	var mesh = build_greedy_mesh()
	var shape = mesh.create_trimesh_shape()
	call_deferred("apply_mesh", mesh, shape)

func reload_chunk():
	WorkerThreadPool.add_task(_reload_process, true)

func _reload_process():
	#var mesh = build_mesh()
	var mesh = build_greedy_mesh()
	var shape = mesh.create_trimesh_shape()
	call_deferred("apply_mesh", mesh, shape)

func apply_mesh(new_mesh: ArrayMesh, shape: ConcavePolygonShape3D):
	chunk_mesh.mesh = new_mesh
	chunk_mesh.material_override = material
	collision_shape.shape = shape
	loaded.emit()
	finished_loading = true

func mark_for_unload():
	marked_for_unload = true

func unload():
	unloaded.emit()
	queue_free()

func set_block(x: int, y: int, z: int, block: int):
	if x < 0 or x >= CHUNK_SIZE or y < 0 or y >= CHUNK_HEIGHT or z < 0 or z >= CHUNK_SIZE:
		return
	var index = coordinate_2_index(x, y, z)
	if index >= 0 and index < blocks_data.size():
		blocks_data[index] = block

func get_block(x:int, y:int, z:int) -> int:
	if  y < 0 or y >= CHUNK_HEIGHT:
		return Blocks.Block.AIR
	if x >= 0 and x < CHUNK_SIZE and z >= 0 and z < CHUNK_SIZE:
		var index = coordinate_2_index(x, y, z)
		if index >= 0 and index < blocks_data.size():
			return blocks_data[index]
		return Blocks.Block.AIR
	var global_x = (chunk_x * CHUNK_SIZE) + x
	var global_z = (chunk_y * CHUNK_SIZE) + z
	var noise_value = noise.get_noise_2d(global_x, global_z)
	var normalized_value = (noise_value + 1.0) / 2.0
	var predicted_height = int(normalized_value * (CHUNK_HEIGHT - CHUNK_GEN_HEIGHT_MARGIN) + CHUNK_GEN_MIN_BASE)
	if y < predicted_height:
		return Blocks.Block.STONE
	return Blocks.Block.AIR

func generate_from_noise(n:FastNoiseLite=noise):
	for x in range(Chunk.CHUNK_SIZE):
		for z in range(Chunk.CHUNK_SIZE):
			# -1 ... 1
			var noise_value = n.get_noise_2d(chunk_x * CHUNK_SIZE + x, chunk_y * CHUNK_SIZE + z)
			# 0 ... 1
			var normalized_value = (noise_value + 1.0) / 2.0
			var height = int(normalized_value * (CHUNK_HEIGHT - CHUNK_GEN_HEIGHT_MARGIN) + CHUNK_GEN_MIN_BASE)
			for y in range(height):
				var block = Blocks.Block.STONE
				if y >  LAYER_STONE_HEIGHT:
					block = Blocks.Block.DIRT
				if y == height - 1:
					block = Blocks.Block.GRASS
				set_block(x, y, z, block)

func build_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_SIZE):
				var block = get_block(x, y, z)
				if block == Blocks.Block.AIR:
					continue
				draw_block(x, y, z, block, st)
	return st.commit()

func build_greedy_mesh():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var dims = [CHUNK_SIZE, CHUNK_HEIGHT, CHUNK_SIZE]
	# Iterate in three axis
	for d in range(3):
		var u = (d + 1) % 3 # Row index (next dim)
		var v = (d + 2) % 3 # Col index (next next dim)
		var x = [0, 0, 0] # Block cursor while iterating
		var q = [0, 0, 0]
		q[d] = 1 # Q vector indicates neighbor blocks
		var mask = []
		mask.resize(dims[u] * dims[v])
		# Scan chunk slices in current axis
		for slice in range(-1, dims[d]):
			x[d] = slice
			var n = 0
			mask.fill(0) # Everything starts as "hidden"
			for y_idx in range(dims[v]):
				x[v] = y_idx
				for j_idx in range(dims[u]):
					x[u] = j_idx
					var current_block = Blocks.Block.AIR
					if slice >= 0:
						current_block = get_block(x[0], x[1], x[2]) as Blocks.Block
					var compare_block = Blocks.Block.AIR
					if slice < dims[d]:
						compare_block = get_block(x[0]+q[0], x[1]+q[1], x[2]+q[2]) as Blocks.Block
					var current_is_transparent = Blocks.is_block_trasnparent(current_block)
					var compare_is_transparent = Blocks.is_block_trasnparent(compare_block)
					if current_is_transparent != compare_is_transparent:
						if not current_is_transparent:
							mask[n] = current_block
						else:
							mask[n] = -compare_block
					n += 1 # Next slice
			x[d] += 1
			var i = 0
			for y_idx in range(dims[v]):
				var j = 0
				while j < dims[u]:
					var mask_val = mask[i]
					if mask_val != 0:
						# Try to expand wide
						var w = 1
						while j+w < dims[u] and mask[i+w] == mask_val:
							w += 1
						# Try to expand hight
						var h = 1
						var done = false
						while y_idx + h < dims[v]:
							for k in range(w):
								if mask[i + k + h * dims[u]] != mask_val:
									done = true
									break
							if done:
								break
							h += 1
						var block = abs(mask_val) as Blocks.Block
						var is_positive = mask_val > 0
						if d == 0:
							var pos = Vector3(x[0], j, y_idx)
							if is_positive: draw_greedy_face_east(block, pos, w, h, st)
							else: draw_greedy_face_west(block, pos, w, h, st)
						elif d == 1:
							var pos = Vector3(y_idx, x[1], j)
							if is_positive: draw_greedy_face_top(block, pos, w, h, st)
							else: draw_greedy_face_bottom(block, pos, w, h, st)
						elif d == 2:
							var pos = Vector3(j, y_idx, x[2])
							if is_positive: draw_greedy_face_north(block, pos, w, h, st)
							else: draw_greedy_face_south(block, pos, w, h, st)
						for l in range(h):
							for k in range(w):
								mask[i + k + l * dims[u]] = 0
						j += w
						i += w
					else:
						j += 1
						i += 1
	return st.commit()

func draw_block(x:int, y:int, z:int, block:int, st:SurfaceTool):
	if get_block(x, y + 1, z) == Blocks.Block.AIR:
		draw_face_top(block, Vector3(x, y, z), st)
	if get_block(x, y - 1, z) == Blocks.Block.AIR:
		draw_face_bottom(block, Vector3(x, y, z), st)
	if get_block(x + 1, y, z) == Blocks.Block.AIR:
		draw_face_east(block, Vector3(x, y, z), st)
	if get_block(x - 1, y, z) == Blocks.Block.AIR:
		draw_face_west(block, Vector3(x, y, z), st)
	if get_block(x, y, z + 1) == Blocks.Block.AIR:
		draw_face_north(block, Vector3(x, y, z), st)
	if get_block(x, y, z - 1) == Blocks.Block.AIR:
		draw_face_south(block, Vector3(x, y, z), st)

func draw_face_top(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 1, 1)
	var v2 = pos + Vector3(1, 1, 1)
	var v3 = pos + Vector3(1, 1, 0)
	var v4 = pos + Vector3(0, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.TOP), Vector3(0, 1, 0))

func draw_face_bottom(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(1, 0, 0)
	var v3 = pos + Vector3(1, 0, 1)
	var v4 = pos + Vector3(0, 0, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.BOTTOM), Vector3(0, -1, 0))

func draw_face_south(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(1, 0, 0)
	var v2 = pos + Vector3(0, 0, 0)
	var v3 = pos + Vector3(0, 1, 0)
	var v4 = pos + Vector3(1, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.SOUTH), Vector3(0, 0, -1))

func draw_face_north(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 1)
	var v2 = pos + Vector3(1, 0, 1)
	var v3 = pos + Vector3(1, 1, 1)
	var v4 = pos + Vector3(0, 1, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.NORTH), Vector3(0, 0, 1))

func draw_face_west(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(0, 0, 1)
	var v3 = pos + Vector3(0, 1, 1)
	var v4 = pos + Vector3(0, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.WEST), Vector3(-1, 0, 0))

func draw_face_east(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(1, 0, 1)
	var v2 = pos + Vector3(1, 0, 0)
	var v3 = pos + Vector3(1, 1, 0)
	var v4 = pos + Vector3(1, 1, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.EAST), Vector3(1, 0, 0))

func add_quad(st:SurfaceTool, v1:Vector3, v2:Vector3, v3:Vector3, v4:Vector3, uvs:Array, normal:Vector3):	
	st.set_normal(normal)
	
	st.set_uv(uvs[0])
	st.add_vertex(v1)
	st.set_uv(uvs[3])
	st.add_vertex(v4)
	st.set_uv(uvs[2])
	st.add_vertex(v3)
	
	st.set_uv(uvs[0])
	st.add_vertex(v1)
	st.set_uv(uvs[2])
	st.add_vertex(v3)
	st.set_uv(uvs[1])
	st.add_vertex(v2)

func draw_greedy_face_east(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(1, 0, h)
	var v2 = pos + Vector3(1, 0, 0)
	var v3 = pos + Vector3(1, w, 0)
	var v4 = pos + Vector3(1, w, h)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.EAST), Vector3(1, 0, 0), Vector2(h, w))

func draw_greedy_face_west(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(0, 0, h)
	var v3 = pos + Vector3(0, w, h)
	var v4 = pos + Vector3(0, w, 0)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.WEST), Vector3(-1, 0, 0), Vector2(h, w))

func draw_greedy_face_top(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(0, 1, w)
	var v2 = pos + Vector3(h, 1, w)
	var v3 = pos + Vector3(h, 1, 0)
	var v4 = pos + Vector3(0, 1, 0)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.TOP), Vector3(0, 1, 0), Vector2(h, w))

func draw_greedy_face_bottom(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(h, 0, 0)
	var v3 = pos + Vector3(h, 0, w)
	var v4 = pos + Vector3(0, 0, w)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.BOTTOM), Vector3(0, -1, 0), Vector2(h, w))

func draw_greedy_face_north(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 1)
	var v2 = pos + Vector3(w, 0, 1)
	var v3 = pos + Vector3(w, h, 1)
	var v4 = pos + Vector3(0, h, 1)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.NORTH), Vector3(0, 0, 1), Vector2(w, h))

func draw_greedy_face_south(block:int, pos:Vector3, w:int, h:int, st:SurfaceTool):
	var v1 = pos + Vector3(w, 0, 0)
	var v2 = pos + Vector3(0, 0, 0)
	var v3 = pos + Vector3(0, h, 0)
	var v4 = pos + Vector3(w, h, 0)
	add_greedy_quad(st, v1, v2, v3, v4, get_uvs(block, Blocks.Face.SOUTH), Vector3(0, 0, -1), Vector2(w, h))

func add_greedy_quad(st:SurfaceTool, v1:Vector3, v2:Vector3, v3:Vector3, v4:Vector3, uvs:Array, normal:Vector3, quad_size:Vector2):   
	st.set_normal(normal)

	st.set_uv2(quad_size)
	st.set_uv(uvs[0])
	st.add_vertex(v1)

	st.set_uv2(quad_size)
	st.set_uv(uvs[3])
	st.add_vertex(v4)

	st.set_uv2(quad_size)
	st.set_uv(uvs[2])
	st.add_vertex(v3)

	st.set_uv2(quad_size)
	st.set_uv(uvs[0])
	st.add_vertex(v1)

	st.set_uv2(quad_size)
	st.set_uv(uvs[2])
	st.add_vertex(v3)

	st.set_uv2(quad_size)
	st.set_uv(uvs[1])
	st.add_vertex(v2)

func get_uvs(block:int, face:int):
	var atlas_index = Blocks.textures[block][face]
	var atlas_x = atlas_index % Blocks.ATLAS_COLS
	var atlas_y = atlas_index / Blocks.ATLAS_COLS
	var uv_w = 1.0 / Blocks.ATLAS_COLS
	var uv_h = 1.0 / Blocks.ATLAS_ROWS
	var u = atlas_x * uv_w
	var v = atlas_y * uv_h
	var m = 0
	return [
	Vector2(u + m, v + uv_h - m),
	Vector2(u + uv_w - m, v + uv_h - m),
	Vector2(u + uv_w - m, v + m),
	Vector2(u + m, v + m)
	]
