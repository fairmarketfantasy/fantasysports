angular.module("app.controllers")
.controller('ForgotPasswordDialogController', ['$scope', 'dialog', 'flash', 'fs', '$timeout', 'registrationService', function($scope, dialog, flash, fs, $timeout, registrationService) {
  $scope.user = $scope.user || {};

  $scope.resetPassword = function(){
    fs.user.resetPassword($scope.user.email).then(function(resp){
      flash.success(resp.message);
      $scope.close();
    });
  };

  $scope.close = function(nextModal){
    dialog.close();
    if (typeof nextModal !== 'undefined') {
      registrationService.showModal(nextModal);
    }
  };

}]);

