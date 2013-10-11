angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', '$dialog', function($scope, rosters, $dialog) {
  $scope.rosters = rosters;
  rosters.fetchMine();
  rosters.fetchPastStats();
  rosters.setPoller(function() { rosters.fetchMine(); }, 10000);

  // Force them to set a user!
  if (_.isEmpty($scope.currentUser.username)) {
    var dialogOpts = {
          backdrop: true,
          keyboard: false,
          backdropClick: false,
          dialogClass: 'modal',
          templateUrl: '/add_username_modal.html',
          controller: 'UserNameController'
        };
    var d = $dialog.dialog(dialogOpts);
    d.open();
  }

}]);

