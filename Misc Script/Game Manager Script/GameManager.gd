# GameManager.gd
extends Node

var player_health_label: Label
var enemy_health_label: Label
var ui = null # Menyimpan HUD
var player_health: int = 100

# Dipanggil oleh HUD saat _ready()
func set_hud(hud_instance):
	ui = hud_instance
	# Langsung update tampilan awal
	if ui:
		ui.update_health(player_health, 100)

func update_player_health(health):
	
	player_health = health
	if ui:
		ui.update_health(player_health, 100)
		
	if player_health_label:
		player_health_label.text = "Player HP: " + str(health)

func update_enemy_health(health):
	if enemy_health_label:
		enemy_health_label.text = "Enemy HP: " + str(health)
		
		
# Dipanggil oleh Player saat skill dipakai
func trigger_cooldown(skill_key: String, time: float):
	if ui:
		ui.play_cooldown(skill_key, time)
		
func trigger_game_over():
	if ui:
		ui.show_game_over()
