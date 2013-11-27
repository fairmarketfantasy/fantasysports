angular.module('app.services')
  .factory('registrationService', function($dialog, $timeout) {
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
      signUpModal: function(){
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/sign_up_dialog.html',
              controller: 'SignUpDialogController'
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
      }
    };

  });
