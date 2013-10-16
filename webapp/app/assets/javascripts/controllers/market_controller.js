angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog) {
  $scope.marketService = marketService;

  marketService.fetchUpcoming($routeParams.market_id);
  $scope.rosters = rosters;
  $scope.contestTypeOrder = ['100k', '10k', '5k', '194', '970', 'h2h', 'h2h rr'];

  $scope.isCurrent = function(market){
    if (!market) { return; }
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
    $scope.games = games;

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
      if (!result) { return; }
      $scope.fs.contests.create(marketService.currentMarket.id, result.contest_type, result.buy_in * (result.takes_tokens ? 1 : 100), result.takes_tokens, result.invitees, result.message).then(function(roster) {
        flash.success = "Awesome, your contest is all setup. Now lets create your entry into the contest."
        rosters.selectRoster(roster);
        $location.path('/market/' + marketService.currentMarket.id + '/roster/' + roster.id);
      });
    });
  };

  $scope.showDayDesc = function(market) {
    return market.games.length > 1 && new Date(market.closed_at) - new Date(market.started_at) < 24 * 60 * 60 * 1000;
  };

  $scope.showGameDesc = function(market) {
    return market.games.length == 1;
  };

  $scope.showDateDesc = function(market) {
    return new Date(market.closed_at) - new Date(market.started_at) > 24 * 60 * 60 * 1000;
  };

  $scope.isBigContest = function(contestClass) {
    return contestClass.match(/\d+k/);
  };

}]);
