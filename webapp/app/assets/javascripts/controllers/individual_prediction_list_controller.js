angular.module("app.controllers")
.controller('IndividualPredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', '$dialog', function($scope, rosterService, markets, flash, $routeParams, $dialog) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.pt_history = true;
  $scope.showMore = false;
  $scope.landingShow = true;
  var page = 0;
  $scope.predictionList = [];

  $scope.fetchMore = function() {
    $scope.showMore = false;
    page++;

    rosterService.fetchMinePrediction({sport: $routeParams.sport, page: page}).then(function(data) {

      if (data.length > 24) {
        $scope.showMore = true;
      }

      $scope.predictionList = $scope.predictionList.concat(data);
      _.each($scope.predictionList, function(list){
        _.each(list.event_predictions, function(data){
          if(data.diff == 'more'){
              data.diff = 'over';
          } else if(data.diff == 'less'){
              data.diff = 'under';
          }
        })
      });
      $scope.landingShow = false;
    });
  };

  $scope.fetchMore();

  $scope.openPredictionDialog = function(event_id, stats_id, name) {
    var player = {event_id:event_id, stats_id:stats_id, name:name}
    var dialogOpts = {
      backdrop: true,
      keyboard: true,
      backdropClick: true,
      dialogClass: 'modal modal-prediction',
      templateUrl: '/create_individual_prediction.html',
      controller: 'UpdateIndividualPredictionController',
      resolve: {
          player: function() { return player; }
      }
    };
    return $dialog.dialog(dialogOpts).open();
  };
}]);

