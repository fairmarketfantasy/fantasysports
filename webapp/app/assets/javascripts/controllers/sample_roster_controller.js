angular.module("app.controllers")
.controller('SampleRosterController', [ '$scope', 'fs', 'registrationService', function($scope, fs, registrationService) {
  fs.rosters.getSample().then(function(roster) {
    $scope.roster = roster;
  });
}]);

