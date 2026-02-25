shader_type spatial;
uniform sampler2DArray texture_array : source_color, filter_nearest_mipmap;

void fragment() {
    vec3 uvw = vec3(UV.xy, UV2.x);
    ALBEDO = texture(texture_array, uvw).rgb;
}