# ============================================================================
# Script AI Musuh (Godot 4.4 - Final Fix)
# ============================================================================
extends CharacterBody3D

const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")

# --- Variabel Ekspor ---
@export_group("Stats")
@export var damage_amount: int = 10 # BARU: Berapa damage serangan musuh ke player?

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
@onready var hurt_timer: Timer = $HurtTimer
@onready var attack_timer: Timer = $AttackTimer
@onready var knockback_timer: Timer = $KnockbackTimer 

# Referensi UI
@onready var hp_bar_viewport = $HealthBarWidget/SubViewport/ProgressBar
@onready var hp_bar_sprite = $HealthBarWidget 

# PERBAIKAN: Kita butuh referensi ke Area3D (Parent dari CollisionShape) untuk mendeteksi hit
# Pastikan path ini benar mengarah ke node Area3D di pedang musuh
@onready var attack_hitbox: Area3D = $Skin/CharacterArmature/Skeleton3D/Sword/Sword/Hitbox
@onready var attack_hitbox_shape: CollisionShape3D = $Skin/CharacterArmature/Skeleton3D/Sword/Sword/Hitbox/CollisionShape3D

# --- Variabel Internal ---
var player: Node3D = null
var start_position: Vector3
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_attacking: bool = false
var max_hp_cached: int = 100 # Menyimpan Max HP agar tidak hardcoded

# Definisi State
enum State { IDLE, CHASING, ATTACKING, HURT, DEAD, RETURNING, KNOCKBACK }
var state = State.IDLE

# ============================================================================ #
# Built-in Godot Functions
# ============================================================================ #
func _ready():
	start_position = global_position
	
	# Simpan Max HP dari component saat mulai
	if health_component:
		max_hp_cached = health_component.max_health
	
	# Hubungkan Sinyal
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	anim_tree.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	knockback_timer.timeout.connect(_on_knockback_timer_timeout)
	health_component.health_changed.connect(_on_health_changed)
	
	# PERBAIKAN: Hubungkan Hitbox Serangan
	if attack_hitbox:
		attack_hitbox.body_entered.connect(_on_attack_hitbox_entered)
	
	# Update Health Bar Awal
	_update_health_bar(health_component.current_health, max_hp_cached)
	
	# Matikan hitbox di awal
	disable_enemy_hitbox()

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
			velocity = velocity.lerp(Vector3.ZERO, delta * 5.0)
	
	move_and_slide()

# ============================================================================ #
# Logika Health Bar
# ============================================================================ #
func _update_health_bar(current, max_val):
	if hp_bar_viewport:
		hp_bar_viewport.max_value = max_val
		hp_bar_viewport.value = current
	
func _on_health_changed(new_health):
	# PERBAIKAN: Gunakan max_hp_cached, jangan hardcode 100
	_update_health_bar(new_health, max_hp_cached)

# ============================================================================ #
# Logika State AI
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
# Logika Serangan (Memberi Damage ke Player)
# ============================================================================ #

func _perform_attack():
	is_attacking = true
	anim_playback.travel("Attack")
	attack_timer.start(attack_cooldown)

# Callback saat Hitbox Pedang menyentuh sesuatu
func _on_attack_hitbox_entered(body: Node3D):
	# Jika yang disentuh adalah Player
	if body.is_in_group("player"):
		# Berikan Damage
		if body.has_node("HealthComponent"):
			body.get_node("HealthComponent").take_damage(damage_amount)

# Fungsi Helper untuk AnimationPlayer (Call Method Track)
func enable_enemy_hitbox(): 
	if attack_hitbox_shape: attack_hitbox_shape.disabled = false

func disable_enemy_hitbox(): 
	if attack_hitbox_shape: attack_hitbox_shape.set_deferred("disabled", true)

func _on_attack_timer_timeout():
	is_attacking = false

# ============================================================================ #
# Logika Knockback & Hurt
# ============================================================================ #

func apply_knockback(direction: Vector3, force: float):
	if state in [State.DEAD, State.KNOCKBACK, State.HURT]: return

	state = State.KNOCKBACK
	var knockback_vector = direction.normalized() * force
	knockback_vector.y = 0
	velocity = knockback_vector
	knockback_timer.start(0.3)

func _on_knockback_timer_timeout():
	if state == State.KNOCKBACK:
		state = State.CHASING

func _on_took_damage(amount: int):
	if state in [State.DEAD, State.HURT, State.KNOCKBACK]: return
	
	state = State.HURT
	is_attacking = false
	attack_timer.stop()
	disable_enemy_hitbox() # Batalkan serangan jika kena hit
	anim_playback.travel("Hurt")
	hurt_timer.start(hurt_duration)
	
	var dmg = DamageNumberScene.instantiate()
	get_tree().root.add_child(dmg)
	dmg.show_damage(amount, global_position + Vector3.UP * 1.8)

func _on_hurt_timer_timeout():
	if state == State.HURT:
		if is_instance_valid(player):
			state = State.CHASING
		else:
			state = State.RETURNING

# ============================================================================ #
# Helper Functions
# ============================================================================ #

func _move_towards(target_pos, speed):
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		_stop_movement()
		return
	
	var dir = global_position.direction_to(nav_agent.get_next_path_position())
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_update_animation(speed)

func _stop_movement():
	velocity.x = 0; velocity.z = 0
	_update_animation(0)

func _update_rotation(target_pos, delta):
	var dir_to_target = global_position.direction_to(target_pos)
	dir_to_target.y = 0
	if dir_to_target.length() > 0.01:
		skin.global_transform = skin.global_transform.looking_at(global_position - dir_to_target, Vector3.UP)

func _update_animation(speed):
	if state in [State.ATTACKING, State.HURT, State.DEAD, State.KNOCKBACK]: return
	
	var blend_position = 0.0
	if speed > run_speed * 0.9: blend_position = 2.0
	elif speed > 0.1: blend_position = 1.0
		
	anim_playback.travel("Movement")
	anim_tree.set("parameters/Movement/blend_position", blend_position)

func _on_death():
	if state != State.DEAD:
		state = State.DEAD
		$CollisionShape3D.set_deferred("disabled", true)
		disable_enemy_hitbox()
		anim_playback.travel("Die")

func _on_animation_finished(anim_name):
	if anim_name == "Die":
		queue_free()
	
	# Matikan hitbox setelah animasi serangan selesai (untuk keamanan)
	if "Attack" in anim_name:
		disable_enemy_hitbox()

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
