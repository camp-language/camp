package camp

JSON_RPC_Version :: "2.0"

JSON_RPC_Error_Code :: enum int {
	ParseError     = -32700,
	InvalidRequest = -32600,
	MethodNotFound = -32601,
	InvalidParams  = -32602,
	InternalError  = -32603,
}

JSON_RPC_Error :: struct {
	code:    int,
	message: string,
}
