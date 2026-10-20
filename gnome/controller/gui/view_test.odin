package main

import "core:fmt"
import "core:strings"
import "core:sys/posix"
import "core:testing"

import "../client"

@(test)
state_label_precedence :: proc(t: ^testing.T) {
	testing.expect_value(t, state_label(nil, true, true), "")
	o := client.Output {
		shader_active = true,
		color_active  = true,
		bypass        = "no GL",
	}
	testing.expect_value(t, state_label(&o, true, false), "Saving…")
	testing.expect_value(t, state_label(&o, false, false), "Bypassed")
	testing.expect_value(t, state_label(&o, false, true), "Unfiltered: no GL")
	o.bypass = ""
	testing.expect_value(t, state_label(&o, false, true), "Preset + color active")
	o.color_active = false
	testing.expect_value(t, state_label(&o, false, true), "Preset active")
	o.shader_active, o.color_active = false, true
	testing.expect_value(t, state_label(&o, false, true), "Color active")
	o.color_active = false
	testing.expect_value(t, state_label(&o, false, true), "No processing active")
}

@(test)
summary_texts :: proc(t: ^testing.T) {
	s := client.Status{}
	testing.expect_value(t, summary_text(&s), "Desktop effects disabled\nOutputs: No connected monitors")
	s.enabled = true
	testing.expect_value(t, summary_text(&s), "Desktop effects enabled, but not active\nOutputs: No connected monitors")
	s.active = true
	s.preset = "/p/a.slangp"
	s.outputs = {{id = "A", name = "A"}, {id = "B", name = "Right"}}
	testing.expect_value(t, summary_text(&s), "Desktop effects active\nLoaded preset: /p/a.slangp\nOutputs: A, Right")
	s.loading = true
	s.requested_preset = "/p/b.slangp"
	testing.expect_value(
		t,
		summary_text(&s),
		"Desktop effects active\nCompiling: /p/b.slangp\nThe previous shader is retained until loading succeeds.\nLoaded preset: /p/a.slangp\nOutputs: A, Right",
	)
}

@(test)
load_errors :: proc(t: ^testing.T) {
	message :: "Choose an existing .slangp preset file."
	dir := fmt.tprintf("/tmp/ws-view-unit-%d", posix.getpid())
	// Exclusive creation: mkdir fails on any pre-existing path, including a planted symlink.
	if posix.mkdir(strings.clone_to_cstring(dir, context.temp_allocator), {.IRUSR, .IWUSR, .IXUSR}) != .OK {
		testing.fail_now(t, "cannot exclusively create the test directory")
	}
	defer posix.rmdir(strings.clone_to_cstring(dir, context.temp_allocator))
	good := fmt.tprintf("%s/a.slangp", dir)
	upper := fmt.tprintf("%s/A.SLANGP", dir)
	other := fmt.tprintf("%s/b.txt", dir)
	for path in ([]string{good, upper, other}) {
		fd := posix.open(strings.clone_to_cstring(path, context.temp_allocator), {.CREAT, .EXCL, .WRONLY}, {.IRUSR, .IWUSR})
		if fd < 0 {
			testing.fail_now(t, "cannot create a fixture file")
		}
		posix.close(fd)
	}
	defer for path in ([]string{good, upper, other}) {
		posix.unlink(strings.clone_to_cstring(path, context.temp_allocator))
	}
	testing.expect_value(t, load_error(good), "")
	testing.expect_value(t, load_error(upper), "")
	testing.expect_value(t, load_error(other), message)
	testing.expect_value(t, load_error(dir), message)
	testing.expect_value(t, load_error(fmt.tprintf("%s/missing.slangp", dir)), message)
	testing.expect_value(t, load_error(""), message)
}

@(test)
rounding :: proc(t: ^testing.T) {
	// exact ties are not asserted (Qt tie rule is [INFERENCE]) except the representable 0.125
	for item in ([]struct {
		in_value, out: f64,
	}{{1.234, 1.23}, {1.236, 1.24}, {4.999, 5.0}, {0.1, 0.1}, {-1.236, -1.24}, {0, 0}, {2, 2}}) {
		testing.expect_value(t, round2(item.in_value), item.out)
	}
	testing.expect_value(t, round2(0.125), 0.13)
	testing.expect_value(t, round2(-0.125), -0.13)
}

@(test)
parameter_rules :: proc(t: ^testing.T) {
	p := client.Parameter {
		name          = "GAIN",
		minimum       = 0.1,
		maximum       = 2,
		step          = 0.1,
		default_value = 1,
	}
	testing.expect_value(t, parameter_step(&p), 0.1)
	p.step = 0
	testing.expect_value(t, parameter_step(&p), (2 - 0.1) / 100)
	p.minimum, p.maximum = 3, 3
	testing.expect_value(t, parameter_step(&p), 1.0)
	p.minimum, p.maximum = 3, 1
	testing.expect_value(t, parameter_step(&p), 1.0)
	p.minimum, p.maximum = 0, 1e-7
	testing.expect_value(t, parameter_step(&p), 1e-7 / 100)

	p = {name = "GAIN", minimum = 0.1, maximum = 2, default_value = 1}
	testing.expect_value(t, parameter_label(&p), "GAIN")
	p.description = "Gain"
	testing.expect_value(t, parameter_label(&p), "Gain")
	testing.expect_value(t, parameter_tooltip(&p), "GAIN\nDefault: 1; range: 0.1 to 2")
	p.minimum, p.maximum, p.default_value = 1e-7, 1234567890, 0.123456789123
	testing.expect_value(t, parameter_tooltip(&p), "GAIN\nDefault: 0.123456789; range: 1e-07 to 1.23456789e+09")
}

@(test)
f32_text :: proc(t: ^testing.T) {
	for item in ([]struct {
		in_value: f64,
		out:      string,
	}{{0, "0"}, {1, "1"}, {0.5, "0.5"}, {-2.25, "-2.25"}, {100, "100"}, {1e-7, "1e-07"}, {3.5e10, "3.5e+10"}, {123456, "123456"}, {0.1, "0.1"}, {f64(f32(0.1)), "0.1"}, {1.0000001e-7, "1.0000001e-07"}, {1.401298464324817e-45, "1e-45"}, {3.4028234e38, "3.4028235e+38"}, {16777216, "16777216"}}) {
		testing.expect_value(t, format_f32(item.in_value), item.out)
	}
	// Round trips, including the smallest subnormal f32
	for value in ([]f64{1e-7, 1.0000001e-7, 1.401298464324817e-45, 0.1, 16777216, 3.4028234e38, -5e-3}) {
		text := format_f32(value)
		back, ok := parse_f32(text)
		testing.expectf(t, ok && back == f32(value), "%v -> %q -> %v", value, text, back)
	}
}

@(test)
f32_parsing :: proc(t: ^testing.T) {
	for text in ([]string{"", " ", "x", "nan", "inf", "0x10", "1_0", "1e", "1,5", ".", "1e39", "--1", "1 2"}) {
		_, ok := parse_f32(text)
		testing.expectf(t, !ok, "%q must be rejected", text)
	}
	for item in ([]struct {
		text:  string,
		value: f32,
	}{{"1", 1}, {" 0.5 ", 0.5}, {".25", 0.25}, {"5.", 5}, {"+1e-7", 1e-7}, {"1.0000001e-7", 1.0000001e-7}, {"-3", -3}}) {
		value, ok := parse_f32(item.text)
		testing.expectf(t, ok && value == item.value, "%q -> %v", item.text, value)
	}
}
