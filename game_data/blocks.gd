extends Node

const BLOCK_SIZE = 1
enum Face {TOP = 0, BOTTOM = 1, EAST = 2, WEST = 3, NORTH = 4, SOUTH = 5}
enum Block {AIR = 0, STONE = 1, DIRT = 2, GRASS = 3}

const ATLAS_ROWS = 32
const ATLAS_COLS = 32

const textures = {
	Block.AIR:   [0,0,0,0,0,0],
	Block.STONE: [4,4,4,4,4,4],
	Block.DIRT:  [3,3,3,3,3,3],
	Block.GRASS: [1,3,2,2,2,2]
				}
