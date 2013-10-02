  angular.module("app.controllers")
.controller('SettingsController', ['$scope', '$timeout', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, $timeout, dialog, fs, flash, currentUserService) {

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;

  if(!$scope.currentUser.confirmed){
    $timeout(function(){
      flash.error = "You haven't confirmed your email address yet.";
    }, 100);
  }

  $scope.user = {};

  $scope.results = function(content, completed) {
    console.log(content, completed);
    if (completed && content.length > 0)
      console.log(content); // process content
    else
    {
      // 1. ignore content and adjust your model to show/hide UI snippets; or
      // 2. show content as an _operation progress_ information
    }
  };

  $scope.resendConfirmation = function(){
    fs.user.resendConfirmation().then(function(resp){
      flash.error = null;
      flash.success = null;
      $scope.close();
      flash.success = resp.message;
    });
  };

  $scope.updateSettings = function(){
    fs.user.update($scope.user).then(function(resp){
      console.log(resp);
    });
  };

  $scope.close = function(){
    dialog.close();
  };


}]);
