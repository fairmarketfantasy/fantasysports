angular.module("app.controllers")
.controller('RosterListController', ['$scope', 'rosters', 'markets', 'flash', function($scope, rosterService, markets, flash) {
  $scope.rosterService = rosterService;
  rosterService.fetchMine();
  rosterService.setPoller(function() { rosters.fetchMine(); }, 10000);
}]);

