angular.module('app.services')
  .factory('currentUserService', ['$dialog', function($dialog) {
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
  }])
  .factory('fsAPIInterceptor', ['$q', 'flash', 'currentUserService', '$injector', function($q, flash, currentUserService, $injector) {
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
          currentUserService.addFundsModal();
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
        return $q.reject(resp);
        return null; // TODO: this doesn't signal failure...figure out how to do that
      }
      return promise.then(success, failure);
    };
  }])
 .factory('fs', ['$http', function($http) {
    return {
      user: {
        // logout: function(){
        //   return $http({method: 'DELETE', url: '/users/sign_out'});
        // },
        create: function(user_attrs){
          return $http({method: 'POST', url: '/users', data: {user: user_attrs}});
        },
        login: function(user_attrs){
          return $http({method: 'POST', url: '/users/sign_in', data: {user: user_attrs}});
        },
        addMoney: function(amount){
          return $http({method: 'POST', url: '/users/add_money', data: {amount: amount} });
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
        },
        destroy: function(cardId){
          return $http({method: 'DELETE', url: '/cards/' + cardId});
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
        for_market: function(market_id) {
          return $http({method: 'GET', url: '/contests/for_market/' + market_id });
        },
        join: function(contest_type_id, copy_roster_id) {
          return $http({method: 'POST', url: '/rosters', data: {contest_type_id: contest_type_id, copy_roster_id: copy_roster_id}});
        }
      },
      games: {
        list: function(market_id) {
          return $http({method: 'GET', url: '/games/for_market/' + market_id});
        }
      },
      players: {
        list: function(roster_id, opts) {
          opts = opts || {}
          return $http({method: 'GET', url: '/players/', params: angular.extend(opts, {roster_id: roster_id})});
        }
      },
      events: {
        for_player: function(market_id, players) {
          return $http({method: 'GET', url: '/events/for_player', params: {player_ids: _.map(players, function(elt) { return elt.stats_id})} });
        },
      },
      rosters: {
        add_player: function(roster_id, player_id) {
          return $http({method: 'POST', url: '/rosters/' + roster_id + '/add_player/' + player_id});
        },
        remove_player: function(roster_id, player_id) {
          return $http({method: 'POST', url: '/rosters/' + roster_id + '/remove_player/' + player_id});
        },
        show: function(id) {
          return $http({method: 'GET', url: '/rosters/' + id});
        },
        mine: function() {
          return $http({method: 'GET', url: '/rosters/mine'});
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
  }]);

