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
      $('.twitter-share').each(function(i, elt) {
        twttr.widgets.createShareButton(
          'https://fairmarketfantasy.com/public/#/market/' +
              (($scope.$routeParams && $scope.$routeParams.market_id) || $scope.roster.market_id)  + '/roster/' +
              (($scope.$routeParams && $scope.$routeParams.roster_id) || $scope.roster.id) + '?view_code=' +
              (($scope.$routeParams && $scope.$routeParams.view_code) || ($scope.roster && $scope.roster.view_code )),
          elt,
          function (el) {
            console.log("Button created.")
          },
          {
            count: 'none',
            text: 'I built an epic roster on FairMarketFantasy. Check it out! #fantasyfootball #dfs',
            size: 'large'
          }
        );
      })

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
        if ($scope.noReport) { return; }
        $('.twitter-follow').parent().find('h3').addClass('success');
        $scope.addBonus('twitter_follow');
      });
      twttr.events.bind('tweet', function (event) {
        if ($scope.noReport) { return; }
        $('.twitter-share').parent().find('h3').addClass('success');
        $scope.addBonus('twitter_share');
      });
    }, 100); // hacky.  Should really wait for roster
  });
}]);

