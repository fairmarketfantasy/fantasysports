angular.module("app.controllers")
.controller('RosterController', ['$scope', 'rosters', '$routeParams', '$location', 'flash', function($scope, rosters, $routeParams, $location, flash) {
  $scope.filter = null;
  $scope.rosters = rosters;
  //$scope.$watch('roster', updatePlayers);

  var filterOpts = {};
  var fetchPlayers = function() {
    if (!rosters.currentRoster) { return; }
    $scope.fs.players.list(rosters.currentRoster.id, filterOpts).then(function(players) {
      $scope.players = players;
    });
  };

  fetchPlayers();

  var fetchRoster = function() {
    if (!rosters.currentRoster) {
      return;
    }
    $scope.fs.rosters.show(rosters.currentRoster.id).then(function(roster){
      rosters.selectRoster(roster);
    });
  };

  if ($scope.pollInterval === undefined) {
    $scope.pollInterval = setInterval(function() {
      fetchPlayers();
      fetchRoster();
    }, 5000);
  }

  $scope.filterPlayers = function(opts) {
    filterOpts = opts;
    fetchPlayers();
  };

  // Super simple validation function. We don't actually care what's in here
  $scope.isValidRoster = function() {
    if (!rosters.currentRoster || _.filter(rosters.currentRoster.players, function(p) { return p.id }).length < 1) {
      return false;
    }
    return true;
  };

  $scope.notInRoster = function(player) {
    if (!rosters.currentRoster) {
      return true;
    }
    return !_.any(rosters.currentRoster.players, function(p) { return p.id === player.id; });
  };
}]);



