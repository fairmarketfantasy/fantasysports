angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'fs', 'currentUser', function($scope, fs, currentUser) {

  $scope.currentUser = currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};
  $scope.cards       = $scope.cards        || [];

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
    if(!$scope.cards.length){
      $scope.errorMessage = "You don't have any cards, add one.";
    }
    $scope.showCardForm = !$scope.cards.length;
    $scope.loaded = true;
  });

  $scope.showAddCardButton = function(){
    return !$scope.showCardForm && ($scope.cards.length < 3);
  };

  $scope.showingAddFunds = function(){
    return !$scope.showCardForm && $scope.cards.length;
  };


  var saveCardCallback = function(st, stripeResp){
    $scope.saveCardSpinner = false;
    if(st === 200){
      var token = stripeResp['id'];
      fs.cards.create(token).then(function(resp){
        if(resp.error){
          $scope.errorMessage = resp.error;
        } else {
          $scope.cards = resp.cards || [];
          $scope.cardInfo = {};
          $scope.showCardForm = false;
          $scope.successMessage = "Success, your card was saved.";
        }
      });
    } else {
      $scope.errorMessage = stripeResp.error.message;
    }
  };

  var localChecks = function(cardInfo){
    if(!Stripe.card.validateCardNumber(cardInfo.number)){
      $scope.cardNumError = true;
      $scope.errorMessage = "This card number looks invalid";
      return false;
    }else if(!Stripe.card.validateCVC(cardInfo.cvc)){
      $scope.cvcError = true;
      $scope.errorMessage = "CVC code doesn't look right";
      return false;
    }else if(!Stripe.card.validateExpiry(cardInfo.exp_month, cardInfo.exp_year)){
      $scope.expError = true;
      $scope.errorMessage = "Expiration doesn't look right";
      return false;
    } else {
      return true;
    }
  };

  $scope.saveCard = function(){
    $scope.errorMessage = null;
    $scope.saveCardSpinner = true;
    if(!localChecks($scope.cardInfo)){
      $scope.saveCardSpinner = false;
      return;
    } else {
      Stripe.card.createToken($scope.cardInfo, function(st, stripeResp){
        $scope.$apply(function(){
          saveCardCallback(st, stripeResp);
        });
      });
    }
  };

  $scope.addFunds = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    $scope.addMoneySpinner = true;
    fs.user.addMoney(amt).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.chargeAmt = null;
      $scope.addMoneySpinner = false;
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
    $scope.deleteCardSpinner = true;
    fs.cards.destroy(cardId).then(function(resp){
      $scope.deleteCardSpinner = false;
      $scope.cards = resp.cards || [];
    });
  };

}]);
