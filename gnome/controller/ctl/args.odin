package ctl

// Pure command-line parser reproducing the Qt 6 QCommandLineParser behaviour of
// src/ctl_main.cpp:22-140 (golden-checked against the baseline binary).

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:unicode/utf8"

import "../../common"
import "../client"

CLI_NAME :: "waylandshader-gnomectl"
DEFAULT_TIMEOUT :: "120"

Kind :: enum {
	Status,
	Parameters,
	Outputs,
	Load,
	Param,
	Output,
	Enable,
	Disable,
	Toggle,
}

Output_Action :: enum {
	Shader,
	Color,
	Gamma,
	Saturation,
}

Command :: struct {
	help:          bool, // print help_text(argv0) to stdout, exit 0
	argv0:         string,
	kind:          Kind,
	name:          string, // command word, also the JSON key for parameters/outputs
	timeout:       int, // seconds
	preset:        string, // load: canonical path
	param_name:    string,
	selector:      string, // output: id or name
	action:        Output_Action,
	enabled:       bool, // output shader|color
	value:         f64, // param value, output gamma|saturation
}

read_only :: proc(kind: Kind) -> bool {
	return kind == .Status || kind == .Parameters || kind == .Outputs
}

// parse returns exit == 0 with err == "" to run `cmd` (or print help when cmd.help),
// and exit == 2 with the complete stderr text in `err` on a usage error.
// Strings are allocated on the temp allocator.
parse :: proc(args: []string) -> (cmd: Command, err: string, exit: int) {
	if len(args) > 0 {
		cmd.argv0 = args[0]
	}
	positional := make([dynamic]string, context.temp_allocator)
	unknown := make([dynamic]string, context.temp_allocator)
	timeout_text: string = DEFAULT_TIMEOUT
	hard_error: string
	force_positional := false

	for i := 1; i < len(args); i += 1 {
		arg := args[i]
		switch {
		case force_positional:
			append(&positional, arg)
		case strings.has_prefix(arg, "--"):
			if len(arg) == 2 {
				force_positional = true
				break
			}
			body := arg[2:]
			name := body
			value: string
			has_value := false
			if eq := strings.index_byte(body, '='); eq >= 0 {
				name, value, has_value = body[:eq], body[eq + 1:], true
			}
			switch name {
			case "h", "help", "help-all":
				if has_value {
					hard_error = fmt.tprintf("Unexpected value after '--%s'.", name)
				} else if name != "help-all" {
					cmd.help = true
				}
			case "timeout":
				if has_value {
					timeout_text = value
				} else if i + 1 < len(args) {
					i += 1
					timeout_text = args[i]
				} else {
					hard_error = "Missing value after '--timeout'."
				}
			case:
				append(&unknown, name)
			}
		case len(arg) > 1 && arg[0] == '-':
			pos := 1
			for pos < len(arg) {
				r, size := utf8.decode_rune_in_string(arg[pos:])
				if r == 'h' {
					if pos + size < len(arg) && arg[pos + size] == '=' {
						hard_error = "Unexpected value after '-h'."
						break
					}
					cmd.help = true
				} else {
					append(&unknown, arg[pos:pos + size])
				}
				pos += size
			}
		case:
			append(&positional, arg)
		}
	}

	if hard_error != "" {
		return cmd, fmt.tprintf("%s\n", hard_error), 2
	}
	if len(unknown) == 1 {
		return cmd, fmt.tprintf("Unknown option '%s'.\n", unknown[0]), 2
	} else if len(unknown) > 1 {
		return cmd, fmt.tprintf("Unknown options: %s.\n", strings.join(unknown[:], ", ", context.temp_allocator)), 2
	}
	if cmd.help {
		return cmd, "", 0
	}

	usage :: proc(message: string) -> string {
		return fmt.tprintf("%s\nUse %s --help for usage.\n", message, CLI_NAME)
	}
	if len(positional) == 0 {
		return cmd, usage("A command is required."), 2
	}
	cmd.name = positional[0]
	switch cmd.name {
	case "status":
		cmd.kind = .Status
	case "parameters":
		cmd.kind = .Parameters
	case "outputs":
		cmd.kind = .Outputs
	case "load":
		cmd.kind = .Load
	case "param":
		cmd.kind = .Param
	case "output":
		cmd.kind = .Output
	case "enable":
		cmd.kind = .Enable
	case "disable":
		cmd.kind = .Disable
	case "toggle":
		cmd.kind = .Toggle
	case:
		return cmd, usage(fmt.tprintf("Unknown command: %s", cmd.name)), 2
	}
	required := 1
	#partial switch cmd.kind {
	case .Load:
		required = 2
	case .Param:
		required = 3
	case .Output:
		required = 4
	}
	if len(positional) != required {
		return cmd, usage(fmt.tprintf("Incorrect number of arguments for %s", cmd.name)), 2
	}
	timeout, timeout_ok := qt_to_int(timeout_text)
	if !timeout_ok || timeout < 1 || timeout > 3600 {
		return cmd, usage("--timeout must be an integer from 1 to 3600."), 2
	}
	cmd.timeout = timeout

	#partial switch cmd.kind {
	case .Load:
		if !is_slangp_file(positional[1]) {
			return cmd, usage("load requires an existing .slangp preset file."), 2
		}
		canonical, resolved := canonical_path(positional[1])
		if !resolved {
			return cmd, usage("Could not resolve the preset's absolute path."), 2
		}
		cmd.preset = canonical
	case .Param:
		value, ok := qt_to_f64(positional[2])
		if positional[1] == "" || !ok {
			return cmd, usage("param requires a nonempty parameter name and a finite numeric value."), 2
		}
		cmd.param_name = positional[1]
		cmd.value = value
	case .Output:
		if positional[1] == "" {
			return cmd, usage("output requires a nonempty monitor id or name."), 2
		}
		cmd.selector = positional[1]
		action := positional[2]
		value := positional[3]
		switch action {
		case "shader", "color":
			if value != "on" && value != "off" {
				return cmd, usage(fmt.tprintf("output %s requires on or off.", action)), 2
			}
			cmd.action = .Shader if action == "shader" else .Color
			cmd.enabled = value == "on"
		case "gamma", "saturation":
			gamma := action == "gamma"
			minimum := common.MIN_GAMMA if gamma else common.MIN_SATURATION
			maximum := common.MAX_GAMMA if gamma else common.MAX_SATURATION
			number, ok := qt_to_f64(value)
			if !ok || number < minimum || number > maximum {
				return cmd, usage(fmt.tprintf("output %s requires a finite number from %g to %g.", action, minimum, maximum)), 2
			}
			cmd.action = .Gamma if gamma else .Saturation
			cmd.value = number
		case:
			return cmd, usage(fmt.tprintf("Unknown output control: %s", action)), 2
		}
	}
	return cmd, "", 0
}

help_text :: proc(argv0: string) -> string {
	// %5, %1-%4, %6 of the Qt description, in order of appearance.
	return fmt.tprintf(
		"Usage: %s [options] command [arguments…]\n" +
		"Control the native %s over the session D-Bus.\n" +
		"Commands:\n" +
		"  status                         Print complete JSON status (does not load the effect)\n" +
		"  parameters                     Print declared parameters as JSON (does not load the effect)\n" +
		"  outputs                        Print connected monitors as JSON (does not load the effect)\n" +
		"  load FILE                      Load a .slangp preset and wait for compilation\n" +
		"  param NAME VALUE               Set a declared shader parameter\n" +
		"  output ID_OR_NAME shader on|off Enable/bypass the preset on one monitor\n" +
		"  output ID_OR_NAME color on|off  Enable/bypass color adjustments on one monitor\n" +
		"  output ID_OR_NAME gamma NUMBER  Set monitor gamma (%g–%g; 1 is neutral)\n" +
		"  output ID_OR_NAME saturation NUMBER\n" +
		"                                 Set monitor saturation (%g–%g; 1 is neutral)\n" +
		"  enable | disable               Set master desktop-effect enablement\n" +
		"  toggle                         Invert master desktop-effect enablement\n" +
		"\n" +
		"Monitor selectors match an exact id first, otherwise a unique exact name.\n" +
		"Master disable bypasses both presets and color adjustments on all monitors.\n" +
		"Monitor controls preserve other settings and never enable the master switch.\n" +
		"Color adjustments work without a preset; shader and color switches are independent.\n" +
		"%s\n" +
		"Exit codes: 0 success, 1 rejected/shader failure, 2 usage error,\n" +
		"3 unavailable/transport/protocol error, 4 timeout (operation may still finish).\n" +
		"\n" +
		"Options:\n" +
		"  -h, --help           Displays help on commandline options.\n" +
		"  --help-all           Displays help, including generic Qt options.\n" +
		"  --timeout <seconds>  Overall deadline in seconds, including asynchronous\n" +
		"                       compilation (1–3600).\n" +
		"\n" +
		"Arguments:\n" +
		"  command              One of the commands above.\n" +
		"  arguments            Command-specific arguments.\n",
		argv0,
		client.EFFECT_DESCRIPTION,
		common.MIN_GAMMA,
		common.MAX_GAMMA,
		common.MIN_SATURATION,
		common.MAX_SATURATION,
		client.ACTIVATION_HINT,
	)
}

// Number grammar of QString::toInt/toDouble in the C locale: surrounding whitespace is
// ignored; no hex, no digit separators, no inf/nan. [pinned against the baseline]
@(private = "file")
scan_number :: proc(text: string, allow_fraction: bool) -> (ok, nonzero: bool) {
	i := 0
	if i < len(text) && (text[i] == '+' || text[i] == '-') {
		i += 1
	}
	digits := 0
	for ; i < len(text) && text[i] >= '0' && text[i] <= '9'; i += 1 {
		digits += 1
		nonzero ||= text[i] != '0'
	}
	if allow_fraction {
		if i < len(text) && text[i] == '.' {
			i += 1
			for ; i < len(text) && text[i] >= '0' && text[i] <= '9'; i += 1 {
				digits += 1
				nonzero ||= text[i] != '0'
			}
		}
		if digits > 0 && i < len(text) && (text[i] == 'e' || text[i] == 'E') {
			i += 1
			if i < len(text) && (text[i] == '+' || text[i] == '-') {
				i += 1
			}
			exponent := 0
			for ; i < len(text) && text[i] >= '0' && text[i] <= '9'; i += 1 {
				exponent += 1
			}
			if exponent == 0 {
				return false, false
			}
		}
	}
	return digits > 0 && i == len(text), nonzero
}

qt_to_int :: proc(text: string) -> (value: int, ok: bool) {
	trimmed := strings.trim_space(text)
	scanned, _ := scan_number(trimmed, false)
	// More than 10 digits cannot be a valid --timeout and must not overflow.
	if !scanned || len(trimmed) > 12 {
		return 0, false
	}
	parsed, parsed_ok := strconv.parse_i64_of_base(trimmed, 10)
	return int(parsed), parsed_ok
}

// Finite doubles only; overflow and underflow-to-zero fail like QString::toDouble
// (1e400 and 1e-400 fail, the denormal 1e-320 passes).
qt_to_f64 :: proc(text: string) -> (value: f64, ok: bool) {
	trimmed := strings.trim_space(text)
	scanned, nonzero := scan_number(trimmed, true)
	if !scanned {
		return 0, false
	}
	parsed, parsed_ok := strconv.parse_f64(trimmed)
	if !parsed_ok || parsed - parsed != 0 || (parsed == 0 && nonzero) {
		return 0, false
	}
	return parsed, true
}

// QFileInfo::isFile() plus suffix() compared case-insensitively with "slangp".
is_slangp_file :: proc(path: string) -> bool {
	cpath, clone_err := strings.clone_to_cstring(path, context.temp_allocator)
	if clone_err != nil {
		return false
	}
	st: posix.stat_t
	if posix.stat(cpath, &st) != .OK || !posix.S_ISREG(st.st_mode) {
		return false
	}
	file_name := path[strings.last_index_byte(path, '/') + 1:]
	dot := strings.last_index_byte(file_name, '.')
	return dot >= 0 && strings.equal_fold(file_name[dot + 1:], "slangp")
}

canonical_path :: proc(path: string) -> (canonical: string, ok: bool) {
	cpath, clone_err := strings.clone_to_cstring(path, context.temp_allocator)
	if clone_err != nil {
		return "", false
	}
	buffer := make([]byte, posix.PATH_MAX, context.temp_allocator)
	resolved := posix.realpath(cpath, raw_data(buffer))
	if resolved == nil {
		return "", false
	}
	return strings.clone(string(resolved), context.temp_allocator), true
}
