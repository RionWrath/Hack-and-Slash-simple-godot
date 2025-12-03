# DamageNumber.gd
extends Node3D

@onready var label: Label3D = $Label3D

func show_damage(amount: float, spawn_position: Vector3):
	label.text = str(roundi(amount))
	global_position = spawn_position # Jauh lebih jelas
	
	# Buat animasi menggunakan Tween
	var tween = create_tween()
	tween.tween_property(self, "position:y", spawn_position.y + 1.5, 0.7).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).from(1.0)
	
	await tween.finished
	queue_free()
