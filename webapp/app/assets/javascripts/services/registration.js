angular.module('app.services')
  .factory('registrationService', ['$dialog', '$timeout', function($dialog, $timeout) {
    return {
      showModal: function(name) {
        if (name == 'signUp') {
          this.signUpModal();
        } else if (name == 'login') {
          this.loginModal();
        } else if (name == 'forgotPassword') {
          this.forgotPasswordModal();
        }
      },
      signUpModal: function(message){
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/sign_up_dialog.html',
              controller: 'SignUpDialogController',
              resolve: {message: function(){ return message; }},
            };

        var d = $dialog.dialog(dialogOpts);
        d.open();
        $timeout(function() {
            $.placeholder.shim();
        });
      },
      loginModal: function(message){
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/login_dialog.html',
              controller: 'LoginDialogController',
              resolve: {message: function(){ return message; }},
            };

        var d = $dialog.dialog(dialogOpts);
        d.open();
        $timeout(function() {
            $.placeholder.shim();
        });
      },
      forgotPasswordModal: function(message){
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/forgot_password_dialog.html',
              controller: 'ForgotPasswordDialogController',
              resolve: {message: function(){ return message; }},
            };

        var d = $dialog.dialog(dialogOpts);
        d.open();
        $timeout(function() {
            $.placeholder.shim();
        });
      },
      login: function(service) {
        var serviceSizes = {
          facebook: 'height=460,width=730',
          /*  linkedin: 'height=260,width=630', // customize these
            google: 'height=260,width=630'*/
        };
        if(service === 'email'){
          fs.user.login($scope.user).then(function(resp){
            // window.setCurrentUser(resp);
            window.location.reload(true);
          });
        } else {
          window.open('/users/auth/' + service, '', serviceSizes[service]);
        }
      }
    };

  }]);
