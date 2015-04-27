angular.module("app.controllers")
.controller('WithdrawFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, dialog, fs, flash, currentUserService) {

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;

  $scope.close = function(){
    dialog.close();
  };

  $scope.resendConfirmation = function(){
    fs.user.resendConfirmation().then(function(resp){
      $scope.close();
      flash.success(resp.message);
    });
  };

  $scope.showAddNewAccount = function(){
    return !$scope.recipient && $scope.currentUser.confirmed;
  };

  fs.recipients.list().then(function(resp){
    $scope.recipient = resp[0];
    $scope.loaded    = true;
    $scope.focusAmount = true;
  });

  $scope.newRecipient = $scope.newRecipient || {};
  $scope.newAccount   = $scope.newAccount   || {};

  $scope.createRecipient = function(){
    $scope.saveAcctSpinner = true;
    fs.recipients.create($scope.newAccount).then(function(resp){
      $scope.saveAcctSpinner = false;
      $scope.focusAmount = true;
      flash.success("Success, your PayPal has been added.");
      $scope.recipient = resp;
    }, function(resp) {
      $scope.saveAcctSpinner = false;
      flash.error(resp.error);
    });
  };

  $scope.deleteRecipient = function(){
    fs.recipients.remove().then(function(resp){
      flash.success("Success, your bank account has been deleted. Add a new one:");
      $scope.recipient = null;
    })
  };

  $scope.initiateTransfer = function(){
    $scope.deleteRecipientSpinner = true;
    $scope.startTransferSpinner = true;
    var amount = $scope.withdrawAmount * 100;
    fs.user.withdrawMoney(amount).then(function(resp){
      $scope.deleteRecipientSpinner = false;
      $scope.close();
      flash.success("Success, transfer of $" +  $scope.withdrawAmount + " has been initiated.");
      $scope.startTransferSpinner = false;
      window.App.currentUser.balance = resp.balance;
      $scope.withdrawAmount = null;
    }, function(resp){
      $scope.startTransferSpinner = false;
    });
  };


}]);
