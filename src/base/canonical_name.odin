package base

NO_NAME :: Intern_ID(-1)

Canonical_Name :: struct {
	module:   Intern_ID,
	name:     Intern_ID,
	is_local: bool,
}

Deferred_Import :: struct {
	module:           Intern_ID,
	exposing:         [dynamic]Intern_ID,
	nominal_exposing: [dynamic]Import_Nominal_Expose,
	alias:            Intern_ID,
	is_unsafe:        bool,
	span:             Source_Span,
}

Import_Nominal_Expose :: struct {
	type_name: Intern_ID,
	variants:  [dynamic]Intern_ID,
}
