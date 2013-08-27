package fetchers

import (
  "os"
  "io"
  "io/ioutil"
  "log"
  "strings"
  "path/filepath"
  "time"
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
    for _, dir := range(directories) {
    time.Sleep(1000000)
      if dir.Name() == "data-fetcher" {
        return pwd
      }
    }
    pwd, _ = filepath.Split(strings.TrimRight(pwd, "/\\"))
  }
}
func FileFetcher(url string) io.ReadCloser {
  rootPath := findRoot()
  path := rootPath + "docs/sportsdata/nfl/" + strings.Replace(strings.Replace(url, "http://api.sportsdatallc.org/nfl-t1/", "", 1), "/", "-", -1)
  file, err := os.Open(path)
  if err != nil {
    log.Panicf("Failed to open file at %s", path)
  }
  return file
}
