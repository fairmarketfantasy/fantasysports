angular.module("app.controllers")
.controller('CompetitionMarketController', ['$scope', 'rosters', '$routeParams', '$location', 'markets', 'flash', '$dialog', 'currentUserService','fs', function($scope, rosters, $routeParams, $location, marketService, flash, $dialog, currentUserService, fs) {
    rosters.setPoller(null);
    if(currentUserService.currentUser.currentSport == 'FWC'){
      $location.path('/' + currentUserService.currentUser.currentCategory + '/' + currentUserService.currentUser.currentSport + '/fifa_world_cup');

    } else{
      $location.path('/' + currentUserService.currentUser.currentCategory + '/' + currentUserService.currentUser.currentSport + '/competition_roster');
    }
}]);
