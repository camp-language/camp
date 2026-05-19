;; Function/const definitions
(const_declaration
  name: (identifier) @name) @definition.function

;; Effect definitions
(effect_declaration
  name: (type_identifier) @name) @definition.type

;; Trait definitions
(trait_declaration
  name: (type_identifier) @name) @definition.type

;; Alias definitions
(alias_declaration
  name: (type_identifier) @name) @definition.type
