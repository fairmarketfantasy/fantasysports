angular.module("app.controllers")
.controller('MarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, currentUserService) {
  $scope.marketService = marketService;

// TODO: Pick up here: UI needs to determine if loaded market is single elim and keep playoff setting when it's clicked
//----- WE SHOULD ALSO MAKE SURE THE SINGLE ELIMS AHVE A LOLLAPALOOZA
  marketService.fetchUpcoming({type: 'single_elimination', sport: currentUserService.currentUser.currentSport}).then(function() {
    marketService.fetchUpcoming({type: 'regular_season', sport: currentUserService.currentUser.currentSport}).then(function() {
      if ($routeParams.market_id) {
        marketService.selectMarketId($routeParams.market_id, currentUserService.currentUser.currentSport);
      } else if ($location.path().match(/\w+\/playoffs/)) {
        marketService.selectMarketType('single_elimination', currentUserService.currentUser.currentSport);
      } else {
        marketService.selectMarketType('regular_season', currentUserService.currentUser.currentSport);
      }
        if(!marketService.currentMarket){
            return;
        }else{
            $scope.marketService.currentMarket.id = marketService.currentMarket.id
            $scope.startRoster();
        }
    });
  });
  $scope.rosters = rosters;
  $scope.contestTypeOrder = ['100k', '10k', '5k', '194', '970', '100/30/30', '65/25/10', '27 H2H','h2h', 'h2h rr'];

  $scope.isCurrent = function(market){
    if (!market) { return; }
    if (!marketService.currentMarket) {
      flash.error("Oops, we couldn't find that market, pick a different one.");
      $location.path(currentUserService.currentUser.currentSport + '/home');
      return;
    }
    return (market.id === marketService.currentMarket.id);
  };
//    $scope.$watch('marketService.currentMarket.id', function() {
//        if(!$routeParams.market_id){
//            $routeParams.market_id = marketService.currentMarket.id
//        }
//         $location.path('/' + currentUserService.currentUser.currentSport + '/market/' + $routeParams.market_id);
//    });
        $scope.startRoster = function(){
        if(!$routeParams.market_id){
            $scope.fs.rosters.roster(marketService.currentMarket.id).then(function(data){
              $location.path('/' + currentUserService.currentUser.currentSport + '/market/' + marketService.currentMarket.id + '/roster/' + data.id);
          });
        } else {
            $scope.fs.rosters.roster($routeParams.market_id).then(function(data){
                $location.path('/' + currentUserService.currentUser.currentSport + '/market/' + $routeParams.market_id + '/roster/' + data.id);

            });
        }
    };

  $scope.hasLollapalooza = function() {
    return _.find(_.keys($scope.contestClasses || {}), function(name) { return name.match(/k/); });
  };

  $scope.day = function(timeStr) {
    var day = moment(timeStr);
    return day.format("ddd, MMM Do , h:mm a");
  };

  $scope.joinContest = function(contestType) {
    $scope.fs.contests.join(contestType.id, rosters.justSubmittedRoster && rosters.justSubmittedRoster.id).then(function(data){
      rosters.selectRoster(data);
      $location.path('/' + currentUserService.currentUser.currentSport + '/market/' + marketService.currentMarket.id + '/roster/' + data.id);
    });
  };
//  $scope.joinContest($scope.contestClasses);

  $scope.setJustSubmittedRoster = function(roster) {
    $scope.justSubmittedRoster = roster;
  };

  $scope.cancelRoster = function() {
    var path =  '/' + currentUserService.currentUser.currentSport +'/market/' + marketService.currentMarket.id;
    rosters.cancel();
    $location.path(path);
  };

  $scope.clearJustSubmittedRoster = function() {
    $scope.justSubmittedRoster = null;
    $location.path('/' + currentUserService.currentUser.currentSport + '/home');
    flash.success("Awesome, You're IN. Good luck!");
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
    return !!contestClass.match(/\d+k/);
  };


}]);
