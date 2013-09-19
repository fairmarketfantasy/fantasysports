angular.module("app.controllers")
.controller('RosterController', ['$scope', 'rosters', 'markets', '$routeParams', '$location', 'flash', '$templateCache', function($scope, rosters, markets, $routeParams, $location, flash, $templateCache) {
  $scope.filter = 'positions';
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

  var filterOpts = {position: 'QB'};
  var fetchPlayers = function() {
    if (!rosters.currentRoster) { return; }
    $scope.fs.players.list(rosters.currentRoster.id, filterOpts).then(function(players) {
      $scope.players = players;
    });
  };

  $scope.$watch('$routeParams.roster_id', function() {
    rosters.fetch($routeParams.roster_id).then(function(roster) {
      rosters.selectRoster(roster);
      fetchPlayers();
    });
  });

  var fetchRoster = function() {
    if (!rosters.currentRoster) {
      return;
    }
    $scope.fs.rosters.show(rosters.currentRoster.id).then(function(roster){
      rosters.selectRoster(roster);
    });
  };

  rosters.setPoller(function() {
      fetchPlayers();
      fetchRoster();
    }, 10000);

  $scope.filterPlayers = function(opts, override) {
    if (override) {
      filterOpts = opts;
    } else {
      if (filterOpts.sort == opts.sort) {
        filterOpts.dir = filterOpts.dir == "desc" ? 'asc' : 'desc';
      }
      filterOpts = angular.extend(filterOpts, opts);
    }
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

  $scope.teams  = function() {
    return _.map(teamsToGames, function(game, team) { return team; });
  };

  $scope.notStartedGames = function() {
    return _.filter($scope.games, function(game) {
      return !$scope.gameStarted(game);
    });
  };

  $scope.fetchPlayerStats = function(player) {
    return $scope.fs.events.for_players($scope.market.id, [player]).then(function(events) {
      $scope.playerStats = events;
      return events;
    });
  };

  $scope.statsContent = function() {
    // This is particularly disgusting, but I couldn't figure out a better way to do it.
    // It's impossible to compile templates and use the content without rendering to the dom.
    return angular.element('#player-stats-content')[0].innerHTML;
  };

}]);



