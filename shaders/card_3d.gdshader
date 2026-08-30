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
// 对局状态:ready=充能完毕闪箔流光;disabled=审判禁用红色;passive=被动卡另一种
uniform float ready : hint_range(0.0, 1.0) = 0.0;
uniform float disabled : hint_range(0.0, 1.0) = 0.0;
uniform float passive : hint_range(0.0, 1.0) = 0.0;
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

	// 选中/充能完毕:虹彩闪箔(参考 balatro POLYCHROME)+ 亮金发光边框(非常醒目)
	float hl = max(selected, ready);
	if (hl > 0.01) {
		float edge = min(min(v_uv.x, 1.0 - v_uv.x), min(v_uv.y, 1.0 - v_uv.y));
		float tsp = (v_uv.x + v_uv.y) * 3.0 + time * 1.2;
		vec3 holo = 0.5 + 0.5 * cos(6.2831 * (tsp + vec3(0.0, 0.33, 0.67)));
		float pulse = 0.8 + 0.2 * sin(time * 7.0);
		// 整卡叠一层虹彩
		col.rgb = mix(col.rgb, col.rgb * (0.72 + holo * 0.55), 0.4 * hl);
		// 斜向扫过的虹彩流光带(加粗:频率降为约 1/3,平滑区间放宽)
		float band = sin((v_uv.x + v_uv.y) * 2.5 - time * 2.5);
		float sheen = smoothstep(-0.4, 1.0, band);
		col.rgb += holo * sheen * 0.6 * hl;
		// 亮金边框(替换卡面边缘)
		vec3 gold = vec3(1.0, 0.9, 0.45);
		float frame = smoothstep(0.20, 0.025, edge);
		col.rgb = mix(col.rgb, gold * (1.05 + 0.35 * pulse), frame * clamp(hl * 0.95, 0.0, 1.0));
		// 边框外侧柔光
		float bloom = smoothstep(0.30, 0.0, edge) - smoothstep(0.12, 0.0, edge);
		col.rgb += gold * bloom * pulse * hl * 0.9;
		col.rgb = mix(col.rgb, col.rgb * 1.18, hl);
	}

	// 被动卡(未禁用):柔和青色冷光,呼吸微亮,区别于选中金/禁用红
	if (passive > 0.01) {
		float br = 0.5 + 0.5 * sin(time * 2.0);
		col.rgb = mix(col.rgb, col.rgb * vec3(0.82, 1.0, 0.95), 0.35);
		col.rgb += vec3(0.2, 0.62, 0.75) * br * 0.18;
		float edge2 = min(min(v_uv.x, 1.0 - v_uv.x), min(v_uv.y, 1.0 - v_uv.y));
		col.rgb += vec3(0.3, 0.8, 1.0) * smoothstep(0.14, 0.03, edge2) * 0.15;
	}

	// 审判禁用:红色暗调 + 半透明,呈"禁止使用"状态
	if (disabled > 0.01) {
		col.rgb = mix(col.rgb, vec3(0.9, 0.12, 0.12), 0.55);
		col.a *= 0.72;
	}
	COLOR = col;
}
