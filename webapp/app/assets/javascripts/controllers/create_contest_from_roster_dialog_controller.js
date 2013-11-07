angular.module("app.controllers")
.controller('CreateContestFromRosterDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout', function($scope, dialog, fs, flash, currentUserService, $timeout) {
  $scope.close = function(){
    dialog.close();
  };
}]);
