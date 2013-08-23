angular.module("app.controllers")
.controller('RosterController', ['$scope', '$routeParams', '$location', 'flash', function($scope, $routeParams, $location, flash) {
  $scope.filter = null;

  var updatePlayers = function() {
    if (!$scope.roster) {
      return;
    }

    $scope.filterPlayers();

    // One time initializer
    var existingPlayers = $scope.roster.players;
    $scope.roster.players = [];
    $scope.positionList = $scope.roster.positions.split(',');
    _.each($scope.positionList, function(str) {
      $scope.roster.players.push({position: str});
    });
    _.each(existingPlayers, function(p) {
      $scope.addPlayer(p, true);
    });
  };
  $scope.$watch('roster', updatePlayers);

  $scope.filterPlayers = function(opts) {
    $scope.fs.players.list($scope.roster.market_id, opts).then(function(players) {
      $scope.players = players;
    });
  };

  $scope.addPlayer = function(player, init) {
    var index = _.findIndex($scope.roster.players, function(p) { return p.position == player.position && !p.id; });
    if (index >= 0) {
      if (init) { // Used for adding initial players from an existing roster
        $scope.roster.players[index] = player;
      } else {
        $scope.fs.rosters.add_player($scope.roster.id, player.id).then(function(market_order) {
          $scope.roster.remaining_salary -= market_order.price;
          player.purchase_price = market_order.price;
          $scope.roster.players[index] = player;
        });
      }
    } else {
      flash.error = "No room for another " + player.position + " in your roster.";
    }
  };

  $scope.removePlayer = function(player) {
    $scope.fs.rosters.remove_player($scope.roster.id, player.id).then(function(market_order) {
      $scope.roster.remaining_salary += market_order.price;
      var index = _.findIndex($scope.players, function(p) { return p.id === player.id; });
      $scope.roster.players[index] = {position: player.position};
    });
  };

  $scope.notInRoster = function(player) {
    return !_.any($scope.roster.players, function(p) { return p.id === player.id; });
  };

  var isValidRoster = function() {
    return _.all($scope.roster.players, function(p) { return p.id; });
  };

}]);



