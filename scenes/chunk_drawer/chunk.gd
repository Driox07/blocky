class_name Chunk
extends Node3D


"""====================================
-------- SIGNALS DECLARATIONS ---------
===================================="""
signal chunk_loaded

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

static func coordinate_2_index(x:int, y:int, z:int) -> int:
	return x + (y * CHUNK_SIZE) + (z * CHUNK_SIZE * CHUNK_HEIGHT)

static func get_chunk_id(x:int, y:int) -> String:
	return "x"+str(x)+"y"+str(y)

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
	WorkerThreadPool.add_task(load_chunk, true)

func _process(delta: float) -> void:
	if marked_for_unload and finished_loading:
		unload()

func load_chunk():
	if noise != null:
		generate_from_noise(noise)
		var mesh = build_mesh()
		var shape = mesh.create_trimesh_shape()
		call_deferred("apply_mesh", mesh, shape)


func apply_mesh(new_mesh: ArrayMesh, shape: ConcavePolygonShape3D):
	chunk_mesh.mesh = new_mesh
	chunk_mesh.material_override = material
	collision_shape.shape = shape
	chunk_loaded.emit()

func mark_for_unload():
	marked_for_unload = true

func unload():
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
