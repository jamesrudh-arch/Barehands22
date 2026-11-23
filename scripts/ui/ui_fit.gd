class_name UiFit
extends RefCounted
## Width-responsive layout helpers.
##
## The code-built UI (menus, notice, title, dialogue, phone, shop, cutscene
## subtitles) uses fixed pixel offsets designed for a wide viewport. On
## XOGOT/iOS the window can be much narrower (portrait phone) and — on some
## hosts — unsized at _ready(). These helpers clamp center/inset offsets to
## the live viewport and re-apply on resize, so nothing ever collapses to
## zero width (the one-character-per-line failure mode).

const FALLBACK_W := 1280.0


static func vw(node: Node) -> float:
	var vp := node.get_viewport()
	if vp == null:
		return FALLBACK_W
	var s: Vector2 = vp.get_visible_rect().size
	return s.x if s.x > 1.0 else FALLBACK_W


## Clamp a center-anchored control to +/-half, or the viewport half minus a
## margin on narrow screens.
static func center(c: Control, half: float, margin: float = 10.0) -> void:
	var h := minf(half, maxf(24.0, vw(c) * 0.5 - margin))
	c.offset_left = -h
	c.offset_right = h


## Clamp a full-rect control's side padding so text columns keep width.
static func inset(c: Control, pad: float) -> void:
	var p := minf(pad, maxf(8.0, vw(c) * 0.06))
	c.offset_left = p
	c.offset_right = -p


## Re-run `fn` whenever the viewport changes size (rotation, host resize,
## or the host finishing its first layout pass).
static func watch(n: Node, fn: Callable) -> void:
	var vp := n.get_viewport()
	if vp != null and not vp.size_changed.is_connected(fn):
		vp.size_changed.connect(fn)


## Apply every "fit_half"/"fit_pad" meta in the subtree (depth-first).
static func refit_tree(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			if c.has_meta("fit_half"):
				center(c, float(c.get_meta("fit_half")))
			elif c.has_meta("fit_pad"):
				inset(c, float(c.get_meta("fit_pad")))
		refit_tree(c)
