package ctl

import "core:fmt"
import "core:sys/posix"
import "core:strings"
import "core:testing"

import "../client"

// Expected texts were captured from the baseline binary (/tmp/ws-baseline-result).

USAGE_TAIL :: "Use waylandshader-gnomectl --help for usage.\n"

run :: proc(args: ..string) -> (cmd: Command, err: string, exit: int) {
	full := make([dynamic]string, context.temp_allocator)
	append(&full, "ctl")
	append(&full, ..args)
	return parse(full[:])
}

expect_usage :: proc(t: ^testing.T, message: string, args: ..string, loc := #caller_location) {
	_, err, exit := run(..args)
	testing.expect_value(t, exit, 2, loc)
	testing.expect_value(t, err, fmt.tprintf("%s\n%s", message, USAGE_TAIL), loc)
}

expect_parse_error :: proc(t: ^testing.T, message: string, args: ..string, loc := #caller_location) {
	_, err, exit := run(..args)
	testing.expect_value(t, exit, 2, loc)
	testing.expect_value(t, err, fmt.tprintf("%s\n", message), loc)
}

@(test)
help_flags :: proc(t: ^testing.T) {
	for flags in ([][]string{{"-h"}, {"--help"}, {"--h"}, {"-hh"}, {"--help", "status"}, {"-h", "--"}, {"--timeout", "x", "-h"}}) {
		cmd, err, exit := run(..flags)
		testing.expect_value(t, exit, 0)
		testing.expect_value(t, err, "")
		testing.expect(t, cmd.help)
	}
	cmd, _, _ := parse({"/x/ctl", "-h"})
	testing.expect(t, strings.has_prefix(help_text(cmd.argv0), "Usage: /x/ctl [options] command [arguments…]\nControl the native WaylandShader GNOME extension"))
	testing.expect(t, strings.has_suffix(help_text("a"), "  arguments            Command-specific arguments.\n"))
}

@(test)
qt_option_errors :: proc(t: ^testing.T) {
	expect_parse_error(t, "Unknown option '?'.", "-?")
	expect_parse_error(t, "Unknown option 'x'.", "-x")
	expect_parse_error(t, "Unknown option 'x'.", "-hx")
	expect_parse_error(t, "Unknown options: e, l, p.", "-help")
	expect_parse_error(t, "Unknown options: t, i, m, e, o, u, t.", "-timeout", "5", "status")
	expect_parse_error(t, "Unknown options: -, x.", "-h-x")
	expect_parse_error(t, "Unknown option 'time'.", "--time", "5", "status")
	expect_parse_error(t, "Unknown option 'version'.", "--version")
	expect_parse_error(t, "Unknown option ''.", "--=")
	expect_parse_error(t, "Unknown option '-x'.", "---x")
	expect_parse_error(t, "Unknown option '0'.", "param", "X", "-0")
	expect_parse_error(t, "Unexpected value after '--help'.", "--help=1")
	expect_parse_error(t, "Unexpected value after '--help-all'.", "--help-all=3")
	expect_parse_error(t, "Unexpected value after '--h'.", "--h=1")
	expect_parse_error(t, "Unexpected value after '-h'.", "-h=1")
	expect_parse_error(t, "Unexpected value after '-h'.", "-h=")
	expect_parse_error(t, "Missing value after '--timeout'.", "--timeout")
	expect_parse_error(t, "Missing value after '--timeout'.", "status", "--timeout")
	expect_parse_error(t, "Unexpected value after '--help'.", "-x", "--help=1")
	// --help-all is known and has no effect
	expect_usage(t, "A command is required.", "--help-all")
	expect_parse_error(t, "Unknown option 'x'.", "--help-all", "-x")
}

@(test)
command_shape :: proc(t: ^testing.T) {
	expect_usage(t, "A command is required.")
	expect_usage(t, "A command is required.", "--")
	expect_usage(t, "A command is required.", "--timeout=")
	expect_usage(t, "A command is required.", "--timeout", "5")
	expect_usage(t, "Unknown command: bogus", "bogus")
	expect_usage(t, "Unknown command: -", "-")
	expect_usage(t, "Unknown command: ", "")
	for name in ([]string{"status", "parameters", "outputs", "enable", "disable", "toggle"}) {
		expect_usage(t, fmt.tprintf("Incorrect number of arguments for %s", name), name, "extra")
		_, err, exit := run(name)
		testing.expect_value(t, exit, 0)
		testing.expect_value(t, err, "")
	}
	expect_usage(t, "Incorrect number of arguments for status", "--", "status", "extra")
	expect_usage(t, "Incorrect number of arguments for load", "load")
	expect_usage(t, "Incorrect number of arguments for param", "param", "X")
	expect_usage(t, "Incorrect number of arguments for param", "param", "X", "1", "2")
	expect_usage(t, "Incorrect number of arguments for output", "output", "a", "gamma")
	// options interleave with positionals; the last --timeout wins
	cmd, err, exit := run("status", "--timeout=7")
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, err, "")
	testing.expect_value(t, cmd.timeout, 7)
	cmd, _, _ = run("--timeout", "3", "--timeout", "9", "toggle")
	testing.expect_value(t, cmd.timeout, 9)
	testing.expect_value(t, cmd.kind, Kind.Toggle)
	cmd, _, _ = run("status")
	testing.expect_value(t, cmd.timeout, 120)
	// "--" makes everything after it positional
	cmd, _, exit = run("--", "status")
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, cmd.kind, Kind.Status)
	// a value option consumes the next argument even when it looks like an option
	expect_usage(t, "--timeout must be an integer from 1 to 3600.", "--timeout", "--help", "status")
}

@(test)
timeout_values :: proc(t: ^testing.T) {
	message :: "--timeout must be an integer from 1 to 3600."
	for bad in ([]string{"0", "3601", "x", "", "-1", "0x10", "5.0", "1e1", "1_0", "+0", "-0", "99999999999", "１", "5 5"}) {
		expect_usage(t, message, fmt.tprintf("--timeout=%s", bad), "status")
	}
	for item in ([]struct {
		text:    string,
		seconds: int,
	}{{"1", 1}, {"3600", 3600}, {" 5", 5}, {"5 ", 5}, {"+5", 5}, {"007", 7}, {"+3600", 3600}}) {
		cmd, err, exit := run("--timeout", item.text, "outputs")
		testing.expect_value(t, exit, 0)
		testing.expect_value(t, err, "")
		testing.expect_value(t, cmd.timeout, item.seconds)
	}
}

@(test)
param_values :: proc(t: ^testing.T) {
	message :: "param requires a nonempty parameter name and a finite numeric value."
	for bad in ([]string{"", " ", "x", "nan", "inf", "infinity", "1e400", "1e-400", "0x10", "1,5", "1_0", "1e", "1e+", "+-1", "1.5.2", ".", "e5", "1d", "1 2"}) {
		expect_usage(t, message, "param", "X", bad)
	}
	expect_usage(t, message, "param", "", "1")
	for item in ([]struct {
		text:  string,
		value: f64,
	}{{"1", 1}, {" 1 ", 1}, {".5", 0.5}, {"5.", 5}, {"+1", 1}, {"1.e5", 1e5}, {"+.5e+3", 500}, {"1E5", 1e5}, {"1e-320", 1e-320}, {"0", 0}, {"0e-9999", 0}}) {
		cmd, err, exit := run("param", "GAIN", item.text)
		testing.expect_value(t, exit, 0)
		testing.expect_value(t, err, "")
		testing.expect_value(t, cmd.param_name, "GAIN")
		testing.expect_value(t, cmd.value, item.value)
	}
}

@(test)
output_values :: proc(t: ^testing.T) {
	expect_usage(t, "output requires a nonempty monitor id or name.", "output", "", "shader", "on")
	expect_usage(t, "output shader requires on or off.", "output", "a", "shader", "ON")
	expect_usage(t, "output color requires on or off.", "output", "a", "color", "1")
	expect_usage(t, "Unknown output control: bogus", "output", "a", "bogus", "1")
	expect_usage(t, "output gamma requires a finite number from 0.1 to 5.", "output", "a", "gamma", "0.05")
	expect_usage(t, "output gamma requires a finite number from 0.1 to 5.", "output", "a", "gamma", "5.1")
	expect_usage(t, "output gamma requires a finite number from 0.1 to 5.", "output", "a", "gamma", "nan")
	expect_usage(t, "output saturation requires a finite number from 0 to 2.", "output", "a", "saturation", "2.1")
	expect_usage(t, "output saturation requires a finite number from 0 to 2.", "output", "a", "saturation", "x")
	// a leading '-' makes the positional an option (baseline: Unknown option '1'.)
	expect_parse_error(t, "Unknown option '1'.", "output", "a", "saturation", "-1")

	cmd, _, exit := run("output", "DP-1", "shader", "off")
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, cmd.action, Output_Action.Shader)
	testing.expect_value(t, cmd.enabled, false)
	testing.expect_value(t, cmd.selector, "DP-1")
	cmd, _, _ = run("output", "a", "color", "on")
	testing.expect_value(t, cmd.action, Output_Action.Color)
	testing.expect_value(t, cmd.enabled, true)
	for text in ([]string{"0.1", "5", ".1", "1e0"}) {
		cmd, _, exit = run("output", "a", "gamma", text)
		testing.expect_value(t, exit, 0)
		testing.expect_value(t, cmd.action, Output_Action.Gamma)
	}
	cmd, _, exit = run("output", "a", "saturation", "0")
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, cmd.value, 0)
	cmd, _, _ = run("output", "a", "saturation", "2")
	testing.expect_value(t, cmd.value, 2)
}

@(test)
load_validation :: proc(t: ^testing.T) {
	message :: "load requires an existing .slangp preset file."
	dir := fmt.tprintf("/tmp/ws-ctl-unit-%d", posix.getpid())
	// Exclusive creation: mkdir fails on any pre-existing path, including a planted symlink.
	if posix.mkdir(strings.clone_to_cstring(dir, context.temp_allocator), {.IRUSR, .IWUSR, .IXUSR}) != .OK {
		testing.fail_now(t, "cannot exclusively create the test directory")
	}
	defer posix.rmdir(strings.clone_to_cstring(dir, context.temp_allocator))
	good := fmt.tprintf("%s/a.slangp", dir)
	upper := fmt.tprintf("%s/B.SLANGP", dir)
	other := fmt.tprintf("%s/c.txt", dir)
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
	expect_usage(t, message, "load", fmt.tprintf("%s/missing.slangp", dir))
	expect_usage(t, message, "load", other)
	expect_usage(t, message, "load", dir)
	expect_usage(t, message, "load", "")
	cmd, err, exit := run("load", upper)
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, err, "")
	testing.expect_value(t, cmd.preset, upper)
	cmd, _, exit = run("load", fmt.tprintf("%s/../%s/a.slangp", dir, dir[5:]))
	testing.expect_value(t, exit, 0)
	testing.expect_value(t, cmd.preset, good)
}

@(test)
backend_strings :: proc(t: ^testing.T) {
	testing.expect_value(t, client.COMPOSITOR, "GNOME Shell")
}
