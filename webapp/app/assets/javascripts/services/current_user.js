angular.module('app.services')
  .factory('currentUserService', ['fs', '$dialog', function(fs, $dialog) {
    return {
      currentUser: window.App.currentUser,
      addFundsModal: function(){
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/assets/add_funds_dialog.html',
              controller: 'AddFundsDialogController'
            };

        var d = $dialog.dialog(dialogOpts);
        d.open();
      }
    };
  }]);

