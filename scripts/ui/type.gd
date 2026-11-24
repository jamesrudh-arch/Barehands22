extends Node
## Type — LEVERAGE's typography.
##
## The game shipped four DejaVu faces in assets/fonts/, credited them by name on
## the menu's about card, and then never loaded a single one of them. There was
## no theme resource anywhere in the project, not one add_theme_font_override()
## call in 42 scripts, and project.godot set only gui/theme/custom_font_size.
## So every label in the game — the title card, the HUD, the phone, dialogue
## speaker names, the cutscene slates — rendered in Godot's built-in fallback
## face while 2.1 MB of imported font data sat in the package doing nothing at
## all. A noir game about paperwork and reputation, running in the engine's
## default sans.
##
## This is the fix and the system in one place. Three roles, one face each:
##
##   display  DejaVu Serif. Titles, slates, speaker names, place names, section
##            headers. A high-contrast serif reads as case file and as
##            newspaper, which is the register the whole game is written in, and
##            it is the face the amber Color(0.95, 0.72, 0.25) has been doing
##            by colour alone until now.
##   body     DejaVu Sans. Everything you read in a hurry: objectives, barks,
##            dialogue, buttons, help text, prompts.
##   mono     DejaVu Sans Mono. Anything that is a NUMBER: credits, wanted
##            level, the clock, ammo, road speed, fuel, XP, prices, phone
##            readouts. Proportional figures make a money counter crawl
##            sideways as it counts; tabular ones hold still.
##
## Roles are asked for by NAME and never by path, so re-cutting the identity
## later is an edit to FACES below and nothing anywhere else. The faces are the
## same DejaVu release already in assets/fonts/ under the same Bitstream Vera /
## Arev licence already shipped in DejaVu-LICENSE.txt.

const DIR := "res://assets/fonts/"
const FACES := {
	"display": "DejaVuSerif.ttf",
	"display_bold": "DejaVuSerif-Bold.ttf",
	"body": "DejaVuSans.ttf",
	"body_bold": "DejaVuSans-Bold.ttf",
	"mono": "DejaVuSansMono.ttf",
	"mono_bold": "DejaVuSansMono-Bold.ttf",
}
## The amber the display role has always been signalled with.
const AMBER := Color(0.95, 0.72, 0.25)

var _cache: Dictionary = {}
var installed_theme: Theme = null


func _ready() -> void:
	install()


func face(role: String) -> Font:
	## The FontFile for a role, loaded once. An unknown role falls back to body
	## rather than to null, because a null font override is indistinguishable
	## from no override at all and would quietly drop that label back onto the
	## engine face — the exact bug this file exists to end.
	if _cache.has(role):
		return _cache[role]
	var file: String = FACES.get(role, FACES["body"])
	var path := DIR + file
	var f: Font = load(path)
	if f == null:
		push_warning("Type: could not load %s for role '%s'" % [path, role])
	_cache[role] = f
	return f


func bold_of(role: String) -> String:
	if role.ends_with("_bold"):
		return role
	if FACES.has(role + "_bold"):
		return role + "_bold"
	return role


func apply(c: Control, role: String) -> Control:
	## Put a role's face on a Control and hand it back, so the call can sit in
	## the same expression that builds the label.
	if c == null:
		return c
	var f := face(role)
	if f == null:
		return c
	if c is RichTextLabel:
		# RichTextLabel ignores "font" entirely: it has one override per weight,
		# and setting only normal_font leaves every bold span on the fallback.
		var r: RichTextLabel = c
		r.add_theme_font_override("normal_font", f)
		r.add_theme_font_override("bold_font", face(bold_of(role)))
		r.add_theme_font_override("italics_font", f)
		r.add_theme_font_override("bold_italics_font", face(bold_of(role)))
	else:
		c.add_theme_font_override("font", f)
	return c


func theme(base_size: int = 18) -> Theme:
	## A Theme whose DEFAULT face is the body role, so a Control nobody thought
	## about still does not fall back to the engine's.
	var t := Theme.new()
	t.default_font = face("body")
	t.default_font_size = base_size
	installed_theme = t
	return t


func install() -> void:
	## Set the project-wide theme on the root Window. Window.theme is inherited
	## by every Control in every scene loaded after this, which is how one
	## autoload reaches 42 scripts' worth of hand-built UI without touching
	## most of them.
	if get_tree() == null or get_tree().root == null:
		return
	var size: int = int(ProjectSettings.get_setting("gui/theme/custom_font_size", 18))
	get_tree().root.theme = theme(size)


func roles_in_use() -> Array:
	## Which roles have actually been asked for. Used by the harness to prove
	## the shipped faces are not dead weight again.
	var out: Array = []
	for r in _cache:
		out.append(r)
	out.sort()
	return out
