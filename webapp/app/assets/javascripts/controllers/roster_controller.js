angular.module("app.controllers")
.controller('RosterController', ['$scope', 'rosters', 'markets', '$routeParams', '$location', 'flash', function($scope, rosters, markets, $routeParams, $location, flash) {
  $scope.filter = null;
  $scope.rosters = rosters;
  $scope.markets = markets;

  var teamsToGames = {};
  markets.fetch($routeParams.market_id).then(function(market) {
    $scope.market = market;
    markets.selectMarket(market);
    markets.gamesFor(market.id).then(function(games) {
      $scope.games = games;
      _.each(games, function(game) {
        teamsToGames[game.home_team] = game;
        teamsToGames[game.away_team] = game;
      });
    });
  });

  var filterOpts = {};
  var fetchPlayers = function() {
    if (!rosters.currentRoster) { return; }
    $scope.fs.players.list(rosters.currentRoster.id, filterOpts).then(function(players) {
      $scope.players = players;
    });
  };

  fetchPlayers();

  if (!rosters.currentRoster && $routeParams.roster_id) {
    rosters.fetch($routeParams.roster_id).then(function(roster) {
      rosters.selectRoster(roster);
    })
  }

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

  $scope.gameFromTeam = function(team) {
    var game = teamsToGames[team];
    return game && (game.away_team + ' @ ' + game.home_team);
  };

}]);



