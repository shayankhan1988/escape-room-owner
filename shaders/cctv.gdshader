shader_type spatial;
render_mode unshaded;

// Security-monitor look for the CCTV feed: desaturated, noisy, scanlines,
// slight lens bulge, rolling jitter lines and a static burst when switching.
uniform sampler2D feed : source_color, filter_linear;
uniform float static_amount = 0.0;

float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 c = UV - 0.5;
	vec2 uv = 0.5 + c * (1.0 + 0.08 * dot(c, c));
	float t = TIME;
	float line = step(0.993, rand(vec2(floor(uv.y * 90.0), floor(t * 10.0))));
	uv.x += line * 0.012;
	vec3 col = texture(feed, uv).rgb;
	col = pow(col * 2.4, vec3(0.8));   // camera gain: night footage is boosted
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(g), col, 0.3) * vec3(0.82, 1.0, 0.88);
	float n = rand(uv * vec2(640.0, 360.0) + fract(t) * 17.0);
	col += (n - 0.5) * 0.14;
	col *= 0.86 + 0.14 * sin(uv.y * 360.0 * 3.14159);
	col *= 0.92 + 0.08 * sin(t * 2.3);
	col *= smoothstep(0.85, 0.25, length(c));
	col = mix(col, vec3(n * 0.9), clamp(static_amount, 0.0, 1.0));
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) col = vec3(0.0);
	ALBEDO = col;
}
