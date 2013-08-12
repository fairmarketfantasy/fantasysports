package com.mustwin.market.core;

import com.google.common.collect.Maps;
import org.skife.jdbi.v2.StatementContext;
import org.skife.jdbi.v2.tweak.ResultSetMapper;

import java.sql.Date;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Map;
import java.util.concurrent.ConcurrentMap;

/**
 * User: spont200
 * Date: 8/8/13
 */
public class Market implements ResultSetMapper<Market> {

    private long id;
    private String name;
    private int shadowBets;
    private Date createdAt;
    private Date publishedAt;
    private Date openedAt;
    private Date closedAt;
    private Date updatedAt;
    private MarketState state;

    private ConcurrentMap<Long, Roster> rosters = Maps.newConcurrentMap();
    private Map<Long, Player> players = Maps.newHashMap();
    private int totalBets;

    public Roster getRoster(long rosterId) {
        return rosters.get(rosterId);
    }

    public Player getPlayer(long playerId) {
        return players.get(playerId);
    }

    public Roster addRoster(Roster roster) {
        return rosters.putIfAbsent(roster.getId(), roster);
    }

    public int getTotalBets() {
        return totalBets;
    }


    public enum MarketState {
        created,
        published,
        opened,
        closed,
    }
    public Market() {}

    public Market(int id) {
        this.id = id;
    }

    private void setState() {
        state = closedAt != null ? MarketState.closed :
                openedAt != null ? MarketState.opened :
                publishedAt != null ? MarketState.published :
                MarketState.created;
    }

    @Override
    public Market map(int index, ResultSet r, StatementContext ctx) throws SQLException {
        Market m = new Market();
        m.id = r.getInt("id");
        m.name = r.getString("name");
        m.shadowBets = r.getInt("shadow_bets");
        m.createdAt = r.getDate("created_at");
        m.publishedAt = r.getDate("published_at");
        m.openedAt = r.getDate("opened_at");
        m.closedAt = r.getDate("closed_at");
        m.updatedAt = r.getDate("updated_at");
        m.setState();
        return m;
    }

    @Override
    public String toString() {
        return "Market{" +
                "id=" + id +
                ", name='" + name + '\'' +
                ", shadowBets=" + shadowBets +
                ", createdAt=" + createdAt +
                ", publishedAt=" + publishedAt +
                ", openedAt=" + openedAt +
                ", closedAt=" + closedAt +
                ", updatedAt=" + updatedAt +
                '}';
    }

    public long getId() {
        return id;
    }

    public void setId(long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getShadowBets() {
        return shadowBets;
    }

    public void setShadowBets(int shadowBets) {
        this.shadowBets = shadowBets;
    }

    public Date getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Date createdAt) {
        this.createdAt = createdAt;
    }

    public Date getPublishedAt() {
        return publishedAt;
    }

    public void setPublishedAt(Date publishedAt) {
        this.publishedAt = publishedAt;
    }

    public Date getOpenedAt() {
        return openedAt;
    }

    public void setOpenedAt(Date openedAt) {
        this.openedAt = openedAt;
    }

    public Date getClosedAt() {
        return closedAt;
    }

    public void setClosedAt(Date closedAt) {
        this.closedAt = closedAt;
    }

    public Date getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Date updatedAt) {
        this.updatedAt = updatedAt;
    }

    public MarketState getState() {
        return state;
    }

    public void setState(MarketState state) {
        this.state = state;
    }

}
