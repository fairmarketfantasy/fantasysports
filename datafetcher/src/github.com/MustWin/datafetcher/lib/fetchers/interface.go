package fetchers

import "io"

type FetchMethod interface {
	GetSport() string
	Fetch(string) io.ReadCloser
	AddUrlParam(string, string)
}
