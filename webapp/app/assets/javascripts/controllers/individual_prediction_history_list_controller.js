angular.module("app.controllers")
.controller('IndividualPredictionHistoryController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', '$dialog', function($scope, rosterService, markets, flash, $routeParams, $dialog) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.pt_history = true;
  $scope.showMore = false;
  var page = 0;
  $scope.rosterList = [];

  $scope.fetchMore = function() {
    $scope.showMore = false
    page++;
    rosterService.fetchMinePrediction({sport: $routeParams.sport, historical: true, page: page}).then(function(data) {
      _.each($scope.predictionList, function(list){
        _.each(list.event_predictions, function(data){
          if(data.diff == 'more'){
            data.diff = 'over';
          } else{
            data.diff = 'under';
          }
        })
      });

      if (data.length > 24) {
        $scope.showMore = true;
      }
        $scope.rosterList = $scope.rosterList.concat(data);
      });
  };
  $scope.fetchMore();

}]);

