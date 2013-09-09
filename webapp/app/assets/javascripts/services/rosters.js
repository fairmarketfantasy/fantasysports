angular.module('app.data')
  .factory('rosters', ['fs', '$q', 'flash', function(fs, $q, flash) {
    var rosterData = {};
    return new function() {
      var fetchRoster = function(id) {
      };

      this.currentRoster = null;
      this.inProgressRoster = null;
      this.justSubmittedRoster = null;

      // TODO: maybe make this the only public function for fetching mine?
      this.mine = function() {
        return _.filter(rosterData, function(roster) {
          return roster.owner_id === window.App.currentUser.id;
        });
      };

      this.startRoster = function() {

      };

      var fetchMineMemo = false;
      this.fetchMine = function() {
        if (fetchMineMemo) {
          var fakeDeferred = $q.defer();
          fakeDeferred.resolve(this.mine());
          return fakeDeferred.promise;
        }
        return fs.rosters.mine().then(function(rosters) {
          _.each(rosters, function(roster) {
            rosterData[roster.id] = roster;
          });
          fetchMineMemo = true;
          return rosters;
        });
      };

      this.selectRoster = function(roster) {
        var self = this;
        this.currentRoster = roster;
        if (roster.state === 'in_progress') {
          this.inProgressRoster = roster;
        }
        this.positionList = roster.positions.split(',');
        this.uniqPositionList = _.uniq(this.positionList);
        var players = roster.players;
        this.currentRoster.players = [];
        _.each(this.positionList, function(str) {
          self.currentRoster.players.push({position: str});
        });
        _.each(players, function(p) {
          self.addPlayer(p, true);
        });
      };


      this.addPlayer = function(player, init) {
        var self = this;
        var index = _.findIndex(this.currentRoster.players, function(p) { return p.position == player.position && !p.id; });
        if (index >= 0) {
          if (init) { // Used for adding initial players from an existing roster
            this.currentRoster.players[index] = player;
          } else {
            fs.rosters.add_player(this.currentRoster.id, player.id).then(function(market_order) {
              self.currentRoster.remaining_salary -= market_order.price;
              player.purchase_price = market_order.price;
              player.sell_price = market_order.price;
              self.currentRoster.players[index] = player;
            });
          }
        } else {
          flash.error = "No room for another " + player.position + " in your roster.";
        }
      };

      this.removePlayer = function(player) {
        var self = this;
        fs.rosters.remove_player(this.currentRoster.id, player.id).then(function(market_order) {
          self.currentRoster.remaining_salary = parseFloat(self.currentRoster.remaining_salary) + parseFloat(market_order.price);
          var index = _.findIndex(self.currentRoster.players, function(p) { return p.id === player.id; });
          self.currentRoster.players[index] = {position: player.position};
        });
      };

      this.reset = function() {
        this.currentRoster = null;
        this.inProgressRoster = null;
        this.justSubmittedRoster = null;
      }

      this.submit = function() {
        var self = this;
        fs.rosters.submit(this.currentRoster.id).then(function(roster) {
          self.reset();
          self.justSubmittedRoster = roster;
        });
      };

      this.cancel = function() {
        var self = this;
        if (this.currentRoster.state != 'in_progress') {
          flash.error("You can only cancel rosters that are in progress");
          return;
        }
        fs.rosters.cancel(this.currentRoster.id).then(function(data) {
          self.reset();
          $location.path('/');
        });
      };
    };
  }])
.run(['$rootScope', 'rosters', function($rootScope, rosters) {
  if(window.App.currentUser){
    rosters.inProgressRoster = window.App.currentUser.in_progress_roster;
  }
}]);

