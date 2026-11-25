#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 shapeSize;
    float cornerRadius;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = max(shapeSize, vec2(0.00001));
    float radius = clamp(cornerRadius, 0.0, min(size.x, size.y) * 0.5);
    vec2 p = (qt_TexCoord0 - vec2(0.5)) * size;
    vec2 q = abs(p) - (size * 0.5 - vec2(radius));
    float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float feather = max(fwidth(edge), 0.00001);
    float coverage = 1.0 - smoothstep(-feather, 0.0, edge);
    fragColor = texture(source, qt_TexCoord0) * coverage * qt_Opacity;
}
