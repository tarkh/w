// W Linux — premium duotone icon tint (Qt 6 RHI fragment shader).
// Maps each pixel's perceptual luminance onto a single-hue brand ramp: a darkened
// variant of the tint for shadows → the tint for mids → a gently lifted variant for
// highlights. Crucially the ramp stays in the tint's OWN hue (it does not mix toward
// white), so the brand color reads clearly and changing the tint is obvious. `shade`
// and `lift` shape the dark/light ends; `strength` mixes original ↔ duotone.
//
// Compile (committed .qsb is what ships; no qsb on target):
//   /usr/lib/qt6/bin/qsb --qt6 -o icontint.frag.qsb icontint.frag
//
// Uniforms auto-bound from ShaderEffect properties by name; qt_Matrix + qt_Opacity
// are provided by Qt Quick.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tintColor;     // brand color (rgb used)
    float strength;     // 0 = original, 1 = full duotone
    float shade;        // shadow end: 0 = black, 1 = tint
    float lift;         // highlight lift toward white: 0 = tint, 1 = white
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    float strength = ubuf.strength;
    float shade    = ubuf.shade;
    float lift     = ubuf.lift;

    vec4 src = texture(source, qt_TexCoord0);
    float a = src.a;
    // Straight (unpremultiplied) color so luminance is correct at the edges.
    vec3 c = a > 0.0 ? src.rgb / a : src.rgb;
    float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));

    vec3 accent = ubuf.tintColor.rgb;
    vec3 dark  = accent * shade;                 // darker accent (same hue)
    vec3 light = mix(accent, vec3(1.0), lift);   // accent lifted toward white
    vec3 grad  = mix(dark, light, smoothstep(0.0, 1.0, lum));

    vec3 outc = mix(c, grad, strength);
    // Re-premultiply and apply item opacity.
    fragColor = vec4(outc * a, a) * ubuf.qt_Opacity;
}
