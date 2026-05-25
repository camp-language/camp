package diagnostics

import "camp:base"

import "core:encoding/json"
import "core:fmt"
import "core:os"

@(private="file")
g_json_mode: bool = false

set_json_mode :: proc(enabled: bool) {
	g_json_mode = enabled
}

is_json_mode :: proc() -> bool {
	return g_json_mode
}

@(private="file")
severity_string :: proc(c: Diagnostic_Category) -> string {
	switch c {
	case .Error:    return "error"
	case .Warning:  return "warning"
	case .Internal: return "internal"
	}
	return "error"
}

@(private="file")
span_to_object :: proc(source: string, span: base.Source_Span) -> json.Object {
	obj := make(json.Object, 6)
	obj["start"] = json.Integer(span.start)
	obj["end"] = json.Integer(span.end)
	if span.file_id >= 0 && len(source) > 0 {
		line, col := diag_span_to_line_col(source, span)
		end_line, end_col := span_end_to_line_col(source, span)
		obj["line"] = json.Integer(line)
		obj["col"] = json.Integer(col)
		obj["end_line"] = json.Integer(end_line)
		obj["end_col"] = json.Integer(end_col)
	}
	return obj
}

@(private="file")
diagnostic_to_object :: proc(d: Diagnostic, source: string) -> json.Object {
	obj := make(json.Object, 8)
	obj["severity"] = json.String(severity_string(d.category))
	obj["code"] = json.String(d.code)
	obj["title"] = json.String(d.title)
	obj["message"] = json.String(d.message)

	if d.span.file_id >= 0 {
		obj["span"] = span_to_object(source, d.span)
	}

	labels := make(json.Array, 0, len(d.labels))
	for label in d.labels {
		lo := make(json.Object, 2)
		lo["span"] = span_to_object(source, label.span)
		lo["message"] = json.String(label.label)
		append(&labels, lo)
	}
	obj["labels"] = labels

	hints := make(json.Array, 0, len(d.hints))
	for hint in d.hints {
		append(&hints, json.String(hint))
	}
	obj["hints"] = hints

	return obj
}

render_all_json :: proc(collector: ^Diagnostic_Collector, file_path: string, source: string) {
	root := make(json.Object, 4)
	root["ok"] = json.Boolean(!diag_collector_has_errors(collector))
	root["file"] = json.String(file_path)

	summary := make(json.Object, 3)
	summary["errors"] = json.Integer(collector.error_count)
	summary["warnings"] = json.Integer(collector.warning_count)
	summary["internal"] = json.Integer(collector.internal_count)
	root["summary"] = summary

	diags := make(json.Array, 0, len(collector.diagnostics))
	for d in collector.diagnostics {
		append(&diags, diagnostic_to_object(d, source))
	}
	root["diagnostics"] = diags

	bytes, err := json.marshal(root, {pretty = false})
	if err != nil {
		fmt.eprintfln("internal: failed to marshal diagnostics: {}", err)
		return
	}
	defer delete(bytes)
	os.write(os.stdout, bytes)
	os.write(os.stdout, []u8{'\n'})
}
