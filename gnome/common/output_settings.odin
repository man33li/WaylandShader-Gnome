package common

Output_Settings :: struct { gamma, saturation: f64, shader_enabled, color_enabled: bool }
#assert(size_of(Output_Settings) == 24)
MIN_GAMMA :: 0.1
MAX_GAMMA :: 5.0
MIN_SATURATION :: 0.0
MAX_SATURATION :: 2.0
DEFAULT_OUTPUT_SETTINGS :: Output_Settings{1, 1, true, false}
adjusts_color :: proc(s: Output_Settings) -> bool { return s.color_enabled && (s.gamma != 1 || s.saturation != 1) }
