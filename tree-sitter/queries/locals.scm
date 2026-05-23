;; Variable definitions
(const_declaration
  name: (identifier) @definition.variable)

;; Lambda parameter definitions
(lambda_parameter
  name: (identifier) @definition.variable)

;; For-loop variable definitions (par for)
(par_expression
  var: (identifier) @definition.variable)

;; Type parameter definitions
(type_parameters
  (identifier) @definition.type_parameter)

;; References
(identifier) @reference
