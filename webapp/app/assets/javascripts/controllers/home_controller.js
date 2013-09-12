angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', function($scope, rosters) {
  $scope.rosters = rosters;
  rosters.fetchMine();
  rosters.setPoller(function() { rosters.fetchMine(); }, 10000);
}]);

