package fetchers

import (
	"io"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	//"time"
)

/* This receives a url like so: http://api.sportsdatallc.org/nfl-t1/2012/REG/standings.xml
This strips of the first part there and translates it into a file path at /docs/sportsdata/nfl/2012-REG-standings.xml
*/

var root string

func findRoot() string {
	if root != "" {
		return root
	}
	pwd, _ := os.Getwd()
	for {
		directories, _ := ioutil.ReadDir(pwd)
		for _, dir := range directories {
			if dir.Name() == "datafetcher" {
				return pwd
			}
		}
		pwd, _ = filepath.Split(strings.TrimRight(pwd, "/\\"))
	}
}

type FileFetcher struct {
	Sport string
}

func (f *FileFetcher) GetSport() string {
	return f.Sport
}

func (f *FileFetcher) Fetch(url string) io.ReadCloser {
	rootPath := findRoot()
	regex, _ := regexp.Compile("http://api.sportsdatallc.org/.*?/")
	cleanUrl := regex.ReplaceAllLiteralString(url, "")
	path := rootPath + "docs/sportsdata/" + strings.ToLower(f.Sport) + "/" + strings.Replace(cleanUrl, "/", "-", -1)
	file, err := os.Open(path)
	if err != nil {
		log.Panicf("Failed to open file at %s", path)
	}
	return file
}

func (f *FileFetcher) AddUrlParam(key string, val string) {
}
