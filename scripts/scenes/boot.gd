extends Control
## Boot — the D'YOUNGS GAMES studio presentation, then the title card.
##
## This is the first thing a player ever sees, so it is treated as a piece of
## direction rather than a loading screen: the visuals are locked to the
## forged studio sting (assets/audio/music/studio_sting.ogg, 3.9 s) so the
## logo *lands* on the strike instead of drifting in on a generic fade.
##
## Sting timeline -> visual beat:
##   0.00-0.95  the breath  : air swell + 62->31 Hz sub drop. The room comes
##                            up out of black — amber bloom builds, the logo
##                            ghosts in and slowly pushes from 1.07 to 1.00.
##   0.95       the STRIKE  : kick + F-minor hit + bright transient. Logo
##                            locks to full alpha with a scale overshoot and a
##                            warm flash frame decays off it.
##   1.15-1.72  the bells   : F4/A4/C5 (minor -> major lift). The studio name
##                            resolves upward, one beat per bell.
##   1.78       the shimmer : octave bell. "presents" fades in beneath.
##   3.20-4.25  the tail    : the whole card releases into the title.
##
## Any key, click or tap skips straight to the title — a studio card must
## never hold a returning player hostage.
##
## The viewport/Godot-version readout that used to be printed in the corner of
## this screen is dev-only now, behind F3. It shipped on the logo once; it
## never should have.

const STRIKE := 0.95      # logo locks, flash fires
const NAME_IN := 1.15     # first bell — studio name resolves
const TAG_IN := 1.78      # shimmer bell — "presents"
const FADE_OUT := 3.20    # card begins its release
const HANDOFF := 4.25     # hand over to the title

const AMBER := Color(0.95, 0.72, 0.25)
const FLASH_COL := Color(1.0, 0.93, 0.80)

var _t := 0.0
var _skipping := false
var _logo: TextureRect
var _name: Label
var _tag: Label
var _glow: TextureRect
var _flash: ColorRect
var _rule: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)  # root must fill the window (XOGOT/device fix)

	var bg := ColorRect.new()
	bg.color = Color(0.020, 0.018, 0.024)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# amber bloom behind the logo: radial gradient, no shader needed
	_glow = TextureRect.new()
	_glow.texture = _radial(AMBER, 0.42)
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.modulate.a = 0.0
	add_child(_glow)

	_logo = TextureRect.new()
	_logo.texture = load("res://assets/textures/ui/splash_dyoungs.png")
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.set_meta("fit_half", float(220))
	_logo.offset_top = -150
	_logo.offset_bottom = 110
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.pivot_offset = Vector2(220, 130)   # scale about the logo's centre
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(1.07, 1.07)
	add_child(_logo)

	# a hairline rule under the logo — gives the card a spine
	_rule = ColorRect.new()
	_rule.color = Color(AMBER.r, AMBER.g, AMBER.b, 0.55)
	_rule.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_rule.set_meta("fit_half", float(150))
	_rule.offset_top = -152
	_rule.offset_bottom = -150
	_rule.modulate.a = 0.0
	add_child(_rule)

	_name = Label.new()
	_name.text = "D'YOUNGS GAMES"
	_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name.set_meta("fit_half", float(300))
	_name.offset_top = -140
	_name.offset_bottom = -100
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 30)
	_name.add_theme_color_override("font_color", AMBER)
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_name.modulate.a = 0.0
	add_child(_name)

	_tag = Label.new()
	_tag.text = "presents"
	_tag.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tag.set_meta("fit_half", float(300))
	_tag.offset_top = -104
	_tag.offset_bottom = -76
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(0.62, 0.60, 0.54))
	_tag.modulate.a = 0.0
	add_child(_tag)

	# edge vignette last so it sits over everything and holds the eye centre
	var vig := TextureRect.new()
	vig.texture = _radial(Color(0, 0, 0), 0.85, true)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

	# strike flash — over the vignette so the hit reads full-frame
	_flash = ColorRect.new()
	_flash.color = FLASH_COL
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	# The title screen starts its own bed (title.gd -> music_menu), so the
	# studio card plays the sting and nothing else: no menu music under it.
	AudioDirector.sting("studio_sting")

	_refit()
	UiFit.watch(self, _refit)


## Radial gradient texture: bright centre fading out (or, with `invert`,
## transparent centre fading to solid at the edges — a vignette).
func _radial(col: Color, strength: float, invert: bool = false) -> GradientTexture2D:
	var g := Gradient.new()
	var inner := Color(col.r, col.g, col.b, 0.0) if invert else Color(col.r, col.g, col.b, strength)
	var outer := Color(col.r, col.g, col.b, strength) if invert else Color(col.r, col.g, col.b, 0.0)
	g.set_color(0, inner)
	g.set_color(1, outer)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.02)
	gt.width = 256
	gt.height = 256
	return gt


func _unhandled_input(ev: InputEvent) -> void:
	# F3 keeps the dev readout available without shipping it on the logo
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F3:
		_toggle_dbg()
		return
	if _skipping:
		return
	if ev is InputEventKey or ev is InputEventMouseButton or ev is InputEventScreenTouch \
			or ev is InputEventJoypadButton:
		_skipping = true


func _process(delta: float) -> void:
	_t += delta
	# a skip runs the card at 6x so the handoff feels like a cut, not a hang
	var tt := _t
	if _skipping:
		tt = maxf(_t, FADE_OUT + 0.35)

	# --- the breath: bloom and logo rise out of black --------------------
	var breathe := clampf(tt / STRIKE, 0.0, 1.0)
	var ease_in := breathe * breathe * (3.0 - 2.0 * breathe)   # smoothstep
	_glow.modulate.a = 0.55 * ease_in
	_logo.modulate.a = clampf((tt - 0.10) / 0.75, 0.0, 1.0) * (0.35 + 0.65 * ease_in)

	# slow push 1.07 -> 1.00, then overshoot on the strike and settle
	if tt < STRIKE:
		var s := lerpf(1.07, 1.00, ease_in)
		_logo.scale = Vector2(s, s)
	else:
		var k := clampf((tt - STRIKE) / 0.34, 0.0, 1.0)
		var over := 1.0 + 0.055 * sin(k * PI)      # overshoot then settle
		_logo.scale = Vector2(over, over)
		_glow.modulate.a = 0.55 + 0.45 * (1.0 - k)  # bloom flares on the hit

	# --- the strike flash ------------------------------------------------
	if tt >= STRIKE:
		var f := clampf(1.0 - (tt - STRIKE) / 0.42, 0.0, 1.0)
		_flash.modulate.a = 0.50 * f * f

	# --- the bells: name resolves, then the tag --------------------------
	_name.modulate.a = clampf((tt - NAME_IN) / 0.55, 0.0, 1.0)
	_name.offset_top = -140.0 - 6.0 * (1.0 - clampf((tt - NAME_IN) / 0.55, 0.0, 1.0))
	_rule.modulate.a = clampf((tt - NAME_IN) / 0.70, 0.0, 1.0)
	_tag.modulate.a = clampf((tt - TAG_IN) / 0.60, 0.0, 1.0)

	# --- the release -----------------------------------------------------
	if tt > FADE_OUT:
		modulate.a = 1.0 - clampf((tt - FADE_OUT) / (HANDOFF - FADE_OUT), 0.0, 1.0)
	if tt > HANDOFF:
		set_process(false)
		get_tree().change_scene_to_file("res://scenes/menu/title.tscn")


func _refit() -> void:
	UiFit.refit_tree(self)
	if _logo != null:
		_logo.pivot_offset = Vector2(_logo.size.x * 0.5, _logo.size.y * 0.5)
	_dbg_text()


var _dbg: Label = null


## Dev-only overlay, toggled with F3. Never visible unless asked for.
func _toggle_dbg() -> void:
	if _dbg == null:
		_dbg = Label.new()
		_dbg.name = "DbgInfo"
		_dbg.position = Vector2(6, 6)
		_dbg.add_theme_font_size_override("font_size", 9)
		_dbg.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55, 0.9))
		add_child(_dbg)
		_dbg_text()
	else:
		_dbg.queue_free()
		_dbg = null


func _dbg_text() -> void:
	if _dbg == null:
		return
	var vp := get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size if vp else Vector2.ZERO
	_dbg.text = "vp %dx%d | root %dx%d | %s | Godot %s | %s" % [
		int(vs.x), int(vs.y), int(size.x), int(size.y), OS.get_name(),
		str(Engine.get_version_info().get("string", "?")), DisplayServer.get_name()]
