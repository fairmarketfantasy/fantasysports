angular.module("app.controllers")
.controller('SampleRosterController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService', 'fs', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, currentUserService, fs) {

    $scope.marketService = marketService;
    $scope.roster = rosters;

    marketService.fetchUpcoming({type: 'single_elimination', sport: 'NBA'}).then(function() {
        marketService.fetchUpcoming({type: 'regular_season', sport: 'NBA'}).then(function() {
            if ($routeParams.market_id) {
                marketService.selectMarketId($routeParams.market_id, 'NBA');
            } else if ($location.path().match(/\w+\/playoffs/)) {
                marketService.selectMarketType('single_elimination', 'NBA');
            } else {
                marketService.selectMarketType('regular_season', 'NBA');
            }
        });
        $scope.reloadRoster();
    });

        $scope.reloadRoster = function(id, sport) {
            $scope.roster = undefined;
            fs.rosters.getSample(id, sport).then(function(roster) {
                $scope.roster = roster;
                $scope.isCurrent(roster.market_id)
            });
        };


    $scope.isCurrent = function(market){
        if (!market) { return; }
        if ($scope.roster == undefined) { return; }
        if (!marketService.currentMarket) {
            flash.error("Oops, we couldn't find that market, pick a different one.");
            return;
        }
            return (market.id === $scope.roster.market.id);
    };



//    slider
    $scope.$slideIndex = 0;
    $scope.next = function() {
        var total = $scope.marketService.upcoming.length;
        if (total > 0) {
            $scope.$slideIndex = ($scope.$slideIndex < total - 3 ) ? $scope.$slideIndex + 1 : total - 3;
        }
    };
    $scope.prev = function() {
        var total = $scope.marketService.upcoming.length;
        if (total > 0) {
            $scope.$slideIndex = ($scope.$slideIndex > 0) ? $scope.$slideIndex = $scope.$slideIndex - 1: $scope.$slideIndex = 0;
        }
    };
}]);

