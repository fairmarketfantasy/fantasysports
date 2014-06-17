angular.module("app.controllers")
.controller('IndividualPredictionListController', ['$scope', 'rosters', 'markets', 'flash', '$routeParams', '$dialog', function($scope, rosterService, markets, flash, $routeParams, $dialog) {
  rosterService.setPoller(null);
  $scope.rosterService = rosterService;
  $scope.pt_history = true;
  $scope.showMore = false;
  $scope.landingShow = true;
  var page = 0;
  $scope.predictionList = [];
  $scope.predicate = '-id';  //sort by id

  $scope.fetchMore = function() {
    $scope.showMore = false;
    page++;

    rosterService.fetchMinePrediction({category: $routeParams.category, sport: $routeParams.sport, page: page}).then(function(data) {

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

  $scope.openTradeDialog = function(prediction) {
    var dialogOpts = {
      backdrop: true,
      keyboard: true,
      backdropClick: true,
      dialogClass: 'modal modal-trade-prediction',
      templateUrl: '/trade_prediction.html',
      controller: 'TradePredictionController',
      resolve: {
        prediction: function() { return prediction; }
      }
    };
    return $dialog.dialog(dialogOpts).open();
  };
}]);

