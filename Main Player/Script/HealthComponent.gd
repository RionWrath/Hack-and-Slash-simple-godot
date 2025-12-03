# HealthComponent.gd
extends Node

# Sinyal yang akan dipancarkan saat health berubah atau habis
signal health_changed(current_health)
signal took_damage(damage_amount)
signal died

# Variabel health
@export var max_health: float = 100.0
var current_health: float

func _ready():
	current_health = max_health

# Fungsi untuk mengurangi health
func take_damage(damage_amount: float):
	if current_health <= 0:
		return # Jangan lakukan apa-apa jika sudah mati

	current_health -= damage_amount
	emit_signal("took_damage", damage_amount)
	emit_signal("health_changed", current_health)
	
	print(get_parent().name + " took " + str(damage_amount) + " damage. Health is now: " + str(current_health))

	if current_health <= 0:
		emit_signal("died")
