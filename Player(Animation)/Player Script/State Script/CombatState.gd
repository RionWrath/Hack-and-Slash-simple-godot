extends State

func enter() -> void:
	player.is_crouching_allowed = false
	player.is_crouching = false
	player.is_in_combat = true
	player.can_attack = true
	player.combo_counter = 0
	player.state_machine.travel("CombatMovement")

func exit() -> void:
	player.is_crouching_allowed = true
	player.is_in_combat = false
	player._reset_combo()

func process_input(_event: InputEvent) -> State:
	if Input.is_action_just_pressed("toggle_combat") and player.can_attack and not player.is_transitioning_combat:
		player.is_transitioning_combat = true
		player.state_machine.travel("SheathSword")
		return null

	if Input.is_action_just_pressed("attack") and player.is_on_floor() and player.can_attack and not player.is_transitioning_combat:
		player._start_attack_combo()
		return null

	return null

func process_physics(delta: float) -> State:
	player._handle_movement(delta)
	player._update_combat_animations()
	player._handle_sounds(delta)
	return null
