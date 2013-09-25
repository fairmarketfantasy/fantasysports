angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', '$dialog', function($scope, rosters, $dialog) {
  $scope.rosters = rosters;
  rosters.fetchMine();
  rosters.setPoller(function() { rosters.fetchMine(); }, 10000);

  $scope.openInviteModal = function() {
    if (!rosters.justSubmittedRoster) { return; }
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/invite.html',
          controller: 'InviteController'
        };

    var d = $dialog.dialog(dialogOpts);
    d.open();
  };
}]);

