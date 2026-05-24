package base

Source_Span :: struct {
	file_id: int,
	start:   int,
	end:     int,
}

Source_Span_ZERO :: Source_Span{-1, 0, 0}

Source_File :: struct {
	path:     string,
	contents: string,
	id:       int,
}
