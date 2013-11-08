angular.module("app.controllers")
.controller('SupportController', ["$scope", "fs", "flash", function($scope, fs, flash) {
  var reset = function() {
    $scope.email = $scope.currentUser.email;
    $scope.title = "";
    $scope.message = "";
    $scope.working = false;
  };
  reset();

  $scope.send = function() {
    if ($scope.message.replace(/^\s+|\s+$/g, '') == "") {
      flash.error("Please fill out the message");
      return;
    }
    $scope.working = true;
    fs.sendSupportRequest($scope.title, $scope.email, $scope.message).then(function() {
      $scope.working = false;
      flash.success("Support message sent successfully. You should hear from us soon!");
      reset();
    });
  };
}]);
