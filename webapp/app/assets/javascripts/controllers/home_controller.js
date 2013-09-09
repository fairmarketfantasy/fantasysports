angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', function($scope, rosters) {
  $scope.rosters = rosters;
  rosters.fetchMine();
}]);

