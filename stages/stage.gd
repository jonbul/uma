class_name Stage
extends Node2D
## Base for every stage: the room art, walls that keep fighters on the
## floor, props, and where fighters spawn.
##
## A stage needs a `SpawnPoints` node with one Marker2D per player slot (10).
## The match puts the stage next to the fighters under one y-sorted node, so
## props whose origin is at their base draw in front of or behind fighters
## correctly. Props block fighters by being on the `world` collision layer.


func get_spawn_points() -> Array[Marker2D]:
	var points: Array[Marker2D] = []
	points.assign($SpawnPoints.get_children())
	return points
