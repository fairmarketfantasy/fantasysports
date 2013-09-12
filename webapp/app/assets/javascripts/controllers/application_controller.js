angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'rosters', '$location', 'flash', '$dialog', function($scope, fs, currentUserService, rosters, $location, flash, $dialog) {

  $scope.fs = fs;

  $scope.currentUser = currentUserService.currentUser;

  $scope.addFundsModal = function(){
    currentUserService.addFundsModal();
  };

  $scope.gameStarted = function(game) {
    return new Date(game.game_time) < new Date();
  };

  // $scope.logout = function(){
  //   fs.user.logout().then(function(resp){
  //     window.App.currentUser = null;
  //   });
  // };

}]);
