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
    var day = moment(timeStr)
    return day.format("dddd, MMMM Do YYYY, h:mm:ss a");
  }

  $scope.gameFromTeam = function(team) {
    var game = teamsToGames[team];
    return game && (game.away_team + ' @ ' + game.home_team)
  };

  $scope.joinContest = function(type, buy_in) {
    $scope.fs.contests.join($scope.market.id, type, buy_in).then(function(data){
      $scope.roster = data;
      window.App.in_progress_roster = data;
    })
  };

  $scope.deleteRoster = function(opts) {
    $scope.fs.rosters.cancel($scope.roster.id).then(function(data) {
      $scope.roster = null;
      window.App.in_progress_roster = null;
    });
  };

}])


