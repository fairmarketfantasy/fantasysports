angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', function($scope, rosters, $routeParams, $location, marketService) {
  $scope.marketService = marketService;

  marketService.fetchUpcoming($routeParams.market_id);
  $scope.rosters = rosters;

  $scope.isCurrent = function(market){
    return (market.id === marketService.currentMarket.id);
  };

  var reloadMarket = function() {
    if (!marketService.currentMarket) {
      return;
    }
    marketService.gamesFor(marketService.currentMarket.id).then(function(games) {
      $scope.games = games;
    })

    $scope.fs.contests.for_market(marketService.currentMarket.id).then(function(contestTypes) {
      $scope.contestClasses = {};
      _.each(contestTypes, function(type) {
        if (!$scope.contestClasses[type.name]) {
          $scope.contestClasses[type.name] = [];
        }
        $scope.contestClasses[type.name].push(type);
      });
    });
  }
  $scope.$watch('marketService.currentMarket', reloadMarket);

  $scope.contestClassDesc = {
    'h2h': "Challenge your friends to head to head games and channel some truly intimate aggression.",
    '194': "Top half doubles their money - all you have to do is be better than average.  You are that, right?",
    '970': "High stakes, winner takes all. This is for the true champions.",
    '100k': "THE LOLLAPALOOZA.  It's like a lottery, because you win lots of money.",
  };

  $scope.day = function(timeStr) {
    var day = moment(timeStr);
    return day.format("ddd, MMM Do , h:mm a");
  };

  $scope.joinContest = function(contestType) {
    $scope.fs.contests.join(contestType.id, rosters.justSubmittedRoster && rosters.justSubmittedRoster.id).then(function(data){
      rosters.selectRoster(data);
      $location.path('/market/' + marketService.currentMarket.id + '/roster/' + data.id);
    });
  };

  $scope.setJustSubmittedRoster = function(roster) {
    $scope.justSubmittedRoster = roster;
  };

  $scope.cancelRoster = function() {
    var path = '/market/' + marketService.currentMarket.id;
    rosters.cancel();
    $location.path(path);
  };

  $scope.clearJustSubmittedRoster = function() {
    $scope.justSubmittedRoster = null;
    $location.path('/');
    flash.success = "Awesome, You're IN. Good luck!";
  };

}]);
