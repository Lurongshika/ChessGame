// Balatro 风格背景:深色有机流动光晕(domain warp 域扭曲 + 多层噪声)
// 静谧高级,低对比,缓慢流动不干扰
shader_type canvas_item;

uniform float time_scale : hint_range(0.0, 3.0) = 0.9;
uniform float warp_strength : hint_range(0.0, 2.5) = 1.2;
uniform float grain_amount : hint_range(0.0, 0.1) = 0.022;

// 深墨蓝底 / 柔和蓝光 / 高光点缀(对比加大,光晕更明显)
uniform vec4 bg_color : source_color = vec4(0.012, 0.022, 0.04, 1.0);
uniform vec4 glow_color : source_color = vec4(0.16, 0.3, 0.46, 1.0);
uniform vec4 accent_color : source_color = vec4(0.24, 0.48, 0.68, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale * 0.02;

	// domain warp:用噪声扭曲坐标,产生有机流动
	vec2 q = vec2(
		fbm(uv + t),
		fbm(uv + vec2(5.2, 1.3) - t * 0.7)
	);
	vec2 r = vec2(
		fbm(uv + warp_strength * q + vec2(1.7, 9.2) + t * 0.5),
		fbm(uv + warp_strength * q + vec2(8.3, 2.8) - t * 0.4)
	);
	float f = fbm(uv + warp_strength * r);

	// 深色底 + 柔和光晕 + 高光丝带
	vec3 col = mix(bg_color.rgb, glow_color.rgb, smoothstep(0.25, 0.85, f));
	col += accent_color.rgb * pow(f, 3.0) * 0.5;

	// 微颗粒质感
	float grain = hash(uv * 900.0 + floor(TIME * 24.0));
	col += (grain - 0.5) * grain_amount;

	COLOR = vec4(col, 1.0);
}
