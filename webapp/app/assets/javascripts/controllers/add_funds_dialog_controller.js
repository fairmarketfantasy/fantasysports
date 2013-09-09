angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'flash', 'fs', 'currentUser', function($scope, flash, fs, currentUser) {

  $scope.currentUser = currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};
  $scope.cards       = $scope.cards        || [];

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
  });

  $scope.addNewCard = function(){
    return !$scope.cards.length;
  };

  $scope.saveCard = function(){
    Stripe.card.createToken($scope.cardInfo, function(st, resp){
      if(st === 200){
        var token = resp['id'];
        fs.cards.create(token).then(function(resp){
          if(resp.error){
            flash.error = resp.error;
          } else {
            $scope.cards = resp.cards || [];
          }
        });
      } else {
        flash.error = resp.error.message;
      }
    });
  };

  $scope.addFunds = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    fs.user.addMoney(amt).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.chargeAmt = null;
    });
  };


  //$scope.confirm keeps track of what confirm tooltip is showing...
  //triggerConfirm sets a property, showConfirm the showing-state for a card
  //, and closeConfirm sets not-showing-state for a card
  $scope.confirm = $scope.confirm || {};

  $scope.triggerConfirm = function(cardId){
    $scope.confirm[cardId] = true;
  };

  $scope.showConfirm = function(cardId){
    return $scope.confirm[cardId];
  };

  $scope.closeConfirm = function(cardId){
    delete($scope.confirm[cardId]);
  };

  $scope.deleteCard = function(cardId){
    fs.cards.destroy(cardId).then(function(resp){
      $scope.cards = resp.cards || [];
    });
  };

}]);
