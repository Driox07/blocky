extends Node

const BLOCK_SIZE = 1
enum Face {TOP = 0, BOTTOM = 1, EAST = 2, WEST = 3, NORTH = 4, SOUTH = 5}
enum Block {AIR = 0, STONE = 1, DIRT = 2, GRASS = 3}

const SOLIDS = [Block.STONE, Block.DIRT, Block.GRASS]
const TRANSPARENTS = [Block.AIR]

const ATLAS_ROWS = 32
const ATLAS_COLS = 32

const textures = {
	Block.AIR:   [0,0,0,0,0,0],
	Block.STONE: [4,4,4,4,4,4],
	Block.DIRT:  [3,3,3,3,3,3],
	Block.GRASS: [1,3,2,2,2,2]
				}

func is_block_solid(block:Block):
	return SOLIDS.has(block)

func is_block_trasnparent(block:Block):
	return TRANSPARENTS.has(block)
