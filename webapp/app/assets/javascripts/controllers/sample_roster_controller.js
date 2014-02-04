angular.module("app.controllers")
.controller('SampleRosterController', [ '$scope', 'fs', 'registrationService', function($scope, fs, registrationService) {

  $scope.reloadRoster = function(reload) {
    $scope.roster = undefined;
    fs.rosters.getSample(reload).then(function(roster) {
      $scope.roster = roster;
    });
  };

  $scope.reloadRoster();
}]);

