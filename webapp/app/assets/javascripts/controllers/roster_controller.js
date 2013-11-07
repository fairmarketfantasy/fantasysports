angular.module("app.controllers")
.controller('RosterController', ['$scope', 'rosters', 'markets', '$routeParams', '$location', '$dialog', 'flash', '$templateCache', function($scope, rosters, markets, $routeParams, $location, $dialog, flash, $templateCache) {
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

  $scope.removeLow = true;
  var filterOpts = {position: 'QB', removeLow: true, sort: 'buy_price', dir: 'desc'};
  $scope.getFilterOpts = function() {
    return angular.extend({}, filterOpts);
  };
  var fetchPlayers = function() {
    $scope.filterPosition = filterOpts.position;
    if (!rosters.currentRoster) { return; }
    $scope.fs.players.list(rosters.currentRoster.id, filterOpts).then(function(players) {
      if (filterOpts.removeLow && players.length > 2) {
        players = _.select(players, function(player) { return player.benched_games < 3 && player.status == 'ACT'; });
      }
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

  $scope.toggleChecked = function(checkedN){
    $scope[checkedN] = !$scope[checkedN];
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

    // Override isn't really an override anymore...this could be better
  $scope.filterPlayers = function(opts, override) {
    rosters.selectOpponentRoster(null);
    if (override) {
      filterOpts = angular.extend({sort: filterOpts.sort, dir: filterOpts.dir, removeLow: filterOpts.removeLow}, opts);
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

  $scope.opponentFor = function(player) {
    var game = teamsToGames[player.team];
    return _.find([game.home_team, game.away_team], function(team) { return team != player.team; });
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

  $scope.dayBefore = function(time) {
    return moment(time).subtract('days', 1);
  };

  $scope.createContestFromRosterModal = function(){
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/create_contest_from_roster_dialog.html',
          controller: 'CreateContestFromRosterDialogController'
    }
    var d = $dialog.dialog(dialogOpts);
    d.open();
  };

  $scope.enterAgain = function() {
    $scope.fs.contests.join(rosters.currentRoster.contest_type.id, rosters.currentRoster.id).then(function(data) {
      rosters.selectRoster(data);
      //flash.success = "Awesome, we've re-added all the players from your last roster. Go ahead and customize then enter again!";
      //$location.path('/market/' + $scope.market.id + '/roster/' + data.id);
      $scope.createContestFromRosterModal();
    });
  };

  $scope.addPlayer = function(player) {
    var promise = rosters.addPlayer(player);
    promise && promise.then(function() {
      // Check to see if all slots for this positions are full
      var position = rosters.nextPosition(player);
      if (position) {
        $scope.filterPlayers({position: position}, true);
      }
    });
  };

  $scope.removePlayer = function(player) {
    rosters.removePlayer(player);
    $scope.filterPlayers({position: player.position}, true);
  };

  $scope.record = function(rosters, roster) {
    var wins, losses, ties, i;
    wins = losses = ties = 0;
    while((i= wins + losses + ties) < rosters.length) {
      if (roster.contest_rank > rosters[i].contest_rank) {
        losses += 1;
      } else if (roster.contest_rank < rosters[i].contest_rank ) {
        wins+= 1;
      } else {
        ties += 1;
      }
    }
    return wins + '-' + losses + '-' + ties;
  };

}]);



