angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'flash', 'fs', 'currentUser', function($scope, flash, fs, currentUser) {

  $scope.currentUser = currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
    $scope.addNewCard = !$scope.cards.length;
  });

  $scope.addNewCard = false;

  $scope.saveCard = function(){
    Stripe.card.createToken($scope.cardInfo, function(st, resp){
      if(st === 200){
        var token = resp['id'];
        fs.cards.create(token).then(function(resp){
          if(resp.error){
            flash.error = resp.error;
          } else {
            $scope.cards = resp.cards;
          }
        });
      } else {
        flash.error = resp.error.message;
      }
    });
  };

  $scope.addMoney = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    fs.user.addMoney(amt).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.chargeAmt = null;
    });
  };

}]);
