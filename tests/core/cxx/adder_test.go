package objc

import (
	"fmt"
	"math/rand"
	"testing"
)

func TestCPPAdder(t *testing.T) {
	a := rand.Int31()
	b := rand.Int31()
	expected := a + b
	if result := Add(a, b); result != expected {
		t.Error(fmt.Errorf("wrong result: got %d, expected %d", result, expected))
	}
	if result := AddLambda(a, b); result != expected {
		t.Error(fmt.Errorf("wrong result: got %d, expected %d", result, expected))
	}
}
