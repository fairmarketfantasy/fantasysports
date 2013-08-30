package lib

import (
	"testing"
	"fmt"
)

//test the beedb model. mostly for my own edification
func TestGetDb(t *testing.T) {
	orm, attrs := DbInit("")
	if orm == nil {
		t.Errorf("should be able to get orm")
	}

	orm, attrs = DbInit("NFL")
	if orm == nil {
		t.Errorf("Run rake db:seed to add NFL to database")
	}
	fmt.Printf("attributes: %v\n", attrs)

}

