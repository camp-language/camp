;; Keywords
[
  "if" "else" "match" "effect" "trait" "is" "alias"
  "handle" "intercept" "with" "import" "exposing"
  "as" "and" "or" "not" "expect" "test"
  "return" "crash"
] @keyword

;; Types
(type_identifier) @type

;; Constructors
(tag_expression name: (type_identifier) @constructor)

;; Variables
(identifier) @variable

;; String
(string) @string

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
