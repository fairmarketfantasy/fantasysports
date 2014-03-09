angular.module("app.controllers")
.controller('RosterListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', function($scope, rosterService, markets, flash, $routeParams) {
  $scope.rosterService = rosterService;

  rosterService.fetchMine({sport: $routeParams.sport}).then(function() {
    $scope.rosterList = rosterService.top($routeParams.sport);
      console.log($scope.rosterList)
  });
  rosterService.setPoller(function() { rosterService.fetchMine({sport: $scope.currentUser.currentSport}); }, 10000);
}]);

