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
      flash.success = resp.message;
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

  var saveAccountCallback = function(st, stripeResp){
    if(st === 200){
      $scope.newRecipient.token = stripeResp['id'];
      fs.recipients.create($scope.newRecipient).then(function(resp){
        $scope.saveAcctSpinner = false;
        $scope.focusAmount = true;
        flash.success = "Success, your bank account has been added.";
        $scope.recipient = resp;
      });
    } else {
      $scope.saveAcctSpinner = false;
      flash.error = stripeResp.error.message;
    }
  };

  $scope.createRecipient = function(){
    $scope.saveAcctSpinner = true;
    $scope.newAccount.country = 'US';
    //have to dup this object otherwise, the values get niled out and the form
    //goes blank. maybe internally in createToken Stripe.js is deleting keys?
    var _newAcct = JSON.parse(JSON.stringify($scope.newAccount));
    Stripe.bankAccount.createToken(_newAcct, function(st, stripeResp){
      $scope.$apply(function(){
        saveAccountCallback(st, stripeResp);
      });
    });
  };

  $scope.deleteRecipient = function(){
    fs.recipients.delete().then(function(resp){
      flash.success = "Success, your bank account has been deleted. Add a new one:";
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
      flash.success = "Success, transfer of $" +  $scope.withdrawAmount + " has been initiated.";
      $scope.startTransferSpinner = false;
      window.App.currentUser.balance = resp.balance;
      $scope.withdrawAmount = null;
    });
  };


}]);
