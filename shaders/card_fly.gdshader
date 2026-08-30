shader_type canvas_item;

// 技能卡飞入动画专用:纯 fragment 透视倾斜(不修改 VERTEX,卡面始终在自身矩形内居中),
// 避免 fake_3D 顶点扩展导致的居中偏移。x/y_rot 单位为角度。
uniform float x_rot = 0.0;
uniform float y_rot = 0.0;

void fragment() {
	vec2 uv = UV - 0.5;
	float ax = radians(x_rot);
	float ay = radians(y_rot);
	// 3D 旋转(绕 X 再绕 Y),z 从 0 平面
	vec3 p = vec3(uv, 0.0);
	float cX = cos(ax); float sX = sin(ax);
	p = vec3(p.x, p.y * cX - p.z * sX, p.y * sX + p.z * cX);
	float cY = cos(ay); float sY = sin(ay);
	p = vec3(p.x * cY + p.z * sY, p.y, -p.x * sY + p.z * cY);
	p.z += 1.0;  // 平面前移,透视除法
	vec2 sp = p.xy / p.z;
	sp += 0.5;
	if (sp.x < 0.0 || sp.x > 1.0 || sp.y < 0.0 || sp.y > 1.0) discard;
	vec4 c = texture(TEXTURE, sp);
	c.rgb *= 0.88 + 0.24 * p.z;  // 轻微立体光照
	COLOR = c;
}
