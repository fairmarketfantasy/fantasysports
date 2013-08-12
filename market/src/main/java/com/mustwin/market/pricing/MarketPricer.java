package com.mustwin.market.pricing;

/**
 * User: spont200
 * Date: 8/11/13
 */
public interface MarketPricer {

    int price(double playerBets, int totalBets, int buyIn);

}
