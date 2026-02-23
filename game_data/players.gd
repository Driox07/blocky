extends Node

var players:Array[Player] = []

func add_player(player:Player):
	if players.has(player): return
	players.append(player)
