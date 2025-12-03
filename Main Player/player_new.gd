# ============================================================================
# Script Kontroler Karakter 3D (Player)
# Fitur: Gerakan, Serangan Kombo, Skill Knockback, Auto-Targeting, HP System
# ============================================================================
extends CharacterBody3D

# --- PRELOAD SCENES ---
# Memuat scene lain ke dalam memori agar siap digunakan (spawn) kapan saja
const DamageNumberScene = preload("res://Scene/DamageNumber.tscn")
const SkillEffectScene = preload("res://Scene/skill_effect.tscn")

# ============================================================================
# VARIABEL PENGATURAN (EXPORT)
# Variabel ini bisa diubah nilainya langsung dari Inspector Godot
# ============================================================================

@export_group("Gameplay")
@export var can_be_stunned: bool = true        # Apakah player bisa kena stun saat dipukul?
@export var hurt_duration: float = 0.6         # Berapa lama player terpana saat kena hit
@export var attack_animation_speed: float = 1.5 # Kecepatan animasi serangan (1.5x lebih cepat)

@export_group("Skills")
@export var light_skill_knockback: float = 8.0 # Kekuatan dorong skill E
@export var light_skill_damage: int = 10       # Damage skill E
@export var heavy_skill_knockback: float = 16.0 # Kekuatan dorong skill Q
@export var heavy_skill_damage: int = 25       # Damage skill Q

@export_group("Attack Lunge")
@export var lunge_max_distance: float = 8.0        # Jarak maksimal auto-aim berfungsi
@export var lunge_stop_distance: float = 1.5       # Jarak berhenti di depan musuh
@export var lunge_duration: float = 0.15           # Durasi gerakan maju saat menyerang
@export var lunge_snap_rotation_duration: float = 0.05 # Secepat apa player berputar ke musuh

@export_group("Movement")
@export var move_speed: float = 4.0   # Kecepatan jalan biasa
@export var run_speed: float = 7.0    # Kecepatan lari (Shift)
@export var crouch_speed: float = 2.0 # Kecepatan jongkok
@export var jump_impulse: float = 8.0 # Kekuatan lompat
@export var rotation_speed: float = 15.0 # Kecepatan putar karakter saat jalan

@export_group("Character Height")
@export var stand_height: float = 1.8  # Tinggi collider saat berdiri
@export var crouch_height: float = 1.2 # Tinggi collider saat jongkok

@export_group("Mouse Control")
@export var mouse_sensitivity: float = 0.003
@export var camera_min_pitch: float = -80.0 # Batas bawah kamera
@export var camera_max_pitch: float = 80.0  # Batas atas kamera

# ============================================================================
# REFERENSI NODE (@ONREADY)
# Mengambil akses ke node anak saat game dimulai (_ready)
# ============================================================================
@onready var skin: Node3D = $Skin                        # Model 3D Karakter
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var spring_arm: SpringArm3D = $SpringArm3D      # Kontrol Kamera
@onready var combo_timer: Timer = $ComboTimer            # Timer untuk reset kombo serangan
@onready var hurt_timer: Timer = $HurtTimer              # Timer durasi stun/hurt
@onready var health_component = $HealthComponent         # Komponen nyawa
@onready var targeting_area: Area3D = $TargetingArea     # Area deteksi musuh
# Hitbox Pedang (lokasi collision shape di dalam struktur bone)
@onready var sword_hitbox_shape: CollisionShape3D = $Skin/metarig/Skeleton3D/BoneAttachment3D/Sword_big2/Hitbox/CollisionShape3D

# ============================================================================
# STATE MACHINE & VARIABEL INTERNAL
# ============================================================================
# Mengambil gravitasi global dari Project Settings
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Playback untuk mengatur transisi animasi di AnimationTree
var anim_playback: AnimationNodeStateMachinePlayback

# Definisi State (Status) Player
enum State { MOVE, ATTACK, SKILL, HURT, DEAD }
var state = State.MOVE  # Status awal adalah bergerak

# Variabel logika
var is_crouching: bool = false
var combo_counter: int = 0

# ============================================================================
# FUNGSI UTAMA GODOT (BUILT-IN)
# ============================================================================

func _ready() -> void:
	# Inisialisasi awal
	animation_tree.active = true
	anim_playback = animation_tree.get("parameters/playback")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Sembunyikan kursor mouse

	# Menghubungkan Sinyal (Signals) ke Fungsi
	combo_timer.timeout.connect(_reset_combo)
	animation_player.animation_finished.connect(_on_animation_finished)
	health_component.died.connect(_on_death)
	health_component.took_damage.connect(_on_took_damage)
	hurt_timer.timeout.connect(_on_hurt_timer_timeout)

	# Update UI Health Bar saat mulai
	health_component.health_changed.connect(
		func(health):
			if is_in_group("player"): GameManager.update_player_health(health)
	)
	if is_in_group("player"):
		GameManager.update_player_health(health_component.current_health)

	disable_sword_hitbox() # Pastikan hitbox mati di awal

func _unhandled_input(event: InputEvent) -> void:
	# 1. Kontrol Rotasi Kamera (Mouse)
	if event is InputEventMouseMotion:
		spring_arm.rotation.y -= event.relative.x * mouse_sensitivity
		spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
		# Batasi rotasi atas-bawah (clamp)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(camera_min_pitch), deg_to_rad(camera_max_pitch))

	# 2. Menampilkan Mouse (Tombol ESC)
	if Input.is_action_just_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	# 3. Input Serangan (Bisa dilakukan saat Move atau Attack untuk kombo)
	if state in [State.MOVE, State.ATTACK]:
		if Input.is_action_just_pressed("attack"):
			_handle_attack_input()

	# 4. Input Gerakan & Skill (Hanya bisa saat state MOVE)
	if state == State.MOVE:
		# Jongkok
		if Input.is_action_just_pressed("crouch") and is_on_floor():
			is_crouching = not is_crouching
			_update_collision_shape()
		
		# Lompat
		if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
			velocity.y = jump_impulse
			
		# Skill (E dan Q)
		if Input.is_action_just_pressed("skill_light"):
			_use_skill(light_skill_knockback, light_skill_damage)
		if Input.is_action_just_pressed("skill_heavy"):
			_use_skill(heavy_skill_knockback, heavy_skill_damage)

func _physics_process(delta: float) -> void:
	# Terapkan Gravitasi
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# State Machine: Menentukan perilaku berdasarkan status saat ini
	match state:
		State.MOVE:
			_handle_locomotion_movement(delta) # Bisa jalan
		State.SKILL:
			_stop_movement(delta)              # Berhenti saat cast skill
		State.ATTACK:
			_stop_movement(delta)              # Berhenti saat menyerang
		State.HURT:
			if can_be_stunned:
				_stop_movement(delta)          # Stun (berhenti)
			else:
				_handle_locomotion_movement(delta) # Jika tidak stun, bisa gerak
		State.DEAD:
			velocity = Vector3.ZERO            # Mati total
	
	_update_animations() # Sinkronisasi animasi
	move_and_slide()     # Fungsi bawaan Godot untuk menggerakkan CharacterBody3D

# ============================================================================
# LOGIKA PERGERAKAN
# ============================================================================

func _handle_locomotion_movement(delta: float):
	# Ambil input WASD
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# Ubah input menjadi arah relatif terhadap kamera (SpringArm)
	var direction = (spring_arm.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Tentukan kecepatan (Jongkok / Lari / Jalan)
	var current_speed = crouch_speed if is_crouching else (run_speed if Input.is_action_pressed("run") else move_speed)

	if direction:
		# Gerakkan karakter
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 10.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 10.0)
		
		# Putar model karakter menghadap arah jalan
		var target_yaw = atan2(direction.x, direction.z)
		skin.rotation.y = lerp_angle(skin.rotation.y, target_yaw, rotation_speed * delta)
	else:
		# Jika tidak ada input, perlambat sampai berhenti (friksi)
		_stop_movement(delta)

# Fungsi helper untuk menghentikan gerakan secara halus (Lerp)
func _stop_movement(delta: float):
	velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
	velocity.z = lerp(velocity.z, 0.0, delta * 10.0)

# ============================================================================
# LOGIKA ANIMASI
# ============================================================================

func _update_animations() -> void:
	# Hanya update animasi gerakan jika sedang di state MOVE
	if state != State.MOVE: return

	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z).length()
	# Remap kecepatan menjadi nilai blend (0=Idle, 1=Walk, 2=Run)
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
	
	# Pindah ke node animasi yang sesuai
	if anim_playback.get_current_node() != target_anim_state:
		anim_playback.travel(target_anim_state)

# ============================================================================
# LOGIKA SERANGAN & SKILL
# ============================================================================

func _handle_attack_input() -> void:
	# Cek syarat serangan (harus di tanah & tidak jongkok)
	if not is_on_floor() or is_crouching: return

	# Logika Kombo: Bisa serang jika MOVE atau (sedang ATTACK tapi timer kombo masih aktif)
	if state == State.MOVE or (state == State.ATTACK and not combo_timer.is_stopped()):
		if combo_counter >= 3: return # Maksimal 3 kombo
		
		state = State.ATTACK
		combo_counter += 1
		
		# Cari target terbaik untuk Auto-Aim
		var target = _find_best_attack_target()
		
		if is_instance_valid(target):
			# Hitung jarak dan arah ke target
			var distance_to_target = global_position.distance_to(target.global_position)
			
			if distance_to_target <= lunge_max_distance:
				var direction = global_position.direction_to(target.global_position)
				# Tentukan titik berhenti di depan musuh
				var destination = target.global_position - direction * lunge_stop_distance
				destination.y = global_position.y
				
				# Putar karakter ke arah musuh
				var target_yaw = atan2(direction.x, direction.z)
				
				# Gunakan Tween untuk animasi gerakan & putaran yang halus (Lunge)
				var tween = create_tween().set_parallel(true)
				tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				
				tween.tween_property(skin, "rotation:y", target_yaw, lunge_snap_rotation_duration)
				
				# Hanya maju jika jaraknya cukup jauh
				if distance_to_target > lunge_stop_distance:
					tween.tween_property(self, "global_position", destination, lunge_duration)
		
		# Set kecepatan dan mainkan animasi
		animation_tree.set("parameters/TimeScale/scale", attack_animation_speed)
		anim_playback.travel("Attack" + str(combo_counter))
		combo_timer.start() # Mulai timer jendela kombo

func _use_skill(knockback_force: float, damage_amount: int):
	state = State.SKILL
	
	# 1. Trigger Efek Cooldown di UI (Mengirim sinyal ke GameManager)
	if damage_amount == light_skill_damage: 
		GameManager.trigger_cooldown("E", 0.5) 
	elif damage_amount == heavy_skill_damage:
		GameManager.trigger_cooldown("Q", 1.0)
	
	# 2. Spawn Efek Skill (Balok/Angin)
	var effect = SkillEffectScene.instantiate()
	var spawn_transform = skin.global_transform
	# Munculkan sedikit di depan karakter (+Z lokal)
	spawn_transform.origin += spawn_transform.basis.z * 1.0
	
	get_tree().root.add_child(effect)
	
	# 3. Inisialisasi data efek
	effect.start(spawn_transform, knockback_force, damage_amount)
	
	# 4. Timer manual untuk kembali ke state MOVE (Failsafe)
	await get_tree().create_timer(0.4).timeout
	if state == State.SKILL:
		state = State.MOVE

# Fungsi Logika Auto-Aim: Mencari musuh terbaik berdasarkan sudut pandang & jarak
func _find_best_attack_target() -> Node3D:
	var enemies_in_range = targeting_area.get_overlapping_bodies()
	if enemies_in_range.is_empty():
		return null

	var best_target: Node3D = null
	var best_score = -INF

	# Tentukan arah prioritas (berdasarkan input player atau arah kamera)
	var input_direction = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var priority_direction: Vector3
	if input_direction.length() > 0.1:
		priority_direction = (spring_arm.transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	else:
		priority_direction = -spring_arm.global_transform.basis.z.normalized()
	
	# Loop semua musuh dan beri nilai (score)
	for enemy in enemies_in_range:
		if not enemy.is_in_group("enemy"): continue

		var direction_to_enemy = global_position.direction_to(enemy.global_position)
		var distance = global_position.distance_to(enemy.global_position)

		if distance > lunge_max_distance: continue
			
		# Skor sudut (dot product) + Skor jarak (semakin dekat semakin besar)
		var angle_score = priority_direction.dot(direction_to_enemy)
		var distance_score = 1.0 - (distance / lunge_max_distance)
		
		var total_score = (angle_score * 1.5) + distance_score
		
		if total_score > best_score:
			best_score = total_score
			best_target = enemy
			
	return best_target

# ============================================================================
# EVENT HANDLERS (CALLBACKS)
# ============================================================================

# Reset kombo jika timer habis (pemain telat menekan tombol)
func _reset_combo() -> void:
	combo_counter = 0
	animation_tree.set("parameters/TimeScale/scale", 1.0)
	if state == State.ATTACK:
		state = State.MOVE

# Dipanggil saat terkena damage (dari HealthComponent)
func _on_took_damage(damage_amount):
	if state in [State.DEAD, State.HURT]: return
	
	state = State.HURT
	combo_counter = 0
	combo_timer.stop()
	disable_sword_hitbox()
	
	animation_tree.set("parameters/TimeScale/scale", 1.0)
	anim_playback.travel("Hurt")
	hurt_timer.start(hurt_duration) # Mulai timer stun
	
	# Spawn angka damage melayang
	var damage_number = DamageNumberScene.instantiate()
	get_tree().root.add_child(damage_number)
	damage_number.show_damage(damage_amount, global_position + Vector3.UP * 1.8)

# Saat timer hurt selesai, player bisa gerak lagi
func _on_hurt_timer_timeout():
	if state == State.HURT:
		state = State.MOVE

# Saat darah habis
func _on_death():
	state = State.DEAD
	disable_sword_hitbox()
	anim_playback.travel("Die")
	GameManager.trigger_game_over() # Panggil layar Game Over

# Dipanggil setiap kali animasi selesai dimainkan
func _on_animation_finished(anim_name: StringName):
	var anim_str = str(anim_name)
	
	# Jika animasi skill selesai (jika ada animasinya)
	if anim_str.begins_with("Skill") and state == State.SKILL:
		state = State.MOVE
	
	# Jika animasi attack selesai
	if anim_str.begins_with("Attack"):
		disable_sword_hitbox()
		if combo_timer.is_stopped(): # Jika player tidak lanjut kombo
			_reset_combo()
	
	elif anim_str == "Die":
		set_physics_process(false) # Hentikan proses fisika

# ============================================================================
# FUNGSI HELPER (BANTUAN)
# ============================================================================

func enable_sword_hitbox(): sword_hitbox_shape.disabled = false
func disable_sword_hitbox(): sword_hitbox_shape.set_deferred("disabled", true)

# Mengatur tinggi CollisionShape saat jongkok/berdiri
func _update_collision_shape() -> void:
	var shape = collision_shape.shape as CapsuleShape3D
	if not shape: return
	var target_height = stand_height if not is_crouching else crouch_height
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(shape, "height", target_height, 0.3)
	tween.tween_property(collision_shape, "position:y", target_height / 2.0, 0.3)

# Fungsi matematika untuk mengubah rentang nilai (Map Range)
func remap(value: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	var denom = in_max - in_min
	if abs(denom) < 0.0001: return out_min
	return out_min + (value - in_min) * (out_max - out_min) / denom
