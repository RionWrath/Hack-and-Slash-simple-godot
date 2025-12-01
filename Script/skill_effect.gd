# skill_effect.gd (Final)
extends Area3D

var knockback_force: float = 10.0
var damage: int = 0 # BARU: Variabel untuk menyimpan damage
var speed: float = 15.0
var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 1.0

var hit_enemies = []

func _ready():
	$LifetimeTimer.start(lifetime)
	$LifetimeTimer.timeout.connect(queue_free)
	body_entered.connect(_on_body_entered)

# DIUBAH: Fungsi start sekarang menerima _damage
func start(spawn_transform: Transform3D, _knockback_force: float, _damage: int):
	global_transform = spawn_transform
	knockback_force = _knockback_force
	damage = _damage # BARU: Simpan damage
	direction = global_transform.basis.z.normalized()

func _physics_process(delta: float):
	global_position += direction * speed * delta

func _on_body_entered(body):
	if body.is_in_group("enemy") and not body in hit_enemies and body.has_method("apply_knockback"):
		hit_enemies.append(body)
		
		# BARU: Terapkan damage ke health component musuh
		if body.has_node("HealthComponent"):
			body.get_node("HealthComponent").take_damage(damage)
		
		body.apply_knockback(direction, knockback_force)
