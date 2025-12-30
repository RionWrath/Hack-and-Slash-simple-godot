# ============================================================================
# Script Kontroler Karakter 3D (Player - Fix Damage & Self Hit)
# ============================================================================
extends CharacterBody3D

# --- PRELOAD SCENES ---
const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")
const SkillEffectScene = preload("res://Scene/skill_effect.tscn")

# ============================================================================
# VARIABEL PENGATURAN (EXPORT)
# ============================================================================

@export_group("Gameplay")
@export var base_damage: int = 15          # PERBAIKAN: Damage dasar pukulan biasa
@export var can_be_stunned: bool = true
@export var hurt_duration: float = 0.6
@export var attack_animation_speed: float = 1.5

@export_group("Skills")
@export var light_skill_knockback: float = 8.0
@export var light_skill_damage: int = 10
@export var heavy_skill_knockback: float = 16.0
@export var heavy_skill_damage: int = 25

@export_group("Attack Lunge")
@export var lunge_max_distance: float = 6.0
@export var lunge_stop_distance: float = 1.0
@export var lunge_duration: float = 0.15
@export var lunge_snap_rotation_duration: float = 0.05

@export_group("Movement")
@export var move_speed: float = 4.0
@export var run_speed: float = 7.0
@export var jump_impulse: float = 8.0
@export var rotation_speed: float = 15.0
@export var animation_smooth_speed: float = 10.0 # Untuk transisi animasi mulus

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
@onready var targeting_area: Area3D = $TargetingArea

# --- PERBAIKAN PENTING: Referensi Area3D dan CollisionShape ---
# Kita butuh Area3D untuk sinyal, dan CollisionShape untuk enable/disable
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
var hit_enemies_in_frame = [] # Agar satu pukulan tidak memberi damage berkali-kali ke musuh yang sama

# ============================================================================
# FUNGSI UTAMA GODOT
# ============================================================================

func _ready() -> void:
	# PERBAIKAN 1: Pastikan Player masuk Group "player" agar dikejar musuh
	add_to_group("player") 
	
	animation_tree.active = true
	anim_playback = animation_tree.get("parameters/playback")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Setup Sinyal
	combo_timer.timeout.connect(_reset_combo)
	animation_player.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	
	# PERBAIKAN 2: Hubungkan sinyal serangan lewat kode
	# Ini mendeteksi saat tangan menyentuh musuh
	if right_hand_area:
		right_hand_area.body_entered.connect(_on_attack_hitbox_entered)
	if left_hand_area:
		left_hand_area.body_entered.connect(_on_attack_hitbox_entered)

	# Setup UI Health
	health_component.health_changed.connect(
		func(health):
			if GameManager: GameManager.update_player_health(health)
	)
	if GameManager:
		GameManager.update_player_health(health_component.current_health)

	disable_all_hitboxes() # Matikan hitbox di awal agar aman

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
# LOGIKA PERGERAKAN (DENGAN LERP MULUS)
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
# LOGIKA SERANGAN, DAMAGE & SKILL (PERBAIKAN UTAMA DI SINI)
# ============================================================================

# PERBAIKAN 3: Fungsi ini dipanggil saat Hitbox Tangan menyentuh Sesuatu
func _on_attack_hitbox_entered(body: Node3D):
	# 1. PENCEGAHAN DAMAGE DIRI SENDIRI
	if body == self: return 
	
	# 2. Pastikan yang dipukul adalah Musuh
	if body.is_in_group("enemy"):
		# 3. Cek apakah musuh ini sudah kena di pukulan frame ini?
		if body in hit_enemies_in_frame: return
		
		hit_enemies_in_frame.append(body) # Tandai sudah kena
		
		# 4. Berikan Damage (Pastikan enemy punya HealthComponent)
		if body.has_node("HealthComponent"):
			body.get_node("HealthComponent").take_damage(base_damage)
		
		# Efek visual opsional (partikel darah, suara, dll) bisa ditaruh di sini

func _handle_attack_input() -> void:
	if not is_on_floor(): return

	if state == State.MOVE or (state == State.ATTACK and not combo_timer.is_stopped()):
		if combo_counter >= 3: return
		
		state = State.ATTACK
		combo_counter += 1
		hit_enemies_in_frame.clear() # Reset daftar musuh kena untuk serangan baru
		
		var target = _find_best_attack_target()
		
		if is_instance_valid(target):
			var distance = global_position.distance_to(target.global_position)
			
			if distance <= lunge_max_distance:
				var direction = global_position.direction_to(target.global_position)
				var dest = target.global_position - direction * lunge_stop_distance
				dest.y = global_position.y
				
				var target_yaw = atan2(direction.x, direction.z)
				var tween = create_tween().set_parallel(true)
				tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(skin, "rotation:y", target_yaw, lunge_snap_rotation_duration)
				
				if distance > lunge_stop_distance:
					tween.tween_property(self, "global_position", dest, lunge_duration)
		
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

func _find_best_attack_target() -> Node3D:
	var bodies = targeting_area.get_overlapping_bodies()
	if bodies.is_empty(): return null

	var best_target: Node3D = null
	var best_score = -INF
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var priority_dir = -spring_arm.global_transform.basis.z.normalized()
	
	if input_dir.length() > 0.1:
		priority_dir = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	for body in bodies:
		if not body.is_in_group("enemy"): continue

		var dir_to = global_position.direction_to(body.global_position)
		var dist = global_position.distance_to(body.global_position)

		if dist > lunge_max_distance: continue
			
		var score = (priority_dir.dot(dir_to) * 1.5) + (1.0 - (dist / lunge_max_distance))
		
		if score > best_score:
			best_score = score
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
	hit_enemies_in_frame.clear() # Reset setiap kali pukulan baru keluar

func enable_left_hand():
	if left_hitbox_shape: left_hitbox_shape.disabled = false
	hit_enemies_in_frame.clear()

func disable_all_hitboxes():
	if right_hitbox_shape: right_hitbox_shape.set_deferred("disabled", true)
	if left_hitbox_shape: left_hitbox_shape.set_deferred("disabled", true)

func remap(value, in_min, in_max, out_min, out_max):
	return out_min + (value - in_min) * (out_max - out_min) / (in_max - in_min)
