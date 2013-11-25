window.twttr = (function (d,s,id) {
  var t, js, fjs = d.getElementsByTagName(s)[0];
  if (d.getElementById(id)) return; js=d.createElement(s); js.id=id;
  js.src="https://platform.twitter.com/widgets.js"; fjs.parentNode.insertBefore(js, fjs);
  return window.twttr || (t = { _e: [], ready: function(f){ t._e.push(f) } });
}(document, "script", "twitter-wjs"));

angular.module("app.controllers")
.controller('TwitterController', ['$scope', '$timeout', 'fs', function($scope, $timeout, fs) {
  twttr.ready(function(twttr) {
    $timeout(function() {
      twttr.widgets.createShareButton(
        'https://fairmarketfantasy.com/contests/join?contest_code=' + $scope.contest.invitation_code,
        $('.twitter-share').get(0),
        function (el) {
          console.log("Button created.")
        },
        {
          count: 'none',
          text: 'I just built a great roster on FairMarketFantasy. Join my league! #fantasyfootball #dfs',
          size: 'large'
        }
      );

      twttr.widgets.createFollowButton(
        'FairMktFantasy',
        $('.twitter-follow').get(0),
        function (el) {
          console.log("Follow button created.")
        },
        {
          size: 'large'
        }
      );

      twttr.events.bind('follow', function (event) {
        $('.twitter-follow').parent().find('h3').addClass('success');
        $scope.addBonus('twitter_follow');
      });
      twttr.events.bind('tweet', function (event) {
        $('.twitter-share').parent().find('h3').addClass('success');
        $scope.addBonus('twitter_share');
      });
    });
  });
}]);

