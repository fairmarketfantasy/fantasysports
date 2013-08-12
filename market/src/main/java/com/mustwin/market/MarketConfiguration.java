package com.mustwin.market;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.mustwin.market.pricing.PricingFunction;
import com.yammer.dropwizard.config.Configuration;
import com.yammer.dropwizard.db.DatabaseConfiguration;

import javax.validation.Valid;
import javax.validation.constraints.NotNull;

/**
 * User: spont200
 * Date: 8/5/13
 */
public class MarketConfiguration extends Configuration {

    @Valid
    @NotNull
    @JsonProperty
    private DatabaseConfiguration database = new DatabaseConfiguration();

    public DatabaseConfiguration getDatabaseConfiguration() {
        return database;
    }

    @Valid @NotNull @JsonProperty
    private PricingFunction pricingFunction;

    public PricingFunction getPricingFunction() {
        return pricingFunction;
    }

    public void setPricingFunction(PricingFunction pricingFunction) {
        this.pricingFunction = pricingFunction;
    }
}
