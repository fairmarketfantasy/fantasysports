  angular.module("app.controllers")
.controller('SettingsController', ['$scope', '$timeout', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, $timeout, dialog, fs, flash, currentUserService) {

  $scope.currentUserService = currentUserService;

  $scope.setUserInfo = function() {
    $scope.currentUser = currentUserService.currentUser;
    $scope.userInfo = {
      id: $scope.currentUser.id,
      name: $scope.currentUser.name,
      username: $scope.currentUser.username,
      email: $scope.currentUser.email,
      current_password: '',
      password: '',
      password_confirmation: ''
    };
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
      if (data.email != $scope.userInfo.email) {
        flash.success("Your user info has been saved. We've sent a confirmation email to your new email address. Please click the link in the email to finish updating your email address.");
      } else {
        flash.success("Success, user info saved");
      }
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

  $scope.addFundsModal = function(){
      $scope.close();
      currentUserService.addFundsModal();
  };
  $scope.addUnsubscribeModal = function(){
      $scope.close();
      currentUserService.addUnsubscribeModal();
  };
}]);
