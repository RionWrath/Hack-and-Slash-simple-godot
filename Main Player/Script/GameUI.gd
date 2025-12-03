# GameUI.gd
extends CanvasLayer

func _ready():
	GameManager.player_health_label = $MarginContainer/VBoxContainer/PlayerHealthLabel
	GameManager.enemy_health_label = $MarginContainer/VBoxContainer/EnemyHealthLabel
