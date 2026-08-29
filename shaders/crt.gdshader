// CRT 后处理效果(参考 CrtTypewriter):屏幕弯曲 + 色散 + 模糊 + 扫描线 + 暗角
// 用法:全屏 ColorRect + CanvasLayer(layer 高),material 用此 shader
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform float scan_intensity : hint_range(0.0, 0.3) = 0.08;
uniform float curve_val : hint_range(1.0, 20.0) = 12.0;
uniform float aberration : hint_range(0.0, 0.01) = 0.0;
uniform float blur_size : hint_range(0.0, 0.01) = 0.0015;
uniform float brightness : hint_range(0.8, 1.6) = 1.15;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

// 屏幕弯曲:边缘向内凹陷
vec2 curve(vec2 uv) {
	uv = (uv - 0.5) * 2.0;
	vec2 offset = abs(uv.yx) / vec2(max(curve_val, 1.0), max(curve_val, 1.0));
	uv = uv + uv * offset * offset;
	uv = (uv / 2.0) + 0.5;
	return uv;
}

// CRT 主体:色散 + 模糊 + 扫描线 + 暗角(在采样坐标上计算)
vec3 crt_color(vec2 crt_uv) {
	// 色散:RGB 通道微偏移(边缘更明显)
	float dist = distance(crt_uv, vec2(0.5));
	float ab = aberration + dist * aberration * 2.0;
	float r = texture(screen_texture, crt_uv + vec2(ab, 0.0)).r;
	float g = texture(screen_texture, crt_uv).g;
	float b = texture(screen_texture, crt_uv - vec2(ab, 0.0)).b;
	vec3 base = vec3(r, g, b);

	// 高斯模糊(对角采样)
	vec3 blur = vec3(0.0);
	float bs = blur_size;
	blur += texture(screen_texture, crt_uv + vec2(-bs, -bs)).rgb;
	blur += texture(screen_texture, crt_uv + vec2(bs, bs)).rgb;
	blur += texture(screen_texture, crt_uv + vec2(-bs, bs)).rgb;
	blur += texture(screen_texture, crt_uv + vec2(bs, -bs)).rgb;
	blur *= 0.25;

	vec3 col = mix(base, blur, 0.3);

	// 扫描线(更细更密集:频率提高 + 尖锐波形)
	float scan_wave = sin(crt_uv.y * 2400.0 + TIME * 5.0);
	scan_wave = pow(scan_wave, 8.0);  // 尖锐化,仅峰值附近形成细线
	float scan = scan_wave * scan_intensity * 2.2;
	col -= scan;

	// 暗角(几乎取消:只在最角落轻微,最低 0.95)
	float vignette = mix(0.95, 1.0, smoothstep(0.95, 0.6, dist));
	col *= vignette;

	// 整体提亮
	col *= brightness;

	return col;
}

void fragment() {
	vec2 uv = UV;
	vec2 crt_uv = curve(uv);

	// 采样坐标:raw 与 eff 必须一致,否则弯曲画面与原始画面叠加出现重影
	vec2 s_uv = crt_uv;
	// 弯曲后超出屏幕:回退到原始 UV(边缘不裁切,仅中部弯曲)
	if (crt_uv.x < 0.0 || crt_uv.x > 1.0 || crt_uv.y < 0.0 || crt_uv.y > 1.0) {
		s_uv = uv;
	}

	// 原始画面(与 eff 同一采样坐标,避免重影;保留弯曲,无扫描线等效果)
	vec3 raw = texture(screen_texture, s_uv).rgb;
	// 完整 CRT 效果
	vec3 eff = crt_color(s_uv);
	// 效果强度:0 = 仅保留曲率(无扫描线/色散/提亮),1 = 完整效果
	COLOR = vec4(mix(raw, eff, strength), 1.0);
}
