#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float zoomVelocity;
    vec2 motionOffset;
    vec2 blurCenter;
};
layout(binding = 1) uniform sampler2D source;

// A short exposure along the actual zoom/translation direction. Premultiplied
// samples preserve smooth transparent cover edges; no persistent soft focus.
void main() {
    vec2 velocity = (qt_TexCoord0 - blurCenter) * zoomVelocity + motionOffset;
    vec4 sum = vec4(0.0);
    float weights = 0.0;
    for (int i = 0; i < 9; ++i) {
        float t = float(i) / 8.0;
        float weight = 1.0 - t * 0.65;
        sum += texture(source, qt_TexCoord0 + velocity * t) * weight;
        weights += weight;
    }
    fragColor = sum / weights * qt_Opacity;
}
