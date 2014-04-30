angular.module('app.data')
  .factory('rosters', ['fs', '$q', '$location', 'flash', 'currentUserService', '$dialog', function(fs, $q, $location, flash, currentUserService, $dialog) {
    var rosterData = {};
    var predictionData = {};
    return new function() {
      var fetchRoster = function(id) {
      };

      this.currentRoster = null;
      this.inProgressRoster = null;
      this.justSubmittedRoster = null;



      // TODO: maybe make this the only public function for fetching mine?
      // TODO: memoize this and myLiveStats
      this.mine = function(opts) {
        return _.filter(rosterData, function(roster) {
            if(roster.sport == opts){
                return roster.owner_id === window.App.currentUser.id;
            }
        });
      };

      this.pastStats = function() {
        return pastStats;
      };

      this.myLiveStats = function(opts) {
        var stats = {top: 0, avg: 0, total_payout: 0, total_score: 0, count: 0};
        _.each(this.mine(opts), function(roster) {
            if(roster.sport == opts){
              stats.count++;
              stats.total_score += roster.score;
              stats.total_payout += roster.contest_rank_payout || 0;
              if (stats.top < roster.score) {
                stats.top = roster.score;
              }
            }
        });
        stats.avg = stats.total_score / stats.count;
        return stats;
      };

      this.top = function(opts, limit) {
        var top = _.sortBy(
          _.filter(this.mine(opts), function(roster) { return roster.state == 'submitted'; }),
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
            $.extend(rosterData[roster.id], opts)
          });
          return rosters;
        });
      };

      this.fetchMinePrediction = function(opts) {
        return fs.prediction.mine(opts).then(function(rosters) {
          _.each(rosters, function(prediction) {
              predictionData[prediction.id] = prediction;
            $.extend(predictionData[prediction.id], opts)
          });
          return rosters;
        });
      };

      var pastStats;
      this.fetchPastStats = function(opts) {
        // TODO: add throttle, effectively a cache TTL
        return fs.rosters.past_stats(opts).then(function(stats) {
          pastStats = stats;
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
          return fs.rosters.add_player(this.currentRoster.id, player.id, player.position).then(function(market_order) {
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

      this.submit = function(gameType) {
        var deferred = $q.defer();

        var self = this;
        fs.rosters.submit(this.currentRoster.id, gameType).then(function(roster) {
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
          $location.path('/' + currentUserService.currentUser.currentSport + '/market/' + currentRoster.market.id);
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

      this.playerNoBorder = function(data){
        if(data % 2 != 0){
          return null;
        }else {
          return data-2
        }
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

