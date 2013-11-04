angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'rosters', '$location', 'flash', '$dialog', function($scope, fs, currentUserService, rosters, $location, flash, $dialog) {

  $scope.fs = fs;

  $scope.currentUser = currentUserService.currentUser;

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

//# TODO: separate sign up controller from login controller.  Right now sign up template calls login controller and login controller calls sign up
  $scope.signUpModal = function(message){
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/sign_up_dialog.html',
          controller: 'SignUpDialogController',
          resolve: {message: function(){ return message; }},
        };

     var d = $dialog.dialog(dialogOpts);
     d.open();
  };

  if ($location.search().autologin) {
    var message = $location.search().autologin;
    $location.search('autologin', null);
    $scope.signUpModal(message);
  }

}]);
