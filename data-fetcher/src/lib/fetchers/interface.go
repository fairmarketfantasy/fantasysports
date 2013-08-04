package fetchers

import "io"

type FetchMethod func (string) io.ReadCloser

