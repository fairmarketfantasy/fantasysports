angular.module("app.controllers")
.controller('WithdrawFundsDialogController', ['$scope', 'dialog', 'fs', 'currentUserService', function($scope, dialog, fs, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;

  $scope.close = function(){
    dialog.close();
  };


}]);
