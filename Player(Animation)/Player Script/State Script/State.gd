# State.gd
class_name State
extends Node

var player: CharacterBody3D

func enter(): pass
func exit(): pass
func process_input(_event: InputEvent): pass
func process_physics(_delta: float): pass
