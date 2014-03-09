angular.module("app.controllers")
.controller('IndividualPredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', '$dialog', function($scope, rosterService, markets, flash, $routeParams, $dialog) {
  $scope.rosterService = rosterService;

  rosterService.fetchMinePrediction({sport: $routeParams.sport}).then(function(data) {
    $scope.predictionList = data;
    _.each($scope.predictionList, function(list){
      _.each(list.event_predictions, function(data){
        if(data.diff == 'more'){
          data.diff = 'over';
        } else{
          data.diff = 'under';
        }
      })
     })
  });

  rosterService.setPoller(function() { rosterService.fetchMinePrediction({sport: $scope.currentUser.currentSport}); }, 10000);

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
                player: function() { return player; }
            }
        };
        return $dialog.dialog(dialogOpts).open();
    };
}]);

