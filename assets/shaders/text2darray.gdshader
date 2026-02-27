shader_type spatial;

uniform sampler2DArray texture_array : filter_nearest_mipmap, source_color;

void fragment() {
    float texture_index = round(UV2.x);
    vec4 albedo_tex = texture(texture_array, vec3(UV, texture_index));
    
    ALBEDO = albedo_tex.rgb;
    ALPHA = albedo_tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}