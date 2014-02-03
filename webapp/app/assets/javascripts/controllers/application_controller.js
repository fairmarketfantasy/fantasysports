angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'registrationService', 'rosters', '$location', 'flash', '$dialog', '$timeout', '$route', '$routeParams',
            function($scope, fs, currentUserService, registrationService, rosters, $location, flash, $dialog, $timeout, $route, $routeParams) {

  $scope.sports = window.App.sports;
  $scope.fs = fs;
  $scope.$routeParams = $routeParams;

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;
  $scope.$watch('currentUserService.currentUser', function(newVal) {$scope.currentUser = newVal;}, true);

  $scope.sportHasPlayoffs = function() {
    return _.find(App.sports, function(s) { return s.name == $scope.currentUser.currentSport; } ).playoffs_on;
  };

  // Watch the sport scope
  $scope.$watch(function() { return $route.current && $route.current.params.sport; }, function(newSport, oldSport) {
    if (!App.currentUser) { return; }
    App.currentUser.currentSport = newSport;
  });

  $scope.signUpModal = function(msg, opts) {
    registrationService.signUpModal(msg, opts);
  }

  $scope.loginModal = function() {
    registrationService.loginModal();
  }

  $scope.forgotPasswordModal = function() {
    registrationService.forgotPasswordModal();
  }

  $scope.resetPasswordModal = function(token){
    currentUserService.resetPasswordModal(token);
  };

  $scope.addFundsModal = function(){
    currentUserService.addFundsModal();
  };

  $scope.addFanFreesModal = function(){
    currentUserService.addFanFreesModal();
  };

  $scope.withdrawFundsModal = function(){
    currentUserService.withdrawFundsModal();
  };

  $scope.settingsModal = function(){
    currentUserService.settingsModal();
  };

  $scope.inThePast = function(time) {
    if (!time) {
      return false;
    }
    return new Date(time) < new Date();
  };

  // TODO: deprecate this and switch them all to inThePast
  $scope.gameStarted = function(game) {
    return new Date(game.game_time) < new Date();
  };

  $scope.log = function(obj) {
    console && console.log(obj);
  };

  if ($location.search().autologin) {
    var message = $location.search().autologin;
    $location.search('autologin', null);
    $scope.signUpModal(message);
  }
  if ($location.search().flash) {
    var msg = '' + $location.search().flash.replace(/\+/g, ' ');
    $location.search('flash', null);
    $timeout(function() {
      flash.success(msg);
    })
  }

}]);
