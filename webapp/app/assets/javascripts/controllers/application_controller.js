angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', 'currentUserService', 'registrationService', 'rosters', '$location', 'flash', '$dialog', '$timeout', '$route', '$routeParams','markets','$timeout',
            function($scope, fs, currentUserService, registrationService, rosters, $location, flash, $dialog, $timeout, $route, $routeParams, marketService, $timeout) {

  if(!currentUserService.currentUser){
    $location.path('/')
  }

  $scope.landingShow = true;
  $scope.disable = false;
  $scope.$on('enableNavBar', function() {
    $scope.disable = false;
  });

  $scope.sports = window.App.sports;
  $scope.defaultSport = window.App.defaultSport;
  $scope.fs = fs;
  $scope.$routeParams = $routeParams;

  $scope.marketService = marketService;

  $scope.currentUserService = currentUserService;
  $scope.currentUser = currentUserService.currentUser;
  $scope.currentLandingSport = $routeParams.sport;

  $scope.$watch('currentUserService.currentUser', function(newVal) {$scope.currentUser = newVal;}, true);

  $scope.sportHasPlayoffs = function() {
    var sport = _.find(App.sports, function(s) { return s.name == $scope.currentUser.currentSport; } );
    return sport && sport.playoffs_on;
  };

  // Watch the sport scope
  $scope.$watch(function() { return $route.current && $route.current.params.sport; }, function(newSport, oldSport) {
    $scope.disable = true;
    if (!App.currentUser || !newSport) { return; }
    console.log(newSport);
    App.currentUser.currentSport = newSport;
  });
  $scope.$watch(function() { return $route.current && $route.current.params.category; }, function(newSport, oldSport) {
    if (!App.currentUser || !newSport) { return; }
    console.log(newSport);
    App.currentUser.currentCategory = newSport;
  });

//    $scope.reloadRoster = function(id, sport) {
//        $scope.roster = undefined;
//        fs.rosters.getSample(id, sport).then(function(roster) {
//            $scope.roster = roster;
//        });
//    };

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
