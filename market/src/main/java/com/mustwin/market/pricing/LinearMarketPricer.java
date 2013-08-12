package com.mustwin.market.pricing;

/**
 * User: spont200
 * Date: 8/11/13
 */
public class LinearMarketPricer implements MarketPricer {

    private final int b;
    private final int m;

    public LinearMarketPricer(int m, int b) {
        this.m = m;
        this.b = b;
    }

    @Override
    public int price(double playerBets, int totalBets, int buyIn) {
        double p = playerBets / totalBets;
        return (int) Math.round(m * p + b);
    }
}
