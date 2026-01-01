# ============================================================================
# Script Kontroler Karakter 3D (Player - Auto Target & Combo Scaling)
# ============================================================================
extends CharacterBody3D

# --- PRELOAD SCENES ---
const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")
const SkillEffectScene = preload("res://Scene/skill_effect.tscn")

# ============================================================================
# VARIABEL PENGATURAN (EXPORT)
# ============================================================================

@export_group("Combat Stats")
# Damage untuk serangan ke-1, ke-2, dan ke-3
@export var combo_damages: Array[int] = [15, 20, 30] 

@export_group("Gameplay")
@export var can_be_stunned: bool = true
@export var hurt_duration: float = 0.6
@export var attack_animation_speed: float = 1.5

@export_group("Skills")
@export var light_skill_knockback: float = 8.0
@export var light_skill_damage: int = 10
@export var heavy_skill_knockback: float = 16.0
@export var heavy_skill_damage: int = 25

@export_group("Attack Lunge & Targeting")
@export var lunge_max_distance: float = 8.0        # Jarak maksimal Auto-Target mendeteksi musuh
@export var lunge_stop_distance: float = 1.2       # Jarak berhenti di depan musuh
@export var lunge_duration: float = 0.15
@export var lunge_snap_rotation_duration: float = 0.05 # Kecepatan putar ke musuh (makin kecil makin instan)

@export_group("Movement")
@export var move_speed: float = 4.0
@export var run_speed: float = 7.0
@export var jump_impulse: float = 8.0
@export var rotation_speed: float = 15.0
@export var animation_smooth_speed: float = 10.0

@export_group("Character Height")
@export var stand_height: float = 1.8

@export_group("Mouse Control")
@export var mouse_sensitivity: float = 0.003
@export var camera_min_pitch: float = -80.0
@export var camera_max_pitch: float = 80.0

# ============================================================================
# REFERENSI NODE (@ONREADY)
# ============================================================================
@onready var skin: Node3D = $Skin
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var combo_timer: Timer = $ComboTimer
@onready var hurt_timer: Timer = $HurtTimer
@onready var health_component = $HealthComponent
@onready var targeting_area: Area3D = $TargetingArea # Pastikan Node ini ada dan cukup besar!

@onready var right_hand_area: Area3D = $Skin/metarig/Skeleton3D/HitBoxRight
@onready var right_hitbox_shape: CollisionShape3D = $Skin/metarig/Skeleton3D/HitBoxRight/CollisionShape3D

@onready var left_hand_area: Area3D = $Skin/metarig/Skeleton3D/HitBoxLeft
@onready var left_hitbox_shape: CollisionShape3D = $Skin/metarig/Skeleton3D/HitBoxLeft/CollisionShape3D

# ============================================================================
# STATE MACHINE & VARIABEL INTERNAL
# ============================================================================
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_playback: AnimationNodeStateMachinePlayback

enum State { MOVE, ATTACK, SKILL, HURT, DEAD }
var state = State.MOVE

var combo_counter: int = 0
var hit_enemies_in_frame = [] 

# ============================================================================
# FUNGSI UTAMA GODOT
# ============================================================================

func _ready() -> void:
	add_to_group("player") 
	
	animation_tree.active = true
	anim_playback = animation_tree.get("parameters/playback")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	combo_timer.timeout.connect(_reset_combo)
	animation_player.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	
	if right_hand_area:
		right_hand_area.body_entered.connect(_on_attack_hitbox_entered)
	if left_hand_area:
		left_hand_area.body_entered.connect(_on_attack_hitbox_entered)

	health_component.health_changed.connect(
		func(health):
			if GameManager: GameManager.update_player_health(health)
	)
	if GameManager:
		GameManager.update_player_health(health_component.current_health)

	call_deferred("disable_all_hitboxes")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		spring_arm.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(camera_min_pitch), deg_to_rad(camera_max_pitch))

	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if state in [State.MOVE, State.ATTACK]:
		if Input.is_action_just_pressed("attack"):
			_handle_attack_input()

	if state == State.MOVE:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_impulse
			
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
		State.SKILL:
			_stop_movement(delta)
		State.ATTACK:
			_stop_movement(delta)
		State.HURT:
			if can_be_stunned:
				_stop_movement(delta)
			else:
				_handle_locomotion_movement(delta)
		State.DEAD:
			velocity = Vector3.ZERO
	
	_update_animations()
	move_and_slide()

# ============================================================================
# LOGIKA PERGERAKAN
# ============================================================================

func _handle_locomotion_movement(delta: float):
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var current_speed = run_speed if Input.is_action_pressed("run") else move_speed

	if direction:
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 10.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 10.0)
		
		var target_yaw = atan2(direction.x, direction.z)
		skin.rotation.y = lerp_angle(skin.rotation.y, target_yaw, rotation_speed * delta)
	else:
		_stop_movement(delta)

func _stop_movement(delta: float):
	velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
	velocity.z = lerp(velocity.z, 0.0, delta * 10.0)

# ============================================================================
# LOGIKA ANIMASI
# ============================================================================

func _update_animations() -> void:
	if state != State.MOVE: return

	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z).length()
	var target_blend_pos = 0.0
	
	if horizontal_velocity < 0.1:
		target_blend_pos = 0.0
	elif Input.is_action_pressed("run"):
		target_blend_pos = 2.0
	else:
		target_blend_pos = 1.0

	var target_anim_state = "Jump" if not is_on_floor() else "Movement"
	
	if is_on_floor():
		var current_blend = animation_tree.get("parameters/Movement/blend_position")
		var smooth_blend = lerp(current_blend, target_blend_pos, get_process_delta_time() * animation_smooth_speed)
		animation_tree.set("parameters/Movement/blend_position", smooth_blend)
	
	if anim_playback.get_current_node() != target_anim_state:
		anim_playback.travel(target_anim_state)

# ============================================================================
# LOGIKA SERANGAN (AUTO TARGETING ADA DI SINI)
# ============================================================================

func _on_attack_hitbox_entered(body: Node3D):
	if body == self: return 
	if state != State.ATTACK: return

	if body.is_in_group("enemy"):
		if body in hit_enemies_in_frame: return
		
		hit_enemies_in_frame.append(body)
		
		var damage_index = clampi(combo_counter - 1, 0, combo_damages.size() - 1)
		var actual_damage = combo_damages[damage_index]
		
		if body.has_node("HealthComponent"):
			body.get_node("HealthComponent").take_damage(actual_damage)

func _handle_attack_input() -> void:
	if not is_on_floor(): return

	if state == State.MOVE or (state == State.ATTACK and not combo_timer.is_stopped()):
		if combo_counter >= 3: return
		
		state = State.ATTACK
		combo_counter += 1
		hit_enemies_in_frame.clear() 
		
		# --- AUTO TARGETING LOGIC MULAI ---
		var target = _find_best_attack_target()
		
		if is_instance_valid(target):
			# 1. Hitung arah ke musuh
			var direction = global_position.direction_to(target.global_position)
			
			# 2. Hitung rotasi yang harus dilakukan
			var target_yaw = atan2(direction.x, direction.z)
			
			# 3. Hitung jarak
			var distance = global_position.distance_to(target.global_position)
			
			# 4. Setup Tween untuk memutar badan + maju (lunge)
			var tween = create_tween().set_parallel(true)
			tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			
			# ROTASI: Paksa player menghadap musuh (sangat cepat)
			# NOTE: Jika model Anda terbalik, tambahkan '+ PI' setelah target_yaw
			tween.tween_property(skin, "rotation:y", target_yaw, lunge_snap_rotation_duration)
			
			# MAJU (LUNGE): Jika musuh agak jauh, player "terbang" sedikit ke arah musuh
			if distance <= lunge_max_distance and distance > lunge_stop_distance:
				var dest = target.global_position - direction * lunge_stop_distance
				dest.y = global_position.y
				tween.tween_property(self, "global_position", dest, lunge_duration)
		# --- AUTO TARGETING LOGIC SELESAI ---
		
		animation_tree.set("parameters/TimeScale/scale", attack_animation_speed)
		anim_playback.travel("Attack" + str(combo_counter))
		combo_timer.start()

func _use_skill(knockback_force: float, damage_amount: int):
	state = State.SKILL
	
	if damage_amount == light_skill_damage:
		GameManager.trigger_cooldown("E", 0.5)
	elif damage_amount == heavy_skill_damage:
		GameManager.trigger_cooldown("Q", 1.0)
	
	var effect = SkillEffectScene.instantiate()
	var spawn_transform = skin.global_transform
	spawn_transform.origin += spawn_transform.basis.z * 1.0
	
	get_tree().root.add_child(effect)
	effect.start(spawn_transform, knockback_force, damage_amount)
	
	await get_tree().create_timer(0.4).timeout
	if state == State.SKILL:
		state = State.MOVE

# Fungsi Mencari Musuh "Terbaik" (Terdekat & Paling Depan)
func _find_best_attack_target() -> Node3D:
	var bodies = targeting_area.get_overlapping_bodies()
	if bodies.is_empty(): return null

	var best_target: Node3D = null
	var best_score = -INF
	
	# Prioritas arah: Arah Input (WASD) kalau ada, kalau tidak pakai arah Kamera
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var priority_dir = -spring_arm.global_transform.basis.z.normalized()
	
	if input_dir.length() > 0.1:
		priority_dir = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	for body in bodies:
		if not body.is_in_group("enemy"): continue

		var dir_to = global_position.direction_to(body.global_position)
		var dist = global_position.distance_to(body.global_position)

		# Abaikan jika di luar jarak lunge
		if dist > lunge_max_distance: continue
			
		# SKORING:
		# Angle Score: Seberapa pas musuh ada di depan kita? (bobot 1.5)
		# Distance Score: Seberapa dekat musuh? (bobot 1.0)
		var angle_score = priority_dir.dot(dir_to) 
		var distance_score = 1.0 - (dist / lunge_max_distance)
		
		var total_score = (angle_score * 1.5) + distance_score
		
		if total_score > best_score:
			best_score = total_score
			best_target = body
			
	return best_target

# ============================================================================
# EVENT HANDLERS
# ============================================================================

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
	disable_all_hitboxes()
	
	animation_tree.set("parameters/TimeScale/scale", 1.0)
	anim_playback.travel("Hurt")
	hurt_timer.start(hurt_duration)
	
	var dmg_num = DamageNumberScene.instantiate()
	get_tree().root.add_child(dmg_num)
	dmg_num.show_damage(damage_amount, global_position + Vector3.UP * 1.8)

func _on_hurt_timer_timeout():
	if state == State.HURT:
		state = State.MOVE

func _on_death():
	state = State.DEAD
	disable_all_hitboxes()
	anim_playback.travel("Die")
	GameManager.trigger_game_over()

func _on_animation_finished(anim_name: StringName):
	var anim_str = str(anim_name)
	
	if anim_str.begins_with("Skill") and state == State.SKILL:
		state = State.MOVE
	
	if anim_str.begins_with("Attack"):
		disable_all_hitboxes()
		if combo_timer.is_stopped():
			_reset_combo()
	
	elif anim_str == "Die":
		set_physics_process(false)

# ============================================================================
# FUNGSI HELPER HITBOX
# ============================================================================

func enable_right_hand():
	if right_hitbox_shape: right_hitbox_shape.disabled = false
	hit_enemies_in_frame.clear() 

func enable_left_hand():
	if left_hitbox_shape: left_hitbox_shape.disabled = false
	hit_enemies_in_frame.clear()

func disable_all_hitboxes():
	if right_hitbox_shape: right_hitbox_shape.set_deferred("disabled", true)
	if left_hitbox_shape: left_hitbox_shape.set_deferred("disabled", true)

func remap(value, in_min, in_max, out_min, out_max):
	return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min)
