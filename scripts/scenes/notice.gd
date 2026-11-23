extends Control
## Content notice — shown once between title and menu (D'Youngs Games
## presentation requirement). Fiction disclaimer + content advisories.

const NOTICE := """This game contains content suitable for mature audiences.
It depicts and references: organized crime, kidnapping, debt coercion,
violence (fist fights, weapons, vehicular crashes), alcohol and nightlife
culture, police pursuits, strong language, injury and blood.

All characters, factions, places and events are fictional. Cinder City,
the Ashfall Syndicate, Halcyon Group, the Vane family and every person
in this story are inventions of D'Youngs Games. Any resemblance to real
people, living or dead, or to real cities and organizations, is coincidental.

No criminal activity is endorsed or encouraged. LEVERAGE is a drama about
what people owe each other — and what happens when the city keeps score.

Player safety: this game contains flashing lights during gunfire and
police scenes. Take breaks during long play sessions."""


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.045)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var adv := TextureRect.new()
	adv.texture = load("res://assets/textures/ui/advisory.png")
	adv.set_anchors_preset(Control.PRESET_CENTER_TOP)
	adv.offset_left = -60
	adv.offset_right = 60
	adv.offset_top = 40
	adv.offset_bottom = 160
	adv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	adv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(adv)
	var t := Label.new()
	t.text = "CONTENT NOTICE"
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.offset_left = -300
	t.offset_right = 300
	t.offset_top = 170
	t.offset_bottom = 200
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	add_child(t)
	var body := Label.new()
	body.text = NOTICE
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 240
	body.offset_right = -240
	body.offset_top = 215
	body.offset_bottom = -90
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", Color(0.82, 0.8, 0.75))
	add_child(body)
	var b := Button.new()
	b.text = "I UNDERSTAND — CONTINUE"
	b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b.offset_left = -220
	b.offset_right = 220
	b.offset_top = -74
	b.offset_bottom = -26
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func():
		AudioDirector.sfx("ui_confirm", 0.2)
		Game.goto_scene("res://scenes/menu/menu.tscn")
		Game.set_state(Game.State.MENU))
	add_child(b)
