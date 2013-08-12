package com.mustwin.market.api;

import java.sql.Date;

/**
 * User: spont200
 * Date: 8/8/13
 */
public class MarketOrder {

    private Action action;
    private long marketId;
    private long contestId;
    private long rosterId;
    private long playerId;

    private int price;

    private boolean rejected;
    private boolean rejectedReason;

    private Date createdAt;

    public MarketOrder() {}

    public MarketOrder(Action action, int marketId, int contestId, int rosterId, int playerId) {
        this.action = action;
        this.marketId = marketId;
        this.contestId = contestId;
        this.rosterId = rosterId;
        this.playerId = playerId;
    }



    public enum Action {
        publish,
        open,
        close,
        buy,
        sell
    }
    public Action getAction() {
        return action;
    }

    public void setAction(Action action) {
        this.action = action;
    }

    public long getMarketId() {
        return marketId;
    }

    public void setMarketId(long marketId) {
        this.marketId = marketId;
    }

    public long getContestId() {
        return contestId;
    }

    public void setContestId(long contestId) {
        this.contestId = contestId;
    }

    public long getRosterId() {
        return rosterId;
    }

    public void setRosterId(long rosterId) {
        this.rosterId = rosterId;
    }

    public long getPlayerId() {
        return playerId;
    }

    public void setPlayerId(long playerId) {
        this.playerId = playerId;
    }

    public int getPrice() {
        return price;
    }

    public void setPrice(int price) {
        this.price = price;
    }

    public boolean isRejected() {
        return rejected;
    }

    public void setRejected(boolean rejected) {
        this.rejected = rejected;
    }

    public boolean isRejectedReason() {
        return rejectedReason;
    }

    public void setRejectedReason(boolean rejectedReason) {
        this.rejectedReason = rejectedReason;
    }

    public Date getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Date createdAt) {
        this.createdAt = createdAt;
    }

}
