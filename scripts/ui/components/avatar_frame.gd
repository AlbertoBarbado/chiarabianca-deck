class_name AvatarFrame
extends Control
## Round character avatar: the face crop masked to a circle inside the ornate round frame.
## The specialization accent can tint a soft ring behind it.

const FRAME := "panels/frame_circle"
const FACE_SHARE := 0.64


func setup(character_id: String, avatar_size: float, accent: Color = Color.TRANSPARENT) -> void:
	UIFactory.clear_children(self)
	custom_minimum_size = Vector2(avatar_size, avatar_size)
	# Never stretched by a container (a taller row would turn the round frame into an oval with the
	# face stuck at the top): the avatar keeps its square size, centred in the space it gets.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if accent.a > 0.0:
		var glow := UIFactory.panel(UITheme.box(Color(accent, 0.22), Color(accent, 0.0), int(avatar_size / 2.0), 0, 0))
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIFactory.full_rect(glow)
		add_child(glow)
	var frame_texture := UIAssets.texture(FRAME)
	if frame_texture != null:
		var frame := TextureRect.new()
		frame.texture = frame_texture
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIFactory.full_rect(frame)
		add_child(frame)
	var face := TextureRect.new()
	face.texture = AssetCatalog.portrait_face_round(character_id)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := avatar_size * (1.0 - FACE_SHARE) / 2.0
	face.position = Vector2(inset, inset)
	face.size = Vector2.ONE * avatar_size * FACE_SHARE
	add_child(face)
