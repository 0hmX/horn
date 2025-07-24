shader_type sky;

// Pure blue anime-style sky, only "day" colors
uniform vec3 sky_bottom_color : source_color = vec3(0.58, 0.78, 1.0);
uniform vec3 sky_top_color    : source_color = vec3(0.24, 0.52, 0.96);

// Sun
uniform vec3 sun_col   : source_color = vec3(1.0, 1.0, 0.9);
uniform float sun_size : hint_range(0.01, 1.0) = 0.14;
uniform float sun_blur : hint_range(0.01, 0.2) = 0.04;

// Clouds (static - sampled from a single noise texture)
uniform sampler2D clouds_texture;
uniform vec3 clouds_color    : source_color = vec3(0.97, 0.97, 1.0);
uniform float clouds_scale   : hint_range(0.05, 1.0) = 0.24;
uniform float clouds_cutoff  : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float clouds_fuzz    : hint_range(0.01, 1.0, 0.01) = 0.14;
uniform float clouds_opacity : hint_range(0.0, 1.0, 0.01) = 0.92;

void sky() {
    // Simple gradient (vertical)
    float t = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
    vec3 color = mix(sky_bottom_color, sky_top_color, t);

    // Static sun disc (direction = default LIGHT0_DIRECTION)
    float sun_dist = distance(EYEDIR, LIGHT0_DIRECTION);
    float sun_intensity = 1.0 - smoothstep(sun_size, sun_size + sun_blur, sun_dist);
    color = mix(color, sun_col, sun_intensity);

    // Clouds sample (static; no animation, fixed pattern)
    vec2 sky_uv = EYEDIR.xz / (1.2 + abs(EYEDIR.y));
    float clouds_sample = texture(clouds_texture, sky_uv * clouds_scale).r;
    float clouds_alpha = smoothstep(clouds_cutoff, clouds_cutoff + clouds_fuzz, clouds_sample) * clouds_opacity;

    // Blend clouds over sky
    color = mix(color, clouds_color, clouds_alpha);

    COLOR = color;
}
