angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', function($scope, rosters, $routeParams, $location) {
  $scope.fs.markets.show($routeParams.id).then(function(market) {
    $scope.market = market;
  });

  $scope.rosters = rosters;

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
    $scope.fs.contests.join(contestType.id, rosters.justSubmittedRoster && rosters.justSubmittedRoster.id).then(function(data){
      rosters.selectRoster(data);
    });
  };

  $scope.setJustSubmittedRoster = function(roster) {
    $scope.justSubmittedRoster = roster;
  };

  $scope.cancelRoster = function() {
    rosters.cancel();
  };

  $scope.clearJustSubmittedRoster = function() {
    $scope.justSubmittedRoster = null;
    $location.path('/');
    flash.success = "Awesome, You're IN. Good luck!";
  };

}]);


