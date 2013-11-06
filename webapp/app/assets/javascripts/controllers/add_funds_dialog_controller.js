angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout', function($scope, dialog, fs, flash, currentUserService, $timeout) {

  $scope.showSpinner = false;

  $scope.addFunds = function(){
    var amt = $scope.chargeAmt;
    $scope.addMoneySpinner = true;
    var w = window.open('/users/paypal_waiting');
    fs.user.addMoney(amt).then(function(resp){
      // window.App.currentUser.balance = resp.balance;
      // $scope.close();
       //flash.success = "Success, $" + $scope.chargeAmt + " added your your account.";
      $scope.chargeAmt = null;
      w.location.href = resp.approval_url;
      $scope.addMoneySpinner = false;
    }, function(resp){
      //failure
      $scope.addMoneySpinner = false;
    });
  };
  $scope.currentUser = currentUserService.currentUser;
  $scope.close = function(){
      dialog.close();
  };

}]);
