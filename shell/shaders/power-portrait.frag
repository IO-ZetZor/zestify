#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float faceShade;
    float sheen;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    float distanceToCenter = length(qt_TexCoord0 - vec2(0.5));
    // Feather only the silhouette over roughly 1.5 physical pixels. Derivatives
    // track display scaling and avoid blurring the artwork inside the circle.
    float feather = max(fwidth(distanceToCenter) * 1.5, 0.00001);
    float coverage = 1.0 - smoothstep(0.5 - feather, 0.5, distanceToCenter);
    vec4 artwork = texture(source, qt_TexCoord0);
    float highlight = exp(-pow((qt_TexCoord0.x + qt_TexCoord0.y * 0.3 - 0.4) * 8.0, 2.0)) * sheen;
    artwork.rgb = min(artwork.rgb * faceShade + vec3(highlight * artwork.a), vec3(artwork.a));
    fragColor = artwork * coverage * qt_Opacity;
}
