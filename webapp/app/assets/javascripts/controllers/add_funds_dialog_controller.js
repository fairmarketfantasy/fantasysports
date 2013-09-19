angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', function($scope, dialog, fs, flash, currentUserService) {

  $scope.currentUser = currentUserService.currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};
  $scope.cards       = $scope.cards        || [];

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
    if(!$scope.cards.length){
      $scope.errorMessage = "You don't have any cards, add one.";
    } else {
      $scope.focusAmount = true;
    }
    $scope.showCardForm = !$scope.cards.length;
    $scope.loaded = true;
    setSelectedCardId();
  });

  var setSelectedCardId = function(){
    if($scope.cards.length){
      $scope.selectedCardId = _.find($scope.cards, function(card){
          return card.default;
      }).id;
    }
  };

  $scope.isSelectedCard = function(card){
    return (card.id === $scope.selectedCardId);
  };

  $scope.setSelectedCard = function(card){
    $scope.selectedCardId = card.id;
  };

  $scope.showAddCardButton = function(){
    return !$scope.showCardForm && ($scope.cards.length < 3);
  };

  $scope.showingAddFunds = function(){
    return !$scope.showCardForm && $scope.cards.length;
  };

  $scope.close = function(){
    dialog.close();
  };


  var saveCardCallback = function(st, stripeResp){
    if(st === 200){
      var token = stripeResp['id'];
      fs.cards.create(token).then(function(resp){
        $scope.saveCardSpinner = false;
        if(resp.error){
          $scope.errorMessage = resp.error;
        } else {
          $scope.cards = resp.cards || [];
          setSelectedCardId();
          $scope.cardInfo = {};
          $scope.showCardForm = false;
          $scope.focusAmount = true;
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
    } else if(cardInfo.address_zip.length !== 5){
      $scope.errorMessage = "Zip code doesn't look right";
      return false;
    } else {
      return true;
    }
  };

  $scope.saveCard = function(){
    $scope.errorMessage   = null;
    $scope.successMessage = null;
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

  $scope.$watch('cardInfo.number', function(){
    $scope.cardInfo.number = $scope.cardInfo.number && $scope.cardInfo.number.match(/\d{4}(?=\d{2,3})|\d+/g).join("-");
  });

  $scope.addFunds = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    $scope.addMoneySpinner = true;
    fs.user.addMoney(amt, $scope.selectedCardId).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.close();
      flash.success = "Success, $" + $scope.chargeAmt + " added your your account.";
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
      setSelectedCardId();
    });
  };

}]);
