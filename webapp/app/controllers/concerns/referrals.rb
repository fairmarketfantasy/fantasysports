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

  def handle_contest_joining(resp)
    Rails.logger.debug '=' * 40
    Rails.logger.debug session
    if session[:contest_code]
      contest = Contest.where(:invitation_code => session[:contest_code]).first
      if contest.private?
        raise HttpException.new(403, "You already have a roster in this contest") if contest.rosters.map(&:owner_id).include?(current_user.id)
        roster = Roster.generate(current_user, contest.contest_type)
        roster.update_attribute(:contest_id, contest.id)
      else
        roster = Roster.generate(current_user, contest.contest_type)
      end
      session.delete(:contest_code)
      resp.merge! redirect: "/market/#{contest.market_id}/roster/#{roster.id}", flash: "Great! We put you in your buddy's contest.  Now let's make a roster"
    end
  end

  def handle_referrals
    resp = {}
    handle_promos(resp)
    handle_referral(resp)
    handle_contest_joining(resp)
    resp
  end

end
