package com.mustwin.market.core;

import org.skife.jdbi.v2.StatementContext;
import org.skife.jdbi.v2.tweak.ResultSetMapper;

import java.sql.Date;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * User: spont200
 * Date: 8/11/13
 */
public class Roster implements ResultSetMapper<Roster> {
    private long id;

    private long ownerId;
    private Date createdAt;
    private int marketId;
    private int contestId;
    private int buyIn;
    private int remainingSalary;
    private boolean isValid;
    private int finalPoints;
    private int finishPlace;
    private int amountPaid;
    private Date paidAt;
    private boolean cancelled;
    private String cancelledCause;
    private Date cancelledAt;

    @Override
    public Roster map(int index, ResultSet r, StatementContext ctx) throws SQLException {
        Roster roster = new Roster();
        roster.id = r.getInt("id");
        roster.ownerId = r.getInt("owner_id");
        roster.marketId = r.getInt("market_id");
        roster.contestId = r.getInt("contest_id");
        roster.buyIn = r.getInt("buy_in");
        roster.remainingSalary = r.getInt("remaining_salary");
        roster.isValid = r.getBoolean("is_valid");
        roster.finalPoints = r.getInt("final_points");
        roster.finishPlace = r.getInt("finish_place");
        roster.amountPaid = r.getInt("amount_paid");
        roster.paidAt = r.getDate("paid_at");
        roster.cancelled = r.getBoolean("cancelled");
        roster.cancelledCause = r.getString("cancelled_cause");
        roster.cancelledAt = r.getDate("cancelled_at");

        return roster;

    }

    public long getId() {
        return id;
    }

    public void setId(long id) {
        this.id = id;
    }

    public long getOwnerId() {
        return ownerId;
    }

    public void setOwnerId(long ownerId) {
        this.ownerId = ownerId;
    }

    public Date getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Date createdAt) {
        this.createdAt = createdAt;
    }

    public int getMarketId() {
        return marketId;
    }

    public void setMarketId(int marketId) {
        this.marketId = marketId;
    }

    public int getContestId() {
        return contestId;
    }

    public void setContestId(int contestId) {
        this.contestId = contestId;
    }

    public int getBuyIn() {
        return buyIn;
    }

    public void setBuyIn(int buyIn) {
        this.buyIn = buyIn;
    }

    public int getRemainingSalary() {
        return remainingSalary;
    }

    public void setRemainingSalary(int remainingSalary) {
        this.remainingSalary = remainingSalary;
    }

    public boolean isValid() {
        return isValid;
    }

    public void setValid(boolean valid) {
        isValid = valid;
    }

    public int getFinalPoints() {
        return finalPoints;
    }

    public void setFinalPoints(int finalPoints) {
        this.finalPoints = finalPoints;
    }

    public int getFinishPlace() {
        return finishPlace;
    }

    public void setFinishPlace(int finishPlace) {
        this.finishPlace = finishPlace;
    }

    public int getAmountPaid() {
        return amountPaid;
    }

    public void setAmountPaid(int amountPaid) {
        this.amountPaid = amountPaid;
    }

    public Date getPaidAt() {
        return paidAt;
    }

    public void setPaidAt(Date paidAt) {
        this.paidAt = paidAt;
    }

    public boolean isCancelled() {
        return cancelled;
    }

    public void setCancelled(boolean cancelled) {
        this.cancelled = cancelled;
    }

    public String getCancelledCause() {
        return cancelledCause;
    }

    public void setCancelledCause(String cancelledCause) {
        this.cancelledCause = cancelledCause;
    }

    public Date getCancelledAt() {
        return cancelledAt;
    }

    public void setCancelledAt(Date cancelledAt) {
        this.cancelledAt = cancelledAt;
    }

}
