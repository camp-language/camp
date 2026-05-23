;; Keywords
[
  "if" "else" "match" "effect" "trait" "is" "alias"
  "handle" "intercept" "with" "import" "exposing"
  "as" "and" "or" "not" "expect" "test"
  "return" "crash" "pub" "derives" "par" "for"
  "unsafe" "alias"
] @keyword

;; Types
(type_identifier) @type

;; Constructors
(tag_expression name: (type_identifier) @constructor)

;; Variables
(identifier) @variable

;; Dot lambda method names
(anonymous_method_expression
  name: (identifier) @function.method)

;; String
(string) @string

;; Interpolated strings
(interpolated_string) @string
(interpolated_string
  "${" @punctuation.special)
(interpolated_string
  "}" @punctuation.special)
(interpolated_string expression: (_) @embedded)

;; Integer
(integer) @number

;; Float
(float) @float

;; Boolean
(boolean) @boolean

;; Operators
[
  "+" "-" "*" "/" "%"
  "==" "!=" "<" ">" "<=" ">="
  "=" "->" "|"
] @operator

;; Comments
(comment) @comment

;; Punctuation
[
  "(" ")" "[" "]" "{" "}"
  ":" "," "." ".." "$" "!"
] @punctuation
