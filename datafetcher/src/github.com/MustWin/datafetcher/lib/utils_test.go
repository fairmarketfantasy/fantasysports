package lib

import (
	"fmt"
	"testing"
)

func TestCamelCase(t *testing.T) {
	camel := CamelCase("snake_case")
	fmt.Println(camel)
	if camel != "SnakeCase" {
		t.Errorf("Expected SnakeCase, got %v", camel)
	}
	camel = CamelCase("more_snake_tests")
	if camel != "MoreSnakeTests" {
		t.Errorf("Expected MoreSnakeTests, got %v", camel)
	}
}

func TestSnakeCase(t *testing.T) {
	snake := SnakeCase("CamelCase")
	if snake != "camel_case" {
		t.Errorf("Expected camel_case, got %v", snake)
	}
	snake = SnakeCase("moreBizarreCase")
	if snake != "more_bizarre_case" {
		t.Errorf("Expected more_bizarre_case, got %v", snake)
	}
	snake = SnakeCase("HandleλCalculus")
	if snake != "handleλ_calculus" {
		t.Errorf("Expected handleλ_calculus, got %v", snake)
	}

}
