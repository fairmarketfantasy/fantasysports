angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'rosters', '$location', 'flash', '$dialog', function($scope, fs, rosters, $location, flash, $dialog) {

  $scope.fs = fs;

  $scope.currentUser = function() {
    return window.App.currentUser;
  };

  $scope.addFunds = function(){
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/assets/add_funds_dialog.html',
          controller: 'AddFundsDialogController',
          resolve: {
            currentUser: function(){
              return $scope.currentUser;
            }
          }
        };

    var d = $dialog.dialog(dialogOpts);
    d.open();
  };

  // $scope.logout = function(){
  //   fs.user.logout().then(function(resp){
  //     window.App.currentUser = null;
  //   });
  // };

}]);
