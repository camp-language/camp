## MODIFIED Requirements

### Requirement: Self is a built-in type variable
`Self` SHALL be a built-in type variable in trait method signatures. During `is` verification, `Self` SHALL be unified with the implementing type. `Self` is not a free type variable — it is always resolved to the implementing type. A trait method signature MAY reference `Self` in parameter and return types.

#### Scenario: Self resolved during trait conformance check
- **WHEN** checking `@UserId is Eq : U64` and the `Eq` trait defines `eq: |Self, Self| -> Bool`
- **THEN** `Self` is unified with `UserId`, producing the expected signature `|UserId, UserId| -> Bool`

#### Scenario: Self in return type
- **WHEN** a trait defines `factory: || -> Self`
- **THEN** for `@Widget is Factory`, `Self` resolves to `Widget` and the method must return `Widget`
