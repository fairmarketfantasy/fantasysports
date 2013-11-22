  angular.module("app.controllers")
.controller('SettingsController', ['$scope', '$timeout', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, $timeout, dialog, fs, flash, currentUserService) {

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;

  var flashForConfirm = function(){
    if(!$scope.currentUser.confirmed){
      $timeout(function(){
        flash.error("You haven't confirmed your email address yet.");
      }, 100);
    }
  };

  flashForConfirm();

  $scope.userInfo = $scope.userInfo || {id: $scope.currentUser.id, name: $scope.currentUser.name, email: $scope.currentUser.email};

  $scope.isAuthedWithFacebook = !!$scope.currentUser.provider;

//fires after multipart upload for picture has completed
  $scope.results = function(content, completed) {
    if (completed)
      fs.user.refresh().then(function(resp){
        $scope.currentUser = resp;
        window.App.currentUser = resp;
        $scope.showUpload  = false;
      });
    else
    {
      // 1. ignore content and adjust your model to show/hide UI snippets; or
      // 2. show content as an _operation progress_ information
    }
  };

  $scope.resendConfirmation = function(){
    fs.user.resendConfirmation().then(function(resp){
      $scope.close();
      flash.success(resp.message);
    });
  };

  $scope.updateUser = function(){
    fs.user.update($scope.userInfo).then(function(resp){
      flash.success("Success, user info saved");
      flashForConfirm();
      $scope.currentUser = resp;
      $scope.userInfo = {};
    });
  };

  $scope.close = function(){
    dialog.close();
  };


}]);
