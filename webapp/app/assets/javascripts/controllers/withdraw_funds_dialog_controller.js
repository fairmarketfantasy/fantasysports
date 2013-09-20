angular.module("app.controllers")
.controller('WithdrawFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, dialog, fs, flash, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;

  $scope.close = function(){
    dialog.close();
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
        if(resp.errors){
          $scope.errorMessage = resp.errors[0];
        } else {
          $scope.successMessage = "Success, your bank account has been added.";
          $scope.recipient = resp;
        }
      });
    } else {
      $scope.errorMessage = resp.error.message;
    }
  };

  $scope.createRecipient = function(){
    $scope.newAccount.country = 'US';
    Stripe.bankAccount.createToken($scope.newAccount, function(st, stripeResp){
      $scope.$apply(function(){
        saveAccountCallback(st, stripeResp);
      });
    });
  };

  $scope.deleteRecipient = function(){
    fs.recipients.delete().then(function(resp){
      if(resp.errors){
        $scope.errorMessage = resp.errors[0];
      } else {
        $scope.successMessage = "Success, your bank account has been deleted. Add a new one:";
        $scope.recipient = null;
      }
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
