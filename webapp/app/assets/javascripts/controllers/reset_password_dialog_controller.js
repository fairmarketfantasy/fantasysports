angular.module("app.controllers")
.controller('ResetPasswordDialogController', ['$scope', 'fs', 'currentUserService', '$dialog', 'token', function($scope, fs, currentUserService, $dialog, token) {

  $scope.user = {reset_password_token: token};

  $scope.updatePassword = function(){
    fs.user.updatePassword($scope.user).then(function(resp){
      //on success, now they have a session, reload the page
      window.location.href = '/';
    });
  };



}]);
