angular.module("app.controllers")
.controller('LoginController', ['$scope', '$dialog', function($scope, $dialog) {

  $scope.signUpModal = function(){
    var dialogOpts = {
          backdrop: true,
          keyboard: true,
          backdropClick: true,
          dialogClass: 'modal',
          templateUrl: '/assets/sign_up_dialog.html',
          controller: 'SignUpDialogController',
        };

     var d = $dialog.dialog(dialogOpts);
     d.open();
  };

  var serviceSizes = {
    facebook: 'height=460,width=730',
    /*  linkedin: 'height=260,width=630', // customize these
      google: 'height=260,width=630'*/
  };

  $scope.login = function(service) {
    if(service === 'email'){
      fs.user.login($scope.user).then(function(resp){
        // window.setCurrentUser(resp);
        window.location.reload(true);
      });
    } else {
      window.open('/users/auth/' + service, '', serviceSizes[service]);
    }
  };

}]);

