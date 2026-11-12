/* SDK-typed intended contracts of NEW public 51 calls, not private ABI/ownership proof.
 * Odin cannot express C const; no exact-type equality is claimed for mutable projections. */
#include <stdint.h>
#include <clutter/clutter.h>
#include <cogl/cogl.h>
#define WLS_SIG(name, type) _Static_assert(__builtin_types_compatible_p(__typeof__(&(name)), type), #name)
_Static_assert(sizeof(size_t)==8 && sizeof(unsigned int)==4 && sizeof(GType)==8, "selected native widths");
WLS_SIG(clutter_color_pipeline_get_ops, const GList *(*)(ClutterColorPipeline *));
WLS_SIG(clutter_color_pipeline_shader_add_transform, void (*)(ClutterColorPipeline *, CoglPipeline *));
WLS_SIG(clutter_color_op_curve_1d_get_data, void (*)(ClutterColorOp *, size_t *, const float **, const float **, const float **, const float **));
WLS_SIG(clutter_color_op_3d_lut_get_data, void (*)(ClutterColorOp *, uint32_t *, const float **));
WLS_SIG(cogl_pipeline_foreach_layer, void (*)(CoglPipeline *, CoglPipelineLayerCallback, void *));
_Static_assert(__builtin_types_compatible_p(CoglPipelineLayerCallback, gboolean (*)(CoglPipeline *, int, void *)), "layer callback");
WLS_SIG(cogl_pipeline_get_layer_texture, CoglTexture *(*)(CoglPipeline *, int));
WLS_SIG(cogl_texture_get_width, unsigned int (*)(CoglTexture *));
WLS_SIG(cogl_texture_get_height, unsigned int (*)(CoglTexture *));
WLS_SIG(cogl_texture_2d_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_curve_1d_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_3d_lut_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_clamp_unit_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_srgb_piecewise_eotf_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_srgb_piecewise_inv_eotf_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_pq_eotf_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_pq_inv_eotf_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_unpremultiply_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_premultiply_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_gamma_power_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_matrix_4x4_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_ycbcr_matrix_get_type, GType (*)(void));
WLS_SIG(clutter_color_op_multiply_get_type, GType (*)(void));
#undef WLS_SIG
