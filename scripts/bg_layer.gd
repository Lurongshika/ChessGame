# 简约白蓝背景层:全屏 ColorRect + shader,不拦截鼠标
# 直接使用视口尺寸(不依赖父容器尺寸,兼容根 Control 0×0 的场景)
extends ColorRect


func _ready() -> void:
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.03, 0.05, 0.08)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bg.gdshader")
	material = mat
