angular.module("app.controllers")
.controller('RosterController', ['$scope', '$routeParams', '$location', 'flash', function($scope, $routeParams, $location, flash) {
  $scope.filter = null;

  var updatePlayers = function() {
    if (!$scope.roster) {
      return;
    }

    // One time initializer
    var existingPlayers = $scope.roster.players;
    $scope.roster.players = [];
    $scope.positionList = $scope.roster.positions.split(',');
    $scope.uniqPositionList = _.uniq($scope.roster.positions.split(','));
    _.each($scope.positionList, function(str) {
      $scope.roster.players.push({position: str});
    });
    _.each(existingPlayers, function(p) {
      $scope.addPlayer(p, true);
    });
  };
  $scope.$watch('roster', updatePlayers);

  var filterOpts = {};
  var fetchPlayers = function() {
    if (!$scope.roster) { return; }
    $scope.fs.players.list($scope.roster.id, filterOpts).then(function(players) {
      $scope.players = players;
    });
  };

  fetchPlayers();

  var fetchRoster = function() {
    if (!$scope.roster) {
      return;
    }
    $scope.fs.rosters.show($scope.roster.id).then(function(roster){
      $scope.setRoster(roster);
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



  $scope.addPlayer = function(player, init) {
    var index = _.findIndex($scope.roster.players, function(p) { return p.position == player.position && !p.id; });
    if (index >= 0) {
      if (init) { // Used for adding initial players from an existing roster
        $scope.roster.players[index] = player;
      } else {
        $scope.fs.rosters.add_player($scope.roster.id, player.id).then(function(market_order) {
          $scope.roster.remaining_salary -= market_order.price;
          player.purchase_price = market_order.price;
          player.sell_price = market_order.price;
          $scope.roster.players[index] = player;
        });
      }
    } else {
      flash.error = "No room for another " + player.position + " in your roster.";
    }
  };

  $scope.removePlayer = function(player) {
    $scope.fs.rosters.remove_player($scope.roster.id, player.id).then(function(market_order) {
      $scope.roster.remaining_salary = parseFloat($scope.roster.remaining_salary) + parseFloat(market_order.price);
      var index = _.findIndex($scope.roster.players, function(p) { return p.id === player.id; });
      $scope.roster.players[index] = {position: player.position};
    });
  };

  $scope.notInRoster = function(player) {
    if (!$scope.roster) {
      return true;
    }
    return !_.any($scope.roster.players, function(p) { return p.id === player.id; });
  };

  // Super simple validation function. We don't actually care what's in here
  $scope.isValidRoster = function() {
    if (!$scope.roster || _.filter($scope.roster.players, function(p) { return p.id }).length < 1) {
      return false;
    }
    return true;
  };

  $scope.submitRoster = function() {
    $scope.fs.rosters.submit($scope.roster.id).then(function(roster) {
      $scope.setRoster(null, true);
      $scope.setJustSubmittedRoster(roster);
    });
  };

}]);



