class_name UIButton
extends Button
## The game's button: a real Godot Button (theme supplies the ornate frame and the normal /
## hover / pressed / disabled looks) with a small scale transition on hover and press.
## Variations: "PrimaryButton" (ornate frame) and "SecondaryButton" / default (plain frame).

const HOVER_SCALE := 1.035
const PRESSED_SCALE := 0.97
const TRANSITION_TIME := 0.12

var _tween: Tween


func _ready() -> void:
	resized.connect(_update_pivot)
	_update_pivot()
	mouse_entered.connect(_animate.bind(HOVER_SCALE))
	mouse_exited.connect(_animate.bind(1.0))
	button_down.connect(_animate.bind(PRESSED_SCALE))
	button_up.connect(func() -> void: _animate(HOVER_SCALE if is_hovered() else 1.0))


func _update_pivot() -> void:
	pivot_offset = size / 2.0


func _animate(target: float) -> void:
	if disabled:
		target = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(target, target), TRANSITION_TIME).set_trans(Tween.TRANS_SINE)
