angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', function($scope, rosters, $routeParams, $location, marketService) {
  $scope.marketService = marketService;

  marketService.fetchUpcoming($routeParams.market_id);
  $scope.rosters = rosters;


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
  $scope.$watch('$routeParams.market_id', function() {
    if ($routeParams.market_id) {
      marketService.selectMarket($routeParams.market_id);
    }
  });

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
