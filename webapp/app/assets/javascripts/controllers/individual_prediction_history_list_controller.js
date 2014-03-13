angular.module("app.controllers")
.controller('IndividualPredictionHistoryController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', '$dialog', function($scope, rosterService, markets, flash, $routeParams, $dialog) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.pt_history = true;

  rosterService.fetchMinePrediction({sport: $routeParams.sport, historical: true}).then(function(data) {
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

}]);

