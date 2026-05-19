package tree_sitter_camp_test

import (
	"testing"

	tree_sitter "github.com/tree-sitter/go-tree-sitter"
	tree_sitter_camp "github.com/camp-language/camp/tree-sitter/bindings/go"
)

func TestCanLoadGrammar(t *testing.T) {
	language := tree_sitter.NewLanguage(tree_sitter_camp.Language())
	if language == nil {
		t.Errorf("Error loading Camp grammar")
	}
}
