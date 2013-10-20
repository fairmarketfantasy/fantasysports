angular.module("app.controllers")
.controller('AddFundsDialogController', ['$scope', 'dialog', 'fs', 'flash', 'currentUserService', '$timeout', function($scope, dialog, fs, flash, currentUserService, $timeout) {
  $timeout(function() { $scope.card = new Skeuocard($("#credit-card-form")); }, 0);

  $scope.currentUser = currentUserService.currentUser;
  $scope.cardInfo    = $scope.cardInfo     || {};
  $scope.cards       = $scope.cards        || [];

  fs.cards.list().then(function(resp){
    $scope.cards = resp.cards || [];
    if(!$scope.cards.length){
      flash.error = "You don't have any cards, add one.";
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
      $scope.showCardForm = false;
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

  $scope.saveCard = function() {
    if (!$scope.card.isValid()) { return; }
    $scope.saveCardSpinner = true;
    fs.cards.create(
        $scope.card._getUnderlyingValue('type'),
        $scope.card._getUnderlyingValue('number'),
        $scope.card._getUnderlyingValue('cvc'),
        $scope.card._getUnderlyingValue('name'),
        $scope.card._getUnderlyingValue('expMonth'),
        $scope.card._getUnderlyingValue('expYear')
    ).then(function(resp) {
        $scope.saveCardSpinner = false;
        if(resp.error){
          flash.error = resp.error;
        } else {
          $scope.cards = resp.cards || [];
          setSelectedCardId();
          $scope.cardInfo = {};
          $scope.showCardForm = false;
          $scope.focusAmount = true;
          flash.success = "Success, your card was saved.";
        }
    }, function(resp){
        //failure
        $scope.saveCardSpinner = false;
      }
    );
  };

  $scope.addFunds = function(){
    var amt = ($scope.chargeAmt * 100); //dollars to cents
    $scope.addMoneySpinner = true;
    fs.user.addMoney(amt, $scope.selectedCardId).then(function(resp){
      window.App.currentUser.balance = resp.balance;
      $scope.close();
      flash.success = "Success, $" + $scope.chargeAmt + " added your your account.";
      $scope.chargeAmt = null;
      $scope.addMoneySpinner = false;
    }, function(resp){
      //failure
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
