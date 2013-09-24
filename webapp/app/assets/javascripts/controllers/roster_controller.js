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
      fetchContest();
    });
  });
  $scope.$watch('$routeParams.opponent_roster_id', function() {
    if ($routeParams.opponent_roster_id) {
      rosters.fetch($routeParams.opponent_roster_id).then(function(roster) {
        rosters.selectOpponentRoster(roster);
      });
    } else {
      rosters.selectOpponentRoster(null);
    }
  });

  var fetchRosters = function() {
    if (rosters.currentRoster) {
      $scope.fs.rosters.show(rosters.currentRoster.id).then(function(roster){
        rosters.selectRoster(roster);
      });
    }
    if (rosters.opponentRoster) {
      $scope.fs.rosters.show(rosters.opponentRoster.id).then(function(roster){
        rosters.selectOpponentRoster(roster);
      });
    }
  };

  var fetchContest = function() {
    if (!rosters.currentRoster.contest_id) { return; }
    rosters.fetchContest(rosters.currentRoster.contest_id).then(function(rosters) {
      $scope.leaderboard = rosters;
    });
  };

  rosters.setPoller(function() {
      fetchPlayers();
      fetchRosters();
      fetchContest();
    }, 10000);

  $scope.filterPlayers = function(opts, override) {
    rosters.selectOpponentRoster(null);
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

  $scope.isInPlay = function(roster) {
    if (!$scope.market) { return; }
    return $scope.market.state != 'published' && roster.state != 'in_progress';
  };

  $scope.enterAgain = function() {
    $scope.fs.contests.join(rosters.currentRoster.contest_type.id, rosters.currentRoster.id).then(function(data) {
      rosters.selectRoster(data);
      flash.success = "Awesome, we've re-added all the players from your last roster. Go ahead and customize then enter again!";
      $location.path('/market/' + $scope.market.id + '/roster/' + data.id);
    });
  };

}]);



