package camp

import "core:fmt"

Error_Category :: enum {
	Warning,
	Error,
	Internal,
}

Error :: struct {
	category: Error_Category,
	message:  string,
	span:     Source_Span,
}

Error_Collector :: struct {
	errors:          [dynamic]Error,
	warning_count:   int,
	error_count:     int,
	internal_count:  int,
}

collector_init :: proc(collector: ^Error_Collector) {
	collector.errors = make([dynamic]Error, 0, 64)
	collector.warning_count = 0
	collector.error_count = 0
	collector.internal_count = 0
}

collector_destroy :: proc(collector: ^Error_Collector) {
	delete(collector.errors)
}

collector_add :: proc(collector: ^Error_Collector, category: Error_Category, message: string, span: Source_Span) {
	append(&collector.errors, Error{category, message, span})
	switch category {
	case .Warning:  collector.warning_count += 1
	case .Error:    collector.error_count += 1
	case .Internal: collector.internal_count += 1
	}
}

collector_has_errors :: proc(collector: ^Error_Collector) -> bool {
	return collector.error_count > 0 || collector.internal_count > 0
}
