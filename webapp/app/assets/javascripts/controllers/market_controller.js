angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog) {
  $scope.marketService = marketService;

  marketService.fetchUpcoming($routeParams.market_id);
  $scope.rosters = rosters;

  $scope.isCurrent = function(market){
    if (!marketService.currentMarket) {
      flash.error = "Oops, we couldn't find that market, pick a different one.";
      $location.path('/');
      return;
    }
    return (market.id === marketService.currentMarket.id);
  };

  var reloadMarket = function() {
    if (!marketService.currentMarket) {
      return;
    }
    marketService.gamesFor(marketService.currentMarket.id).then(function(games) {
      $scope.games = games;
    });

    $scope.fs.contests.for_market(marketService.currentMarket.id).then(function(contestTypes) {
      $scope.contestClasses = {};
      _.each(contestTypes, function(type) {
        if (!$scope.contestClasses[type.name]) {
          $scope.contestClasses[type.name] = [];
        }
        $scope.contestClasses[type.name].push(type);
      });
    });
  }
  $scope.$watch('marketService.currentMarket', reloadMarket);

  $scope.day = function(timeStr) {
    var day = moment(timeStr);
    return day.format("ddd, MMM Do , h:mm a");
  };

  $scope.joinContest = function(contestType) {
    $scope.fs.contests.join(contestType.id, rosters.justSubmittedRoster && rosters.justSubmittedRoster.id).then(function(data){
      rosters.selectRoster(data);
      $location.path('/market/' + marketService.currentMarket.id + '/roster/' + data.id);
    });
  };

  $scope.setJustSubmittedRoster = function(roster) {
    $scope.justSubmittedRoster = roster;
  };

  $scope.cancelRoster = function() {
    var path = '/market/' + marketService.currentMarket.id;
    rosters.cancel();
    $location.path(path);
  };

  $scope.clearJustSubmittedRoster = function() {
    $scope.justSubmittedRoster = null;
    $location.path('/');
    flash.success = "Awesome, You're IN. Good luck!";
  };

  $scope.openCreateDialog = function() {
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/create_contest.html',
          controller: 'CreateContestController'
        };

    var d = $dialog.dialog(dialogOpts);
    d.open().then(function(result) {
      $scope.fs.contests.create(marketService.currentMarket.id, result.contest_type, result.buy_in, result.invitees, result.message).then(function(roster) {
        flash.success = "Awesome, your contest is all setup. Now lets create your entry into the contest."
        rosters.selectRoster(roster);
        $location.path('/market/' + marketService.currentMarket.id + '/roster/' + roster.id);
      });
    });
  };

}]);
