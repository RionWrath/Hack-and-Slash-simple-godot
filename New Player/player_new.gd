# ============================================================================
# Script Kontroler Karakter 3D (Player - Dengan Skill Knockback)
# ============================================================================
extends CharacterBody3D

const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")
# BARU: Preload scene efek skill
const SkillEffectScene = preload("res://Scene/skill_effect.tscn")

# --- Variabel Ekspor ---
@export_group("Gameplay")
@export var can_be_stunned: bool = true
# ... (sisa variabel Anda tetap sama) ...
@export var hurt_duration: float = 0.6
@export var attack_animation_speed: float = 1.5

@export_group("Skills")
@export var light_skill_knockback: float = 8.0
@export var light_skill_damage: int = 10
@export var heavy_skill_knockback: float = 16.0
@export var heavy_skill_damage: int = 25

# ... (sisa grup export Anda tetap sama) ...
@export_group("Attack Lunge", "lunge_")
@export var lunge_max_distance: float = 8.0
@export var lunge_stop_distance: float = 1.5
@export var lunge_duration: float = 0.15
@export var lunge_snap_rotation_duration: float = 0.05

@export_group("Movement")
@export var move_speed: float = 4.0
@export var run_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var jump_impulse: float = 8.0
@export var rotation_speed: float = 15.0

@export_group("Character Height")
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.2

@export_group("Mouse Control")
@export var mouse_sensitivity: float = 0.003
@export var camera_min_pitch: float = -80.0
@export var camera_max_pitch: float = 80.0


# --- Referensi Node ---
@onready var skin: Node3D = $Skin
# ... (sisa referensi node Anda tetap sama) ...
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var combo_timer: Timer = $ComboTimer
@onready var health_component = $HealthComponent
@onready var sword_hitbox_shape: CollisionShape3D = $Skin/metarig/Skeleton3D/BoneAttachment3D/Sword_big2/Hitbox/CollisionShape3D
@onready var targeting_area: Area3D = $TargetingArea
@onready var hurt_timer: Timer = $HurtTimer

# --- Variabel Internal & State ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_playback: AnimationNodeStateMachinePlayback
# DIUBAH: Tambahkan state SKILL
enum State { MOVE, ATTACK, SKILL, HURT, DEAD }
var state = State.MOVE
var is_crouching: bool = false
var combo_counter: int = 0

# ============================================================================ #
# Built-in Godot Functions
# ============================================================================ #

func _ready() -> void:
	# ... (isi fungsi _ready() tetap sama) ...
	animation_tree.active = true
	anim_playback = animation_tree.get("parameters/playback")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	combo_timer.timeout.connect(_reset_combo)
	animation_player.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)

	health_component.health_changed.connect(
		func(health):
			if is_in_group("player"): GameManager.update_player_health(health)
	)
	if is_in_group("player"):
		GameManager.update_player_health(health_component.current_health)

	disable_sword_hitbox()

func _unhandled_input(event: InputEvent) -> void:
	# ... (kode mouse motion & ui_cancel tetap sama) ...
	if event is InputEventMouseMotion:
		spring_arm.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(camera_min_pitch), deg_to_rad(camera_max_pitch))

	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# Cek input serangan
	if state in [State.MOVE, State.ATTACK]:
		if Input.is_action_just_pressed("attack"):
			_handle_attack_input()

	# Cek input movement & skill HANYA jika sedang di state MOVE
	if state == State.MOVE:
		if Input.is_action_just_pressed("crouch") and is_on_floor():
			is_crouching = not is_crouching
			_update_collision_shape()
		
		if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
			velocity.y = jump_impulse
			
		# BARU: Cek input skill
		if Input.is_action_just_pressed("skill_light"):
			_use_skill(light_skill_knockback, light_skill_damage)
		if Input.is_action_just_pressed("skill_heavy"):
			_use_skill(heavy_skill_knockback, heavy_skill_damage)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	match state:
		State.MOVE:
			_handle_locomotion_movement(delta)
		# BARU: Tambahkan case untuk SKILL
		State.SKILL:
			# Saat menggunakan skill, player berhenti sejenak
			velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		State.ATTACK:
			velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		State.HURT:
			if can_be_stunned:
				velocity.x = lerp(velocity.x, 0.0, delta * 8.0)
				velocity.z = lerp(velocity.z, 0.0, delta * 8.0)
			else:
				_handle_locomotion_movement(delta)
		State.DEAD:
			velocity = Vector3.ZERO
	
	_update_animations()
	move_and_slide()

# ... (Sisa skrip dari _handle_locomotion_movement ke bawah tetap sama, kecuali fungsi baru di akhir)
func _handle_locomotion_movement(delta: float):
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = crouch_speed if is_crouching else (run_speed if Input.is_action_pressed("run") else move_speed)

	if direction:
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 10.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 10.0)
		var target_yaw = atan2(direction.x, direction.z)
		skin.rotation.y = lerp_angle(skin.rotation.y, target_yaw, rotation_speed * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 8.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 8.0)

func _update_animations() -> void:
	# DIUBAH: Tambahkan pengecualian untuk state SKILL
	if state != State.MOVE: return

	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z).length()
	var blend_position = remap(horizontal_velocity, 0, run_speed, 0, 2)

	var target_anim_state: StringName
	if not is_on_floor():
		target_anim_state = "JumpRun" if Input.is_action_pressed("run") else "Jump"
	elif is_crouching:
		target_anim_state = "CrouchMovement"
		var blend_crouch = remap(horizontal_velocity, 0, crouch_speed, 0, 1)
		animation_tree.set("parameters/CrouchMovement/blend_position", blend_crouch)
	else:
		target_anim_state = "Movement"
		animation_tree.set("parameters/Movement/blend_position", blend_position)
	
	if anim_playback.get_current_node() != target_anim_state:
		anim_playback.travel(target_anim_state)

func _handle_attack_input() -> void:
	if not is_on_floor() or is_crouching: return

	if state == State.MOVE or (state == State.ATTACK and not combo_timer.is_stopped()):
		if combo_counter >= 3: return
		
		state = State.ATTACK
		combo_counter += 1
		
		var target = _find_best_attack_target()
		
		if is_instance_valid(target):
			var distance_to_target = global_position.distance_to(target.global_position)
			
			if distance_to_target <= lunge_max_distance:
				var direction = global_position.direction_to(target.global_position)
				var destination = target.global_position - direction * lunge_stop_distance
				destination.y = global_position.y
				
				var target_yaw = atan2(direction.x, direction.z)
				
				var tween = create_tween().set_parallel(true)
				tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				
				tween.tween_property(skin, "rotation:y", target_yaw, lunge_snap_rotation_duration)
				
				if distance_to_target > lunge_stop_distance:
					tween.tween_property(self, "global_position", destination, lunge_duration)
		
		animation_tree.set("parameters/TimeScale/scale", attack_animation_speed)
		anim_playback.travel("Attack" + str(combo_counter))
		combo_timer.start()

# VERSI BARU YANG SUDAH DIPERBAIKI
func _use_skill(knockback_force: float, damage_amount: int): # <<< PERBAIKAN 1: Terima damage_amount
	state = State.SKILL
	
	# Anda bisa memutar animasi skill di sini jika ada, misal: "SkillCast"
	# anim_playback.travel("SkillCast") 
	
	if damage_amount == light_skill_damage: 
		# Skill E (Light), cooldown visual misal 0.5 detik
		GameManager.trigger_cooldown("E", 0.5) 
		
	elif damage_amount == heavy_skill_damage:
		# Skill Q (Heavy), cooldown visual misal 1.0 detik
		GameManager.trigger_cooldown("Q", 1.0)
	
	var effect = SkillEffectScene.instantiate()
	
	var spawn_transform = skin.global_transform
	spawn_transform.origin += spawn_transform.basis.z * 1.0
	
	get_tree().root.add_child(effect)
	
	# PERBAIKAN 2: Kirim damage_amount sebagai argumen ke-3
	effect.start(spawn_transform, knockback_force, damage_amount)
	
	# Setelah durasi skill singkat, kembalikan state ke MOVE
	# (Jika Anda punya animasi skill, lebih baik gunakan sinyal animation_finished)
	await get_tree().create_timer(0.4).timeout
	if state == State.SKILL:
		state = State.MOVE

func _find_best_attack_target() -> Node3D:
	var enemies_in_range = targeting_area.get_overlapping_bodies()
	if enemies_in_range.is_empty():
		return null

	var best_target: Node3D = null
	var best_score = -INF

	var input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var priority_direction: Vector3
	if input_direction.length() > 0.1:
		priority_direction = (spring_arm.transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	else:
		priority_direction = -spring_arm.global_transform.basis.z.normalized()
	
	for enemy in enemies_in_range:
		if not enemy.is_in_group("enemy"):
			continue

		var direction_to_enemy = global_position.direction_to(enemy.global_position)
		var distance = global_position.distance_to(enemy.global_position)

		if distance > lunge_max_distance:
			continue
			
		var angle_score = priority_direction.dot(direction_to_enemy)
		var distance_score = 1.0 - (distance / lunge_max_distance)
		
		var total_score = (angle_score * 1.5) + distance_score
		
		if total_score > best_score:
			best_score = total_score
			best_target = enemy
			
	return best_target

func _reset_combo() -> void:
	combo_counter = 0
	animation_tree.set("parameters/TimeScale/scale", 1.0)
	if state == State.ATTACK:
		state = State.MOVE

func _on_took_damage(damage_amount):
	if state in [State.DEAD, State.HURT]: return
	
	state = State.HURT
	combo_counter = 0
	combo_timer.stop()
	disable_sword_hitbox()
	
	animation_tree.set("parameters/TimeScale/scale", 1.0)
	
	anim_playback.travel("Hurt")
	hurt_timer.start(hurt_duration)
	
	var damage_number = DamageNumberScene.instantiate()
	get_tree().root.add_child(damage_number)
	damage_number.show_damage(damage_amount, global_position + Vector3.UP * 1.8)

func _on_hurt_timer_timeout():
	if state == State.HURT:
		state = State.MOVE

func _on_death():
	state = State.DEAD
	disable_sword_hitbox()
	anim_playback.travel("Die")

func _on_animation_finished(anim_name: StringName):
	var anim_str = str(anim_name)
	
	# DIUBAH: Tambahkan pengecekan untuk animasi Skill
	if anim_str.begins_with("Skill"):
		if state == State.SKILL:
			state = State.MOVE
	
	if anim_str.begins_with("Attack"):
		disable_sword_hitbox()
		if combo_timer.is_stopped():
			_reset_combo()
	
	elif anim_str == "Die":
		set_physics_process(false)

func enable_sword_hitbox(): sword_hitbox_shape.disabled = false
func disable_sword_hitbox(): sword_hitbox_shape.set_deferred("disabled", true)

func _update_collision_shape() -> void:
	var shape = collision_shape.shape as CapsuleShape3D
	if not shape: return
	var target_height = stand_height if not is_crouching else crouch_height
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(shape, "height", target_height, 0.3)
	tween.tween_property(collision_shape, "position:y", target_height / 2.0, 0.3)

func remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var denom = in_max - in_min
	if abs(denom) < 0.0001: return out_min
	return out_min + (value - in_min) * (out_max - out_min) / denom
	
	
