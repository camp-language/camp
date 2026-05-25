package base

NO_NAME :: Intern_ID(-1)

Canonical_Name :: struct {
	module:   Intern_ID,
	name:     Intern_ID,
	is_local: bool,
}

Deferred_Import :: struct {
	module:   Intern_ID,
	names:    [dynamic]Intern_ID,
	alias:    Intern_ID,
	span:     Source_Span,
}
