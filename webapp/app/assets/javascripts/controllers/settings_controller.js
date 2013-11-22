  angular.module("app.controllers")
.controller('SettingsController', ['$scope', '$timeout', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, $timeout, dialog, fs, flash, currentUserService) {

  $scope.currentUserService = currentUserService;

  $scope.setUserInfo = function() {
    $scope.currentUser = currentUserService.currentUser;
    $scope.userInfo = $scope.userInfo || {id: $scope.currentUser.id, name: $scope.currentUser.name, username: $scope.currentUser.username, email: $scope.currentUser.email};
  }

  $scope.setUserInfo();

  var flashForConfirm = function(){
    if(!$scope.currentUser.confirmed){
      $timeout(function(){
        flash.error("You haven't confirmed your email address yet.");
      }, 100);
    }
  };

  flashForConfirm();

  $scope.editUser = function() {
    $scope.setUserInfo();
    $scope.showUserForm = true;
  }

  $scope.isAuthedWithFacebook = !!$scope.currentUser.provider;

  //fires after multipart upload for picture has completed
  $scope.results = function(content, completed) {
    if (completed)
      // the response includes the updated user, but it's simpler to get it straight from $http rather than ng-upload
      fs.user.refresh().then(function(data){
        flash.success("Success, avatar saved");
        currentUserService.setUser(data);
        $scope.setUserInfo();
        $scope.showUpload  = false;
      });
    else
    {
      flash.error("Error saving avatar");
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
    fs.user.update($scope.userInfo).then(function(data){
      flash.success("Success, user info saved");
      flashForConfirm();
      currentUserService.setUser(data);
      $scope.setUserInfo();
      $scope.showUserForm = false;
      $scope.showPasswordForm = false;
    }, function() {
      flash.error("Error saving user info");
    });
  };

  $scope.close = function(){
    dialog.close();
  };


}]);
