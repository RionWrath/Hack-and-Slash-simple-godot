# HUD.gd
extends CanvasLayer

# --- Referensi Node sesuai struktur Anda ---
@onready var health_bar = $Control/MarginContainer/VBoxContainer/HealthBar

# Ambil referensi ICON (ColorRect), bukan panelnya, karena warna ada di icon
@onready var icon_e = $Control/MarginContainer/VBoxContainer/SkillContainer/SkillSlot_E/Icon
@onready var icon_q = $Control/MarginContainer/VBoxContainer/SkillContainer/SkillSlot_Q/Icon

func _ready():
	# Daftarkan diri ke GameManager
	if GameManager:
		GameManager.set_hud(self)

# Fungsi Update Darah
func update_health(current: int, max_hp: int):
	health_bar.max_value = max_hp
	health_bar.value = current

# Fungsi Animasi Cooldown
func play_cooldown(skill_key: String, duration: float):
	var target_icon = null
	
	# Pilih icon mana yang akan digelapkan
	if skill_key == "E":
		target_icon = icon_e
	elif skill_key == "Q":
		target_icon = icon_q
	
	if target_icon:
		# 1. Ubah warna jadi gelap (Abu-abu transparan)
		target_icon.modulate = Color(0.3, 0.3, 0.3, 1.0)
		
		# 2. Buat Tween (Animasi)
		var tween = create_tween()
		
		# 3. Animasi warna kembali ke Putih (Normal) selama 'duration' detik
		tween.tween_property(target_icon, "modulate", Color(1, 1, 1, 1), duration)
