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
static var CHUNK_SECTIONS = 4
@warning_ignore("integer_division")
static var CHUNK_SECTION_H = CHUNK_HEIGHT / CHUNK_SECTIONS

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

static func y_2_section(y:int) -> int:
	@warning_ignore("integer_division")
	return y / CHUNK_SECTION_H

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
		texture = preload("res://assets/blocks/block_textures.png")
		var shader = preload("res://assets/shaders/text2darray.gdshader")
		material = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("texture_array", texture)

"""====================================
----------- INSTANCE LOGIC ------------
===================================="""

var noise:FastNoiseLite
var chunk_x:int
var chunk_y:int
var blocks_data:PackedByteArray
var finished_loading:bool = false
var marked_for_unload:bool = false
var sections:Array[Array] = [] # Array of arrays with format [Mesh, Collision]
var section_loaded:Array[bool] = []
var is_reloading = false

# Establish noise and chunk coordinates
func init_chunk(n:FastNoiseLite, cx:int=0, cy:int=0):
	self.noise = n
	self.chunk_x = cx
	self.chunk_y = cy

# Load material if it is not, and air box
func _ready():
	setup_material()
	create_section_instances()
	blocks_data.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_HEIGHT)
	blocks_data.fill(Blocks.Block.AIR)
	load_chunk()

func _process(_delta: float) -> void:
	if marked_for_unload and finished_loading:
		unload()

# Initialize a mesh instance for each chunk section
func create_section_instances():
	for i in range(CHUNK_SECTIONS):
		section_loaded.append(false)
		var section = MeshInstance3D.new()
		var static_body = StaticBody3D.new()
		var collider = CollisionShape3D.new()
		static_body.add_child(collider)
		section.position.y = i * CHUNK_SECTION_H
		static_body.position.y = i * CHUNK_SECTION_H
		sections.append([section, collider])
		add_child(section)
		add_child(static_body)

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
	for i in range(CHUNK_SECTIONS):
		var mesh = build_mesh(i)
		var shape = mesh.create_trimesh_shape()
		call_deferred("apply_mesh", i, mesh, shape)

func reload_chunk(sections_to_reload:Array[int]):
	for s in sections_to_reload:
		if is_reloading: return
		var chunk_reload_process = Callable(self, "_reload_process").bind(s)
		WorkerThreadPool.add_task(chunk_reload_process, true)

func _reload_process(section:int):
	var mesh = build_mesh(section)
	var shape = mesh.create_trimesh_shape()
	print("Reloading chunk (", chunk_x, ", ", chunk_y, "), section ", section)
	#call_deferred("apply_mesh", section, mesh, shape)

func apply_mesh(section:int, new_mesh: ArrayMesh, shape: ConcavePolygonShape3D):
	if sections[section][0].mesh==null:sections[section][0].mesh = new_mesh
	sections[section][0].material_override = material
	if sections[section][1].shape==null:sections[section][1].shape = shape
	section_loaded[section] = true
	for s in section_loaded:
		if not s: return
	loaded.emit()
	finished_loading = true
	is_reloading = false

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

func build_mesh(section:int):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SECTION_H):
			for z in range(CHUNK_SIZE):
				var block = get_block(x, y + section * CHUNK_SECTION_H, z)
				if block == Blocks.Block.AIR:
					continue
				draw_block(x, y, z, block, st, section)
	return st.commit()

func draw_block(x:int, y:int, z:int, block:int, st:SurfaceTool, section:int):
	if Blocks.is_block_transparent(get_block(x, y + section * CHUNK_SECTION_H + 1, z)):
		draw_face_top(block, Vector3(x, y, z), st)
	if Blocks.is_block_transparent(get_block(x, y + section * CHUNK_SECTION_H - 1, z)):
		draw_face_bottom(block, Vector3(x, y, z), st)
	if Blocks.is_block_transparent(get_block(x + 1, y + section * CHUNK_SECTION_H, z)):
		draw_face_east(block, Vector3(x, y, z), st)
	if Blocks.is_block_transparent(get_block(x - 1, y + section * CHUNK_SECTION_H, z)):
		draw_face_west(block, Vector3(x, y, z), st)
	if Blocks.is_block_transparent(get_block(x, y + section * CHUNK_SECTION_H, z + 1)):
		draw_face_north(block, Vector3(x, y, z), st)
	if Blocks.is_block_transparent(get_block(x, y + section * CHUNK_SECTION_H, z - 1)):
		draw_face_south(block, Vector3(x, y, z), st)

func draw_face_top(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 1, 1)
	var v2 = pos + Vector3(1, 1, 1)
	var v3 = pos + Vector3(1, 1, 0)
	var v4 = pos + Vector3(0, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(0, 1, 0), Blocks.textures[block][Blocks.Face.TOP])

func draw_face_bottom(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(1, 0, 0)
	var v3 = pos + Vector3(1, 0, 1)
	var v4 = pos + Vector3(0, 0, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(0, -1, 0), Blocks.textures[block][Blocks.Face.BOTTOM])

func draw_face_south(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(1, 0, 0)
	var v2 = pos + Vector3(0, 0, 0)
	var v3 = pos + Vector3(0, 1, 0)
	var v4 = pos + Vector3(1, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(0, 0, -1), Blocks.textures[block][Blocks.Face.SOUTH])

func draw_face_north(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 1)
	var v2 = pos + Vector3(1, 0, 1)
	var v3 = pos + Vector3(1, 1, 1)
	var v4 = pos + Vector3(0, 1, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(0, 0, 1), Blocks.textures[block][Blocks.Face.NORTH])

func draw_face_west(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(0, 0, 0)
	var v2 = pos + Vector3(0, 0, 1)
	var v3 = pos + Vector3(0, 1, 1)
	var v4 = pos + Vector3(0, 1, 0)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(-1, 0, 0), Blocks.textures[block][Blocks.Face.WEST])

func draw_face_east(block:int, pos:Vector3, st:SurfaceTool):
	var v1 = pos + Vector3(1, 0, 1)
	var v2 = pos + Vector3(1, 0, 0)
	var v3 = pos + Vector3(1, 1, 0)
	var v4 = pos + Vector3(1, 1, 1)
	add_quad(st, v1, v2, v3, v4, get_uvs(), Vector3(1, 0, 0), Blocks.textures[block][Blocks.Face.EAST])

func add_quad(st:SurfaceTool, v1:Vector3, v2:Vector3, v3:Vector3, v4:Vector3, uvs:Array, normal:Vector3, texture_idx:int):	
	st.set_normal(normal)
	
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[0])
	st.add_vertex(v1)
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[3])
	st.add_vertex(v4)
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[2])
	st.add_vertex(v3)
	
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[0])
	st.add_vertex(v1)
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[2])
	st.add_vertex(v3)
	st.set_uv2(Vector2(texture_idx, 0))
	st.set_uv(uvs[1])
	st.add_vertex(v2)

func get_uvs():
	return [
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	]
