angular.module("app.controllers")
.controller('RosterController', ['$scope', 'rosters', 'markets', '$routeParams', '$location', '$dialog', '$timeout', 'flash', '$templateCache', 'markets','currentUserService',
            function($scope, rosters, markets, $routeParams, $location, $dialog, $timeout, flash, $templateCache, marketService, currentUserService) {
  $scope.filter = 'positions';
  $scope.rosters = rosters;
  $scope.markets = markets;
  $scope.landingShow = false;

  $scope.Math = window.Math;

    if(!marketService.upcoming[0]){
        marketService.fetchUpcoming({type: 'single_elimination', category:$routeParams.category, sport: currentUserService.currentUser.currentSport}).then(function() {
            marketService.fetchUpcoming({type: 'regular_season', category:currentUserService.currentUser.currentCategory, sport: currentUserService.currentUser.currentSport}).then(function() {
                if ($routeParams.market_id) {
                    marketService.selectMarketId($routeParams.market_id, currentUserService.currentUser.currentCategory, currentUserService.currentUser.currentSport);
                } else if ($location.path().match(/\w+\/playoffs/)) {
                    marketService.selectMarketType('single_elimination', currentUserService.currentUser.currentCategory, currentUserService.currentUser.currentSport);
                } else {
                    marketService.selectMarketType('regular_season', currentUserService.currentUser.currentCategory, currentUserService.currentUser.currentSport);
                }
            });
        });
    }

    $scope.isCurrent = function(market){
        if (!market) { return; }
        if (!marketService.currentMarket) {
            flash.error("Oops, we couldn't find that market, pick a different one.");
            $location.path('/' +  currentUserService.currentUser.currentCategory + '/'+ currentUserService.currentUser.currentSport + '/home');
            return;
        }
        return (market.id === marketService.currentMarket.id);
    };

  var teamsToGames = {};
  $scope.startMarket = function(){
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
  }

  $scope.startMarket();

  $scope.removeLow = false;
  var filterOpts = {position: rosters.uniqPositionList && rosters.uniqPositionList[0], removeLow: false, sort: 'buy_price', dir: 'desc'};
  $scope.getFilterOpts = function() {
    return angular.extend({}, filterOpts);
  };
  var fetchPlayers = function() {
    // This is hideous, and all it does is set the default position
    filterOpts.position = filterOpts.position || (!filterOpts.game && !filterOpts.autocomplete && rosters.uniqPositionList[0]) || undefined;
    $scope.filterPosition = filterOpts.position;
    if (!rosters.currentRoster || !$scope.currentUser) { return; }
    $scope.fs.players.list(rosters.currentRoster.id, filterOpts).then(function(players) {
      if (filterOpts.removeLow && players.length > 2) {
        players = _.select(players, function(player) { return player.benched_games < 3 && player.status == 'ACT'; });
      }
      $scope.players = players;
    });

  };

  $scope.$watch('$routeParams.roster_id', function() {
    rosters.fetch($routeParams.roster_id, $routeParams.view_code).then(function(roster) {
      rosters.selectRoster(roster);
      filterOpts = {position: rosters.uniqPositionList && rosters.uniqPositionList[0], removeLow: false, sort: 'buy_price', dir: 'desc'};
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
      $scope.fs.rosters.show(rosters.currentRoster.id, $routeParams.view_code).then(function(roster){
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

  $scope.leaderboardPage = 1;
  $scope.showMoreLeaders = function() {
    $scope.leaderboardPage++;
    fetchContest();
  };

  var counter = 0
  fetchContest = function() {
    if (!rosters.currentRoster.contest_id) { return null; }
    counter++; // Only fetch the contest ever other time.
    if (counter % 2 == 0 && !rosters.currentRoster.contest_id || !$scope.currentUser) { return; }
    rosters.fetchContest(rosters.currentRoster.contest_id, $scope.leaderboardPage).then(function(rosters) {
      $scope.leaderboard = rosters;
    });
  };

  rosters.setPoller(function() {
    fetchPlayers();
    fetchRosters();
    fetchContest();
  }, 20000);

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

  $scope.pointsColumn = function(player) {
    if ($scope.market && $scope.market.game_type && $scope.market.game_type.match(/elimination/) && new Date() > new Date($scope.market.started_at)) {
      return 'score';
    } else {
      return 'ppg';
    }
  };

  $scope.opponentFor = function(player) {
    var game = teamsToGames[player.team];
    return game && _.find([game.home_team, game.away_team], function(team) { return team != player.team; });
  };

  $scope.notStartedGames = function() {
    return _.filter($scope.games, function(game) {
      return !$scope.gameStarted(game);
    });
  };

  $scope.isHomeTeam = function(team) {
    return !teamsToGames[team] || teamsToGames[team].home_team == team;
  };

  $scope.showPlayer = function(roster, player) {
    if (
      (player.id && $scope.currentUser && ($scope.currentUser.admin || roster.owner_id == $scope.currentUser.id )) ||
      $routeParams.view_code || // Totes not secure
      player.locked ||
      $scope.inThePast(player.next_game_at)) {
      return true;
    }
    return false;
  };

  $scope.dayBefore = function(time) {
    return moment(time).subtract('days', 1);
  };

  $scope.openStatsDialog = function(player) {
    var player = player,
      dialogOpts = {
      backdrop: true,
      keyboard: true,
      backdropClick: true,
      dialogClass: 'modal',
      templateUrl: '/stats_dialog.html',
      controller: 'StatsDialogController',
      resolve: {
        player: function() { return player; },
        market: function() {  return rosters.currentRoster.market; }
      }
    };
    return $dialog.dialog(dialogOpts).open();
  };

  // doesn't depend on $scope because it's used after navigating away from this controller
  function joinContestModal(buttonAction, roster) {
    var dialogOpts = {
      backdrop: true,
      keyboard: true,
      backdropClick: true,
      dialogClass: 'modal',
      templateUrl: '/join_contest_dialog.html',
      controller: 'JoinContestDialogController',
      resolve: {
        buttonAction: function() { return buttonAction; },
        contestClasses: function($q) {
          var deferred = $q.defer();

          if (! markets.currentMarket) {
            deferred.resolve([]);
          }

          markets.contestClassesFor(markets.currentMarket.id).then(function(contestClasses) {
            deferred.resolve(contestClasses);
          });

          return deferred.promise;
        },
        roster: function() {
          return roster;
        },
        market: function() {
          return $scope.market;
        }
      }
    };

    return $dialog.dialog(dialogOpts).open();
  };

  // doesn't depend on $scope because it's used after navigating away from this controller
  function joinContest(fs, contestType, roster) {
    fs.contests.join(contestType.id, roster.id).then(function(data) {
      rosters.selectRoster(data);
      flash.success("Awesome, we've started a new roster with all the players from your last roster. Go ahead and customize then enter again!");
      $location.path('/' + $scope.currentUser.currentCategory + '/' + $scope.currentUser.currentSport + '/market/' + $scope.market.id + '/roster/' + data.id);
    });
  };

  $scope.submitRoster = function(gameType) {
    rosters.submit(gameType).then(function(roster) {
      $location.path('/' + $scope.currentUser.currentCategory + '/' + $scope.currentUser.currentSport + '/market/' + roster.market.id);
//      $timeout(function() {
//        joinContestModal('submitRoster', roster).then(function(result) {
//          if (result && result.contestType) {
//            joinContest($scope.fs, result.contestType, roster);
//          }
//        });
//      }, 100);
    });
  };

//  $scope.enterAgain = function() {
//    joinContestModal('enterAgain', rosters.currentRoster).then(function(result) {
//      if (result && result.contestType) {
//        joinContest($scope.fs, result.contestType, rosters.currentRoster);
//      }
//    });
//  };

  $scope.finish = function() {
    rosters.reset('/market/' + rosters.currentRoster.market.id);
    $location.path( '/' + $routeParams.category + '/' + $routeParams.sport +'/home' )
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
    $timeout(function(){
      $scope.filterPlayers({position: player.position}, true);
    },500)
  };

  $scope.totalSalary = function(roster) {
    if (!roster) { return false; }
    return _.reduce(roster.players, function(sum, player) { return sum + parseInt(player.purchase_price); }, 0);
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

    function joinLeague(leagueId) {
        $scope.fs.contests.join_league(leagueId).then(function(data){
            // give the server time to save everything
            $timeout(function() {
                rosters.selectRoster(data);
                $location.path('/' + $scope.currentUser.currentCategory + '/' + $scope.currentUser.currentSport + '/market/' + data.market.id + '/roster/' + data.id);
            }, 500);
        });
    }

    $scope.showNextLeagueRoster = function(league) {
        joinLeague(league.id);
    };

    if (typeof $routeParams.league_id !== 'undefined') {
        joinLeague($routeParams.league_id);
    }

$scope.openCreateDialog = function() {
    var dialogOpts = {
        backdrop: true,
        keyboard: true,
        backdropClick: true,
        dialogClass: 'modal',
        templateUrl: '/create_contest.html',
        controller: 'CreateContestController'
    };

    var d = $dialog.dialog(dialogOpts);
    d.open().then(function(result) {
        if (!result) { return; }
        $scope.fs.contests.create({
                market_id: marketService.currentMarket.id,
                invitees: result.invitees,
                message: result.message,
                type: result.contest_type,
                buy_in: result.buy_in * (result.takes_tokens ? 1 : 100),
                takes_tokens: result.takes_tokens,
                league_name: result.league_name,
                salary_cap: 100000}
        ).then(function(roster) {
                flash.success("Awesome, your contest is all setup. Now lets create your entry into the contest.");
                rosters.selectRoster(roster);
                $location.path('/' + currentUserService.currentUser.currentCategory + '/' + currentUserService.currentUser.currentSport +'/market/' + marketService.currentMarket.id + '/roster/' + roster.id);
                currentUserService.refreshUser();
            });
    });
};
$scope.openPredictionDialog = function(player) {
    var player = player
    var dialogOpts = {
        backdrop: true,
        keyboard: true,
        backdropClick: true,
        dialogClass: 'modal modal-prediction',
        templateUrl: '/create_individual_prediction.html',
        controller: 'CreateIndividualPredictionController',
        resolve: {
            player: function() { return player; },
            market: function() {  return rosters.currentRoster.market; },
            betAlias: function() {  return $scope.betAlias; }
        }
    };
    return $dialog.dialog(dialogOpts).open();
};

}]);
