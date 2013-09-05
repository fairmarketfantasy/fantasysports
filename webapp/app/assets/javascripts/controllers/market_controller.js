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

  $scope.day = function(timeStr) {
    var day = moment(timeStr);
    return day.format("dddd, MMMM Do YYYY, h:mm:ss a");
  };

  $scope.gameFromTeam = function(team) {
    var game = teamsToGames[team];
    return game && (game.away_team + ' @ ' + game.home_team);
  };

  $scope.joinContest = function(type_id, buy_in) {
    $scope.fs.contests.join($scope.market.id, type_id, buy_in).then(function(data){
      setCurrentRoster(data);
    });
  };

  var setCurrentRoster = function(roster) {
    $scope.roster = roster;
    window.App.in_progress_roster = roster;
  };

  $scope.deleteRoster = function() {
    $scope.fs.rosters.cancel($scope.roster.id).then(function(data) {
      setCurrentRoster(null);
    });
  };

  $scope.submitRoster = function() {
    $scope.fs.rosters.submit($scope.roster.id).then(function(data) {
      // TODO: open dialog, ask if user wants to submit another roster
    console.log('success');
      setCurrentRoster(null);
    },function(data){ console.log("FAIL"); });
  }

}])


