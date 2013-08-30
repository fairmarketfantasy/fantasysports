package fetchers

import (
	"io"
	"io/ioutil"
	"log"
	"time"

	"crypto/tls"
	"github.com/mreiferson/go-httpclient"
	"net/http"
	"net/url"
)

// Configure the HTTP client

var transport = &httpclient.Transport{
	ConnectTimeout:        5 * time.Second,
	ResponseHeaderTimeout: 5 * time.Second,
	RequestTimeout:        12 * time.Second,
	TLSClientConfig:       &tls.Config{InsecureSkipVerify: true},
}

var client = &http.Client{
	Transport: transport,
}

// You must close the returned value
func makeRequestWithRetries(u string, tries int) io.ReadCloser {
	req, _ := http.NewRequest("GET", u, nil)
	req.Header.Add("User-Agent", "fair-fantasy-sports/fetcher")
	resp, err := client.Do(req)
	if err != nil {
		// This handles timeouts, 500s, etc
		if tries > 0 {
			return makeRequestWithRetries(u, tries-1)
		} else {
			//    if (resp.StatusCode != 200) {
			defer resp.Body.Close()
			body, err := ioutil.ReadAll(resp.Body)
			log.Panicf("Request to %s failed: returned status code %i\nBody:\n%s", u, resp.StatusCode, body)
			//   }
			log.Panicf("Request to %s failed: %s\n", u, err)
		}
	}
	return resp.Body
}

func makeRequest(u string) io.ReadCloser {
	log.Println(u)
	// Set the SportsData API key
	urlObj, err := url.Parse(u)
	if err != nil {
		log.Printf("Failed to parse url %s: %s\n", u, err)
	}
	query := urlObj.Query()
	query.Add("api_key", "un32n24mu43xpmk594dzvm2p")
	urlObj.RawQuery = query.Encode()

	return makeRequestWithRetries(urlObj.String(), 1)
}

func HttpFetcher(u string) io.ReadCloser {
	return makeRequest(u)
}
