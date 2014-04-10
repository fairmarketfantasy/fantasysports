module Referrals
  def handle_promos(resp)
    if session[:promo_code]
      promo = Promo.where(['code = ? AND valid_until > ?', session[:promo_code], Time.new]).first
      #raise HttpException(404, "No such promotion") unless promo
      promo.redeem!(current_user) if promo
    end
  end

  def handle_referral(resp)
    if session[:referral_code]
      Invitation.redeem(current_user, session[:referral_code])
      session.delete(:referral_code)
    end
  end

  def handle_roster_claiming(resp)
    if params[:claim_roster]
      existing = Roster.find(params[:claim_roster])
      roster = Roster.generate(current_user, existing.contest_type)
      roster.build_from_existing(existing)
      resp.merge! redirect: "/#{existing.market.sport.name}/market/#{existing.market_id}/roster/#{roster.id}", flash: "Thanks for signing up. Let's get that roster entered."
    end
  end

  def handle_contest_joining(resp)
    Rails.logger.debug '=' * 40
    Rails.logger.debug session
    if session[:contest_code]
      contest = Contest.where(:invitation_code => session[:contest_code]).first
      if contest.private?
        roster = contest.rosters.select{|r| r.owner_id == current_user.id }.first
        #raise HttpException.new(403, "You already have a roster in this contest") if contest.rosters.map(&:owner_id).include?(current_user.id)
        roster ||= Roster.generate(current_user, contest.contest_type)
        roster.update_attribute(:contest_id, contest.id)
      else
        roster = Roster.generate(current_user, contest.contest_type)
      end
      session.delete(:contest_code)
      resp.merge! redirect: "/#{contest.market.sport.name}/market/#{contest.market_id}/roster/#{roster.id}", flash: "Great! We put you in your buddy's contest.  Now let's make a roster"
    end
  end

  def handle_referrals(sport_name = nil)
    resp = {}
    handle_promos(resp)
    handle_referral(resp)
    handle_roster_claiming(resp)
    handle_contest_joining(resp)
    unless resp[:redirect]
      sport_name ||= Sport.where('is_active').first.name
      resp[:redirect] = "/#{sport_name}/home"
    end

    resp
  end

end
