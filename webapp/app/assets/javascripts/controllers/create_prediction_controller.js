angular.module("app.controllers")
.controller('CreateIndividualPredictionController', ['$scope', 'dialog', 'fs', 'player', 'market' ,'flash', '$routeParams', 'betAlias', function($scope, dialog, fs, player, market, flash, $routeParams, betAlias) {
    $scope.player = player;
    $scope.market = market;
    $scope.betAlias = betAlias;
    $scope.confirmShow = false;
    $scope.eventData = {};

    $scope.playerStats = function(){
        fs.prediction.show(player.stats_id, $routeParams.market_id, player.position).then(function(data){
           $scope.points = data.events;
        });
    }

    $scope.confirmModal = function(text, point, name, current_bid, current_pt) {
        if(current_bid){return}
        $scope.confirmShow = true;
        $scope.confirm = {
            value: point,
            diff: text,
            name: name,
            current_bit : text,
            current_pt : current_pt
        }
    }


    var teamsToGames = {};
    _.each($scope.market.games, function(game) {
      teamsToGames[game.home_team] = game;
      teamsToGames[game.away_team] = game;
    });

    $scope.opponentFor = function(player) {
      var game = teamsToGames[player.team];
      return game && _.find([game.home_team, game.away_team], function(team) { return team != player.team; });
    };

    $scope.isHomeTeam = function(team) {
      return !teamsToGames[team] || teamsToGames[team].home_team == team;
    };

    $scope.count = 0;
    $scope.confirmSubmit = function(){
        $scope.eventSubmit = [];
        $scope.confirmShow = false;
        $scope.eventSubmit.push($scope.confirm);

        fs.prediction.submit($routeParams.roster_id,$routeParams.market_id,player.stats_id, $scope.eventSubmit).then(function(data){
            flash.success("Individual prediction submitted successfully!");
            _.each($scope.points, function(events){
                if(events.name == $scope.confirm.name){
                    $scope.confirm.current_bit == 'less' ?  events.bid_less = true : events.bid_more = true;
                }
            });
        });
    };

    $scope.close = function(){
       dialog.close();
    };

    $scope.playerStats();

}]);

