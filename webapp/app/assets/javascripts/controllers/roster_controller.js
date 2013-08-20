angular.module("app.controllers")
.controller('RosterController', ['$scope', '$routeParams', '$location', function($scope, $routeParams, $location) {

  $scope.fs.players.list($scope.roster.market_id).then(function(players) {
    $scope.players = players;
  });

}]);



