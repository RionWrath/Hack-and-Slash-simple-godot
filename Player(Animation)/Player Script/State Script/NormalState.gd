# NormalState.gd
extends State

func enter():
	player.is_in_combat = false
	player.is_crouching_allowed = true
	# Saat masuk state ini, pastikan animasi kembali ke Movement
	player.anim_playback.travel("Movement")

func process_input(_event: InputEvent) -> State:
	if Input.is_action_just_pressed("toggle_combat"):
		player.is_transitioning_combat = true
		player.anim_playback.travel("DrawSword")
		return null
	return null


func process_physics(delta: float):
	# Jalankan semua fungsi yang relevan untuk mode normal.
	player._handle_movement(delta)
	player._update_animations()
	player._handle_sounds(delta)
