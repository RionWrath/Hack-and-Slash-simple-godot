# ============================================================================
# Script Kontroler Karakter Orang Ketiga (Third-Person Controller)
# v4.4 - Implementasi FSM Penuh & Bersih
# ============================================================================
extends CharacterBody3D

# ... (Semua @export var Anda tetap sama di sini) ...
@export_group("Movement")
@export var move_speed: float = 4.0
@export var run_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var jump_impulse: float = 8.0
@export var rotation_speed: float = 10.0

@export_group("Character Height")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.2

@export_group("Mouse Control")
@export var mouse_sensitivity: float = 0.003
@export var camera_min_pitch: float = -80.0
@export var camera_max_pitch: float = 80.0

@export_group("Sound Effects")
@export var footstep_sounds: Array = []
@export var footstep_interval: float = 0.45
@export var jump_sound: AudioStream
@export var land_sound: AudioStream
@export var voice_sounds: Array = []
@export var voice_interval_min: float = 8.0
@export var voice_interval_max: float = 15.0


# ============================================================================ #
# NODE REFERENCES
# ============================================================================ #
@onready var skin: Node3D = $Skin
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var jump_land_player: AudioStreamPlayer3D = $JumpLandPlayer
@onready var voice_player: AudioStreamPlayer3D = $VoicePlayer
@onready var voice_timer: Timer = $VoiceTimer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var combo_timer: Timer = $ComboTimer

# ============================================================================ #
# INTERNAL & FSM VARS
# ============================================================================ #
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_playback: AnimationNodeStateMachinePlayback
var is_crouching: bool = false
var is_crouching_allowed: bool = true
var yaw: float = 0.0
var pitch: float = 0.0
var _was_on_floor := true
var _footstep_time := 0.0

# Combat
var is_in_combat: bool = false # Variabel ini sekarang HANYA sebagai penanda, bukan pengambil keputusan
var can_attack: bool = true
var combo_counter: int = 0

# State logic
var current_state: State
var states: Dictionary = {}

var is_transitioning_combat: bool = false


# ============================================================================ #
# READY & PROCESS
# ============================================================================ #
func _ready() -> void:
	anim_playback = animation_tree.get("parameters/playback")
	animation_tree.active = true
	
	# Inisialisasi semua state dari	 scene tree
	# PASTIKAN ANDA MEMILIKI NODE DAN SKRIP INI DI SCENE ANDA
	states = {
		"normal": $States/NormalState,
		"combat": $States/CombatState,
	}
	for state_node in states.values():
		state_node.player = self
	
	# Mulai dengan state normal
	change_state(states.normal)

	# Koneksi sinyal
	voice_timer.timeout.connect(_on_voice_timer_timeout)
	animation_player.animation_finished.connect(_on_animation_finished)
	combo_timer.timeout.connect(_reset_combo)
	_start_voice_timer()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_mouse_look(event)
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# [FIX] HANYA delegasikan input ke state yang aktif. Tidak ada logika lain di sini.
	if current_state:
		current_state.process_input(event)

func _physics_process(delta: float) -> void:
	# [FIX] HANYA delegasikan proses fisika ke state yang aktif.
	if current_state:
		current_state.process_physics(delta)

# ============================================================================ #
# STATE MANAGEMENT
# ============================================================================ #
func change_state(new_state: State) -> void:
	if current_state:
		current_state.exit()
	current_state = new_state
	current_state.enter()

func _on_animation_finished(anim_name: StringName) -> void:
	match str(anim_name):
		"DrawSword":
			is_transitioning_combat = false
			change_state(states.combat)
		"SheathSword":
			is_transitioning_combat = false
			change_state(states.normal)
		_:
			if str(anim_name).begins_with("Attack"):
				can_attack = true
				if combo_timer.is_stopped():
					_reset_combo()


# ============================================================================ #
# FUNGSI INTI (Sekarang dipanggil oleh States)
# ============================================================================ #
func _start_attack_combo() -> void:
	can_attack = false
	combo_counter += 1
	if combo_counter > 3: combo_counter = 1
	anim_playback.travel("Attack" + str(combo_counter))
	combo_timer.start()

func _reset_combo() -> void:
	combo_counter = 0
	can_attack = true
	combo_timer.stop()
	
func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and _was_on_floor and not is_crouching and can_attack:
		velocity.y = jump_impulse
		play_sound(jump_land_player, jump_sound)

	if _update_crouch_state():
		_update_collision_shape()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var current_speed: float = move_speed
	if Input.is_action_pressed("run") and not is_crouching: current_speed = run_speed
	elif is_crouching: current_speed = crouch_speed
	if not can_attack: current_speed = 0

	if direction:
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 10.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 10.0)
		if is_in_combat:
			var target_yaw = spring_arm.rotation.y
			skin.rotation.y = lerp_angle(skin.rotation.y, target_yaw, rotation_speed * delta)
		else:
			var target_yaw = atan2(direction.x, direction.z)
			skin.rotation.y = lerp_angle(skin.rotation.y, target_yaw, rotation_speed * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 8.0)

	move_and_slide()
	_was_on_floor = is_on_floor()

func _update_animations() -> void:
	if not can_attack: return
	
	var horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z).length()
	
	if is_in_combat:
		var blend_combat = remap(horizontal_velocity, 0.0, run_speed, 0.0, 2.0)
		animation_tree.set("parameters/CombatMovement/blend_position", blend_combat)
	else:
		if is_crouching:
			var blend_crouch = remap(horizontal_velocity, 0.0, crouch_speed, 0.0, 1.0)
			animation_tree.set("parameters/CrouchMovement/blend_position", blend_crouch)
		else:
			var blend_move = remap(horizontal_velocity, 0.0, run_speed, 0.0, 2.0)
			animation_tree.set("parameters/Movement/blend_position", blend_move)

	if not is_on_floor():
		var is_running = horizontal_velocity > move_speed
		var target_jump_state = "JumpRun" if is_running else "Jump"
		if is_in_combat:
			target_jump_state = "CombatJumpRun" if is_running else "CombatJump"
		travel_if_not(target_jump_state)
	else:
		var target_ground_state = "Movement"
		if is_in_combat:
			target_ground_state = "CombatMovement"
		elif is_crouching:
			target_ground_state = "CrouchMovement"
		travel_if_not(target_ground_state)


func travel_if_not(target_state: StringName) -> void:
	if anim_playback.get_current_node() != target_state:
		anim_playback.travel(target_state)

# ... (Semua fungsi lain seperti _handle_mouse_look, _handle_sounds, dll. tetap sama) ...
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	yaw -= event.relative.x * mouse_sensitivity
	pitch -= event.relative.y * mouse_sensitivity
	pitch = clamp(pitch, deg_to_rad(camera_min_pitch), deg_to_rad(camera_max_pitch))
	spring_arm.rotation.x = pitch
	spring_arm.rotation.y = yaw
		
func _handle_sounds(delta: float) -> void:
	if is_on_floor() and not _was_on_floor: play_sound(jump_land_player, land_sound)
	var horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and horizontal_velocity > 0.1:
		_footstep_time += delta
		var interval_modifier = 1.0
		if is_crouching: interval_modifier = 1.5
		elif Input.is_action_pressed("run"): interval_modifier = 0.7
		if _footstep_time >= footstep_interval * interval_modifier:
			_footstep_time = 0.0
			play_sound_random(footstep_player, footstep_sounds)
	else:
		footstep_player.stop()

func _update_crouch_state() -> bool:
	if not is_crouching_allowed: return false
	if Input.is_action_just_pressed("crouch"):
		is_crouching = not is_crouching
		return true
	return false

func _update_collision_shape() -> void:
	var shape = collision_shape.shape as CapsuleShape3D
	if not shape: return
	var target_height = stand_height if not is_crouching else crouch_height
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(shape, "height", target_height, 0.2)
	tween.tween_property(collision_shape, "position:y", target_height / 2.0, 0.2)

func play_sound(player: AudioStreamPlayer3D, sound: AudioStream) -> void:
	if sound and not player.is_playing():
		player.stream = sound
		player.play()

func play_sound_random(player: AudioStreamPlayer3D, sounds: Array) -> void:
	if not sounds.is_empty() and not player.is_playing():
		player.stream = sounds.pick_random()
		player.play()

func _start_voice_timer() -> void:
	if voice_sounds.is_empty(): return
	voice_timer.wait_time = randf_range(voice_interval_min, voice_interval_max)
	voice_timer.start()

func _on_voice_timer_timeout() -> void:
	play_sound_random(voice_player, voice_sounds)
	_start_voice_timer()

func remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var denom = in_max - in_min
	if abs(denom) < 0.0001: return out_min
	return out_min + (value - in_min) * (out_max - out_min) / denom
