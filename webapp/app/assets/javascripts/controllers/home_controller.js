angular.module("app.controllers")
.controller('HomeController', ['$scope', 'rosters', '$dialog', '$location', function($scope, rosters, $dialog, $location) {
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

  $scope.showNextLeagueRoster = function(league) {
    $scope.fs.contests.join_league(league.id).then(function(data){
      rosters.selectRoster(data);
      $location.path('/market/' + data.market.id + '/roster/' + data.id);
    });
  };

  //$scope.$watch('league')

}]);

