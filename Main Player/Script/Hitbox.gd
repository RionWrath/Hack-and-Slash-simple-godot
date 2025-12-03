extends Area3D

@export var damage: float = 10.0 # Damage yang diberikan

func _on_area_entered(area):
	# "area" adalah hurtbox yang terkena
	if area.get_parent().has_node("HealthComponent"):
		var health_component = area.get_parent().get_node("HealthComponent")
		health_component.take_damage(damage)
