angular.module('app.services')
  .factory('fsAPIInterceptor', ['models', 'flash', '$injector', function(models, flash, $injector) {
// TODO: this is where jsonH stuff will go
    var $dialog;
    return function(promise) {
      var success = function(resp) {
        if (resp.headers()['content-type']  === "application/json; charset=utf-8") {
          return JSONH.unpack(resp.data.data)
        }
        return resp;
      }, failure = function(resp) {
        // TODO: we'll need to implement this again
        if(resp.status == 403) {
        /*  var dialogOpts = {
            backdrop: true,
            keyboard: true,
            backdropClick: true,
            dialogClass: 'modal signin-modal',
            templateUrl: 'partials/login_modal.html',
            controller: 'LoginController'
          };
          $dialog = $injector.get('$dialog');
          var openLoginModal = function(){
            var d = $dialog.dialog(dialogOpts);
            d.open();
          };
          openLoginModal();*/
        } else if (resp.data.error) {
          flash.error = resp.data.error;
        } else {
          flash.error = "Oops, something went wrong, try again later";
        }
        console && console.log('API Error: ');
        console.log(resp);
        return null;
      }
      return promise.then(success, failure);
    };
  }])
 .factory('fs', ['$http', function($http) {
    return {
      markets: {
        list: function() {
          return $http({method: 'GET', url: '/markets'});
        }
      }
    }
  }])
  .config(['$httpProvider', function($httpProvider) {
    $httpProvider.responseInterceptors.push('fsAPIInterceptor');
  }])

