package client

import "base:runtime"

import json "core:encoding/json"
import "core:fmt"
import "core:math"
import common "../../common"

Parameter :: struct { name, description: string, minimum, maximum, step, default_value, value: f64 }
Output :: struct { id, name: string, settings: common.Output_Settings, shader_active, color_active: bool, bypass: string }
Status :: struct {
    enabled, active, loading: bool,
    preset, requested_preset, error: string,
    recent_presets: []string, parameters: []Parameter, outputs: []Output, json: common.JSON_Document,
}

free_status :: proc(s: ^Status) {
    delete(s.recent_presets)
    delete(s.parameters)
    delete(s.outputs)
    common.destroy_document(&s.json)
    s^ = {}
}
invalid :: proc(message: string) -> Error { return {.Protocol, fmt.tprintf("Invalid WaylandShader status: %s", message)} }
number :: proc(object: json.Object, key: string) -> (f64, bool) {
    value, ok := object[key].(json.Float)
    return value, ok && !math.is_nan(value) && !math.is_inf(value)
}

accept_json :: proc(c: ^Client, source: string) -> Error {
    // QDBusDemarshaller::toStringUnchecked performs QString::fromUtf8 before acceptJson.
    input:=source
    if len(input)>=3 && input[:3]=="\xef\xbb\xbf" { input=input[3:] }
    root, parse_error := common.parse_json(input)
    object, is_object := root.value.(json.Object)
    if parse_error != nil || !is_object {
        common.destroy_document(&root)
        if message, failed := parse_error.?; failed {
            if message == "Out of memory" { return {.Transport, message} }
            return invalid(fmt.tprintf("expected a JSON object: %s", message))
        }
        return invalid("expected a JSON object: no error occurred")
    }
    next: Status
    next.json = root
    accepted := false
    defer if !accepted { free_status(&next) }
    for field in ([]string{"enabled", "active", "loading"}) {
        if _, ok := object[field].(json.Boolean); !ok { return invalid(fmt.tprintf("%s must be boolean.", field)) }
    }
    for field in ([]string{"preset", "requestedPreset", "error"}) {
        if _, ok := common.json_string_value(&next.json,object[field]); !ok { return invalid(fmt.tprintf("%s must be a string.", field)) }
    }
    parameters, params_ok := object["parameters"].(json.Array)
    outputs, outputs_ok := object["outputs"].(json.Array)
    if !params_ok || !outputs_ok { return invalid("parameters and outputs must be arrays.") }
    next.enabled = object["enabled"].(json.Boolean)
    next.active = object["active"].(json.Boolean)
    next.loading = object["loading"].(json.Boolean)
    next.preset, _ = common.json_string_value(&next.json,object["preset"])
    next.requested_preset, _ = common.json_string_value(&next.json,object["requestedPreset"])
    next.error, _ = common.json_string_value(&next.json,object["error"])
    if recent_value, present := object["recentPresets"]; present {
        recent, ok := recent_value.(json.Array)
        if !ok { return invalid("recentPresets must be an array.") }
        allocation_error: runtime.Allocator_Error
        next.recent_presets, allocation_error = make([]string, len(recent))
        if allocation_error != nil { return {.Transport, "Out of memory"} }
        for entry, i in recent {
            path, string_ok := common.json_string_value(&next.json,entry)
            if !string_ok || path == "" { return invalid("recent preset must be a nonempty string.") }
            next.recent_presets[i] = path
        }
    }
    allocation_error: runtime.Allocator_Error
    next.parameters, allocation_error = make([]Parameter, len(parameters))
    if allocation_error != nil { return {.Transport, "Out of memory"} }
    for entry, i in parameters {
        row, ok := entry.(json.Object)
        if !ok { return invalid("parameter must be an object.") }
        name, name_ok := common.json_string_value(&next.json,row["name"])
        description, desc_ok := common.json_string_value(&next.json,row["description"])
        if !name_ok || name == "" || !desc_ok { return invalid("parameter name/description must be strings; name must not be empty.") }
        for key in ([]string{"minimum", "maximum", "step", "default", "value"}) {
            if _, valid := number(row, key); !valid { return invalid(fmt.tprintf("parameter %s must be finite numeric data.", key)) }
        }
        p := Parameter{name=name, description=description, minimum=row["minimum"].(json.Float), maximum=row["maximum"].(json.Float), step=row["step"].(json.Float), default_value=row["default"].(json.Float), value=row["value"].(json.Float)}
        duplicate := false
        for old in next.parameters[:i] { if old.name == name { duplicate = true; break } }
        if duplicate || p.minimum > p.maximum || p.step < 0 || p.value < p.minimum || p.value > p.maximum || p.default_value < p.minimum || p.default_value > p.maximum {
            return invalid(fmt.tprintf("duplicate parameter or invalid bounds: %s", name))
        }
        next.parameters[i] = p
    }
    next.outputs, allocation_error = make([]Output, len(outputs))
    if allocation_error != nil { return {.Transport, "Out of memory"} }
    for entry, i in outputs {
        row, ok := entry.(json.Object)
        if !ok { return invalid("output must be an object.") }
        id, id_ok := common.json_string_value(&next.json,row["id"])
        name, name_ok := common.json_string_value(&next.json,row["name"])
        if !id_ok || id == "" || !name_ok { return invalid("output id/name must be strings; id must not be empty.") }
        for key in ([]string{"shaderEnabled", "colorEnabled", "shaderActive", "colorActive"}) {
            if _, valid := row[key].(json.Boolean); !valid { return invalid(fmt.tprintf("output %s must be boolean.", key)) }
        }
        for key in ([]string{"gamma", "saturation"}) {
            if _, valid := number(row, key); !valid { return invalid(fmt.tprintf("output %s must be finite numeric data.", key)) }
        }
        bypass := ""
        if value, present := row["bypass"]; present {
            var_ok: bool
            bypass, var_ok = common.json_string_value(&next.json,value)
            if !var_ok { return invalid("output bypass must be a string.") }
        }
        o := Output{id=id, name=name, bypass=bypass, shader_active=row["shaderActive"].(json.Boolean), color_active=row["colorActive"].(json.Boolean), settings={gamma=row["gamma"].(json.Float), saturation=row["saturation"].(json.Float), shader_enabled=row["shaderEnabled"].(json.Boolean), color_enabled=row["colorEnabled"].(json.Boolean)}}
        duplicate := false
        for old in next.outputs[:i] { if old.id == id { duplicate = true; break } }
        if duplicate || o.settings.gamma < common.MIN_GAMMA || o.settings.gamma > common.MAX_GAMMA || o.settings.saturation < common.MIN_SATURATION || o.settings.saturation > common.MAX_SATURATION {
            return invalid(fmt.tprintf("duplicate output id or invalid bounds: %s", id))
        }
        next.outputs[i] = o
    }
    previous := c.status
    c.status = next
    c.has_status = true
    accepted = true
    // Keep the replaced JSON alive through a reentrant listener call.
    defer free_status(&previous)
    if c.on_status != nil { c.on_status(c.listener, &c.status) }
    return {}
}
