angular.module("app.controllers")
.controller('ApplicationController', ['$scope', 'fs', '$location', 'flash', function($scope, fs, $location, flash) {

  $scope.fs = fs;

  $scope.currentUser = function() {
    return window.App.currentUser;
  };

  // Put the user back on their in progress roster, if applicable.  # TODO: this may not work yet...and the check may need to be elsewhere
  if ($scope.currentUser() && $scope.currentUser().in_progress_roster) {
    flash.message = "Looks like you already have a roster going.  Let's finish entering!"
    var roster = $scope.currentUser().in_progress_roster;
    $location.path('/market/' + roster.market_id);
    $scope.roster = roster;
  }
}])
