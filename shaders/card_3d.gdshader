shader_type canvas_item;

// 卡牌假 3D 偏转:基于旋转矩阵 + 透视除法,模拟卡牌朝鼠标方向 3D 偏转
// 参考 MrEliptik/godot_ui_components 的 fake_3D.gdshader 移植(Unity CardView 同思路)
// x_rot / y_rot 单位为角度,由脚本根据鼠标相对卡牌中心的偏移驱动
uniform vec2 rect_size = vec2(100.0, 155.0);

// 相机 FOV(90 较自然)
uniform float fov : hint_range(1, 179) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-360.0, 360.0) = 0.0;
uniform float x_rot : hint_range(-360.0, 360.0) = 0.0;
// 0:未旋转时保持原尺寸;1:缩小以便整圈旋转不裁剪
uniform float inset : hint_range(0, 1) = 0.0;

// 选中确认感:金色脉动描边 + 增亮
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

varying flat vec2 o;
varying vec3 p;
varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	float sin_b = sin(y_rot / 180.0 * PI);
	float cos_b = cos(y_rot / 180.0 * PI);
	float sin_c = sin(x_rot / 180.0 * PI);
	float cos_c = cos(x_rot / 180.0 * PI);

	mat3 inv_rot_mat;
	inv_rot_mat[0][0] = cos_b;
	inv_rot_mat[0][1] = 0.0;
	inv_rot_mat[0][2] = -sin_b;
	inv_rot_mat[1][0] = sin_b * sin_c;
	inv_rot_mat[1][1] = cos_c;
	inv_rot_mat[1][2] = cos_b * sin_c;
	inv_rot_mat[2][0] = sin_b * cos_c;
	inv_rot_mat[2][1] = -sin_c;
	inv_rot_mat[2][2] = cos_b * cos_c;

	float t = tan(fov / 360.0 * PI);
	p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
	float v = (0.5 / t) + 0.5;
	p.xy *= v * inv_rot_mat[2].z;
	o = v * inv_rot_mat[2].xy;

	VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
}

void fragment() {
	if (cull_back && p.z <= 0.0) discard;
	vec2 uv = (p.xy / p.z).xy - o;
	vec4 col = texture(TEXTURE, uv + 0.5);
	col.a *= step(max(abs(uv.x), abs(uv.y)), 0.5);

	// 选中确认感:金色脉动描边 + 亮度提升
	if (selected > 0.01) {
		float edge = min(min(v_uv.x, 1.0 - v_uv.x), min(v_uv.y, 1.0 - v_uv.y));
		float band = smoothstep(0.09, 0.012, edge);
		float pulse = 0.5 + 0.5 * sin(time * 8.0);
		col.rgb = mix(col.rgb, col.rgb * 1.12, selected);
		col.rgb += vec3(1.0, 0.85, 0.35) * band * pulse * selected * 0.9;
	}
	COLOR = col;
}
