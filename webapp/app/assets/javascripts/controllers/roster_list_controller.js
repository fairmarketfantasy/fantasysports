angular.module("app.controllers")
.controller('RosterListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', function($scope, rosterService, markets, flash, $routeParams) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.history = true;
  $scope.showMore = false;
  var page = 0;
  $scope.rosterList = [];
  $scope.fetchMore = function() {
    $scope.showMore = false;
    page++;
    rosterService.fetchMine({sport: $routeParams.sport, page: page}).then(function(rosters) {
      if (rosters.length > 24) {
          $scope.showMore = true;
      }
      $scope.rosterList = $scope.rosterList.concat(rosters);
    });
  };
  $scope.fetchMore();
}]);

