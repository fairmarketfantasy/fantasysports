angular.module("app.controllers")
.controller('SampleRosterController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'fs', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, fs) {

    $scope.marketService = marketService;
    $scope.roster = rosters;

    marketService.fetchUpcoming({type: 'single_elimination', sport: $scope.$routeParams.sport}).then(function() {
        marketService.fetchUpcoming({type: 'regular_season', sport: $scope.$routeParams.sport}).then(function() {
            if ($routeParams.market_id) {
                marketService.selectMarketId($routeParams.market_id, $scope.$routeParams.sport);
            } else if ($location.path().match(/\w+\/playoffs/)) {
                marketService.selectMarketType('single_elimination', $scope.$routeParams.sport);
            } else {
                marketService.selectMarketType('regular_season', $scope.$routeParams.sport);
            }
            $scope.reloadRoster(true, $scope.$routeParams.sport);
        });
    });

    $scope.reloadRoster = function(id, sport) {
        $scope.roster = undefined;
        fs.rosters.getSample(id, sport).then(function(roster) {
            $scope.roster = roster;
            $scope.isCurrent(roster.market_id)
        });
    };


    $scope.isCurrent = function(market){
        if (!market) {
            $scope.gameNotFound = "There are no contents at this moment";
            return;
        }
        if ($scope.roster == undefined) { return; }
        if (!marketService.currentMarket) {
            flash.error("Oops, we couldn't find that market, pick a different one.");
            $scope.gameNotFound = "There are no contents at this moment";
            console.log($scope.gameNotFound)
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

