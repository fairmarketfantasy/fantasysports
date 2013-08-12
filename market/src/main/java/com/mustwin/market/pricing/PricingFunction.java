package com.mustwin.market.pricing;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * User: spont200
 * Date: 8/11/13
 */
public class PricingFunction {

    @JsonProperty
    public FunctionType type;
    public double a;
    public double b;

    public enum FunctionType {
        linear,
    }
}
