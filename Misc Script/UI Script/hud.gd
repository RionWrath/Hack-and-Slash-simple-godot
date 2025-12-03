# HUD.gd
extends CanvasLayer

# --- Referensi HUD In-Game ---
@onready var health_bar = $Control/MarginContainer/VBoxContainer/HealthBar
@onready var icon_e = $Control/MarginContainer/VBoxContainer/SkillContainer/SkillSlot_E/Icon
@onready var icon_q = $Control/MarginContainer/VBoxContainer/SkillContainer/SkillSlot_Q/Icon

# --- Referensi Menu Baru ---
@onready var pause_menu = $Control/PauseMenu
@onready var game_over_screen = $Control/GameOverScreen

# --- Referensi Tombol ---
@onready var resume_btn = $Control/PauseMenu/VBoxContainer/ResumeButton
@onready var quit_btn = $Control/PauseMenu/VBoxContainer/QuitButton
@onready var restart_btn = $Control/GameOverScreen/VBoxContainer/RestartButton

var is_game_over: bool = false

func _ready():
	if GameManager:
		GameManager.set_hud(self)
	
	# Sembunyikan menu saat mulai
	pause_menu.visible = false
	game_over_screen.visible = false
	
	# Hubungkan sinyal tombol (Signal) lewat kode agar rapi
	resume_btn.pressed.connect(_on_resume_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	restart_btn.pressed.connect(_on_restart_pressed)

func _unhandled_input(event):
	# Jika tombol ESC ditekan dan belum Game Over
	if event.is_action_pressed("ui_cancel") and not is_game_over:
		_toggle_pause()

# --- Fungsi Pause ---
func _toggle_pause():
	var tree = get_tree()
	tree.paused = not tree.paused # Balikkan status pause (True/False)
	
	if tree.paused:
		pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Munculkan mouse
	else:
		pause_menu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Sembunyikan mouse

func _on_resume_pressed():
	_toggle_pause() # Panggil fungsi yang sama untuk unpause

func _on_quit_pressed():
	get_tree().quit() # Keluar game

# --- Fungsi Game Over ---
func show_game_over():
	if is_game_over: return
	is_game_over = true
	
	# Pause game agar musuh tidak terus menyerang mayat player
	get_tree().paused = true 
	
	game_over_screen.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Munculkan mouse

func _on_restart_pressed():
	# PENTING: Unpause dulu sebelum reload, kalau tidak scene baru akan tetap ter-pause
	get_tree().paused = false 
	is_game_over = false
	
	# Reload scene saat ini
	get_tree().reload_current_scene()

# --- Fungsi Lama (Tetap Ada) ---
func update_health(current: int, max_hp: int):
	health_bar.max_value = max_hp
	health_bar.value = current

func play_cooldown(skill_key: String, duration: float):
	var target_icon = null
	if skill_key == "E": target_icon = icon_e
	elif skill_key == "Q": target_icon = icon_q
	
	if target_icon:
		target_icon.modulate = Color(0.3, 0.3, 0.3, 1.0)
		var tween = create_tween()
		tween.tween_property(target_icon, "modulate", Color(1, 1, 1, 1), duration)
