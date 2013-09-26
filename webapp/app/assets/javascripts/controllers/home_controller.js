angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', '$dialog', function($scope, rosters, $dialog) {
  $scope.rosters = rosters;
  rosters.fetchMine();
  rosters.setPoller(function() { rosters.fetchMine(); }, 10000);

}]);

