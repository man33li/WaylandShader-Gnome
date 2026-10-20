package main

// Pure presentation helpers of the GUI (no GTK). Returned strings live on the temp
// allocator; callers copy what they keep. Ports of src/controller_main.cpp.

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:sys/posix"

import "../client"

// GUI:294-301
state_label :: proc(output: ^client.Output, pending, enabled: bool) -> string {
	switch {
	case output == nil:
		return ""
	case pending:
		return "Saving…"
	case !enabled:
		return "Bypassed"
	case output.bypass != "":
		return fmt.tprintf("Unfiltered: %s", output.bypass)
	case output.shader_active && output.color_active:
		return "Preset + color active"
	case output.shader_active:
		return "Preset active"
	case output.color_active:
		return "Color active"
	}
	return "No processing active"
}

// GUI:535-547
summary_text :: proc(status: ^client.Status) -> string {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	switch {
	case status.active:
		strings.write_string(&b, "Desktop effects active")
	case !status.enabled:
		strings.write_string(&b, "Desktop effects disabled")
	case:
		strings.write_string(&b, "Desktop effects enabled, but not active")
	}
	if status.loading {
		fmt.sbprintf(&b, "\nCompiling: %s\nThe previous shader is retained until loading succeeds.", status.requested_preset)
	}
	if status.preset != "" {
		fmt.sbprintf(&b, "\nLoaded preset: %s", status.preset)
	}
	strings.write_string(&b, "\nOutputs: ")
	if len(status.outputs) == 0 {
		strings.write_string(&b, "No connected monitors")
	}
	for output, index in status.outputs {
		if index > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, output.name)
	}
	return strings.to_string(b)
}

// GUI:398-413: "" when `path` is an existing file with a case-insensitive .slangp suffix.
// The caller resolves the canonical path itself.
load_error :: proc(path: string) -> string {
	if path != "" {
		cpath, clone_err := strings.clone_to_cstring(path, context.temp_allocator)
		if clone_err != nil {
			return "Out of memory"
		}
		st: posix.stat_t
		if posix.stat(cpath, &st) == .OK && posix.S_ISREG(st.st_mode) {
			file_name := path[strings.last_index_byte(path, '/') + 1:]
			dot := strings.last_index_byte(file_name, '.')
			if dot >= 0 && strings.equal_fold(file_name[dot + 1:], "slangp") {
				return ""
			}
		}
	}
	return "Choose an existing .slangp preset file."
}

// QDoubleSpinBox with 2 decimals: round to the nearest hundredth, exact ties away from zero.
round2 :: proc(value: f64) -> f64 {
	if math.is_nan(value) || math.is_inf(value) {
		return value
	}
	eighths := value * 8
	if eighths == math.floor(eighths) && math.mod(math.abs(eighths), 2) == 1 {
		// n/8 with odd n is an exact tie at two decimals (x.125, x.375, ...)
		scaled := math.floor(math.abs(value) * 100) + 1
		return math.copy_sign(scaled / 100, value)
	}
	rounded, _ := strconv.parse_f64(fmt.tprintf("%.2f", value))
	return rounded
}

// GUI:444-445
parameter_step :: proc(p: ^client.Parameter) -> f64 {
	span := p.maximum - p.minimum
	switch {
	case p.step > 0:
		return p.step
	case span > 0 && !math.is_inf(span):
		return span / 100
	}
	return 1
}

// GUI:448-452
parameter_tooltip :: proc(p: ^client.Parameter) -> string {
	return fmt.tprintf("%s\nDefault: %.9g; range: %.9g to %.9g", p.name, p.default_value, p.minimum, p.maximum)
}

// GUI:457
parameter_label :: proc(p: ^client.Parameter) -> string {
	return p.description if p.description != "" else p.name
}

// std::to_chars(float): the shortest round-trip digits, in fixed or scientific notation,
// whichever is shorter (ties fixed) [INFERENCE for the tie rule].
format_f32 :: proc(value: f64) -> string {
	f := f32(value)
	if f == 0 {
		return "-0" if math.sign_bit(f) else "0"
	}
	if math.is_nan(f) || math.is_inf(f) {
		return fmt.tprintf("%v", f)
	}
	// Shortest round-trip digits found by search: odin's -1 precision can emit extra digits.
	// The f32 widened to f64 is exact, so formatting it to p digits is correctly rounded.
	buf: [48]byte
	text: string
	for digits_wanted in 1 ..= 9 {
		candidate := strings.trim_prefix(
			strconv.write_float(buf[:], f64(abs(f)), 'e', digits_wanted - 1, 64),
			"+",
		)
		back, _ := strconv.parse_f32(candidate)
		text = candidate
		if back == abs(f) {
			break
		}
	}
	e_at := strings.index_byte(text, 'e')
	mantissa, _ := strings.remove_all(text[:e_at], ".", context.temp_allocator)
	exponent, _ := strconv.parse_int(text[e_at + 1:])
	digits := len(mantissa)
	sign := "-" if f < 0 else ""

	abs_exponent := exponent if exponent >= 0 else -exponent
	exp_digits := 2 if abs_exponent < 100 else 3
	sci_len := digits + (1 if digits > 1 else 0) + 2 + exp_digits
	fixed_len: int
	if exponent >= 0 {
		fixed_len = max(digits, exponent + 1) + (1 if digits > exponent + 1 else 0)
	} else {
		fixed_len = 2 - exponent - 1 + digits
	}
	if fixed_len <= sci_len {
		switch {
		case exponent >= 0 && digits <= exponent + 1:
			return fmt.tprintf("%s%s%s", sign, mantissa, strings.repeat("0", exponent + 1 - digits, context.temp_allocator))
		case exponent >= 0:
			return fmt.tprintf("%s%s.%s", sign, mantissa[:exponent + 1], mantissa[exponent + 1:])
		}
		return fmt.tprintf("%s0.%s%s", sign, strings.repeat("0", -exponent - 1, context.temp_allocator), mantissa)
	}
	point := "." if digits > 1 else ""
	return fmt.tprintf("%s%s%s%se%s%02d", sign, mantissa[:1], point, mantissa[1:], "-" if exponent < 0 else "+", abs_exponent)
}

// ParameterSpinBox::valueFromText: C-locale double cast to float. Grammar as in
// ctl/args.odin: optional surrounding whitespace, no hex, separators, inf or nan.
parse_f32 :: proc(text: string) -> (value: f32, ok: bool) {
	trimmed := strings.trim_space(text)
	i := 0
	if i < len(trimmed) && (trimmed[i] == '+' || trimmed[i] == '-') {
		i += 1
	}
	scan_digits :: proc(s: string, i: ^int) -> (count: int) {
		for ; i^ < len(s) && s[i^] >= '0' && s[i^] <= '9'; i^ += 1 {
			count += 1
		}
		return
	}
	digits := scan_digits(trimmed, &i)
	if i < len(trimmed) && trimmed[i] == '.' {
		i += 1
		digits += scan_digits(trimmed, &i)
	}
	if digits > 0 && i < len(trimmed) && (trimmed[i] == 'e' || trimmed[i] == 'E') {
		i += 1
		if i < len(trimmed) && (trimmed[i] == '+' || trimmed[i] == '-') {
			i += 1
		}
		if scan_digits(trimmed, &i) == 0 {
			return 0, false
		}
	}
	if digits == 0 || i != len(trimmed) {
		return 0, false
	}
	parsed, parsed_ok := strconv.parse_f64(trimmed)
	if !parsed_ok || parsed - parsed != 0 {
		return 0, false
	}
	narrowed := f32(parsed)
	return narrowed, !math.is_inf(narrowed)
}
