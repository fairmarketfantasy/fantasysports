angular.module("app.controllers")
.controller('SampleRosterController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'fs', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, fs) {
  if($routeParams.category == 'fantasy_sports') {
    $scope.marketService = marketService;
    $scope.roster = rosters;
    $scope.player_price = {};
    marketService.fetchUpcoming({type: 'single_elimination', category: $scope.$routeParams.category, sport: $scope.$routeParams.sport}).then(function() {
      marketService.fetchUpcoming({type: 'regular_season', category: $scope.$routeParams.category, sport: $scope.$routeParams.sport}).then(function() {
        if ($routeParams.market_id) {
          marketService.selectMarketId($routeParams.market_id, $scope.$routeParams.category, $scope.$routeParams.sport);
        } else if ($location.path().match(/\w+\/playoffs/)) {
          marketService.selectMarketType('single_elimination', $scope.$routeParams.category,  $scope.$routeParams.sport);
        } else {
          marketService.selectMarketType('regular_season', $scope.$routeParams.category, $scope.$routeParams.sport);
        }
        $scope.reloadRoster(true, $scope.$routeParams.category, $scope.$routeParams.sport);
      });
    });
    $scope.reloadRoster = function(id,category, sport) {
      $scope.hide_loading = false;
      $scope.roster = undefined;
      fs.rosters.getSample(id, category, sport).then(function(roster) {
          $scope.roster = roster;
          $scope.isCurrent(roster.market_id);
        $scope.mostExpencive = function() {
          if(!roster.players){return;}
          return _.max(roster.players, function(top_price){
            return parseInt(top_price.buy_price)
          })
        };
        $scope.playerStats($scope.mostExpencive());
        $scope.$emit('enableNavBar');
        $scope.hide_loading = true;
      }, function(){
        $scope.$emit('enableNavBar');
        $scope.hide_loading = true;
      });
    };
    $scope.playerStats = function(player){
      if(!player){return;}
      $scope.player = player;
      fs.prediction.show(player.stats_id).then(function(data){
        $scope.events = data.events;
      });
    }
    $scope.isCurrent = function(market){
        if (!market) {
            $scope.gameNotFound = true;
            return;
        }
    };
  } else{
    if($routeParams.sport == 'FWC'){
        $scope.gameNotFound = false;
    } else{
      fs.game_predictions.dayGames($routeParams.sport).then(function(gamePrediction) {
        $scope.gamePrediction = gamePrediction;
        if(!$scope.gamePrediction.games.length){
          $scope.gameNotFound = true;
        }
        $scope.hide_loading = true;
      });
      fs.game_predictions.sample($routeParams.sport).then(function(game) {
        $scope.landingGameList = game;
        $scope.$emit('enableNavBar');
      });
    }
  }
}]);
