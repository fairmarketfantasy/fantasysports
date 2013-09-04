angular.module('app.services')
  .factory('fsAPIInterceptor', ['models', 'flash', '$injector', function(models, flash, $injector) {
// TODO: this is where jsonH stuff will go
    var $dialog;
    return function(promise) {
      var success = function(resp) {
        if (resp.headers()['content-type']  === "application/json; charset=utf-8") {
          if (resp.data.data) {
            return JSONH.unpack(resp.data.data);
          }
          return resp.data;
        }
        return resp;
      }, failure = function(resp) {
        if(resp.status == 402) {
          // TODO: implement payment modal
        }
        // TODO: we'll need to implement this again
        if (resp.status == 403) {
        /*  var dialogOpts = {
            backdrop: true,
            keyboard: true,
            backdropClick: true,
            dialogClass: 'modal signin-modal',
            templateUrl: 'assets/login_modal.html',
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
        return null; // TODO: this doesn't signal failure...figure out how to do that
      }
      return promise.then(success, failure);
    };
  }])
 .factory('fs', ['$http', function($http) {
    return {
      user: {
        logout: function(){
          return $http({method: 'DELETE', url: '/users/sign_out'});
        },
        create: function(user_attrs){
          return $http({method: 'POST', url: '/users', data: {user: user_attrs}});
        },
        login: function(user_attrs){
          return $http({method: 'POST', url: '/users/sign_in', data: {user: user_attrs}});
        }
      },
      recipients: {
        list: function(){
          return $http({method: 'GET', url: '/recipients'});
        },
        create: function(recipient_attrs){
          return $http({method: 'POST', url: '/recipients', data: {recipient: recipient_attrs}});
        }
      },
      cards: {
        list: function(){
          return $http({method: 'GET', url: '/cards'});
        },
        create: function(token){
          return $http({method: 'POST', url: '/cards', data: {token: token}});
        }
      },
      markets: {
        show: function(id) {
          return $http({method: 'GET', url: '/markets/' + id});
        },
        list: function() {
          return $http({method: 'GET', url: '/markets'});
        }
      },
      contests: {
        join: function(market_id, type, buy_in) {
          return $http({method: 'POST', url: '/rosters', data: {market_id: market_id, contest_type: type, buy_in: buy_in}})
        }
      },
      games: {
        list: function(market_id) {
          return $http({method: 'GET', url: '/games/for_market/' + market_id});
        }
      },
      players: {
        list: function(market_id, opts) {
          opts = opts || {}
          return $http({method: 'GET', url: '/players/', params: angular.extend(opts, {market_id: market_id})});
        }
      },
      rosters: {
        add_player: function(roster_id, player_id) {
          return $http({method: 'POST', url: '/rosters/' + roster_id + '/add_player/' + player_id});
        },
        remove_player: function(roster_id, player_id) {
          return $http({method: 'POST', url: '/rosters/' + roster_id + '/remove_player/' + player_id});
        },
        list: function(roster_id) {
          return $http({method: 'GET', url: '/players/for_roster/' + roster_id});
        },
        submit: function(roster_id) {
          return $http({method: 'POST', url: '/rosters/' + roster_id + '/submit'});
        },
        cancel: function(roster_id) {
          return $http({method: 'DELETE', url: '/rosters/' + roster_id});
        },
      },
    }
  }])
  .config(['$httpProvider', function($httpProvider) {
    $httpProvider.responseInterceptors.push('fsAPIInterceptor');
  }])

