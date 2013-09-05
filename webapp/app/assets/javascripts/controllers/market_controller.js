angular.module("app.controllers")
.controller('MarketController', ['$scope', '$routeParams', '$location', function($scope, $routeParams, $location) {
  $scope.fs.markets.show($routeParams.id).then(function(market) {
    $scope.market = market;
  });

  var teamsToGames = {};
  $scope.fs.games.list($routeParams.id).then(function(games) {
    $scope.games = games;
    _.each(games, function(game) {
      teamsToGames[game.home_team] = game;
      teamsToGames[game.away_team] = game;
    });
  });

  $scope.fs.contests.for_market($routeParams.id).then(function(contestTypes) {
    $scope.contestClasses = {};
    _.each(contestTypes, function(type) {
      if (!$scope.contestClasses[type.name]) {
        $scope.contestClasses[type.name] = [];
      }
      $scope.contestClasses[type.name].push(type);
    });
  });

  $scope.day = function(timeStr) {
    var day = moment(timeStr);
    return day.format("dddd, MMMM Do YYYY, h:mm:ss a");
  };

  $scope.gameFromTeam = function(team) {
    var game = teamsToGames[team];
    return game && (game.away_team + ' @ ' + game.home_team);
  };

  $scope.joinContest = function(contestType) {
    $scope.fs.contests.join(contestType.id).then(function(data){
      $scope.setRoster(data, true);
    });
  };

  $scope.setRoster = function(roster, inProgress) {
    $scope.roster = roster;
    if (inProgress) {
      window.App.in_progress_roster = roster;
    }
  };

  $scope.deleteRoster = function() {
    $scope.fs.rosters.cancel($scope.roster.id).then(function(data) {
      $scope.setRoster(null, true);
      $location.path('/');
    });
  };

  $scope.submitRoster = function() {
    $scope.fs.rosters.submit($scope.roster.id).then(function(data) {
      // TODO: open dialog, ask if user wants to submit another roster
    console.log('success');
      $scope.setRoster(null, true);
    },function(data){ console.log("FAIL"); });
  };

}]);


