package fetchers

import (
  "log"
  "io"
  "time"

  "net/http"
  "crypto/tls"
  "github.com/mreiferson/go-httpclient"
)

// Configure the HTTP client

var transport = &httpclient.Transport{
  ConnectTimeout: 5 * time.Second,
  ResponseHeaderTimeout: 5 * time.Second,
  RequestTimeout: 12 * time.Second,
  TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
}

var client = &http.Client{
  Transport: transport,
}

// You must close the returned value
func makeRequestWithRetries(url string, tries int) io.ReadCloser {
  req, _ := http.NewRequest("GET", url, nil)
  req.Header.Add("User-Agent", "fair-fantasy-sports/fetcher")
  resp, err := client.Do(req)
  if (err != nil) {
    // This handles timeouts, 500s, etc 
    if (tries > 0) {
      return makeRequestWithRetries(url, tries - 1)
    } else {
      log.Panicf("Request to %s failed: %s\n", url, err)
    }
  }
  if (resp.StatusCode != 200) {
    defer resp.Body.Close()
    log.Panicf("Request to %s failed: returned status code %i\n", url, resp.StatusCode)
  }
  return resp.Body
}

func HttpFetcher(url string) io.ReadCloser {
  return makeRequestWithRetries(url, 1)
}
