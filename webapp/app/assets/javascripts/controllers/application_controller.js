angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'rosters', '$location', 'flash', '$dialog', function($scope, fs, currentUserService, rosters, $location, flash, $dialog) {

  $scope.fs = fs;

  $scope.currentUser = currentUserService.currentUser;

  $scope.addFundsModal = function(){
    currentUserService.addFundsModal();
  };

  $scope.withdrawFundsModal = function(){
    currentUserService.withdrawFundsModal();
  };

  $scope.settingsModal = function(){
    currentUserService.settingsModal();
  };

  $scope.inThePast = function(time) {
    if (!time) {
      return false;
    }
    return new Date(time) < new Date();
  };

  // TODO: deprecate this and switch them all to inThePast
  $scope.gameStarted = function(game) {
    return new Date(game.game_time) < new Date();
  };

  $scope.log = function(obj) {
    console && console.log(obj);
  };

}]);
