shader_type spatial;
render_mode unshaded, shadows_disabled, ambient_light_disabled, fog_disabled; 

uniform float q_levels = 1.0;
uniform float interpolation_z = 0.0;
uniform float zoom = 1.0;
uniform float o_y = 0.0005;
// 6 cubemap faces
uniform sampler2D tex_posx : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negx : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_posy : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negy : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_posz : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negz : filter_nearest_mipmap_anisotropic;  

uniform sampler2D tex_posx_z : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negx_z : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_posy_z : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negy_z : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_posz_z : filter_nearest_mipmap_anisotropic;
uniform sampler2D tex_negz_z : filter_nearest_mipmap_anisotropic; 
 
uniform sampler2D previous_frame : source_color, filter_nearest_mipmap_anisotropic;
uniform sampler3D lut : filter_nearest;

// controls how "smooth" the transition is between cube faces
uniform float blend_sharpness : hint_range(1.0, 256.0) = 8.0;


// Convert a direction vector into UVs for a given face
vec2 cube_uv(vec3 dir, int face) {
	dir = normalize(dir);
	vec2 uv;

	if (face == 0) uv = vec2(-dir.z, dir.y) / abs(dir.x);   // +X
	if (face == 1) uv = vec2(dir.z, dir.y) / abs(dir.x);    // -X
	if (face == 2) uv = vec2(dir.x, -dir.z) / abs(dir.y);   // +Y
	if (face == 3) uv = vec2(dir.x, dir.z) / abs(dir.y);    // -Y
	if (face == 4) uv = vec2(dir.x, dir.y) / abs(dir.z);    // +Z
	if (face == 5) uv = vec2(-dir.x, dir.y) / abs(dir.z);   // -Z

	uv = vec2(-uv.x, uv.y);
	uv = clamp(uv, -0.999, 0.999);

	return uv * 0.5 + 0.5;
}


// Blend all 6 cube faces based on the view direction
vec3 sample_cubemap(vec3 dir) {
	vec3 abs_dir = abs(dir);
	float max_axis = max(max(abs_dir.x, abs_dir.y), abs_dir.z);

	// Smooth blending weights
	vec3 weights = pow(abs_dir / max_axis, vec3(blend_sharpness));
	weights /= (weights.x + weights.y + weights.z);

	vec3 col_x = mix(
		texture(tex_posx, cube_uv(dir, 1)).rgb,
		texture(tex_negx, cube_uv(dir, 0)).rgb,
		step(0.0, dir.x)
	);
	vec3 col_y = mix(
		texture(tex_posy, cube_uv(dir, 3)).rgb,
		texture(tex_negy, cube_uv(dir, 2)).rgb,
		step(0.0, dir.y)
	);
	vec3 col_z = mix(
		texture(tex_posz, cube_uv(dir, 5)).rgb,
		texture(tex_negz, cube_uv(dir, 4)).rgb,
		step(0.0, dir.z)
	);

	return weights.x * col_x + weights.y * col_y + weights.z * col_z;
}

vec3 sample_cubemap2(vec3 dir) {
	vec3 abs_dir = abs(dir);
	float max_axis = max(max(abs_dir.x, abs_dir.y), abs_dir.z);

	// Smooth blending weights
	vec3 weights = pow(abs_dir / max_axis, vec3(blend_sharpness));
	weights /= (weights.x + weights.y + weights.z);

	// offset half a pixel to create antialiasing
	// but if we do so, we are doubling our final render resolution.
	// out textures are 256x256, a pixel equals 1/256 or 0.004. Half a pixel = 0.002
	// we can add a smaller value to keep the final image very pixelated and
	// still add a bit of antialiasing like 0.0004

	vec3 col_x = mix(
		texture(tex_posx_z, clamp(cube_uv(dir, 1) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		texture(tex_negx_z, clamp(cube_uv(dir, 0) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		step(0.0, dir.x)
	);
	vec3 col_y = mix(
		texture(tex_posy_z, clamp(cube_uv(dir, 3) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		texture(tex_negy_z, clamp(cube_uv(dir, 2) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		step(0.0, dir.y)
	);
	vec3 col_z = mix(
		texture(tex_posz_z, clamp(cube_uv(dir, 5) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		texture(tex_negz_z, clamp(cube_uv(dir, 4) + vec2(o_y,o_y), 0.001, 0.999)).rgb,
		step(0.0, dir.z)
	);

	return weights.x * col_x + weights.y * col_y + weights.z * col_z;
}

vec3 agx_tonemap(vec3 color)
{
    // --- Exposure compression (soft logarithmic rolloff)
    color = max(color, vec3(0.0));

    const float A = 0.10;   // shoulder strength
    const float B = 0.40;   // linear section start
    const float C = 0.10;   // linear section length
    const float D = 0.20;   // shoulder angle
    const float Es = 0.02;   // toe strength
    const float F = 0.20;   // linear gain

    // Filmic-like curve (from AgX / Uncharted2 fit)
    color = ((color * (A * color + C * B) + D * Es) /
             (color * (A * color + B) + D * F)) - Es / F;

    // optional gamma for perceptual display
    color = pow(color, vec3(1.0 / 2.2));

    // clamp final output
    return clamp(color, 0.0, 1.0);
}

void fragment() {
	// Camera direction for this pixel (from camera to fragment)
	vec3 world_view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW*zoom, 0.0)).xyz);

	vec3 color = sample_cubemap(world_view_dir);
	vec3 color2 = sample_cubemap2(world_view_dir);
	//ALBEDO = mix(color, color2, interpolation_z);
	
	// quantize before mixing, to have intermediate colors for blending
	//color = floor(color * 6.0) / 6.0;
	//color2 = floor(color2 * 6.0) / 6.0;
	
	// remap before lookup table
	// cheap log compression
	float white = 2.0;
	color = log2(1.0 + color) / log2(1.0 + white);
	color2 = log2(1.0 + color2) / log2(1.0 + white);
	
	//color = agx_tonemap(color);
	//color2 = agx_tonemap(color2);
	
	// quantize via quantized LUT
	color = texture(lut, color).xyz;
	color2 = texture(lut, color2).xyz;
	
	ALBEDO = mix(color, color2, 0.5); // blend to minimize distance flickering
	
	//ALBEDO = texture(lut, ALBEDO).xyz;
	
	// blend with previous frame to accumulate and add a bit more softness
	vec3 prev_quant = texture(previous_frame, SCREEN_UV).xyz;
	ALBEDO = mix(ALBEDO, prev_quant, 0.05);
	//naive quantize
	//ALBEDO = floor(ALBEDO * 6.0) / 6.0;
	
	// quantize with weights
	/*
	ALBEDO = vec3(
    floor(pow(ALBEDO.r, 0.8) * (6.0+q_levels)) / (6.0+q_levels),
    floor(pow(ALBEDO.g, 0.8) * (8.0+q_levels)) / (8.0+q_levels),
    floor(pow(ALBEDO.b, 0.8) * (5.0+q_levels)) / (5.0+q_levels)
	);
	ALBEDO = pow(ALBEDO, vec3(1.0 / 0.8)); // undo gamma curve
	*/
	
}
