angular.module("app.controllers")
.controller('RosterListController', ['$scope', 'rosters', 'markets', 'flash', function($scope, rosterService, markets, flash) {
  $scope.rosterService = rosterService;
  rosterService.fetchMine().then(function() {
    $scope.rosterList = rosterService.top();
  });
  rosterService.setPoller(function() { rosterService.fetchMine(); }, 10000);
}]);

