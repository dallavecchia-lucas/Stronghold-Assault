class_name StopNaNs
extends CompositorEffect
## Stops NaNs: after the transparent pass, before the bloom and the tonemapper, a compute pass over the frame
## finds the pixels whose colour came out NaN or infinite (a model's degenerate tangents behind its normal map, a
## zero vector normalized somewhere in a shader) and gives each its neighbours' colour instead. Left alone, one
## such pixel is a white-hot ball: the bloom's downsample turns NaN and infinity into 100 and blurs it over a
## wide disc. It works on the frame itself (a shader reading the screen sees a copy in which the NaN is already
## gone), costs a read a pixel, and runs on the Forward+ renderer. Atmosphere puts one on every level's
## WorldEnvironment.

const SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_image;
layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 pad;
} params;

// NaN or infinite: told by the bits (all of the exponent's set).
bool bad(vec3 c) {
	uvec3 e = floatBitsToUint(c) & uvec3(0x7F800000u);
	return any(equal(e, uvec3(0x7F800000u)));
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.size);
	if (p.x >= size.x || p.y >= size.y) {
		return;
	}
	vec4 c = imageLoad(color_image, p);
	if (!bad(c.rgb)) {
		return;
	}
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 q = clamp(p + ivec2(dx, dy), ivec2(0), size - 1);
			vec3 s = imageLoad(color_image, q).rgb;
			if ((dx != 0 || dy != 0) && !bad(s)) {
				sum += s;
				n += 1.0;
			}
		}
	}
	imageStore(color_image, p, vec4(n > 0.0 ? sum / n : vec3(0.0), bad(vec3(c.a)) ? 1.0 : c.a));
}
"""

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	RenderingServer.call_on_render_thread(_build)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shader.is_valid() and _rd:
		# Freeing the shader frees its pipeline.
		_rd.free_rid(_shader)


func _build() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = SHADER
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("StopNaNs: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if _shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or _rd == null or not _pipeline.is_valid():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	var push := PackedFloat32Array([size.x, size.y, 0.0, 0.0]).to_byte_array()
	for view in buffers.get_view_count():
		var image := RDUniform.new()
		image.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image.binding = 0
		image.add_id(buffers.get_color_layer(view))
		var uniforms := UniformSetCacheRD.get_cache(_shader, 0, [image])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, uniforms, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_rd.compute_list_end()
