angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'registrationService', 'rosters', '$location', 'flash', '$dialog', '$timeout', function($scope, fs, currentUserService, registrationService, rosters, $location, flash, $dialog, $timeout) {

  $scope.fs = fs;

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;
  $scope.$watch('currentUserService.currentUser', function(newVal) {$scope.currentUser = newVal;}, true);

  $scope.signUpModal = function() {
    registrationService.signUpModal();
  }

  $scope.loginModal = function() {
    registrationService.loginModal();
  }

  $scope.forgotPasswordModal = function() {
    registrationService.forgotPasswordModal();
  }

  $scope.resetPasswordModal = function(token){
    currentUserService.resetPasswordModal(token);
  };

  $scope.addFundsModal = function(){
    currentUserService.addFundsModal();
  };

  $scope.addFanFreesModal = function(){
    currentUserService.addFanFreesModal();
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

  if ($location.search().autologin) {
    var message = $location.search().autologin;
    $location.search('autologin', null);
    $scope.signUpModal(message);
  }

}]);
