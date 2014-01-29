package model

import (
//  "log"
)

type Model interface {
	Valid() bool
	Errors() []error
	BeforeSave(Orm, Model) (error, bool)
	AfterSave(Orm, Model) error
}

type ModelBase struct {
}

func (m *ModelBase) Valid() bool {
	return true
}

func (m *ModelBase) Errors() []error {
	return nil
}

func (m *ModelBase) BeforeSave(Orm, Model) (error, bool) {
	return nil, true
}

func (m *ModelBase) AfterSave(Orm, Model) error {
	return nil
}
