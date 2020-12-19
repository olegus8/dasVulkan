#version 450
#extension GL_ARB_separate_shader_objects : enable

layout(binding = 0) uniform UniformBufferObject {
    vec2 offset;
} ubo;

layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_tex_pos;

layout(location = 0) out vec3 frag_color;

void main() {
    gl_Position = vec4(in_pos + ubo.offset, 0.0, 1.0);
    frag_color = in_color;
}
