# ============================================================================
# Script AI Musuh (Godot 4.4 - Final dengan Knockback)
# ============================================================================
extends CharacterBody3D

const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")

# --- Variabel Ekspor ---
@export_group("AI Settings")
@export var walk_speed: float = 2.0
@export var run_speed: float = 4.5
@export var walk_range: float = 8.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var leash_distance: float = 25.0
@export var rotation_speed: float = 12.0
@export var hurt_duration: float = 0.5

# --- Referensi Node ---
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_playback = anim_tree.get("parameters/playback")
@onready var skin: Node3D = $Skin
@onready var detection_area: Area3D = $DetectionArea
@onready var health_component = $HealthComponent
@onready var enemy_hitbox_shape: CollisionShape3D = $Skin/CharacterArmature/Skeleton3D/Sword/Sword/Hitbox/CollisionShape3D
@onready var hurt_timer: Timer = $HurtTimer
@onready var attack_timer: Timer = $AttackTimer
@onready var knockback_timer: Timer = $KnockbackTimer # Node Timer Wajib Ada

@onready var hp_bar_viewport = $HealthBarWidget/SubViewport/ProgressBar # Path ke ProgressBar
@onready var hp_bar_sprite = $HealthBarWidget # Path ke Sprite3D

# --- Variabel Internal ---
var player: Node3D = null
var start_position: Vector3
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_attacking: bool = false



# Definisi State
enum State { IDLE, CHASING, ATTACKING, HURT, DEAD, RETURNING, KNOCKBACK }
var state = State.IDLE

# ============================================================================ #
# Built-in Godot Functions
# ============================================================================ #
func _ready():
	start_position = global_position
	
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	anim_tree.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	knockback_timer.timeout.connect(_on_knockback_timer_timeout)
	health_component.health_changed.connect(_on_health_changed)
	
	var max_hp = health_component.max_health # Asumsi ada variabel max_health di component
	var current_hp = health_component.current_health
	
	_update_health_bar(current_hp, max_hp)
	
	
func _update_health_bar(current, max_val):
	if hp_bar_viewport:
		hp_bar_viewport.max_value = max_val
		hp_bar_viewport.value = current
		
	# Opsional: Sembunyikan bar jika darah penuh (biar layar bersih)
	# hp_bar_sprite.visible = current < max_val
	
func _on_health_changed(new_health):
	# Ambil max health (jika statis bisa pakai angka langsung, misal 100)
	var max_hp = 100 # Atau ambil dari health_component.max_health jika ada
	_update_health_bar(new_health, max_hp)
	

func _physics_process(delta):
	if state == State.DEAD: return

	if not is_on_floor():
		velocity.y -= gravity * delta

	match state:
		State.IDLE:
			_stop_movement()
			if is_instance_valid(player):
				state = State.CHASING
		State.CHASING:
			_state_chasing(delta)
		State.ATTACKING:
			_state_attacking(delta)
		State.RETURNING:
			_state_returning(delta)
		State.HURT:
			_stop_movement()
		State.KNOCKBACK:
			# Efek gesekan: perlambat dorongan secara bertahap
			velocity = velocity.lerp(Vector3.ZERO, delta * 5.0)
	
	move_and_slide()

# ============================================================================ #
# Logika State
# ============================================================================ #
func _state_chasing(delta):
	if not is_instance_valid(player): state = State.RETURNING; return
	
	var dist_to_player = global_position.distance_to(player.global_position)
	var dist_to_start = global_position.distance_to(start_position)

	if dist_to_player <= attack_range:
		state = State.ATTACKING
		return
	if dist_to_start > leash_distance:
		state = State.RETURNING
		return
	
	_update_rotation(player.global_position, delta)
	var speed = run_speed if dist_to_player > walk_range else walk_speed
	_move_towards(player.global_position, speed)

func _state_attacking(delta):
	_stop_movement()
	if not is_instance_valid(player): state = State.RETURNING; return
	
	_update_rotation(player.global_position, delta)
	
	var dist = global_position.distance_to(player.global_position)
	if dist > attack_range and not is_attacking:
		state = State.CHASING
		return
		
	if not is_attacking:
		_perform_attack()

func _state_returning(delta):
	if global_position.distance_to(start_position) < 0.5:
		state = State.IDLE
	else:
		_update_rotation(start_position, delta)
		_move_towards(start_position, walk_speed)

# ============================================================================ #
# Fungsi Aksi & Sinyal
# ============================================================================ #

# --- Logika Knockback ---
func apply_knockback(direction: Vector3, force: float):
	# Jangan di-knockback kalau sudah mati atau sedang knockback
	if state in [State.DEAD, State.KNOCKBACK, State.HURT]: return

	state = State.KNOCKBACK
	
	# Hitung vektor dorongan
	var knockback_vector = direction.normalized() * force
	knockback_vector.y = 0
	
	# Override velocity saat ini dengan dorongan
	velocity = knockback_vector
	
	# Mulai timer (misal 0.3 detik durasi terpental)
	knockback_timer.start(0.3)

func _on_knockback_timer_timeout():
	if state == State.KNOCKBACK:
		# Kembali mengejar player setelah berhenti terpental
		state = State.CHASING
# ------------------------

func _move_towards(target_pos, speed):
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		_stop_movement()
		return
	
	var dir = global_position.direction_to(nav_agent.get_next_path_position())
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_update_animation(speed)

func _perform_attack():
	is_attacking = true
	anim_playback.travel("Attack")
	attack_timer.start(attack_cooldown)

func _stop_movement():
	velocity.x = 0; velocity.z = 0
	_update_animation(0)

func _on_animation_finished(anim_name):
	if anim_name == "Die":
		queue_free()

func _on_attack_timer_timeout():
	is_attacking = false

func _on_hurt_timer_timeout():
	if state == State.HURT:
		if is_instance_valid(player):
			state = State.CHASING
		else:
			state = State.RETURNING

func _on_took_damage(amount: int):
	# Jika sedang Knockback, jangan di-interrupt oleh animasi Hurt biasa
	if state in [State.DEAD, State.HURT, State.KNOCKBACK]: return
	
	state = State.HURT
	is_attacking = false
	attack_timer.stop()
	disable_enemy_hitbox()
	anim_playback.travel("Hurt")
	hurt_timer.start(hurt_duration)
	
	var dmg = DamageNumberScene.instantiate()
	get_tree().root.add_child(dmg)
	dmg.show_damage(amount, global_position + Vector3.UP * 1.8)

func _on_death():
	if state != State.DEAD:
		state = State.DEAD
		$CollisionShape3D.set_deferred("disabled", true)
		disable_enemy_hitbox()
		anim_playback.travel("Die")

func enable_enemy_hitbox(): enemy_hitbox_shape.disabled = false
func disable_enemy_hitbox(): enemy_hitbox_shape.set_deferred("disabled", true)

# ============================================================================ #
# Helper
# ============================================================================ #
func _update_rotation(target_pos, delta):
	var dir_to_target = global_position.direction_to(target_pos)
	dir_to_target.y = 0
	if dir_to_target.length() > 0.01:
		skin.global_transform = skin.global_transform.looking_at(global_position - dir_to_target, Vector3.UP)

func _update_animation(speed):
	# Jangan update animasi jalan jika sedang dalam state khusus
	if state in [State.ATTACKING, State.HURT, State.DEAD, State.KNOCKBACK]: return
	
	var blend_position = 0.0
	if speed > run_speed * 0.9: blend_position = 2.0
	elif speed > 0.1: blend_position = 1.0
		
	anim_playback.travel("Movement")
	anim_tree.set("parameters/Movement/blend_position", blend_position)

func _on_detection_area_body_entered(body):
	if body.is_in_group("player") and state != State.DEAD:
		player = body
		if state in [State.IDLE, State.RETURNING]:
			state = State.CHASING

func _on_detection_area_body_exited(body):
	if body == player and state != State.DEAD:
		player = null
		if state in [State.CHASING, State.IDLE]:
			state = State.RETURNING
