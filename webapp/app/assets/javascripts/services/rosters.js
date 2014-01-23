angular.module('app.data')
  .factory('rosters', ['fs', '$q', '$location', 'flash', 'currentUserService', '$dialog', function(fs, $q, $location, flash, currentUserService, $dialog) {
    var rosterData = {};
    return new function() {
      var fetchRoster = function(id) {
      };

      this.currentRoster = null;
      this.inProgressRoster = null;
      this.justSubmittedRoster = null;

      // TODO: maybe make this the only public function for fetching mine?
      // TODO: memoize this and myLiveStats
      this.mine = function() {
        return _.filter(rosterData, function(roster) {
          return roster.owner_id === window.App.currentUser.id;
        });
      };

      this.pastStats = function() {
        return pastStats;
      };

      this.myLiveStats = function() {
        var stats = {top: 0, avg: 0, total_payout: 0, total_score: 0, count: 0};
        _.each(this.mine(), function(roster) {
          stats.count++;
          stats.total_score += roster.score;
          stats.total_payout += roster.contest_rank_payout || 0;
          if (stats.top < roster.score) {
            stats.top = roster.score;
          }
        });
        stats.avg = stats.total_score / stats.count;
        return stats;
      };

      this.top = function(limit) {
        var top = _.sortBy(
          _.filter(this.mine(), function(roster) { return roster.state == 'submitted'; }),
          function(r) { return -(new Date(r.started_at)).valueOf(); }
        );
        if (limit) {
          top = top.slice(0, limit);
        }
        return top;
      };

      // Takes a value and a function returning a promise. If value is present, we return
      // a promise resolved with that value. If not, we return the fetchPromise
      var promiseWrapper = function(value, fetchPromise) {
        if (value && !value.abridged) {
          var fakeDeferred = $q.defer();
          fakeDeferred.resolve(value);
          return fakeDeferred.promise;
        } else {
          return fetchPromise();
        }
      };

      this.fetch = function(id, view_code) {
        return promiseWrapper(rosterData[id], function() {
          return fs.rosters.show(id, view_code).then(function(roster) {
            rosterData[roster.id] = roster;
            return roster;
          });
        });
      };

      this.fetchMine = function(opts) {
        return fs.rosters.mine(opts).then(function(rosters) {
          _.each(rosters, function(roster) {
            rosterData[roster.id] = roster;
          });
          return rosters;
        });
      };

      var pastStats;
      this.fetchPastStats = function() {
        // TODO: add throttle, effectively a cache TTL
        return promiseWrapper(pastStats, function() {
          return fs.rosters.past_stats().then(function(stats) {
            pastStats = stats;
          });
        });
      };

      this.fetchContest = function(contest_id, upToPage) {
        upToPage = upToPage || 1;
        return fs.rosters.in_contest(contest_id, upToPage).then(function(rosters) {
          _.each(rosters, function(roster) {
            rosterData[roster.id] = roster;
          });
          return rosters;
        });
      };

      // Used on init to order players properly
      this._addPlayersToRoster = function(roster){
        var players = roster.players;
        roster.players = [];
        _.each(this.positionList, function(str) {
          roster.players.push({position: str});
        });
        _.each(players, function(p) {
          roster.players[indexForPlayerInRoster(roster, p)] = p;
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
        this._addPlayersToRoster(this.currentRoster);
      };

      this.selectOpponentRoster = function(roster) {
        this.opponentRoster = roster;
        if (roster) {
          this._addPlayersToRoster(roster);
        }
      }

      var indexForPlayerInRoster = function(roster, player) {
        return _.findIndex(roster.players, function(p) { return p.position == player.position && !p.id; });
      };

      this.addPlayer = function(player, init) {
        var self = this;
        var index = indexForPlayerInRoster(this.currentRoster, player)
        if (index >= 0) {
          return fs.rosters.add_player(this.currentRoster.id, player.id).then(function(market_order) {
            self.currentRoster.remaining_salary -= parseInt(market_order.price);
            player.purchase_price = market_order.price;
            player.sell_price = market_order.price;
            self.currentRoster.players[index] = player;
          });
        } else {
          flash.error("No room for another " + player.position + " in your roster.");
        }
      };

      this.removePlayer = function(player) {
        this.selectOpponentRoster(null);
        var self = this;
          var index = _.findIndex(self.currentRoster.players, function(p) { return p.id === player.id; });
          self.currentRoster.players[index] = {position: player.position};
        fs.rosters.remove_player(this.currentRoster.id, player.id).then(
          function(market_order) {
            self.currentRoster.remaining_salary = parseFloat(self.currentRoster.remaining_salary) + parseFloat(market_order.price);
          },
          function() {
            self.currentRoster.players[index] = player;
          }
        );
      };

      this.nextPosition = function(justAddedPlayer) {
        var self = this;
        var nextPositions = this.uniqPositionList.slice(_.findIndex(this.uniqPositionList, function(p) { return (justAddedPlayer || self.currentRoster.players.first).position == p; }));
        return _.find(nextPositions, function(position) {
          if (indexForPlayerInRoster(self.currentRoster, {position: position}) >= 0) {
            return position;
          }
        });
      };

      this.reset = function(path) {
        clearInterval(this.poller);
        this.currentRoster = null;
        this.inProgressRoster = null;
        this.justSubmittedRoster = null;
        this.poller = null;
        if (path) {
          $location.path(path);
        }
      };

      this.submit = function() {
        var deferred = $q.defer();

        var self = this;
        fs.rosters.submit(this.currentRoster.id).then(function(roster) {
          if (roster.contest_type.takes_tokens) {
            currentUserService.currentUser.token_balance -= roster.buy_in;
          } else {
            currentUserService.currentUser.balance -= roster.buy_in;
          }
          self.reset();
          currentUserService.refreshUser();
          deferred.resolve(roster);
          //self.justSubmittedRoster = roster;
        });

        return deferred.promise;
      };

      this.cancel = function() {
        var self = this;
        if (this.currentRoster.state != 'in_progress') {
          flash.error("You can only cancel rosters that are in progress");
          return;
        }
        var currentRoster = this.currentRoster;
        this.currentRoster = null;
        fs.rosters.cancel(currentRoster.id).then(function(data) {
          delete rosterData[currentRoster.id];
          self.reset();
          $location.path('/market/' + currentRoster.market.id);
        });
      };

      this.toggleRemoveBenched = function() {
        var self = this;
        fs.rosters.toggleRemoveBenched(this.currentRoster.id).then(function(roster) {
          self.selectRoster(roster);
        });
      };

      this.autoFill = function() {
        var self = this;
        fs.rosters.autoFill(this.currentRoster.id).then(function(roster) {
          self.selectRoster(roster);
        });
      };

      this.openInviteFriends = function(roster) {
        var dialogOpts = {
              backdrop: true,
              keyboard: true,
              backdropClick: true,
              dialogClass: 'modal',
              templateUrl: '/invite.html',
              controller: 'InviteController',
            };

        var d = $dialog.dialog(dialogOpts);
        d.open().then(function(result) {
          if (!result) { return; }
          fs.contests.invite(roster.contest_id, result.invitees, result.message, roster.contest.invitation_code).then(function() {
            flash.success("Invitations sent successfully");
          });
        });
      };

      this.setPoller = function(fn, interval) {
        clearInterval(this.poller);
        this.poller = setInterval(fn, interval);
      };
    }();
  }])
.run(['$rootScope', 'rosters', function($rootScope, rosters) {
  if(window.App.currentUser){
    rosters.inProgressRoster = window.App.currentUser.in_progress_roster;
  }
}]);

