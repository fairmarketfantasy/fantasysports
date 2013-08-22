angular.module("app.controllers")
.controller('RosterController', ['$scope', '$routeParams', '$location', 'flash', function($scope, $routeParams, $location, flash) {

  var updatePlayers = function() {
    if (!$scope.roster) {
      return;
    }
    $scope.fs.players.list($scope.roster.market_id).then(function(players) {
      $scope.players = players;
    });

    // One time initializer
    $scope.roster.players = [];
    $scope.position_list = $scope.roster.positions.split(',');
    _.each($scope.position_list, function(str) {
      $scope.roster.players.push({position: str});
    });
  };
  $scope.$watch('roster', updatePlayers);

  $scope.addPlayer = function(player) {
    var index = _.findIndex($scope.roster.players, function(p) { return p.position == player.position && !p.id; })
    if (index >= 0) {
      $scope.fs.rosters.add_player($scope.roster.id, player.id).then(function(market_order) {
        $scope.roster.remaining_salary -= market_order.price;
        player.purchase_price = market_order.price;
        $scope.roster.players[index] = player;
      });
    } else {
      flash.error = "No room for another " + player.position + " in your roster.";
    }
  };

  $scope.removePlayer = function(player) {
    $scope.fs.rosters.remove_player($scope.roster.id, player.id).then(function(market_order) {
      $scope.roster.remaining_salary += market_order.price;
      var index = _.findIndex($scope.players, function(p) { return p.id == player.id; })
      $scope.roster.players[index] = {position: player.position};
    });
  };

  $scope.notInRoster = function(player) {
    return !_.any($scope.roster.players, function(p) { return p.id == player.id });
  };

  var isValidRoster = function() {
    return _.all($scope.roster.players, function(p) { return p.id });
  }

}]);



