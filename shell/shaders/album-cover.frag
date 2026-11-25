#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 shapeSize;
    vec2 cropScale;
    float rotationRadians;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 size = max(shapeSize, vec2(0.00001));
    vec2 p = (qt_TexCoord0 - vec2(0.5)) * size;
    float radius = min(size.x, size.y) * 0.5;
    vec2 q = abs(p) - (size * 0.5 - vec2(radius));
    float distanceToEdge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float feather = max(fwidth(distanceToEdge) * 1.5, 0.00001);
    float coverage = 1.0 - smoothstep(-feather, 0.0, distanceToEdge);

    // Match a centered, cropped rotating square behind a stationary capsule.
    vec2 square = p / max(size.x, size.y);
    float c = cos(rotationRadians);
    float s = sin(rotationRadians);
    vec2 rotated = vec2(c * square.x + s * square.y, -s * square.x + c * square.y);
    vec2 uv = vec2(0.5) + rotated * cropScale;
    fragColor = texture(source, uv) * coverage * qt_Opacity;
}
