angular.module("app.controllers")
.controller('RosterHistoryController', ['$scope', 'rosters', 'markets', 'flash', 'currentUserService', '$routeParams', function($scope, rosterService, markets, flash, currentUserService, $routeParams) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.history = true;
  $scope.showMore = false;
  var page = 0;
  $scope.rosterList = [];
  $scope.fetchMore = function() {
    $scope.showMore = false;
    page++;
    rosterService.fetchMine({category: $routeParams.category, sport: $routeParams.sport, historical: true, page: page}).then(function(rosters) {

      if (rosters.length > 24) {
        $scope.showMore = true;
      }
      $scope.rosterList = $scope.rosterList.concat(rosters);
    });
  };
  $scope.fetchMore();
}]);


