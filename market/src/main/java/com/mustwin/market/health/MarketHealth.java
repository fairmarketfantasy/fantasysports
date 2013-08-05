package com.mustwin.market.health;

import com.yammer.metrics.core.HealthCheck;

/**
 * User: spont200
 * Date: 8/5/13
 */
public class MarketHealth extends HealthCheck {

    public MarketHealth(String name) {
        super(name);
    }

    @Override
    protected Result check() throws Exception {
        return Result.healthy();
    }
}
