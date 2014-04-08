--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: buy(integer, integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
	_market_player market_players;
	_market markets;
	_price numeric;
BEGIN
	SELECT * FROM rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--if the roster is in progress, we can just add the player to the roster without locking on the market
	IF _roster.state = 'in_progress' THEN
		INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
			values (_player_id, _roster_id, 0, _market_player.player_stats_id, _roster.market_id);
		RETURN;
	END IF;

	-- Check if roster already has player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF FOUND THEN
		RAISE EXCEPTION 'player % already in roster %', _player_id, _roster_id;
	END IF;

	-- TODO: test positional requirements here
	-- Get price, test salary cap
	SELECT * from markets WHERE id = _roster.market_id and state in ('published', 'opened') 
		INTO _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	SELECT * FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _market_player;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is locked or nonexistent', _player_id;
	END IF;

	SELECT price(_market_player.bets, _market.total_bets, _roster.buy_in, _market.price_multiplier) INTO _price;

	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
		values  (_player_id, _roster_id, _price, _market_player.player_stats_id, _market.id);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price WHERE id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price);
END;
$$;


ALTER FUNCTION public.buy(_roster_id integer, _player_id integer) OWNER TO fantasysports;

--
-- Name: buy_prices(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION buy_prices(_roster_id integer) RETURNS TABLE(player_id integer, buy_price numeric)
    LANGUAGE sql
    AS $_$
	SELECT mp.player_id, price(mp.bets, m.total_bets, r.buy_in, m.price_multiplier)
	FROM market_players mp, markets m, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		mp.locked = false AND
		mp.player_id NOT IN (SELECT rosters_players.player_id FROM rosters_players WHERE roster_id = $1);
$_$;


ALTER FUNCTION public.buy_prices(_roster_id integer) OWNER TO fantasysports;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: markets; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE markets (
    id integer NOT NULL,
    name character varying(255),
    shadow_bets numeric NOT NULL,
    shadow_bet_rate numeric NOT NULL,
    opened_at timestamp without time zone,
    closed_at timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    published_at timestamp without time zone,
    state character varying(255),
    total_bets numeric,
    sport_id integer NOT NULL,
    initial_shadow_bets numeric,
    price_multiplier numeric DEFAULT 1,
    started_at timestamp without time zone
);


ALTER TABLE public.markets OWNER TO fantasysports;

--
-- Name: lock_players(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION lock_players(_market_id integer, OUT _market markets) RETURNS markets
    LANGUAGE plpgsql
    AS $$
DECLARE
	_locked_bets numeric := 0;
	_now timestamp;
BEGIN
	--ensure that the market exists and may be closed
	PERFORM id FROM markets WHERE id = _market_id FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % not found', _market_id;
	END IF;

	--for each locked player that has not been removed: lock the player and sum the bets
	select CURRENT_TIMESTAMP INTO _now;

	select sum(bets) from market_players
		WHERE market_id = _market_id and locked_at < _now and locked = false 
		INTO _locked_bets;

	update market_players set locked = true
		WHERE market_id = _market_id and locked_at < _now and locked = false;

	IF _locked_bets > 0 THEN
		--update the price multiplier
		update markets set 
			total_bets = total_bets - _locked_bets, 
			price_multiplier = price_multiplier * (total_bets - _locked_bets) / total_bets
			WHERE id = _market_id returning * into _market;
	END IF;
	
END;
$$;


ALTER FUNCTION public.lock_players(_market_id integer, OUT _market markets) OWNER TO fantasysports;

--
-- Name: open_market(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION open_market(_market_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_real_bets numeric;
	_market markets;
	_new_shadow_bets numeric := 0;
	_price numeric;
	_market_player market_players;
	_roster_id integer;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state = 'published' FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not openable', _market_id;
	END IF;


	--adjust shadow bets:
	--if it's time to open the market, simply remove remaining shadow bets
	--else, ensure that the total number of shadow bets removed from the initial
	--pool of shadow bets is proportial to the number of bets cast, where the coefficient
	--is the shadow_bet_rate
	_real_bets = _market.total_bets - _market.shadow_bets;
	_new_shadow_bets = GREATEST(0, _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate);

	--if the market is published but all games have started, open it so that we can close it properly
	PERFORM 1 FROM games_markets gm JOIN games g on g.stats_id = gm.game_stats_id
		WHERE market_id = _market_id AND g.game_time > CURRENT_TIMESTAMP;
	IF NOT FOUND THEN
		_new_shadow_bets = 0;
	END IF;

	--don't bother with the update if the change is miniscule
	IF _new_shadow_bets != 0 AND _market.shadow_bets - _new_shadow_bets < 10 THEN
		RETURN;
	END IF;

	IF _new_shadow_bets = 0 THEN
		RAISE NOTICE 'opening market %', _market_id;

		--remove all shadow bets from the market
		UPDATE markets SET shadow_bets = 0, total_bets = _real_bets,
			state='opened', opened_at = CURRENT_TIMESTAMP WHERE id = _market_id;

		--remove shadow bets from all players in the market
		UPDATE market_players SET bets = bets-shadow_bets, shadow_bets = 0 WHERE market_id = _market_id;

		--update purchase price for all orders yet placed - in both market_order and rosters_players
	    FOR _market_player IN SELECT * FROM market_players WHERE market_id = _market_id LOOP
	    	SELECT price(_market_player.bets, _market.total_bets, 0, _market.price_multiplier) INTO _price;
	    	UPDATE rosters_players SET purchase_price = _price WHERE player_id = _market_player.player_id;
	    	UPDATE market_orders SET price = _price WHERE player_id = _market_player.player_id;
	    END LOOP;

	    --update the remaining salary for all rosters in the market
	    UPDATE rosters set remaining_salary = 100000 - 
	    	(SELECT sum(purchase_price) FROM rosters_players WHERE roster_id = rosters.id) 
	    	WHERE market_id = _market_id;

	ELSE
		RAISE NOTICE 'updating published market to % shadow bets', _new_shadow_bets;
		UPDATE markets SET shadow_bets = _new_shadow_bets, total_bets = _real_bets + _new_shadow_bets WHERE id = _market_id;
		UPDATE market_players SET
			bets = (bets - shadow_bets) + (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets,
			shadow_bets = (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets
		where market_id = _market_id;
	END IF;

	--return the market -- in whatever state
	SELECT * FROM markets WHERE id = _market_id INTO _market;

END;
$$;


ALTER FUNCTION public.open_market(_market_id integer) OWNER TO fantasysports;

--
-- Name: price(numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
	SELECT ROUND(LEAST(100000, GREATEST(1000, ($1 + $3) * 100000 * $4 / ($2 + $3))));
$_$;


ALTER FUNCTION public.price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) OWNER TO fantasysports;

--
-- Name: publish_market(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION publish_market(_market_id integer, OUT _market markets) RETURNS markets
    LANGUAGE plpgsql
    AS $$
DECLARE
	_total_ppg numeric;
	_game games;
	_bets numeric;
BEGIN
	--ensure that the market exists and may be published
	SELECT * FROM markets WHERE id = _market_id AND published_at < CURRENT_TIMESTAMP AND
			(state is null OR state = '') FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not publishable', _market_id;
	END IF;

	--check that shadow_bets is something reasonable
	IF _market.shadow_bets = 0 THEN
		RAISE NOTICE 'shadow bets is 0, setting to 1000';
		UPDATE markets set shadow_bets = 1000 where id = _market_id;
	END IF;

	--make sure the shadow bet rate is reasonable
	IF _market.shadow_bet_rate <= 0 THEN
		UPDATE markets set shadow_bet_rate = 1 WHERE id = _market_id;
	END IF;

	--just to be safe, re-set the total bets to shadow bets
	UPDATE markets SET 
		total_bets = shadow_bets, initial_shadow_bets = shadow_bets, price_multiplier = 1 
		WHERE id = _market_id;

	--ensure that the market has at least 1 game that has not yet started
	PERFORM 1 FROM games_markets gm JOIN games g on g.stats_id = gm.game_stats_id
		WHERE market_id = _market_id AND g.game_time > CURRENT_TIMESTAMP;
	IF NOT FOUND THEN
		UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP WHERE id = _market_id;
		RAISE NOTICE 'market % has no upcoming games -- will be closed', _market_id;
		return;
	END IF;

	--ensure that there are no associated market_players, market_orders, or rosters.
	--TODO: this is nice for dev and testing but may be a little dangerous in production
	DELETE FROM market_players WHERE market_id = _market_id;
	DELETE FROM market_orders WHERE market_id = _market_id;
	DELETE FROM rosters_players WHERE market_id = _market_id;
	DELETE FROM rosters WHERE market_id = _market_id;

	--get the total ppg. use ghetto lagrangian filtering
	SELECT sum((total_points + .01) / (total_games + .1))
		FROM players WHERE team in (
			SELECT home_team from games g, games_markets gm WHERE gm.market_id = _market_id and g.stats_id = gm.game_stats_id
			UNION
			SELECT away_team from games g, games_markets gm WHERE gm.market_id = _market_id and g.stats_id = gm.game_stats_id
		) INTO _total_ppg;

	-- insert players into market. use the first game time for which the player is participating and calculate shadow bets.
	INSERT INTO market_players (market_id, player_id, shadow_bets, locked_at, player_stats_id)
		SELECT
			_market_id, p.id,
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets,
			min(g.game_time), p.stats_id
		FROM 
			players p, games g, games_markets gm 
		WHERE 
			gm.market_id = _market_id AND
			g.stats_id = gm.game_stats_id AND
			(p.team = g.home_team OR p.team = g.away_team)
		GROUP BY p.id;

	--set bets and initial_shadow_bets shadow bets for all those players we just added - avoids calculating it thrice per player
	UPDATE market_players SET bets = shadow_bets, initial_shadow_bets = shadow_bets WHERE market_id = _market_id;

	--set market to published. reset closed_at time, in case the game time has moved since the market was created
	UPDATE markets SET state = 'published', published_at = CURRENT_TIMESTAMP, price_multiplier = 1,
	 	closed_at = 
	 		(select max(g.game_time) - INTERVAL '5m' from games g 
 			JOIN games_markets gm on g.stats_id = gm.game_stats_id 
 			where gm.market_id = _market_id)
		WHERE id = _market_id returning * into _market;

	RAISE NOTICE 'published market %', _market_id;
END;
$$;


ALTER FUNCTION public.publish_market(_market_id integer, OUT _market markets) OWNER TO fantasysports;

--
-- Name: sell(integer, integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION sell(_roster_id integer, _player_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
	_price numeric;
BEGIN
	SELECT * from rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--if in progress, simply remove from roster and exit stage left
	IF _roster.state = 'in_progress' THEN
		DELETE FROM rosters_players where roster_id = _roster_id AND player_id = _player_id;
		RETURN;
	END IF;

	-- Check if roster has the player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is not in roster %', _player_id, _roster_id;
	END IF;

	-- Get price
	SELECT * FROM markets WHERE id = _roster.market_id and state in ('opened', 'published')
		INTO _market FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;

	IF _market.state = 'opened' THEN
		SELECT price(_bets, _market.total_bets, 0, _market.price_multiplier) INTO _price;
	ELSIF _market.state = 'published' THEN --if market is pre-open, you get back what you paid, no more no less
		SELECT purchase_price FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id INTO _price;
	ELSE
		RAISE EXCEPTION 'unknown market state, panic!';
	END IF;

	--perform the updates.
	DELETE FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id;
	UPDATE markets SET total_bets = total_bets - _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets - _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
	  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price);
END;
$$;


ALTER FUNCTION public.sell(_roster_id integer, _player_id integer) OWNER TO fantasysports;

--
-- Name: sell_prices(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION sell_prices(_roster_id integer) RETURNS TABLE(roster_player_id integer, player_id integer, sell_price numeric, purchase_price numeric, locked boolean)
    LANGUAGE sql
    AS $_$
	SELECT rp.id, mp.player_id, price(mp.bets, m.total_bets, 0, m.price_multiplier), rp.purchase_price, mp.locked
	FROM market_players mp, markets m, rosters_players rp, rosters r
	WHERE
		r.id = $1 AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		r.id = rp.roster_id AND
		mp.player_id = rp.player_id
$_$;


ALTER FUNCTION public.sell_prices(_roster_id integer) OWNER TO fantasysports;

--
-- Name: submit_roster(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION submit_roster(_roster_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
BEGIN
	--make sure the roster is in progress
	SELECT * from rosters where id = _roster_id AND state = 'in_progress' INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist or is not in_progress', _roster_id;
	END IF;

	--make sure that the market is available
	PERFORM id from markets WHERE id = _roster.market_id and state in ('published', 'opened') FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable', _roster.market_id;
	END IF;

	--remove players that are now locked (edge case)
	WITH locked_out AS (
		SELECT rp.id from rosters_players rp, market_players mp
		WHERE 
			rp.roster_id = _roster_id AND
			mp.market_id = _roster.market_id AND
			mp.player_id = rp.player_id AND
			mp.locked_at < CURRENT_TIMESTAMP)
		DELETE FROM rosters_players using locked_out 
		WHERE rosters_players.id = locked_out.id;

	-- increment bets for all market players in roster by buy_in amount
	UPDATE market_players SET bets = bets + _roster.buy_in 
		WHERE market_id = _roster.market_id AND player_id IN
			(SELECT player_id from rosters_players where roster_id = _roster_id); 

	-- increment total_bets by buy_in times number of players bought
	update markets set total_bets = total_bets + 
		_roster.buy_in * (select count(*) from rosters_players where roster_id  = _roster.id)
		where id = _roster.market_id;

	-- update rosters_players with current sell prices of players
	WITH prices as (select roster_player_id, sell_price from sell_prices(_roster_id)) 
		UPDATE rosters_players set purchase_price = prices.sell_price FROM prices 
		WHERE id = prices.roster_player_id;

	-- insert into market_orders
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price, created_at, updated_at)
	   SELECT _roster.market_id, _roster_id, 'buy', player_id, purchase_price, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
	   FROM rosters_players where roster_id = _roster_id;

	--update roster's remaining salary and state
	update rosters set remaining_salary = 100000 - 
		GREATEST(0, (select sum(purchase_price) from rosters_players where roster_id = _roster.id)),
		state = 'submitted', updated_at = CURRENT_TIMESTAMP
		where id = _roster_id;

END;
$$;


ALTER FUNCTION public.submit_roster(_roster_id integer) OWNER TO fantasysports;

--
-- Name: tabulate_scores(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION tabulate_scores(_market_id integer) RETURNS void
    LANGUAGE sql
    AS $_$

	UPDATE market_players set score = 
		(select Greatest(0, sum(point_value)) FROM stat_events 
			WHERE player_stats_id = market_players.player_stats_id and game_stats_id in 
				(select game_stats_id from games_markets where market_id = $1)
		) where market_id = $1;

	UPDATE rosters set score = 
		(select sum(score) from market_players where player_stats_id in 
			(select player_stats_id from rosters_players where roster_id = rosters.id)
		) where market_id = $1;

	WITH ranks as 
		(SELECT id, rank() OVER (PARTITION BY contest_id ORDER BY score DESC) FROM rosters WHERE market_id = $1) 
		UPDATE rosters set contest_rank = rank FROM ranks where rosters.id = ranks.id;

$_$;


ALTER FUNCTION public.tabulate_scores(_market_id integer) OWNER TO fantasysports;

--
-- Name: contest_types; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE contest_types (
    id integer NOT NULL,
    market_id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    max_entries integer NOT NULL,
    buy_in integer NOT NULL,
    rake numeric NOT NULL,
    payout_structure text NOT NULL,
    user_id integer,
    private boolean
);


ALTER TABLE public.contest_types OWNER TO fantasysports;

--
-- Name: contest_types_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE contest_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contest_types_id_seq OWNER TO fantasysports;

--
-- Name: contest_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE contest_types_id_seq OWNED BY contest_types.id;


--
-- Name: contests; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE contests (
    id integer NOT NULL,
    owner_id integer NOT NULL,
    buy_in integer NOT NULL,
    user_cap integer,
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    market_id integer NOT NULL,
    invitation_code character varying(255),
    contest_type_id integer NOT NULL,
    num_rosters integer DEFAULT 0
);


ALTER TABLE public.contests OWNER TO fantasysports;

--
-- Name: contests_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE contests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.contests_id_seq OWNER TO fantasysports;

--
-- Name: contests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE contests_id_seq OWNED BY contests.id;


--
-- Name: customer_objects; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE customer_objects (
    id integer NOT NULL,
    stripe_id character varying(255) NOT NULL,
    user_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    balance integer DEFAULT 0,
    locked boolean DEFAULT false NOT NULL,
    locked_reason text
);


ALTER TABLE public.customer_objects OWNER TO fantasysports;

--
-- Name: customer_objects_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE customer_objects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.customer_objects_id_seq OWNER TO fantasysports;

--
-- Name: customer_objects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE customer_objects_id_seq OWNED BY customer_objects.id;


--
-- Name: game_events; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE game_events (
    id integer NOT NULL,
    stats_id character varying(255),
    sequence_number integer NOT NULL,
    type character varying(255) NOT NULL,
    summary character varying(255) NOT NULL,
    clock character varying(255) NOT NULL,
    data text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    game_stats_id character varying(255) NOT NULL,
    acting_team character varying(255)
);


ALTER TABLE public.game_events OWNER TO fantasysports;

--
-- Name: game_events_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE game_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.game_events_id_seq OWNER TO fantasysports;

--
-- Name: game_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE game_events_id_seq OWNED BY game_events.id;


--
-- Name: games; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE games (
    id integer NOT NULL,
    stats_id character varying(255) NOT NULL,
    status character varying(255) NOT NULL,
    game_day date NOT NULL,
    game_time timestamp without time zone NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    home_team character varying(255) NOT NULL,
    away_team character varying(255) NOT NULL,
    season_type character varying(255),
    season_week integer,
    season_year integer,
    network character varying(255)
);


ALTER TABLE public.games OWNER TO fantasysports;

--
-- Name: games_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.games_id_seq OWNER TO fantasysports;

--
-- Name: games_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE games_id_seq OWNED BY games.id;


--
-- Name: games_markets; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE games_markets (
    id integer NOT NULL,
    game_stats_id character varying(255) NOT NULL,
    market_id integer
);


ALTER TABLE public.games_markets OWNER TO fantasysports;

--
-- Name: games_markets_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE games_markets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.games_markets_id_seq OWNER TO fantasysports;

--
-- Name: games_markets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE games_markets_id_seq OWNED BY games_markets.id;


--
-- Name: market_orders; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE market_orders (
    id integer NOT NULL,
    market_id integer NOT NULL,
    roster_id integer NOT NULL,
    action character varying(255) NOT NULL,
    player_id integer NOT NULL,
    price numeric NOT NULL,
    rejected boolean,
    rejected_reason character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.market_orders OWNER TO fantasysports;

--
-- Name: market_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE market_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.market_orders_id_seq OWNER TO fantasysports;

--
-- Name: market_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE market_orders_id_seq OWNED BY market_orders.id;


--
-- Name: market_players; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE market_players (
    id integer NOT NULL,
    market_id integer NOT NULL,
    player_id integer NOT NULL,
    shadow_bets numeric,
    bets numeric DEFAULT 0,
    locked_at timestamp without time zone,
    initial_shadow_bets numeric,
    locked boolean DEFAULT false,
    score integer DEFAULT 0 NOT NULL,
    player_stats_id character varying(255)
);


ALTER TABLE public.market_players OWNER TO fantasysports;

--
-- Name: market_players_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE market_players_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.market_players_id_seq OWNER TO fantasysports;

--
-- Name: market_players_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE market_players_id_seq OWNED BY market_players.id;


--
-- Name: markets_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE markets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.markets_id_seq OWNER TO fantasysports;

--
-- Name: markets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE markets_id_seq OWNED BY markets.id;


--
-- Name: players; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE players (
    id integer NOT NULL,
    stats_id character varying(255),
    sport_id integer,
    name character varying(255),
    name_abbr character varying(255),
    birthdate character varying(255),
    height integer,
    weight integer,
    college character varying(255),
    "position" character varying(255),
    jersey_number integer,
    status character varying(255),
    total_games integer DEFAULT 0 NOT NULL,
    total_points integer DEFAULT 0 NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    team character varying(255)
);


ALTER TABLE public.players OWNER TO fantasysports;

--
-- Name: players_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE players_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.players_id_seq OWNER TO fantasysports;

--
-- Name: players_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE players_id_seq OWNED BY players.id;


--
-- Name: recipients; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE recipients (
    id integer NOT NULL,
    stripe_id character varying(255) NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.recipients OWNER TO fantasysports;

--
-- Name: recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE recipients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.recipients_id_seq OWNER TO fantasysports;

--
-- Name: recipients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE recipients_id_seq OWNED BY recipients.id;


--
-- Name: rosters; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE rosters (
    id integer NOT NULL,
    owner_id integer NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    market_id integer NOT NULL,
    contest_id integer,
    buy_in integer NOT NULL,
    remaining_salary numeric NOT NULL,
    score integer,
    contest_rank integer,
    amount_paid numeric,
    paid_at timestamp without time zone,
    cancelled_cause character varying(255),
    cancelled_at timestamp without time zone,
    state character varying(255) NOT NULL,
    positions character varying(255),
    submitted_at timestamp without time zone,
    contest_type_id integer DEFAULT 0 NOT NULL,
    cancelled boolean DEFAULT false
);


ALTER TABLE public.rosters OWNER TO fantasysports;

--
-- Name: rosters_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE rosters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rosters_id_seq OWNER TO fantasysports;

--
-- Name: rosters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE rosters_id_seq OWNED BY rosters.id;


--
-- Name: rosters_players; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE rosters_players (
    id integer NOT NULL,
    player_id integer NOT NULL,
    roster_id integer NOT NULL,
    purchase_price numeric DEFAULT 1000 NOT NULL,
    player_stats_id character varying(255),
    market_id integer NOT NULL
);


ALTER TABLE public.rosters_players OWNER TO fantasysports;

--
-- Name: rosters_players_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE rosters_players_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rosters_players_id_seq OWNER TO fantasysports;

--
-- Name: rosters_players_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE rosters_players_id_seq OWNED BY rosters_players.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO fantasysports;

--
-- Name: sports; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE sports (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.sports OWNER TO fantasysports;

--
-- Name: sports_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE sports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sports_id_seq OWNER TO fantasysports;

--
-- Name: sports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE sports_id_seq OWNED BY sports.id;


--
-- Name: stat_events; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE stat_events (
    id integer NOT NULL,
    type character varying(255) NOT NULL,
    data text NOT NULL,
    point_value numeric NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    player_stats_id character varying(255) NOT NULL,
    game_stats_id character varying(255) NOT NULL
);


ALTER TABLE public.stat_events OWNER TO fantasysports;

--
-- Name: stat_events_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE stat_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stat_events_id_seq OWNER TO fantasysports;

--
-- Name: stat_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE stat_events_id_seq OWNED BY stat_events.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE teams (
    id integer NOT NULL,
    sport_id integer NOT NULL,
    abbrev character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    conference character varying(255) NOT NULL,
    division character varying(255) NOT NULL,
    market character varying(255),
    state character varying(255),
    country character varying(255),
    lat numeric,
    long numeric,
    standings text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.teams OWNER TO fantasysports;

--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.teams_id_seq OWNER TO fantasysports;

--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE teams_id_seq OWNED BY teams.id;


--
-- Name: transaction_records; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE transaction_records (
    id integer NOT NULL,
    event character varying(255) NOT NULL,
    user_id integer,
    roster_id integer,
    amount integer
);


ALTER TABLE public.transaction_records OWNER TO fantasysports;

--
-- Name: transaction_records_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE transaction_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.transaction_records_id_seq OWNER TO fantasysports;

--
-- Name: transaction_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE transaction_records_id_seq OWNED BY transaction_records.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    email character varying(255) DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying(255) DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying(255),
    reset_password_sent_at timestamp without time zone,
    remember_created_at timestamp without time zone,
    sign_in_count integer DEFAULT 0,
    current_sign_in_at timestamp without time zone,
    last_sign_in_at timestamp without time zone,
    current_sign_in_ip character varying(255),
    last_sign_in_ip character varying(255),
    provider character varying(255),
    uid character varying(255),
    confirmation_token character varying(255),
    confirmed_at timestamp without time zone,
    unconfirmed_email character varying(255),
    confirmation_sent_at timestamp without time zone,
    admin boolean DEFAULT false,
    image_url character varying(255)
);


ALTER TABLE public.users OWNER TO fantasysports;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO fantasysports;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: venues; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE venues (
    id integer NOT NULL,
    stats_id character varying(255),
    country character varying(255),
    state character varying(255),
    city character varying(255),
    type character varying(255),
    name character varying(255),
    surface character varying(255)
);


ALTER TABLE public.venues OWNER TO fantasysports;

--
-- Name: venues_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE venues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.venues_id_seq OWNER TO fantasysports;

--
-- Name: venues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE venues_id_seq OWNED BY venues.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY contest_types ALTER COLUMN id SET DEFAULT nextval('contest_types_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY contests ALTER COLUMN id SET DEFAULT nextval('contests_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY customer_objects ALTER COLUMN id SET DEFAULT nextval('customer_objects_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY game_events ALTER COLUMN id SET DEFAULT nextval('game_events_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY games ALTER COLUMN id SET DEFAULT nextval('games_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY games_markets ALTER COLUMN id SET DEFAULT nextval('games_markets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY market_orders ALTER COLUMN id SET DEFAULT nextval('market_orders_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY market_players ALTER COLUMN id SET DEFAULT nextval('market_players_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY markets ALTER COLUMN id SET DEFAULT nextval('markets_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY players ALTER COLUMN id SET DEFAULT nextval('players_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY recipients ALTER COLUMN id SET DEFAULT nextval('recipients_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY rosters ALTER COLUMN id SET DEFAULT nextval('rosters_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY rosters_players ALTER COLUMN id SET DEFAULT nextval('rosters_players_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY sports ALTER COLUMN id SET DEFAULT nextval('sports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY stat_events ALTER COLUMN id SET DEFAULT nextval('stat_events_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY teams ALTER COLUMN id SET DEFAULT nextval('teams_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY transaction_records ALTER COLUMN id SET DEFAULT nextval('transaction_records_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY venues ALTER COLUMN id SET DEFAULT nextval('venues_id_seq'::regclass);


--
-- Data for Name: contest_types; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY contest_types (id, market_id, name, description, max_entries, buy_in, rake, payout_structure, user_id, private) FROM stdin;
\.


--
-- Name: contest_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('contest_types_id_seq', 1, false);


--
-- Data for Name: contests; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY contests (id, owner_id, buy_in, user_cap, start_time, end_time, created_at, updated_at, market_id, invitation_code, contest_type_id, num_rosters) FROM stdin;
\.


--
-- Name: contests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('contests_id_seq', 1, false);


--
-- Data for Name: customer_objects; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY customer_objects (id, stripe_id, user_id, created_at, updated_at, balance, locked, locked_reason) FROM stdin;
\.


--
-- Name: customer_objects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('customer_objects_id_seq', 1, false);


--
-- Data for Name: game_events; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY game_events (id, stats_id, sequence_number, type, summary, clock, data, created_at, updated_at, game_stats_id, acting_team) FROM stdin;
\.


--
-- Name: game_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('game_events_id_seq', 1, false);


--
-- Data for Name: games; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY games (id, stats_id, status, game_day, game_time, created_at, updated_at, home_team, away_team, season_type, season_week, season_year, network) FROM stdin;
1	7049af11-be32-463a-b291-017601a041f0	closed	2013-08-04	2013-08-05 00:00:00	2013-09-14 23:47:54.62845	2013-09-14 23:47:54.628452	DAL	MIA	PRE	0	2013	NBC
2	2158cc5b-8a73-4b57-b94e-11d4924653f6	closed	2013-08-08	2013-08-08 23:30:00	2013-09-14 23:47:54.634409	2013-09-14 23:47:54.634412	TB	BAL	PRE	1	2013	
3	48b1b6b3-9cd3-4ba9-994e-6e683c0835ab	closed	2013-08-08	2013-08-09 00:00:00	2013-09-14 23:47:54.638386	2013-09-14 23:47:54.638389	ATL	CIN	PRE	1	2013	ESPN
4	947526b4-ef31-4f90-bf40-798b762b2d14	closed	2013-08-08	2013-08-09 00:00:00	2013-09-14 23:47:54.642403	2013-09-14 23:47:54.642406	TEN	WAS	PRE	1	2013	
5	f62832ca-ae40-4665-b656-8cc1d505fab4	closed	2013-08-08	2013-08-09 00:00:00	2013-09-14 23:47:54.646279	2013-09-14 23:47:54.646281	CLE	STL	PRE	1	2013	
6	77b8b88e-340a-41bf-a168-66ae8e7f1942	closed	2013-08-08	2013-08-09 01:00:00	2013-09-14 23:47:54.649535	2013-09-14 23:47:54.649537	SF	DEN	PRE	1	2013	
7	f74c5b3e-417e-46f3-a9ff-2ec9d54e2596	closed	2013-08-08	2013-08-09 02:00:00	2013-09-14 23:47:54.653136	2013-09-14 23:47:54.653139	SD	SEA	PRE	1	2013	NFL
8	35568bb9-513b-4d8d-b863-0275683fbf9d	closed	2013-08-09	2013-08-09 23:30:00	2013-09-14 23:47:54.656991	2013-09-14 23:47:54.656994	JAC	MIA	PRE	1	2013	
9	1137b780-b2a8-41b9-8748-ac2fc51c2af4	closed	2013-08-09	2013-08-09 23:30:00	2013-09-14 23:47:54.660595	2013-09-14 23:47:54.660598	DET	NYJ	PRE	1	2013	
10	ec2c4504-0722-4e81-8680-6eaae821deaf	closed	2013-08-09	2013-08-09 23:30:00	2013-09-14 23:47:54.663981	2013-09-14 23:47:54.663983	PHI	NE	PRE	1	2013	NFL
11	f6703798-2d38-423b-b4ea-ea7a786f994f	closed	2013-08-09	2013-08-10 00:00:00	2013-09-14 23:47:54.667037	2013-09-14 23:47:54.667039	GB	ARI	PRE	1	2013	
12	69632ae5-db8b-40e7-a858-a8cadbdec767	closed	2013-08-09	2013-08-10 00:00:00	2013-09-14 23:47:54.670302	2013-09-14 23:47:54.670305	CAR	CHI	PRE	1	2013	
13	87faa628-2d0c-4cf5-9271-500715bf79f8	closed	2013-08-09	2013-08-10 00:00:00	2013-09-14 23:47:54.673983	2013-09-14 23:47:54.673985	NO	KC	PRE	1	2013	
14	e1fdd7c9-02c2-4b25-8c83-6325970768d8	closed	2013-08-09	2013-08-10 00:00:00	2013-09-14 23:47:54.677439	2013-09-14 23:47:54.677443	MIN	HOU	PRE	1	2013	
15	0a5ad96c-53f9-477e-95f0-cd456176b00a	closed	2013-08-09	2013-08-10 02:00:00	2013-09-14 23:47:54.680667	2013-09-14 23:47:54.680669	OAK	DAL	PRE	1	2013	NFL
16	e24fff4c-a509-4fb5-80bc-bc95aa9ab09a	closed	2013-08-10	2013-08-10 23:30:00	2013-09-14 23:47:54.683718	2013-09-14 23:47:54.683721	PIT	NYG	PRE	1	2013	
17	ccab4c86-922c-4dd2-9edd-ed6b6bf29239	closed	2013-08-11	2013-08-11 17:30:00	2013-09-14 23:47:54.686805	2013-09-14 23:47:54.686806	IND	BUF	PRE	1	2013	
18	03af509b-cf23-4131-a930-e2128a7c4ca2	closed	2013-08-15	2013-08-15 23:30:00	2013-09-14 23:47:54.689398	2013-09-14 23:47:54.689401	BAL	ATL	PRE	2	2013	
19	bfebb3e2-44fc-42d2-8791-024e9ecacbcc	closed	2013-08-15	2013-08-15 23:30:00	2013-09-14 23:47:54.695402	2013-09-14 23:47:54.695404	PHI	CAR	PRE	2	2013	
20	612a7635-75d2-49c4-ba49-39dd48931f7f	closed	2013-08-15	2013-08-15 23:30:00	2013-09-14 23:47:54.698875	2013-09-14 23:47:54.698877	CLE	DET	PRE	2	2013	
21	bb702d78-7f58-4599-a40a-c396dccfdd6b	closed	2013-08-15	2013-08-16 00:00:00	2013-09-14 23:47:54.701732	2013-09-14 23:47:54.701734	CHI	SD	PRE	2	2013	ESPN
22	16c73abc-acca-41ac-bf05-56ddff423e03	closed	2013-08-16	2013-08-16 23:00:00	2013-09-14 23:47:54.705038	2013-09-14 23:47:54.70504	BUF	MIN	PRE	2	2013	
23	e88cf3c6-43c5-4837-984f-bb9a1138ed92	closed	2013-08-16	2013-08-17 00:00:00	2013-09-14 23:47:54.708362	2013-09-14 23:47:54.708364	NO	OAK	PRE	2	2013	
24	378a3ecf-fb9a-4d7c-87a5-c3abd75c996a	closed	2013-08-16	2013-08-17 00:00:00	2013-09-14 23:47:54.711262	2013-09-14 23:47:54.711264	NE	TB	PRE	2	2013	FOX
25	afe21447-7588-48a7-b5f8-f7bfbe161133	closed	2013-08-16	2013-08-17 00:00:00	2013-09-14 23:47:54.714023	2013-09-14 23:47:54.714026	KC	SF	PRE	2	2013	
26	76da5490-a99d-49c8-a3b7-d21ed86622f5	closed	2013-08-17	2013-08-17 20:30:00	2013-09-14 23:47:54.717201	2013-09-14 23:47:54.717204	ARI	DAL	PRE	2	2013	NFL
27	3f83ccab-a11c-419d-bb9d-caa9bec2066c	closed	2013-08-17	2013-08-17 23:00:00	2013-09-14 23:47:54.720365	2013-09-14 23:47:54.720369	CIN	TEN	PRE	2	2013	
28	c4b01fc6-cf01-4a37-9ad5-243624426ace	closed	2013-08-17	2013-08-17 23:30:00	2013-09-14 23:47:54.723899	2013-09-14 23:47:54.723901	NYJ	JAC	PRE	2	2013	NFL
29	9379c390-daa9-4533-acfd-25f0a27cfebb	closed	2013-08-17	2013-08-18 00:00:00	2013-09-14 23:47:54.727062	2013-09-14 23:47:54.727064	HOU	MIA	PRE	2	2013	
30	25995327-329d-4cca-8b5d-36e8fb4ff870	closed	2013-08-17	2013-08-18 00:00:00	2013-09-14 23:47:54.730275	2013-09-14 23:47:54.730277	STL	GB	PRE	2	2013	
31	ced27f3b-3a28-44dd-a617-9c6366dc0ef2	closed	2013-08-17	2013-08-18 02:00:00	2013-09-14 23:47:54.733394	2013-09-14 23:47:54.733396	SEA	DEN	PRE	2	2013	NFL
32	c5c86073-c8c1-4ea8-b6d0-182e0518e447	closed	2013-08-18	2013-08-18 23:00:00	2013-09-14 23:47:54.736504	2013-09-14 23:47:54.736507	NYG	IND	PRE	2	2013	FOX
33	10c6bb82-53fc-4bc8-bc89-166adeeee26b	closed	2013-08-19	2013-08-20 00:00:00	2013-09-14 23:47:54.739815	2013-09-14 23:47:54.739817	WAS	PIT	PRE	2	2013	ESPN
34	2b5e3daf-719f-4ded-87ee-097b0f99f86d	closed	2013-08-22	2013-08-22 23:30:00	2013-09-14 23:47:54.743024	2013-09-14 23:47:54.743026	DET	NE	PRE	3	2013	
35	57df450a-5125-483b-953d-b2e71b1859dc	closed	2013-08-22	2013-08-23 00:00:00	2013-09-14 23:47:54.746167	2013-09-14 23:47:54.74617	BAL	CAR	PRE	3	2013	ESPN
36	5123bb8a-d2af-420d-9156-6b2735d44850	closed	2013-08-23	2013-08-24 00:00:00	2013-09-14 23:47:54.749266	2013-09-14 23:47:54.749269	GB	SEA	PRE	3	2013	CBS
37	011419f4-1a16-45f1-b308-105f7b673090	closed	2013-08-23	2013-08-24 02:00:00	2013-09-14 23:47:54.752483	2013-09-14 23:47:54.752486	OAK	CHI	PRE	3	2013	NFL
38	8f8f93f2-46af-4142-ac13-7dc534fb5891	closed	2013-08-24	2013-08-24 20:30:00	2013-09-14 23:47:54.755559	2013-09-14 23:47:54.755561	WAS	BUF	PRE	3	2013	NFL
39	28be6c50-b1f4-4ce6-9860-86901a3d3d9d	closed	2013-08-24	2013-08-24 23:00:00	2013-09-14 23:47:54.758616	2013-09-14 23:47:54.758618	IND	CLE	PRE	3	2013	
40	cd5be605-b6f3-43f5-83f2-cbd48895a0fc	closed	2013-08-24	2013-08-24 23:00:00	2013-09-14 23:47:54.762068	2013-09-14 23:47:54.762072	NYG	NYJ	PRE	3	2013	
41	349984d3-a858-4756-ad63-f77dd97c81ea	closed	2013-08-24	2013-08-24 23:30:00	2013-09-14 23:47:54.765022	2013-09-14 23:47:54.765026	PIT	KC	PRE	3	2013	
42	c50c4944-f00b-4207-b7e9-fe2fcd89da26	closed	2013-08-24	2013-08-24 23:30:00	2013-09-14 23:47:54.76842	2013-09-14 23:47:54.768424	JAC	PHI	PRE	3	2013	
43	21c73b6a-bb6e-43e5-a58a-8ccdb50c5d2d	closed	2013-08-24	2013-08-24 23:30:00	2013-09-14 23:47:54.771479	2013-09-14 23:47:54.771481	MIA	TB	PRE	3	2013	
44	a2eea7a6-4779-402d-9968-897b616131df	closed	2013-08-24	2013-08-25 00:00:00	2013-09-14 23:47:54.774247	2013-09-14 23:47:54.774249	DEN	STL	PRE	3	2013	CBS
45	98e0bf4a-dad8-4817-8ece-05f1d5f943c0	closed	2013-08-24	2013-08-25 00:00:00	2013-09-14 23:47:54.777174	2013-09-14 23:47:54.777177	DAL	CIN	PRE	3	2013	
46	dd92b86d-813c-4fd3-8286-680614001cfe	closed	2013-08-24	2013-08-25 00:00:00	2013-09-14 23:47:54.780271	2013-09-14 23:47:54.780275	TEN	ATL	PRE	3	2013	
47	5386936c-0fb7-4484-8f2e-d2e4394dadcf	closed	2013-08-24	2013-08-25 02:00:00	2013-09-14 23:47:54.783449	2013-09-14 23:47:54.783452	ARI	SD	PRE	3	2013	NFL
48	e10d2ccf-f68e-4df8-af5e-1382c4031644	closed	2013-08-25	2013-08-25 20:00:00	2013-09-14 23:47:54.786856	2013-09-14 23:47:54.786859	HOU	NO	PRE	3	2013	FOX
49	31b47f4a-7a5e-4251-af88-f77a9f5bf0bc	closed	2013-08-25	2013-08-26 00:00:00	2013-09-14 23:47:54.790101	2013-09-14 23:47:54.790104	SF	MIN	PRE	3	2013	NBC
50	048f8eb7-e72e-4ac0-8943-6eada5e4d632	closed	2013-08-29	2013-08-29 23:00:00	2013-09-14 23:47:54.793051	2013-09-14 23:47:54.793053	CIN	IND	PRE	4	2013	
51	eda4612d-d965-4d82-a1a1-c4a610d60374	closed	2013-08-29	2013-08-29 23:00:00	2013-09-14 23:47:54.796136	2013-09-14 23:47:54.796139	BUF	DET	PRE	4	2013	
52	c5bb17cb-bbd9-4b05-b203-dfb871562633	closed	2013-08-29	2013-08-29 23:00:00	2013-09-14 23:47:54.799025	2013-09-14 23:47:54.799028	NYJ	PHI	PRE	4	2013	
53	a18db579-188c-4d9e-aadd-f52a3cc39794	closed	2013-08-29	2013-08-29 23:30:00	2013-09-14 23:47:54.802087	2013-09-14 23:47:54.80209	MIA	NO	PRE	4	2013	
54	9efef726-f9e2-44fb-bfd8-5be420f0865e	closed	2013-08-29	2013-08-29 23:30:00	2013-09-14 23:47:54.805277	2013-09-14 23:47:54.805279	NE	NYG	PRE	4	2013	NFL
55	186c59c5-769f-4987-9262-56078cc0c206	closed	2013-08-29	2013-08-29 23:30:00	2013-09-14 23:47:54.808792	2013-09-14 23:47:54.808794	CAR	PIT	PRE	4	2013	
56	178bd8e4-ba66-4fee-a364-70a34798a7b3	closed	2013-08-29	2013-08-29 23:30:00	2013-09-14 23:47:54.812239	2013-09-14 23:47:54.812243	TB	WAS	PRE	4	2013	
57	b9f0be14-c9c9-40c4-8b2c-c5838a4372c8	closed	2013-08-29	2013-08-29 23:30:00	2013-09-14 23:47:54.815356	2013-09-14 23:47:54.815358	ATL	JAC	PRE	4	2013	
58	2b32188f-56d9-478c-aae2-25400c25e5ed	closed	2013-08-29	2013-08-30 00:00:00	2013-09-14 23:47:54.818379	2013-09-14 23:47:54.818381	MIN	TEN	PRE	4	2013	
59	76f0307e-b990-4fb6-88d5-e3b9a0391a2c	closed	2013-08-29	2013-08-30 00:00:00	2013-09-14 23:47:54.821537	2013-09-14 23:47:54.821539	CHI	CLE	PRE	4	2013	
60	c4272052-ad4d-4ce1-be07-150f77ffcabe	closed	2013-08-29	2013-08-30 00:00:00	2013-09-14 23:47:54.824663	2013-09-14 23:47:54.824666	DAL	HOU	PRE	4	2013	
61	dd203bfb-f799-4066-8dba-eb3ab2c093bf	closed	2013-08-29	2013-08-30 00:00:00	2013-09-14 23:47:54.830227	2013-09-14 23:47:54.83023	STL	BAL	PRE	4	2013	
62	83072ef1-438b-44d1-b4e7-9b58cf15fb38	closed	2013-08-29	2013-08-30 00:00:00	2013-09-14 23:47:54.833629	2013-09-14 23:47:54.833631	KC	GB	PRE	4	2013	
63	c8323919-77ca-4609-af6a-79e2b69b96fa	closed	2013-08-29	2013-08-30 01:00:00	2013-09-14 23:47:54.836727	2013-09-14 23:47:54.836729	DEN	ARI	PRE	4	2013	
64	abbda9df-5e9f-4400-80da-5a3e4b611cec	closed	2013-08-29	2013-08-30 02:00:00	2013-09-14 23:47:54.839573	2013-09-14 23:47:54.839575	SD	SF	PRE	4	2013	NFL
65	7dfa72f9-f587-4ec3-bff0-0fba0195a271	closed	2013-08-29	2013-08-30 02:00:00	2013-09-14 23:47:54.842497	2013-09-14 23:47:54.842499	SEA	OAK	PRE	4	2013	
66	880d99e7-8c18-4a1a-882c-e0d96e8ecf15	closed	2013-09-05	2013-09-06 00:30:00	2013-09-14 23:47:56.087975	2013-09-14 23:47:56.087976	DEN	BAL	REG	1	2013	NBC
67	e036a429-1be6-4547-a99d-26602db584f9	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.091447	2013-09-14 23:47:56.09145	NO	ATL	REG	1	2013	FOX
68	77c4d7dc-6196-4d58-864d-5e70e06e9070	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.094744	2013-09-14 23:47:56.094747	PIT	TEN	REG	1	2013	CBS
69	b9d81c1f-fa7b-46b3-ada4-4354bc2a9909	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.097614	2013-09-14 23:47:56.097617	NYJ	TB	REG	1	2013	FOX
70	268a558b-ca2a-418e-8f46-8e3ce202363d	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.099297	2013-09-14 23:47:56.099298	BUF	NE	REG	1	2013	CBS
71	4869a6d0-4ef7-4712-a620-d10ffd8722d6	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.101005	2013-09-14 23:47:56.101007	IND	OAK	REG	1	2013	CBS
72	be8f3ead-127f-4ccf-8882-006d18f93b7b	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.103945	2013-09-14 23:47:56.103947	DET	MIN	REG	1	2013	FOX
73	5a28bf90-8f71-479d-9016-9dcd2ebea4c4	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.106626	2013-09-14 23:47:56.106627	CAR	SEA	REG	1	2013	FOX
74	327f19da-5407-49bd-bcc8-298f69d99751	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.109663	2013-09-14 23:47:56.109665	JAC	KC	REG	1	2013	CBS
75	c91ae72a-289b-41c1-ae02-ce7d733bf9a1	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.112363	2013-09-14 23:47:56.112366	CHI	CIN	REG	1	2013	CBS
76	56e13273-73f7-4b57-8e79-e1b88268f32a	closed	2013-09-08	2013-09-08 17:00:00	2013-09-14 23:47:56.115102	2013-09-14 23:47:56.115105	CLE	MIA	REG	1	2013	CBS
77	6726b995-cb4c-4582-b729-fd9c21d063d2	closed	2013-09-08	2013-09-08 20:25:00	2013-09-14 23:47:56.119113	2013-09-14 23:47:56.119116	STL	ARI	REG	1	2013	FOX
78	2b972664-949e-4025-9f3d-48b3484674cd	closed	2013-09-08	2013-09-08 20:25:00	2013-09-14 23:47:56.122995	2013-09-14 23:47:56.122998	SF	GB	REG	1	2013	FOX
79	05e9531d-e7e7-45c8-ae5a-91a2eb8acfa8	closed	2013-09-08	2013-09-09 00:30:00	2013-09-14 23:47:56.1265	2013-09-14 23:47:56.126502	DAL	NYG	REG	1	2013	NBC
80	e6aad620-bbaf-4510-96f0-d2e8086c256d	closed	2013-09-09	2013-09-09 22:55:00	2013-09-14 23:47:56.129584	2013-09-14 23:47:56.129586	WAS	PHI	REG	1	2013	ESPN
81	7dd862f9-21d6-4768-89f8-f82929ae575c	closed	2013-09-09	2013-09-10 02:20:00	2013-09-14 23:47:56.132933	2013-09-14 23:47:56.132936	SD	HOU	REG	1	2013	ESPN
82	270c4e8d-bf5c-4e60-bf20-9add63d900f4	closed	2013-09-12	2013-09-13 00:25:00	2013-09-14 23:47:56.135616	2013-09-14 23:47:56.135618	NE	NYJ	REG	2	2013	NFLN
83	7a0dd3a2-ab98-469e-946b-8f29426b690a	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.138376	2013-09-14 23:47:56.138378	GB	WAS	REG	2	2013	FOX
84	e9274ae1-2eb9-4e72-af54-88c0a20c7959	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.140327	2013-09-14 23:47:56.140329	PHI	SD	REG	2	2013	CBS
85	6489d032-9a0d-4737-b1a5-14dff7bfdc5e	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.142715	2013-09-14 23:47:56.142717	BUF	CAR	REG	2	2013	FOX
86	0613eb13-6c71-4309-b833-ba2fa6412df1	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.145261	2013-09-14 23:47:56.145263	CHI	MIN	REG	2	2013	FOX
87	11484a7c-33e2-4742-b912-c9313d2cd22b	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.148198	2013-09-14 23:47:56.1482	BAL	CLE	REG	2	2013	CBS
88	fd98e184-7339-487a-b74c-3290031afa51	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.154614	2013-09-14 23:47:56.154616	KC	DAL	REG	2	2013	FOX
89	28b6dbec-8530-4999-a088-baab4008039e	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.15731	2013-09-14 23:47:56.157312	IND	MIA	REG	2	2013	CBS
90	922b1d35-bb06-4991-bf7e-518d9c413dc7	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.160402	2013-09-14 23:47:56.160404	HOU	TEN	REG	2	2013	CBS
91	7d813a68-ba3f-4d7c-92d6-ebc5220bab6f	created	2013-09-15	2013-09-15 17:00:00	2013-09-14 23:47:56.163513	2013-09-14 23:47:56.163516	ATL	STL	REG	2	2013	FOX
92	6079ba37-2e42-494e-9975-6fafbdb2fc56	created	2013-09-15	2013-09-15 20:05:00	2013-09-14 23:47:56.166738	2013-09-14 23:47:56.16674	TB	NO	REG	2	2013	FOX
93	90fbe39a-4726-4341-8567-65ab4b6ef13b	created	2013-09-15	2013-09-15 20:05:00	2013-09-14 23:47:56.169784	2013-09-14 23:47:56.169786	ARI	DET	REG	2	2013	FOX
94	2b5699be-768e-480e-a837-2318706f87ed	created	2013-09-15	2013-09-15 20:25:00	2013-09-14 23:47:56.172762	2013-09-14 23:47:56.172764	OAK	JAC	REG	2	2013	CBS
95	d9453347-1660-426d-ba4f-717578674593	created	2013-09-15	2013-09-15 20:25:00	2013-09-14 23:47:56.17571	2013-09-14 23:47:56.175712	NYG	DEN	REG	2	2013	CBS
96	3578ecdd-d181-4a07-adf1-e41b5061a653	created	2013-09-15	2013-09-16 00:30:00	2013-09-14 23:47:56.178425	2013-09-14 23:47:56.178427	SEA	SF	REG	2	2013	NBC
97	04937dbf-6755-4617-a9b2-0b843d470181	created	2013-09-16	2013-09-17 00:40:00	2013-09-14 23:47:56.181431	2013-09-14 23:47:56.181433	CIN	PIT	REG	2	2013	ESPN
98	3614b73e-1a12-43cf-a34f-1da37078951a	scheduled	2013-09-19	2013-09-20 00:25:00	2013-09-14 23:47:56.184293	2013-09-14 23:47:56.184295	PHI	KC	REG	3	2013	NFL Network
99	d0c5ca41-8ce3-465e-a448-4a17293cde66	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.187103	2013-09-14 23:47:56.187105	NO	ARI	REG	3	2013	FOX
100	da21bd78-8d94-4b34-8c67-bd03fc4948e5	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.189807	2013-09-14 23:47:56.189809	MIN	CLE	REG	3	2013	CBS
101	c5cb8bc0-2576-4400-b481-602cf86f5307	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.192661	2013-09-14 23:47:56.192663	NE	TB	REG	3	2013	FOX
102	c2d6ec89-aec9-47f9-8f3e-2dd4927210a1	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.19548	2013-09-14 23:47:56.195482	WAS	DET	REG	3	2013	FOX
103	dc09a0ee-b17a-4643-bdb2-a4b1c9537c2d	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.19827	2013-09-14 23:47:56.198272	BAL	HOU	REG	3	2013	CBS
104	cf785d70-c342-486d-8907-db45ae0eb18e	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.20105	2013-09-14 23:47:56.201052	CIN	GB	REG	3	2013	FOX
105	f560e86b-56c8-4aa0-a5c0-04425de8ac70	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.204163	2013-09-14 23:47:56.204165	DAL	STL	REG	3	2013	FOX
106	9a602bc2-14f5-4c9d-81e6-3e1366e87c0f	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.207064	2013-09-14 23:47:56.207066	TEN	SD	REG	3	2013	CBS
107	d38f352a-3b21-45d4-92f7-b4ef8bbb6ce3	scheduled	2013-09-22	2013-09-22 17:00:00	2013-09-14 23:47:56.209885	2013-09-14 23:47:56.209888	CAR	NYG	REG	3	2013	FOX
108	4d9a84cd-583f-44d2-9473-4787cc913dbb	scheduled	2013-09-22	2013-09-22 20:05:00	2013-09-14 23:47:56.213241	2013-09-14 23:47:56.213243	MIA	ATL	REG	3	2013	FOX
109	3157abd8-3a05-4ef3-afe3-e109c3476651	scheduled	2013-09-22	2013-09-22 20:25:00	2013-09-14 23:47:56.216491	2013-09-14 23:47:56.216493	SF	IND	REG	3	2013	CBS
110	dc10a366-cef3-416e-8944-598cd318d09a	scheduled	2013-09-22	2013-09-22 20:25:00	2013-09-14 23:47:56.219575	2013-09-14 23:47:56.219577	NYJ	BUF	REG	3	2013	CBS
111	1cd0f1f9-ea49-47e6-bbc5-7eec8a89f4c4	scheduled	2013-09-22	2013-09-22 20:25:00	2013-09-14 23:47:56.22274	2013-09-14 23:47:56.222743	SEA	JAC	REG	3	2013	CBS
112	3baea51f-ec38-470a-8928-b2f463695cf4	scheduled	2013-09-22	2013-09-23 00:30:00	2013-09-14 23:47:56.225553	2013-09-14 23:47:56.225556	PIT	CHI	REG	3	2013	NBC
113	8109d41d-2519-4b84-80e7-27abe6a36e83	scheduled	2013-09-23	2013-09-24 00:40:00	2013-09-14 23:47:56.228205	2013-09-14 23:47:56.228206	DEN	OAK	REG	3	2013	ESPN
114	3f4534e3-1544-41e7-8655-f2355e6bbc9a	scheduled	2013-09-26	2013-09-27 00:25:00	2013-09-14 23:47:56.231104	2013-09-14 23:47:56.231106	STL	SF	REG	4	2013	NFL Network
115	2e99eeeb-fec0-4fd0-a704-97c36071b9b8	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.234355	2013-09-14 23:47:56.234357	HOU	SEA	REG	4	2013	FOX
116	732c7acd-ef1a-4538-b72c-27effc5fbb1f	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.236587	2013-09-14 23:47:56.236588	JAC	IND	REG	4	2013	CBS
117	238955ce-ceb5-49e5-8028-4abfd1ba1dd5	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.238623	2013-09-14 23:47:56.238625	TB	ARI	REG	4	2013	FOX
118	7b96cd18-e1d3-4383-b2ef-c33e31312b6a	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.240661	2013-09-14 23:47:56.240663	DET	CHI	REG	4	2013	FOX
119	39bb625c-2c72-4ab2-a094-36675d9d2d8d	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.242492	2013-09-14 23:47:56.242493	CLE	CIN	REG	4	2013	CBS
120	baf2750e-91fa-43b1-89c2-790af7bb505b	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.24433	2013-09-14 23:47:56.244331	MIN	PIT	REG	4	2013	CBS
121	01dff60a-f6b1-438c-abec-43ffbe590475	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.246305	2013-09-14 23:47:56.246307	BUF	BAL	REG	4	2013	CBS
122	4316e543-e764-48ba-af45-6f9462a6141d	scheduled	2013-09-29	2013-09-29 17:00:00	2013-09-14 23:47:56.248249	2013-09-14 23:47:56.24825	KC	NYG	REG	4	2013	FOX
123	15958065-3655-46f9-9063-b9a5ab38a232	scheduled	2013-09-29	2013-09-29 20:05:00	2013-09-14 23:47:56.250265	2013-09-14 23:47:56.250267	TEN	NYJ	REG	4	2013	CBS
124	f05087b2-4f8a-42c6-9a9c-b175c64adb4e	scheduled	2013-09-29	2013-09-29 20:25:00	2013-09-14 23:47:56.252208	2013-09-14 23:47:56.25221	OAK	WAS	REG	4	2013	FOX
125	1da8fcb4-90b3-47ac-ab9e-3b1a011f418d	scheduled	2013-09-29	2013-09-29 20:25:00	2013-09-14 23:47:56.254112	2013-09-14 23:47:56.254113	DEN	PHI	REG	4	2013	FOX
126	2899394a-4176-433a-80bc-057bf61d9350	scheduled	2013-09-29	2013-09-29 20:25:00	2013-09-14 23:47:56.255893	2013-09-14 23:47:56.255894	SD	DAL	REG	4	2013	FOX
127	02cf4b1d-7d6a-4630-b927-9b5d0ecdfaa5	scheduled	2013-09-29	2013-09-30 00:30:00	2013-09-14 23:47:56.257788	2013-09-14 23:47:56.257789	ATL	NE	REG	4	2013	NBC
128	a9abbe53-91fe-45a5-bc9e-bdb0f66bf0ed	scheduled	2013-09-30	2013-10-01 00:40:00	2013-09-14 23:47:56.259687	2013-09-14 23:47:56.259689	NO	MIA	REG	4	2013	ESPN
129	86bf67e2-af7d-4f57-89c5-2cecc0b983be	scheduled	2013-10-03	2013-10-04 00:25:00	2013-09-14 23:47:56.261567	2013-09-14 23:47:56.261568	CLE	BUF	REG	5	2013	NFL Network
130	c6e609a3-f3d9-4af7-aaf7-c50850d8cafc	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.263543	2013-09-14 23:47:56.263544	MIA	BAL	REG	5	2013	CBS
131	f46ca246-5d50-4c01-83c0-bfd765e99235	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.265357	2013-09-14 23:47:56.265359	IND	SEA	REG	5	2013	FOX
132	3c04ed97-d324-48d7-bb35-ec956f5b9f3f	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.267271	2013-09-14 23:47:56.267272	GB	DET	REG	5	2013	FOX
133	e5c7e52d-0849-4e4c-b723-5466d3197112	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.269181	2013-09-14 23:47:56.269183	STL	JAC	REG	5	2013	CBS
134	065b340a-2fbc-4ee4-a186-173c40cb8fc2	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.271278	2013-09-14 23:47:56.27128	CHI	NO	REG	5	2013	FOX
135	2a295c8c-446b-463c-8433-a7753cfdc5eb	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.273473	2013-09-14 23:47:56.273475	NYG	PHI	REG	5	2013	FOX
136	75bde93d-518d-4a7b-bbf1-50cab08d5330	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.275526	2013-09-14 23:47:56.275528	TEN	KC	REG	5	2013	CBS
137	4b3ebfe7-181b-455a-9173-c15c2b44857c	scheduled	2013-10-06	2013-10-06 17:00:00	2013-09-14 23:47:56.277384	2013-09-14 23:47:56.277385	CIN	NE	REG	5	2013	CBS
138	f461625b-739b-40e3-a584-f6cc90de80d2	scheduled	2013-10-06	2013-10-06 20:05:00	2013-09-14 23:47:56.279288	2013-09-14 23:47:56.279289	ARI	CAR	REG	5	2013	FOX
139	2e148b67-5083-4f89-98d4-c5706fb6f4e9	scheduled	2013-10-06	2013-10-06 20:25:00	2013-09-14 23:47:56.281215	2013-09-14 23:47:56.281217	OAK	SD	REG	5	2013	CBS
140	9dd6dc5f-6632-47a2-9bf3-9fc6f6b348c4	scheduled	2013-10-06	2013-10-06 20:25:00	2013-09-14 23:47:56.283323	2013-09-14 23:47:56.283325	DAL	DEN	REG	5	2013	CBS
141	2362bd57-0ebb-4ebb-a3a5-3041792926ed	scheduled	2013-10-06	2013-10-07 00:30:00	2013-09-14 23:47:56.287809	2013-09-14 23:47:56.28781	SF	HOU	REG	5	2013	NBC
142	c2d5e64d-ed0d-495e-8ec1-6bd3fd226f74	scheduled	2013-10-07	2013-10-08 00:40:00	2013-09-14 23:47:56.289717	2013-09-14 23:47:56.289718	ATL	NYJ	REG	5	2013	ESPN
143	ce60383a-6b41-464f-a02d-6f2b43678cae	scheduled	2013-10-10	2013-10-11 00:25:00	2013-09-14 23:47:56.291853	2013-09-14 23:47:56.291855	CHI	NYG	REG	6	2013	NFL Network
144	8e142368-c61b-43f7-9597-0692b0fd7e92	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.294012	2013-09-14 23:47:56.294013	TB	PHI	REG	6	2013	FOX
145	eb289b02-1f84-4e9d-9085-749eba939a04	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.295881	2013-09-14 23:47:56.295882	BAL	GB	REG	6	2013	FOX
146	d11d883a-c9ae-497c-b5d6-50d2f81af1e7	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.297891	2013-09-14 23:47:56.297892	MIN	CAR	REG	6	2013	FOX
147	84765c33-3678-4354-b722-a8b804f65b1b	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.299784	2013-09-14 23:47:56.299785	KC	OAK	REG	6	2013	CBS
148	6e154e97-b99d-40d7-8f3d-fd9cb09d2c45	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.30176	2013-09-14 23:47:56.301762	BUF	CIN	REG	6	2013	CBS
149	53c476f5-543f-46e4-952a-39078ed54535	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.303788	2013-09-14 23:47:56.303789	NYJ	PIT	REG	6	2013	CBS
150	2abccb3e-1a0c-4905-98fc-43f567cc975c	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.305606	2013-09-14 23:47:56.305607	HOU	STL	REG	6	2013	FOX
151	464307fb-5e6b-4048-9660-968ddd7c79a3	scheduled	2013-10-13	2013-10-13 17:00:00	2013-09-14 23:47:56.307504	2013-09-14 23:47:56.307506	CLE	DET	REG	6	2013	FOX
152	9c74acd7-257d-4d87-8b97-4855fe2b6304	scheduled	2013-10-13	2013-10-13 20:05:00	2013-09-14 23:47:56.309318	2013-09-14 23:47:56.309319	DEN	JAC	REG	6	2013	CBS
153	80635d24-4fb4-4b8a-ba6c-fabe6a545eef	scheduled	2013-10-13	2013-10-13 20:05:00	2013-09-14 23:47:56.311386	2013-09-14 23:47:56.311387	SEA	TEN	REG	6	2013	CBS
154	46f17fa4-f2ef-41ef-9ede-00929c043ebe	scheduled	2013-10-13	2013-10-13 20:25:00	2013-09-14 23:47:56.313288	2013-09-14 23:47:56.313289	SF	ARI	REG	6	2013	FOX
155	e76450a1-a8df-46f6-96dc-6416dbfa03fe	scheduled	2013-10-13	2013-10-13 20:25:00	2013-09-14 23:47:56.31514	2013-09-14 23:47:56.315142	NE	NO	REG	6	2013	FOX
156	d099476b-b195-4d05-ac5e-38d87d48dacc	scheduled	2013-10-13	2013-10-14 00:30:00	2013-09-14 23:47:56.316942	2013-09-14 23:47:56.316943	DAL	WAS	REG	6	2013	NBC
157	45787908-3a63-4981-a1cd-d3f535dbd969	scheduled	2013-10-14	2013-10-15 00:40:00	2013-09-14 23:47:56.319053	2013-09-14 23:47:56.319055	SD	IND	REG	6	2013	ESPN
158	1d9ae6b9-55c1-492a-bb0a-bbe7bade4c80	scheduled	2013-10-17	2013-10-18 00:25:00	2013-09-14 23:47:56.322148	2013-09-14 23:47:56.322151	ARI	SEA	REG	7	2013	NFL Network
159	20d2e51a-2c82-415a-9e2c-6c04793eb30a	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.32541	2013-09-14 23:47:56.325413	NYJ	NE	REG	7	2013	CBS
160	268d622b-1f42-4933-a781-e11271cd3463	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.328178	2013-09-14 23:47:56.32818	ATL	TB	REG	7	2013	FOX
161	4562d053-5acc-4228-aa29-1a4ffba6a643	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.330905	2013-09-14 23:47:56.330907	DET	CIN	REG	7	2013	CBS
162	7cd03c45-e067-4302-92bf-d69387bd29a5	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.334058	2013-09-14 23:47:56.33406	JAC	SD	REG	7	2013	CBS
163	3e1339fc-ce3b-4237-bcc4-a94446e97125	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.337383	2013-09-14 23:47:56.337386	KC	HOU	REG	7	2013	CBS
164	84ec7271-9cb0-46b7-8329-1759033874a8	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.340192	2013-09-14 23:47:56.340194	WAS	CHI	REG	7	2013	FOX
165	6df21ec8-69bd-43f4-b8ec-fa9cb76ec74a	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.343323	2013-09-14 23:47:56.343326	CAR	STL	REG	7	2013	FOX
166	e67e1d1a-0b8f-4389-bc9a-6e438b3349ed	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.346086	2013-09-14 23:47:56.346087	MIA	BUF	REG	7	2013	CBS
167	98c71b0b-0621-45d1-b365-27f9743c11be	scheduled	2013-10-20	2013-10-20 17:00:00	2013-09-14 23:47:56.349059	2013-09-14 23:47:56.349061	PHI	DAL	REG	7	2013	FOX
168	06c49ec3-7a0c-4a48-a579-9e11163ffa16	scheduled	2013-10-20	2013-10-20 20:05:00	2013-09-14 23:47:56.352021	2013-09-14 23:47:56.352023	TEN	SF	REG	7	2013	FOX
169	53a05755-95ac-4567-9de8-0f47c87f8a33	scheduled	2013-10-20	2013-10-20 20:25:00	2013-09-14 23:47:56.354828	2013-09-14 23:47:56.35483	PIT	BAL	REG	7	2013	CBS
170	54b4c573-e279-4fc5-af5c-7a4010187d6b	scheduled	2013-10-20	2013-10-20 20:25:00	2013-09-14 23:47:56.357776	2013-09-14 23:47:56.357779	GB	CLE	REG	7	2013	CBS
171	3988058a-946b-4955-a453-a42a94bd395b	scheduled	2013-10-20	2013-10-21 00:30:00	2013-09-14 23:47:56.361079	2013-09-14 23:47:56.361082	IND	DEN	REG	7	2013	NBC
172	5494577c-74cd-45f7-9a6b-1abf869b59ed	scheduled	2013-10-21	2013-10-22 00:40:00	2013-09-14 23:47:56.364377	2013-09-14 23:47:56.364379	NYG	MIN	REG	7	2013	ESPN
173	a7d96802-7dfe-4ce7-9998-40b0d1fdda7a	scheduled	2013-10-24	2013-10-25 00:25:00	2013-09-14 23:47:56.367335	2013-09-14 23:47:56.367337	TB	CAR	REG	8	2013	NFL Network
174	8991291e-3091-4afe-8b46-a55f1afc5189	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.370289	2013-09-14 23:47:56.370292	KC	CLE	REG	8	2013	CBS
175	cef61098-a738-4088-90c3-345fcdde437c	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.373879	2013-09-14 23:47:56.373883	NE	MIA	REG	8	2013	CBS
176	5ef1d70f-1724-4f6c-a336-cb45de67a1c0	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.376774	2013-09-14 23:47:56.376775	PHI	NYG	REG	8	2013	FOX
177	091a2e49-9676-475a-a971-ff44319e88dc	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.379617	2013-09-14 23:47:56.379619	DET	DAL	REG	8	2013	FOX
178	311e06f4-5903-4256-914f-fc6c760fe16b	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.3827	2013-09-14 23:47:56.382702	JAC	SF	REG	8	2013	FOX
179	809bfd80-f8d8-42dd-b70f-1dc1417a941d	scheduled	2013-10-27	2013-10-27 17:00:00	2013-09-14 23:47:56.385481	2013-09-14 23:47:56.385483	NO	BUF	REG	8	2013	CBS
180	739c8619-130c-4685-839c-5c10ab2089ce	scheduled	2013-10-27	2013-10-27 20:05:00	2013-09-14 23:47:56.388839	2013-09-14 23:47:56.388842	CIN	NYJ	REG	8	2013	CBS
181	60735be9-8d78-449c-9ce9-95d8e7fb475c	scheduled	2013-10-27	2013-10-27 20:05:00	2013-09-14 23:47:56.391936	2013-09-14 23:47:56.391938	OAK	PIT	REG	8	2013	CBS
182	a2e3c3f1-784f-4c1f-915b-a1d6f212ed22	scheduled	2013-10-27	2013-10-27 20:25:00	2013-09-14 23:47:56.395225	2013-09-14 23:47:56.395229	DEN	WAS	REG	8	2013	FOX
183	d527c806-2f13-4f60-bc5c-9d5584d35c93	scheduled	2013-10-27	2013-10-27 20:25:00	2013-09-14 23:47:56.398279	2013-09-14 23:47:56.398282	ARI	ATL	REG	8	2013	FOX
184	2101add1-3609-4e3d-821d-488490cdc6d4	scheduled	2013-10-27	2013-10-28 00:30:00	2013-09-14 23:47:56.401883	2013-09-14 23:47:56.401885	MIN	GB	REG	8	2013	NBC
185	1fcaa0af-f883-4cde-b6ba-99c2043e24ed	scheduled	2013-10-28	2013-10-29 00:40:00	2013-09-14 23:47:56.405367	2013-09-14 23:47:56.40537	STL	SEA	REG	8	2013	ESPN
186	b660ad53-14e5-4ada-8b0c-f3563de89bd6	scheduled	2013-10-31	2013-11-01 00:25:00	2013-09-14 23:47:56.40864	2013-09-14 23:47:56.408642	MIA	CIN	REG	9	2013	NFL Network
187	75d88d7d-40c0-4584-9247-08518fbcd418	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.412154	2013-09-14 23:47:56.412156	BUF	KC	REG	9	2013	CBS
188	4c9d915d-5e3a-46db-af33-05cbfaefeab3	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.415726	2013-09-14 23:47:56.415729	STL	TEN	REG	9	2013	CBS
189	aad60255-4659-4f43-b5a9-04ca334f1597	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.418588	2013-09-14 23:47:56.418591	NYJ	NO	REG	9	2013	FOX
190	c27c5257-6165-4a52-b9c0-c60eb475a303	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.421292	2013-09-14 23:47:56.421294	WAS	SD	REG	9	2013	CBS
191	2710e9ce-3455-4987-a24d-9e008884472a	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.424391	2013-09-14 23:47:56.424393	DAL	MIN	REG	9	2013	FOX
192	8aab2375-3792-460e-a3ce-61ece499e63f	scheduled	2013-11-03	2013-11-03 18:00:00	2013-09-14 23:47:56.427698	2013-09-14 23:47:56.427701	CAR	ATL	REG	9	2013	FOX
193	e77fc30f-d216-4e91-868b-3bf7ed6c35ba	scheduled	2013-11-03	2013-11-03 21:05:00	2013-09-14 23:47:56.430789	2013-09-14 23:47:56.430792	OAK	PHI	REG	9	2013	FOX
194	b88f4133-d7c7-45e0-aabd-ca48131a5b72	scheduled	2013-11-03	2013-11-03 21:05:00	2013-09-14 23:47:56.434186	2013-09-14 23:47:56.434188	SEA	TB	REG	9	2013	FOX
195	30ce85f3-70f0-4d2e-a370-450af8fa130f	scheduled	2013-11-03	2013-11-03 21:25:00	2013-09-14 23:47:56.437287	2013-09-14 23:47:56.437319	NE	PIT	REG	9	2013	CBS
196	dedcadd1-bbb1-4680-9fc1-41185a369f40	scheduled	2013-11-03	2013-11-03 21:25:00	2013-09-14 23:47:56.440262	2013-09-14 23:47:56.440266	CLE	BAL	REG	9	2013	CBS
197	17392fed-d847-48a7-9e6d-018a6e8fc18b	scheduled	2013-11-03	2013-11-04 01:30:00	2013-09-14 23:47:56.443903	2013-09-14 23:47:56.443905	HOU	IND	REG	9	2013	NBC
198	08828edd-dfcd-4225-a073-3420cf8fda2f	scheduled	2013-11-04	2013-11-05 01:40:00	2013-09-14 23:47:56.447061	2013-09-14 23:47:56.447063	GB	CHI	REG	9	2013	ESPN
199	91305a1b-adda-4020-9970-aa935efed693	scheduled	2013-11-07	2013-11-08 01:25:00	2013-09-14 23:47:56.454508	2013-09-14 23:47:56.454512	MIN	WAS	REG	10	2013	NFL Network
200	703eae22-db9d-4129-9a05-2aa36ac65211	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.457427	2013-09-14 23:47:56.457429	CHI	DET	REG	10	2013	FOX
201	5350812f-61b0-4801-945f-0c8865453717	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.460248	2013-09-14 23:47:56.460251	TEN	JAC	REG	10	2013	CBS
202	c313230b-0e9f-40b2-a667-ea09bb27d057	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.463087	2013-09-14 23:47:56.463089	IND	STL	REG	10	2013	FOX
203	f5c57c7d-16f8-4c8c-819b-4d3b7bbfe9a3	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.465843	2013-09-14 23:47:56.465846	NYG	OAK	REG	10	2013	CBS
204	2c296921-30b0-4b3f-9710-f0db0d56add8	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.469137	2013-09-14 23:47:56.46914	GB	PHI	REG	10	2013	FOX
205	9cb29902-3d97-4d74-b63a-8284de864f26	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.472029	2013-09-14 23:47:56.472031	ATL	SEA	REG	10	2013	FOX
206	5e53b903-b620-4346-86a9-146ce00ea41e	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.474915	2013-09-14 23:47:56.474917	BAL	CIN	REG	10	2013	CBS
207	240d588f-e541-4b2f-864b-863632b1460d	scheduled	2013-11-10	2013-11-10 18:00:00	2013-09-14 23:47:56.478004	2013-09-14 23:47:56.478006	PIT	BUF	REG	10	2013	CBS
208	df53a3dc-d4f5-4844-aa9b-47581f43ac83	scheduled	2013-11-10	2013-11-10 21:05:00	2013-09-14 23:47:56.480792	2013-09-14 23:47:56.480794	SF	CAR	REG	10	2013	FOX
209	d11618a3-20ff-47ac-ab22-f61509d9b5b3	scheduled	2013-11-10	2013-11-10 21:25:00	2013-09-14 23:47:56.484145	2013-09-14 23:47:56.484148	ARI	HOU	REG	10	2013	CBS
210	166fe22e-bc84-4d01-9924-dfacc2251bae	scheduled	2013-11-10	2013-11-10 21:25:00	2013-09-14 23:47:56.487234	2013-09-14 23:47:56.487237	SD	DEN	REG	10	2013	CBS
211	eec8c2fc-e599-4eb0-8bb4-ceb229b706c0	scheduled	2013-11-10	2013-11-11 01:30:00	2013-09-14 23:47:56.490099	2013-09-14 23:47:56.490102	NO	DAL	REG	10	2013	NBC
212	7164060c-b880-4a46-b4e3-5fb9fbfe85fa	scheduled	2013-11-11	2013-11-12 01:40:00	2013-09-14 23:47:56.493014	2013-09-14 23:47:56.493017	TB	MIA	REG	10	2013	ESPN
213	d9bcee64-af7e-4c9f-8f0d-976cc8b6bf9f	scheduled	2013-11-14	2013-11-15 01:25:00	2013-09-14 23:47:56.49601	2013-09-14 23:47:56.496012	TEN	IND	REG	11	2013	NFL Network
214	a69d4ac6-d6bb-4c09-a7bc-4efd83f5edd6	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.498962	2013-09-14 23:47:56.498964	JAC	ARI	REG	11	2013	FOX
215	d40c2c71-1d87-42bd-ba73-e3f5a0923cf8	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.501758	2013-09-14 23:47:56.50176	BUF	NYJ	REG	11	2013	CBS
216	bbe07916-8f81-4116-9f51-7db2aeba8c8d	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.504902	2013-09-14 23:47:56.504905	HOU	OAK	REG	11	2013	CBS
217	4d940428-e35e-4ace-8d23-2a23d6c6520e	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.508052	2013-09-14 23:47:56.508054	TB	ATL	REG	11	2013	FOX
218	aa5e2a6a-51c9-40c0-85ff-97b83dad7321	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.510842	2013-09-14 23:47:56.510846	CIN	CLE	REG	11	2013	CBS
219	5489901b-a1b1-44eb-92e4-c12dc06bfe78	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.513629	2013-09-14 23:47:56.513631	PHI	WAS	REG	11	2013	FOX
220	ef8b7683-6add-409f-8211-bf9636b3e24e	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.516607	2013-09-14 23:47:56.516609	MIA	SD	REG	11	2013	CBS
221	253ed1c1-3cb5-46e9-8d38-c345d3c6092f	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.519384	2013-09-14 23:47:56.519386	PIT	DET	REG	11	2013	FOX
222	ac3fedac-1240-444e-b9d7-4c183e34d50d	scheduled	2013-11-17	2013-11-17 18:00:00	2013-09-14 23:47:56.522132	2013-09-14 23:47:56.522134	CHI	BAL	REG	11	2013	CBS
223	5256b0a0-ef98-4389-924d-01b2ed6347d4	scheduled	2013-11-17	2013-11-17 21:05:00	2013-09-14 23:47:56.524935	2013-09-14 23:47:56.524937	DEN	KC	REG	11	2013	CBS
224	ffd007f0-4232-4d9e-9dae-68111b051cfc	scheduled	2013-11-17	2013-11-17 21:25:00	2013-09-14 23:47:56.527781	2013-09-14 23:47:56.527783	NO	SF	REG	11	2013	FOX
225	bf2c3a79-7dab-435a-b2e8-faaf32b1c3e4	scheduled	2013-11-17	2013-11-17 21:25:00	2013-09-14 23:47:56.530609	2013-09-14 23:47:56.530612	SEA	MIN	REG	11	2013	FOX
226	f8a1be80-f3d8-4fe6-aecf-21e76ba52661	scheduled	2013-11-17	2013-11-18 01:30:00	2013-09-14 23:47:56.53354	2013-09-14 23:47:56.533542	NYG	GB	REG	11	2013	NBC
227	ee87810e-cc94-4d9b-9566-57e9beb7d43c	scheduled	2013-11-18	2013-11-19 01:40:00	2013-09-14 23:47:56.536493	2013-09-14 23:47:56.536495	CAR	NE	REG	11	2013	ESPN
228	e2135cc1-8b12-470e-8de0-94c503776e57	scheduled	2013-11-21	2013-11-22 01:25:00	2013-09-14 23:47:56.539593	2013-09-14 23:47:56.539597	ATL	NO	REG	12	2013	NFL Network
229	71882a6b-8d3b-46a1-9e3e-51512bbb780b	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.542605	2013-09-14 23:47:56.542608	CLE	PIT	REG	12	2013	CBS
230	1a5f3ddb-d6cb-404e-9b44-ac539e309ba1	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.545518	2013-09-14 23:47:56.545522	BAL	NYJ	REG	12	2013	CBS
231	f354dcae-a85f-45b8-a926-18872a77e1e2	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.548867	2013-09-14 23:47:56.548869	KC	SD	REG	12	2013	CBS
232	89228027-f127-428b-8409-f7828a8342c0	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.551907	2013-09-14 23:47:56.55191	GB	MIN	REG	12	2013	FOX
233	95f09252-6f0a-4218-bce7-bde576d28998	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.555429	2013-09-14 23:47:56.555433	HOU	JAC	REG	12	2013	CBS
234	73e01826-3d28-48ad-9883-a5acaf767f19	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.558614	2013-09-14 23:47:56.558616	DET	TB	REG	12	2013	FOX
235	6b7cb3b6-bfb8-4638-8776-913777155072	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.561623	2013-09-14 23:47:56.561625	STL	CHI	REG	12	2013	FOX
236	34058912-d9a6-41f3-baa9-edab82100225	scheduled	2013-11-24	2013-11-24 18:00:00	2013-09-14 23:47:56.564572	2013-09-14 23:47:56.564575	MIA	CAR	REG	12	2013	FOX
237	13037b8b-7a76-4d2a-9721-ea7d5f770c37	scheduled	2013-11-24	2013-11-24 21:05:00	2013-09-14 23:47:56.567771	2013-09-14 23:47:56.567774	OAK	TEN	REG	12	2013	CBS
238	ac2902ee-49c8-4a84-9dde-30c2fa68f910	scheduled	2013-11-24	2013-11-24 21:05:00	2013-09-14 23:47:56.570661	2013-09-14 23:47:56.570663	ARI	IND	REG	12	2013	CBS
239	63bf6a82-d3dc-4cd3-8df9-5a55348cb50e	scheduled	2013-11-24	2013-11-24 21:25:00	2013-09-14 23:47:56.573856	2013-09-14 23:47:56.573858	NYG	DAL	REG	12	2013	FOX
240	12e7f75b-fc51-479d-a0df-8fb55398560f	scheduled	2013-11-24	2013-11-25 01:30:00	2013-09-14 23:47:56.577324	2013-09-14 23:47:56.577326	NE	DEN	REG	12	2013	NBC
241	7d134ccf-c0f3-4304-a5d1-470902750d63	scheduled	2013-11-25	2013-11-26 01:40:00	2013-09-14 23:47:56.580482	2013-09-14 23:47:56.580485	WAS	SF	REG	12	2013	ESPN
242	ddcba74e-8269-49be-a581-8bda7350fc5d	scheduled	2013-11-28	2013-11-28 17:30:00	2013-09-14 23:47:56.583739	2013-09-14 23:47:56.583743	DET	GB	REG	13	2013	FOX
243	4bfc4f52-35f9-493d-bda1-171daa426a15	scheduled	2013-11-28	2013-11-28 21:30:00	2013-09-14 23:47:56.587066	2013-09-14 23:47:56.587068	DAL	OAK	REG	13	2013	CBS
244	428b8a16-61c4-413a-a8e8-069efa78f8a9	scheduled	2013-11-28	2013-11-29 01:30:00	2013-09-14 23:47:56.590593	2013-09-14 23:47:56.590596	BAL	PIT	REG	13	2013	NBC
245	4feed4c2-a965-45b1-b857-c2f1e2c77771	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.593727	2013-09-14 23:47:56.59373	IND	TEN	REG	13	2013	CBS
246	6cc91b42-78e1-47ab-b574-acc4b70cd933	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.597312	2013-09-14 23:47:56.597315	CLE	JAC	REG	13	2013	CBS
247	f7e2539d-e237-46ff-a3be-0ba6b4cb46bb	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.60056	2013-09-14 23:47:56.600564	NYJ	MIA	REG	13	2013	CBS
248	e0a8585b-8d6b-446a-b6f6-67c4884b01d1	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.603575	2013-09-14 23:47:56.603578	KC	DEN	REG	13	2013	CBS
249	6d2ad37c-e74a-44c5-9db5-a6bba295bf29	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.606875	2013-09-14 23:47:56.606878	CAR	TB	REG	13	2013	FOX
250	ef78d200-84e8-43c8-b5f2-9527b7b65a6a	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.610368	2013-09-14 23:47:56.610371	PHI	ARI	REG	13	2013	FOX
251	66e4c0fc-b75c-4ecb-a0fb-2c4459807237	scheduled	2013-12-01	2013-12-01 18:00:00	2013-09-14 23:47:56.613535	2013-09-14 23:47:56.613537	MIN	CHI	REG	13	2013	FOX
252	287823a1-bd7e-4e77-b54d-6e0c4cbc49ba	scheduled	2013-12-01	2013-12-01 21:05:00	2013-09-14 23:47:56.616468	2013-09-14 23:47:56.61647	SF	STL	REG	13	2013	FOX
253	3543954e-b2db-49a5-955a-4281c1e4c5f5	scheduled	2013-12-01	2013-12-01 21:05:00	2013-09-14 23:47:56.619446	2013-09-14 23:47:56.619448	BUF	ATL	REG	13	2013	FOX
254	f29fc024-b6a3-43ff-9446-cd222a65f190	scheduled	2013-12-01	2013-12-01 21:25:00	2013-09-14 23:47:56.622281	2013-09-14 23:47:56.622283	SD	CIN	REG	13	2013	CBS
255	f1620754-ba0c-42b4-94cd-33615963224a	scheduled	2013-12-01	2013-12-01 21:25:00	2013-09-14 23:47:56.625209	2013-09-14 23:47:56.625211	HOU	NE	REG	13	2013	CBS
256	17d48893-149b-4772-92cc-dc778fd2a18b	scheduled	2013-12-01	2013-12-02 01:30:00	2013-09-14 23:47:56.632247	2013-09-14 23:47:56.632249	WAS	NYG	REG	13	2013	NBC
257	576bfe0c-6f41-4f46-b1db-f867b605578e	scheduled	2013-12-02	2013-12-03 01:40:00	2013-09-14 23:47:56.636099	2013-09-14 23:47:56.636101	SEA	NO	REG	13	2013	ESPN
258	100b2034-4c3e-4fa3-bf87-aca4c99b30a2	scheduled	2013-12-05	2013-12-06 01:25:00	2013-09-14 23:47:56.639559	2013-09-14 23:47:56.639561	JAC	HOU	REG	14	2013	NFL Network
259	05607db7-59cf-4acb-aa83-f352584bf668	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.642627	2013-09-14 23:47:56.642631	BAL	MIN	REG	14	2013	FOX
260	d442b3bc-7ba3-4ad9-91ba-2b856212419d	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.645519	2013-09-14 23:47:56.645522	NE	CLE	REG	14	2013	CBS
261	cc87f6e5-bc5a-42fb-b858-746bc1690528	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.648783	2013-09-14 23:47:56.648785	TB	BUF	REG	14	2013	CBS
262	d9a034e0-94bc-4656-8a4d-1459786308e5	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.65199	2013-09-14 23:47:56.651994	WAS	KC	REG	14	2013	CBS
263	4908d76e-8c92-41bc-8683-e95ff80e9400	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.654909	2013-09-14 23:47:56.654911	PIT	MIA	REG	14	2013	CBS
264	df54dac1-721f-4197-b366-5649dfa8d31f	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.658122	2013-09-14 23:47:56.658124	PHI	DET	REG	14	2013	FOX
265	dccdb33b-862a-4d03-9f47-9b0f596a5525	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.661325	2013-09-14 23:47:56.661328	NYJ	OAK	REG	14	2013	CBS
266	89eebd47-1360-456e-82c6-30f603b611c5	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.66433	2013-09-14 23:47:56.664332	CIN	IND	REG	14	2013	CBS
267	e5ac19f4-2942-4e6d-8eda-1beca4e1388c	scheduled	2013-12-08	2013-12-08 18:00:00	2013-09-14 23:47:56.667283	2013-09-14 23:47:56.667285	NO	CAR	REG	14	2013	FOX
268	089f468c-d6fb-4458-adea-ba30c6965d97	scheduled	2013-12-08	2013-12-08 21:05:00	2013-09-14 23:47:56.670158	2013-09-14 23:47:56.670161	DEN	TEN	REG	14	2013	CBS
269	0529bbee-e403-48c4-90d6-dc6b434799a6	scheduled	2013-12-08	2013-12-08 21:25:00	2013-09-14 23:47:56.673011	2013-09-14 23:47:56.673014	SF	SEA	REG	14	2013	FOX
270	b937265e-4475-481d-a598-7e027ebc425b	scheduled	2013-12-08	2013-12-08 21:25:00	2013-09-14 23:47:56.675982	2013-09-14 23:47:56.675984	SD	NYG	REG	14	2013	FOX
271	d72fde4a-2ed1-49af-b346-e1afd5be6484	scheduled	2013-12-08	2013-12-08 21:25:00	2013-09-14 23:47:56.678997	2013-09-14 23:47:56.679001	ARI	STL	REG	14	2013	FOX
272	476e617c-7ca2-4952-a420-7b7c94c1b1dc	scheduled	2013-12-08	2013-12-09 01:30:00	2013-09-14 23:47:56.682232	2013-09-14 23:47:56.682236	GB	ATL	REG	14	2013	NBC
273	792a5277-6f1d-4228-af16-878ff896ecf7	scheduled	2013-12-09	2013-12-10 01:40:00	2013-09-14 23:47:56.685902	2013-09-14 23:47:56.685906	CHI	DAL	REG	14	2013	ESPN
274	871f0882-0a67-4fc9-aa65-c980f2f2dacd	scheduled	2013-12-12	2013-12-13 01:25:00	2013-09-14 23:47:56.689061	2013-09-14 23:47:56.689063	DEN	SD	REG	15	2013	NFL Network
275	fe5eefcc-017c-4994-bbeb-703e56951796	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.692304	2013-09-14 23:47:56.692307	CLE	CHI	REG	15	2013	FOX
276	8b5257ff-9e94-4616-92c3-d0795f2737db	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.69592	2013-09-14 23:47:56.695924	TEN	ARI	REG	15	2013	FOX
277	3644ad13-070b-40b0-afac-58bfd65dd1df	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.700155	2013-09-14 23:47:56.700159	JAC	BUF	REG	15	2013	CBS
278	fe9b4c59-cc95-4d33-bae1-437dc024c644	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.704205	2013-09-14 23:47:56.704208	TB	SF	REG	15	2013	FOX
279	ee91e78e-d444-47e8-8159-8e5836613a01	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.707674	2013-09-14 23:47:56.707677	NYG	SEA	REG	15	2013	FOX
280	27d7fdaa-2b4f-4975-b727-309dbc76bcb6	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.711077	2013-09-14 23:47:56.711079	ATL	WAS	REG	15	2013	FOX
281	90132602-2aab-4ac7-b97d-0fef9e034350	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.713466	2013-09-14 23:47:56.713468	MIN	PHI	REG	15	2013	FOX
282	9f925164-88da-49fa-a704-ddfccae9e3a5	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.715378	2013-09-14 23:47:56.715378	MIA	NE	REG	15	2013	CBS
283	1ac5f6be-e662-4d0a-bd85-5e308a08ce52	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.719599	2013-09-14 23:47:56.7196	STL	NO	REG	15	2013	FOX
284	26fe3c8e-216c-433d-9562-be92da490c1e	scheduled	2013-12-15	2013-12-15 18:00:00	2013-09-14 23:47:56.721218	2013-09-14 23:47:56.72122	IND	HOU	REG	15	2013	CBS
285	0faa402c-e6c8-41ed-9bb6-b282c5faeea9	scheduled	2013-12-15	2013-12-15 21:05:00	2013-09-14 23:47:56.722376	2013-09-14 23:47:56.722377	OAK	KC	REG	15	2013	CBS
286	0affdcc6-87ee-4554-8032-40f82d93fece	scheduled	2013-12-15	2013-12-15 21:05:00	2013-09-14 23:47:56.72357	2013-09-14 23:47:56.723584	CAR	NYJ	REG	15	2013	CBS
287	320deb05-37b7-4427-b670-c53e7fd3f744	scheduled	2013-12-15	2013-12-15 21:25:00	2013-09-14 23:47:56.725881	2013-09-14 23:47:56.725883	DAL	GB	REG	15	2013	FOX
288	2ea09a98-61b2-4944-b760-45521cf58867	scheduled	2013-12-15	2013-12-16 01:30:00	2013-09-14 23:47:56.72762	2013-09-14 23:47:56.727621	PIT	CIN	REG	15	2013	NBC
289	88d5ea4a-3300-48f2-b024-1e5aa7823ab3	scheduled	2013-12-16	2013-12-17 01:40:00	2013-09-14 23:47:56.729342	2013-09-14 23:47:56.729343	DET	BAL	REG	15	2013	ESPN
290	1916fa49-5e91-4b12-9bb8-7d66588b8539	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.730898	2013-09-14 23:47:56.730898	CIN	MIN	REG	16	2013	FOX
291	139725fe-8eb0-4290-8d54-1952cd13c08d	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.732638	2013-09-14 23:47:56.732639	JAC	TEN	REG	16	2013	CBS
292	a824c875-bd11-4cec-ad50-275bf5f08da1	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.734422	2013-09-14 23:47:56.734423	WAS	DAL	REG	16	2013	FOX
293	04a2c6e9-cde6-451c-9e01-b519c1719de1	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.736144	2013-09-14 23:47:56.736145	CAR	NO	REG	16	2013	FOX
294	333c6ec1-eb4f-4be4-96bc-d3fef78b16a9	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.737461	2013-09-14 23:47:56.737462	NYJ	CLE	REG	16	2013	CBS
295	4b2cbbaa-c17b-4aa0-a6a0-13d394a63a4f	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.739153	2013-09-14 23:47:56.739155	BUF	MIA	REG	16	2013	CBS
296	721d340c-c317-452a-907b-5a7bae4aed56	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.740898	2013-09-14 23:47:56.7409	KC	IND	REG	16	2013	CBS
297	65022472-03a8-402f-8a02-cc0aa9c7b275	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.743306	2013-09-14 23:47:56.743307	PHI	CHI	REG	16	2013	FOX
298	e3944202-9ad3-468c-96fc-36ab710237ba	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.745107	2013-09-14 23:47:56.745108	STL	TB	REG	16	2013	FOX
299	e74a482a-8e98-4d97-9bad-ce7998713f2d	scheduled	2013-12-22	2013-12-22 18:00:00	2013-09-14 23:47:56.746844	2013-09-14 23:47:56.746845	HOU	DEN	REG	16	2013	CBS
300	2ae0e3df-1e4a-40cc-ba8a-ef5c5c79fbfe	scheduled	2013-12-22	2013-12-22 21:05:00	2013-09-14 23:47:56.748745	2013-09-14 23:47:56.748746	DET	NYG	REG	16	2013	FOX
301	ffb9ca46-744b-4cb0-8b29-6a9035134271	scheduled	2013-12-22	2013-12-22 21:05:00	2013-09-14 23:47:56.75064	2013-09-14 23:47:56.75064	SEA	ARI	REG	16	2013	FOX
302	56f3e9ad-a5f1-4f19-9965-654357c84db1	scheduled	2013-12-22	2013-12-22 21:25:00	2013-09-14 23:47:56.752505	2013-09-14 23:47:56.752506	SD	OAK	REG	16	2013	CBS
303	00d5024b-0853-4e09-ad5a-4981a968f0ad	scheduled	2013-12-22	2013-12-22 21:25:00	2013-09-14 23:47:56.754502	2013-09-14 23:47:56.754503	GB	PIT	REG	16	2013	CBS
304	9c305126-3310-4c3a-8a83-90e4c45cc846	scheduled	2013-12-22	2013-12-23 01:30:00	2013-09-14 23:47:56.756438	2013-09-14 23:47:56.756439	BAL	NE	REG	16	2013	NBC
305	bd2c7cf6-a537-4d2d-b526-e4b1b3193c66	scheduled	2013-12-23	2013-12-24 01:40:00	2013-09-14 23:47:56.758681	2013-09-14 23:47:56.758683	SF	ATL	REG	16	2013	ESPN
306	99d975a1-1709-48d9-849d-a90850ad941a	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.761157	2013-09-14 23:47:56.761159	MIN	DET	REG	17	2013	FOX
307	1b434a0c-70e8-4cb6-a283-517129f46349	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.764345	2013-09-14 23:47:56.764348	CHI	GB	REG	17	2013	FOX
308	d05bd327-3449-405d-9a39-9a4b5c28b7da	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.76756	2013-09-14 23:47:56.767562	CIN	BAL	REG	17	2013	CBS
309	f5bbc5f5-55a2-49cb-86a9-4dcfddbf31cf	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.770642	2013-09-14 23:47:56.770644	NO	TB	REG	17	2013	FOX
310	4bdeccf6-b272-48ac-a5aa-1b17017c7bc0	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.773322	2013-09-14 23:47:56.773324	IND	JAC	REG	17	2013	CBS
311	f41b6223-bda6-4e7e-bcba-1f9cdda6c39c	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.775994	2013-09-14 23:47:56.775995	PIT	CLE	REG	17	2013	CBS
312	8cee7652-971f-45fd-8dcf-c7611160ba0b	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.777642	2013-09-14 23:47:56.777643	TEN	HOU	REG	17	2013	CBS
313	9c2f5cfa-dad3-4bf3-b5c9-722991429873	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.779148	2013-09-14 23:47:56.779149	NYG	WAS	REG	17	2013	FOX
314	4c455c72-b2c3-45bf-91b7-438f5d5bd8c6	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.780437	2013-09-14 23:47:56.780438	ATL	CAR	REG	17	2013	FOX
315	c69a61aa-7315-44d0-81cf-0a4d2e1fed3a	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.783646	2013-09-14 23:47:56.783648	DAL	PHI	REG	17	2013	FOX
316	9de37bdb-9f47-4d8a-9fc6-4eaa4037a8cb	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.785088	2013-09-14 23:47:56.785089	MIA	NYJ	REG	17	2013	CBS
317	e2ca316b-8814-4823-9c68-0cd674a2ab0d	scheduled	2013-12-29	2013-12-29 18:00:00	2013-09-14 23:47:56.786394	2013-09-14 23:47:56.786394	NE	BUF	REG	17	2013	CBS
318	dc2da130-1143-4a57-a821-91cf0e5d4454	scheduled	2013-12-29	2013-12-29 21:25:00	2013-09-14 23:47:56.787849	2013-09-14 23:47:56.78785	ARI	SF	REG	17	2013	FOX
319	d7e411e5-84c7-404c-9c9e-126023d9f794	scheduled	2013-12-29	2013-12-29 21:25:00	2013-09-14 23:47:56.78944	2013-09-14 23:47:56.789441	SD	KC	REG	17	2013	CBS
320	f11d052b-9254-4f03-97f7-438eab3596ab	scheduled	2013-12-29	2013-12-29 21:25:00	2013-09-14 23:47:56.790659	2013-09-14 23:47:56.79066	SEA	STL	REG	17	2013	FOX
321	99c06bd0-9e9c-4c1e-8e0a-43260d5020e8	scheduled	2013-12-29	2013-12-29 21:25:00	2013-09-14 23:47:56.791834	2013-09-14 23:47:56.791834	OAK	DEN	REG	17	2013	CBS
\.


--
-- Name: games_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('games_id_seq', 321, true);


--
-- Data for Name: games_markets; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY games_markets (id, game_stats_id, market_id) FROM stdin;
1	e24fff4c-a509-4fb5-80bc-bc95aa9ab09a	1
2	e036a429-1be6-4547-a99d-26602db584f9	2
3	77c4d7dc-6196-4d58-864d-5e70e06e9070	2
4	b9d81c1f-fa7b-46b3-ada4-4354bc2a9909	2
5	268a558b-ca2a-418e-8f46-8e3ce202363d	2
6	4869a6d0-4ef7-4712-a620-d10ffd8722d6	2
7	be8f3ead-127f-4ccf-8882-006d18f93b7b	2
8	5a28bf90-8f71-479d-9016-9dcd2ebea4c4	2
9	327f19da-5407-49bd-bcc8-298f69d99751	2
10	c91ae72a-289b-41c1-ae02-ce7d733bf9a1	2
11	56e13273-73f7-4b57-8e79-e1b88268f32a	2
12	6726b995-cb4c-4582-b729-fd9c21d063d2	2
13	2b972664-949e-4025-9f3d-48b3484674cd	2
14	05e9531d-e7e7-45c8-ae5a-91a2eb8acfa8	2
15	ce60383a-6b41-464f-a02d-6f2b43678cae	3
16	1916fa49-5e91-4b12-9bb8-7d66588b8539	4
17	139725fe-8eb0-4290-8d54-1952cd13c08d	4
18	a824c875-bd11-4cec-ad50-275bf5f08da1	4
19	04a2c6e9-cde6-451c-9e01-b519c1719de1	4
20	333c6ec1-eb4f-4be4-96bc-d3fef78b16a9	4
21	4b2cbbaa-c17b-4aa0-a6a0-13d394a63a4f	4
22	721d340c-c317-452a-907b-5a7bae4aed56	4
23	65022472-03a8-402f-8a02-cc0aa9c7b275	4
24	e3944202-9ad3-468c-96fc-36ab710237ba	4
25	e74a482a-8e98-4d97-9bad-ce7998713f2d	4
26	2ae0e3df-1e4a-40cc-ba8a-ef5c5c79fbfe	4
27	ffb9ca46-744b-4cb0-8b29-6a9035134271	4
28	56f3e9ad-a5f1-4f19-9965-654357c84db1	4
29	00d5024b-0853-4e09-ad5a-4981a968f0ad	4
30	9c305126-3310-4c3a-8a83-90e4c45cc846	4
31	871f0882-0a67-4fc9-aa65-c980f2f2dacd	5
48	16c73abc-acca-41ac-bf05-56ddff423e03	7
49	e88cf3c6-43c5-4837-984f-bb9a1138ed92	7
50	378a3ecf-fb9a-4d7c-87a5-c3abd75c996a	7
51	afe21447-7588-48a7-b5f8-f7bfbe161133	7
52	270c4e8d-bf5c-4e60-bf20-9add63d900f4	8
55	4feed4c2-a965-45b1-b857-c2f1e2c77771	11
56	6cc91b42-78e1-47ab-b574-acc4b70cd933	11
57	f7e2539d-e237-46ff-a3be-0ba6b4cb46bb	11
58	e0a8585b-8d6b-446a-b6f6-67c4884b01d1	11
59	6d2ad37c-e74a-44c5-9db5-a6bba295bf29	11
60	ef78d200-84e8-43c8-b5f2-9527b7b65a6a	11
61	66e4c0fc-b75c-4ecb-a0fb-2c4459807237	11
62	287823a1-bd7e-4e77-b54d-6e0c4cbc49ba	11
63	3543954e-b2db-49a5-955a-4281c1e4c5f5	11
64	f29fc024-b6a3-43ff-9446-cd222a65f190	11
65	f1620754-ba0c-42b4-94cd-33615963224a	11
66	17d48893-149b-4772-92cc-dc778fd2a18b	11
68	fe5eefcc-017c-4994-bbeb-703e56951796	13
69	8b5257ff-9e94-4616-92c3-d0795f2737db	13
70	3644ad13-070b-40b0-afac-58bfd65dd1df	13
71	fe9b4c59-cc95-4d33-bae1-437dc024c644	13
72	ee91e78e-d444-47e8-8159-8e5836613a01	13
73	27d7fdaa-2b4f-4975-b727-309dbc76bcb6	13
74	90132602-2aab-4ac7-b97d-0fef9e034350	13
75	9f925164-88da-49fa-a704-ddfccae9e3a5	13
76	1ac5f6be-e662-4d0a-bd85-5e308a08ce52	13
77	26fe3c8e-216c-433d-9562-be92da490c1e	13
78	0faa402c-e6c8-41ed-9bb6-b282c5faeea9	13
79	0affdcc6-87ee-4554-8032-40f82d93fece	13
80	320deb05-37b7-4427-b670-c53e7fd3f744	13
81	2ea09a98-61b2-4944-b760-45521cf58867	13
85	b660ad53-14e5-4ada-8b0c-f3563de89bd6	16
86	e2135cc1-8b12-470e-8de0-94c503776e57	17
87	71882a6b-8d3b-46a1-9e3e-51512bbb780b	18
88	1a5f3ddb-d6cb-404e-9b44-ac539e309ba1	18
89	f354dcae-a85f-45b8-a926-18872a77e1e2	18
90	89228027-f127-428b-8409-f7828a8342c0	18
91	95f09252-6f0a-4218-bce7-bde576d28998	18
92	73e01826-3d28-48ad-9883-a5acaf767f19	18
93	6b7cb3b6-bfb8-4638-8776-913777155072	18
94	34058912-d9a6-41f3-baa9-edab82100225	18
95	13037b8b-7a76-4d2a-9721-ea7d5f770c37	18
96	ac2902ee-49c8-4a84-9dde-30c2fa68f910	18
97	63bf6a82-d3dc-4cd3-8df9-5a55348cb50e	18
98	12e7f75b-fc51-479d-a0df-8fb55398560f	18
100	3614b73e-1a12-43cf-a34f-1da37078951a	20
103	2e99eeeb-fec0-4fd0-a704-97c36071b9b8	23
104	732c7acd-ef1a-4538-b72c-27effc5fbb1f	23
105	238955ce-ceb5-49e5-8028-4abfd1ba1dd5	23
106	7b96cd18-e1d3-4383-b2ef-c33e31312b6a	23
107	39bb625c-2c72-4ab2-a094-36675d9d2d8d	23
54	ee87810e-cc94-4d9b-9566-57e9beb7d43c	10
99	bd2c7cf6-a537-4d2d-b526-e4b1b3193c66	19
102	10c6bb82-53fc-4bc8-bc89-166adeeee26b	22
53	c2d5e64d-ed0d-495e-8ec1-6bd3fd226f74	9
84	5494577c-74cd-45f7-9a6b-1abf869b59ed	15
67	792a5277-6f1d-4228-af16-878ff896ecf7	12
82	e10d2ccf-f68e-4df8-af5e-1382c4031644	14
83	31b47f4a-7a5e-4251-af88-f77a9f5bf0bc	14
32	99d975a1-1709-48d9-849d-a90850ad941a	6
34	d05bd327-3449-405d-9a39-9a4b5c28b7da	6
35	f5bbc5f5-55a2-49cb-86a9-4dcfddbf31cf	6
36	4bdeccf6-b272-48ac-a5aa-1b17017c7bc0	6
37	f41b6223-bda6-4e7e-bcba-1f9cdda6c39c	6
38	8cee7652-971f-45fd-8dcf-c7611160ba0b	6
39	9c2f5cfa-dad3-4bf3-b5c9-722991429873	6
40	4c455c72-b2c3-45bf-91b7-438f5d5bd8c6	6
41	c69a61aa-7315-44d0-81cf-0a4d2e1fed3a	6
42	9de37bdb-9f47-4d8a-9fc6-4eaa4037a8cb	6
43	e2ca316b-8814-4823-9c68-0cd674a2ab0d	6
44	dc2da130-1143-4a57-a821-91cf0e5d4454	6
45	d7e411e5-84c7-404c-9c9e-126023d9f794	6
46	f11d052b-9254-4f03-97f7-438eab3596ab	6
47	99c06bd0-9e9c-4c1e-8e0a-43260d5020e8	6
108	baf2750e-91fa-43b1-89c2-790af7bb505b	23
109	01dff60a-f6b1-438c-abec-43ffbe590475	23
110	4316e543-e764-48ba-af45-6f9462a6141d	23
111	15958065-3655-46f9-9063-b9a5ab38a232	23
112	f05087b2-4f8a-42c6-9a9c-b175c64adb4e	23
113	1da8fcb4-90b3-47ac-ab9e-3b1a011f418d	23
114	2899394a-4176-433a-80bc-057bf61d9350	23
115	02cf4b1d-7d6a-4630-b927-9b5d0ecdfaa5	23
116	c6e609a3-f3d9-4af7-aaf7-c50850d8cafc	24
117	f46ca246-5d50-4c01-83c0-bfd765e99235	24
118	3c04ed97-d324-48d7-bb35-ec956f5b9f3f	24
119	e5c7e52d-0849-4e4c-b723-5466d3197112	24
120	065b340a-2fbc-4ee4-a186-173c40cb8fc2	24
121	2a295c8c-446b-463c-8433-a7753cfdc5eb	24
122	75bde93d-518d-4a7b-bbf1-50cab08d5330	24
123	4b3ebfe7-181b-455a-9173-c15c2b44857c	24
124	f461625b-739b-40e3-a584-f6cc90de80d2	24
125	2e148b67-5083-4f89-98d4-c5706fb6f4e9	24
126	9dd6dc5f-6632-47a2-9bf3-9fc6f6b348c4	24
127	2362bd57-0ebb-4ebb-a3a5-3041792926ed	24
128	8991291e-3091-4afe-8b46-a55f1afc5189	25
129	cef61098-a738-4088-90c3-345fcdde437c	25
130	5ef1d70f-1724-4f6c-a336-cb45de67a1c0	25
131	091a2e49-9676-475a-a971-ff44319e88dc	25
132	311e06f4-5903-4256-914f-fc6c760fe16b	25
133	809bfd80-f8d8-42dd-b70f-1dc1417a941d	25
134	739c8619-130c-4685-839c-5c10ab2089ce	25
135	60735be9-8d78-449c-9ce9-95d8e7fb475c	25
136	a2e3c3f1-784f-4c1f-915b-a1d6f212ed22	25
137	d527c806-2f13-4f60-bc5c-9d5584d35c93	25
138	2101add1-3609-4e3d-821d-488490cdc6d4	25
139	75d88d7d-40c0-4584-9247-08518fbcd418	26
140	4c9d915d-5e3a-46db-af33-05cbfaefeab3	26
141	aad60255-4659-4f43-b5a9-04ca334f1597	26
142	c27c5257-6165-4a52-b9c0-c60eb475a303	26
143	2710e9ce-3455-4987-a24d-9e008884472a	26
144	8aab2375-3792-460e-a3ce-61ece499e63f	26
145	e77fc30f-d216-4e91-868b-3bf7ed6c35ba	26
146	b88f4133-d7c7-45e0-aabd-ca48131a5b72	26
147	30ce85f3-70f0-4d2e-a370-450af8fa130f	26
148	dedcadd1-bbb1-4680-9fc1-41185a369f40	26
149	17392fed-d847-48a7-9e6d-018a6e8fc18b	26
152	8e142368-c61b-43f7-9597-0692b0fd7e92	29
153	eb289b02-1f84-4e9d-9085-749eba939a04	29
154	d11d883a-c9ae-497c-b5d6-50d2f81af1e7	29
155	84765c33-3678-4354-b722-a8b804f65b1b	29
156	6e154e97-b99d-40d7-8f3d-fd9cb09d2c45	29
157	53c476f5-543f-46e4-952a-39078ed54535	29
158	2abccb3e-1a0c-4905-98fc-43f567cc975c	29
159	464307fb-5e6b-4048-9660-968ddd7c79a3	29
160	9c74acd7-257d-4d87-8b97-4855fe2b6304	29
161	80635d24-4fb4-4b8a-ba6c-fabe6a545eef	29
162	46f17fa4-f2ef-41ef-9ede-00929c043ebe	29
163	e76450a1-a8df-46f6-96dc-6416dbfa03fe	29
164	d099476b-b195-4d05-ac5e-38d87d48dacc	29
166	35568bb9-513b-4d8d-b863-0275683fbf9d	31
167	1137b780-b2a8-41b9-8748-ac2fc51c2af4	31
168	ec2c4504-0722-4e81-8680-6eaae821deaf	31
169	f6703798-2d38-423b-b4ea-ea7a786f994f	31
170	69632ae5-db8b-40e7-a858-a8cadbdec767	31
171	87faa628-2d0c-4cf5-9271-500715bf79f8	31
172	e1fdd7c9-02c2-4b25-8c83-6325970768d8	31
173	0a5ad96c-53f9-477e-95f0-cd456176b00a	31
174	76da5490-a99d-49c8-a3b7-d21ed86622f5	32
175	3f83ccab-a11c-419d-bb9d-caa9bec2066c	32
176	c4b01fc6-cf01-4a37-9ad5-243624426ace	32
177	9379c390-daa9-4533-acfd-25f0a27cfebb	32
178	25995327-329d-4cca-8b5d-36e8fb4ff870	32
179	ced27f3b-3a28-44dd-a617-9c6366dc0ef2	32
180	2b5e3daf-719f-4ded-87ee-097b0f99f86d	33
181	57df450a-5125-483b-953d-b2e71b1859dc	33
199	ddcba74e-8269-49be-a581-8bda7350fc5d	36
200	4bfc4f52-35f9-493d-bda1-171daa426a15	36
201	428b8a16-61c4-413a-a8e8-069efa78f8a9	36
202	5123bb8a-d2af-420d-9156-6b2735d44850	37
203	011419f4-1a16-45f1-b308-105f7b673090	37
205	86bf67e2-af7d-4f57-89c5-2cecc0b983be	39
209	05607db7-59cf-4acb-aa83-f352584bf668	43
210	d442b3bc-7ba3-4ad9-91ba-2b856212419d	43
211	cc87f6e5-bc5a-42fb-b858-746bc1690528	43
212	d9a034e0-94bc-4656-8a4d-1459786308e5	43
213	4908d76e-8c92-41bc-8683-e95ff80e9400	43
214	df54dac1-721f-4197-b366-5649dfa8d31f	43
208	1fcaa0af-f883-4cde-b6ba-99c2043e24ed	42
182	048f8eb7-e72e-4ac0-8943-6eada5e4d632	34
183	eda4612d-d965-4d82-a1a1-c4a610d60374	34
184	c5bb17cb-bbd9-4b05-b203-dfb871562633	34
185	a18db579-188c-4d9e-aadd-f52a3cc39794	34
186	9efef726-f9e2-44fb-bfd8-5be420f0865e	34
187	186c59c5-769f-4987-9262-56078cc0c206	34
188	178bd8e4-ba66-4fee-a364-70a34798a7b3	34
189	b9f0be14-c9c9-40c4-8b2c-c5838a4372c8	34
191	76f0307e-b990-4fb6-88d5-e3b9a0391a2c	34
192	c4272052-ad4d-4ce1-be07-150f77ffcabe	34
193	dd203bfb-f799-4066-8dba-eb3ab2c093bf	34
194	83072ef1-438b-44d1-b4e7-9b58cf15fb38	34
195	c8323919-77ca-4609-af6a-79e2b69b96fa	34
196	abbda9df-5e9f-4400-80da-5a3e4b611cec	34
197	7dfa72f9-f587-4ec3-bff0-0fba0195a271	34
204	04937dbf-6755-4617-a9b2-0b843d470181	38
151	8109d41d-2519-4b84-80e7-27abe6a36e83	28
165	45787908-3a63-4981-a1cd-d3f535dbd969	30
206	88d5ea4a-3300-48f2-b024-1e5aa7823ab3	40
198	7d134ccf-c0f3-4304-a5d1-470902750d63	35
150	7164060c-b880-4a46-b4e3-5fb9fbfe85fa	27
215	dccdb33b-862a-4d03-9f47-9b0f596a5525	43
216	89eebd47-1360-456e-82c6-30f603b611c5	43
217	e5ac19f4-2942-4e6d-8eda-1beca4e1388c	43
218	089f468c-d6fb-4458-adea-ba30c6965d97	43
219	0529bbee-e403-48c4-90d6-dc6b434799a6	43
220	b937265e-4475-481d-a598-7e027ebc425b	43
221	d72fde4a-2ed1-49af-b346-e1afd5be6484	43
222	476e617c-7ca2-4952-a420-7b7c94c1b1dc	43
223	d0c5ca41-8ce3-465e-a448-4a17293cde66	44
224	da21bd78-8d94-4b34-8c67-bd03fc4948e5	44
225	c5cb8bc0-2576-4400-b481-602cf86f5307	44
226	c2d6ec89-aec9-47f9-8f3e-2dd4927210a1	44
227	dc09a0ee-b17a-4643-bdb2-a4b1c9537c2d	44
228	cf785d70-c342-486d-8907-db45ae0eb18e	44
229	f560e86b-56c8-4aa0-a5c0-04425de8ac70	44
230	9a602bc2-14f5-4c9d-81e6-3e1366e87c0f	44
231	d38f352a-3b21-45d4-92f7-b4ef8bbb6ce3	44
232	4d9a84cd-583f-44d2-9473-4787cc913dbb	44
233	3157abd8-3a05-4ef3-afe3-e109c3476651	44
234	dc10a366-cef3-416e-8944-598cd318d09a	44
235	1cd0f1f9-ea49-47e6-bbc5-7eec8a89f4c4	44
236	3baea51f-ec38-470a-8928-b2f463695cf4	44
237	20d2e51a-2c82-415a-9e2c-6c04793eb30a	45
238	268d622b-1f42-4933-a781-e11271cd3463	45
239	4562d053-5acc-4228-aa29-1a4ffba6a643	45
240	7cd03c45-e067-4302-92bf-d69387bd29a5	45
241	3e1339fc-ce3b-4237-bcc4-a94446e97125	45
242	84ec7271-9cb0-46b7-8329-1759033874a8	45
243	6df21ec8-69bd-43f4-b8ec-fa9cb76ec74a	45
244	e67e1d1a-0b8f-4389-bc9a-6e438b3349ed	45
245	98c71b0b-0621-45d1-b365-27f9743c11be	45
246	06c49ec3-7a0c-4a48-a579-9e11163ffa16	45
247	53a05755-95ac-4567-9de8-0f47c87f8a33	45
248	54b4c573-e279-4fc5-af5c-7a4010187d6b	45
249	3988058a-946b-4955-a453-a42a94bd395b	45
250	d9bcee64-af7e-4c9f-8f0d-976cc8b6bf9f	46
251	880d99e7-8c18-4a1a-882c-e0d96e8ecf15	47
252	1d9ae6b9-55c1-492a-bb0a-bbe7bade4c80	48
253	100b2034-4c3e-4fa3-bf87-aca4c99b30a2	49
254	c5c86073-c8c1-4ea8-b6d0-182e0518e447	50
257	7a0dd3a2-ab98-469e-946b-8f29426b690a	52
258	e9274ae1-2eb9-4e72-af54-88c0a20c7959	52
259	6489d032-9a0d-4737-b1a5-14dff7bfdc5e	52
260	0613eb13-6c71-4309-b833-ba2fa6412df1	52
261	11484a7c-33e2-4742-b912-c9313d2cd22b	52
262	fd98e184-7339-487a-b74c-3290031afa51	52
263	28b6dbec-8530-4999-a088-baab4008039e	52
264	922b1d35-bb06-4991-bf7e-518d9c413dc7	52
265	7d813a68-ba3f-4d7c-92d6-ebc5220bab6f	52
266	6079ba37-2e42-494e-9975-6fafbdb2fc56	52
267	90fbe39a-4726-4341-8567-65ab4b6ef13b	52
268	2b5699be-768e-480e-a837-2318706f87ed	52
269	d9453347-1660-426d-ba4f-717578674593	52
270	3578ecdd-d181-4a07-adf1-e41b5061a653	52
271	a7d96802-7dfe-4ce7-9998-40b0d1fdda7a	53
273	a69d4ac6-d6bb-4c09-a7bc-4efd83f5edd6	55
274	d40c2c71-1d87-42bd-ba73-e3f5a0923cf8	55
275	bbe07916-8f81-4116-9f51-7db2aeba8c8d	55
276	4d940428-e35e-4ace-8d23-2a23d6c6520e	55
277	aa5e2a6a-51c9-40c0-85ff-97b83dad7321	55
278	5489901b-a1b1-44eb-92e4-c12dc06bfe78	55
279	ef8b7683-6add-409f-8211-bf9636b3e24e	55
280	253ed1c1-3cb5-46e9-8d38-c345d3c6092f	55
281	ac3fedac-1240-444e-b9d7-4c183e34d50d	55
282	5256b0a0-ef98-4389-924d-01b2ed6347d4	55
283	ffd007f0-4232-4d9e-9dae-68111b051cfc	55
284	bf2c3a79-7dab-435a-b2e8-faaf32b1c3e4	55
285	f8a1be80-f3d8-4fe6-aecf-21e76ba52661	55
286	03af509b-cf23-4131-a930-e2128a7c4ca2	56
287	bfebb3e2-44fc-42d2-8791-024e9ecacbcc	56
288	612a7635-75d2-49c4-ba49-39dd48931f7f	56
289	bb702d78-7f58-4599-a40a-c396dccfdd6b	56
290	3f4534e3-1544-41e7-8655-f2355e6bbc9a	57
291	91305a1b-adda-4020-9970-aa935efed693	58
292	2158cc5b-8a73-4b57-b94e-11d4924653f6	59
293	48b1b6b3-9cd3-4ba9-994e-6e683c0835ab	59
294	947526b4-ef31-4f90-bf40-798b762b2d14	59
295	f62832ca-ae40-4665-b656-8cc1d505fab4	59
296	77b8b88e-340a-41bf-a168-66ae8e7f1942	59
297	f74c5b3e-417e-46f3-a9ff-2ec9d54e2596	59
299	8f8f93f2-46af-4142-ac13-7dc534fb5891	61
300	28be6c50-b1f4-4ce6-9860-86901a3d3d9d	61
301	cd5be605-b6f3-43f5-83f2-cbd48895a0fc	61
302	349984d3-a858-4756-ad63-f77dd97c81ea	61
303	c50c4944-f00b-4207-b7e9-fe2fcd89da26	61
304	21c73b6a-bb6e-43e5-a58a-8ccdb50c5d2d	61
305	a2eea7a6-4779-402d-9968-897b616131df	61
306	98e0bf4a-dad8-4817-8ece-05f1d5f943c0	61
307	dd92b86d-813c-4fd3-8286-680614001cfe	61
308	5386936c-0fb7-4484-8f2e-d2e4394dadcf	61
309	703eae22-db9d-4129-9a05-2aa36ac65211	62
310	5350812f-61b0-4801-945f-0c8865453717	62
311	c313230b-0e9f-40b2-a667-ea09bb27d057	62
312	f5c57c7d-16f8-4c8c-819b-4d3b7bbfe9a3	62
313	2c296921-30b0-4b3f-9710-f0db0d56add8	62
314	9cb29902-3d97-4d74-b63a-8284de864f26	62
315	5e53b903-b620-4346-86a9-146ce00ea41e	62
316	240d588f-e541-4b2f-864b-863632b1460d	62
317	df53a3dc-d4f5-4844-aa9b-47581f43ac83	62
318	d11618a3-20ff-47ac-ab22-f61509d9b5b3	62
319	166fe22e-bc84-4d01-9924-dfacc2251bae	62
320	eec8c2fc-e599-4eb0-8bb4-ceb229b706c0	62
256	7dd862f9-21d6-4768-89f8-f82929ae575c	51
272	08828edd-dfcd-4225-a073-3420cf8fda2f	54
298	ccab4c86-922c-4dd2-9edd-ed6b6bf29239	60
321	576bfe0c-6f41-4f46-b1db-f867b605578e	63
207	7049af11-be32-463a-b291-017601a041f0	41
322	880d99e7-8c18-4a1a-882c-e0d96e8ecf15	51
323	e036a429-1be6-4547-a99d-26602db584f9	51
324	77c4d7dc-6196-4d58-864d-5e70e06e9070	51
325	b9d81c1f-fa7b-46b3-ada4-4354bc2a9909	51
326	268a558b-ca2a-418e-8f46-8e3ce202363d	51
327	4869a6d0-4ef7-4712-a620-d10ffd8722d6	51
328	be8f3ead-127f-4ccf-8882-006d18f93b7b	51
329	5a28bf90-8f71-479d-9016-9dcd2ebea4c4	51
330	327f19da-5407-49bd-bcc8-298f69d99751	51
331	c91ae72a-289b-41c1-ae02-ce7d733bf9a1	51
332	56e13273-73f7-4b57-8e79-e1b88268f32a	51
333	6726b995-cb4c-4582-b729-fd9c21d063d2	51
334	2b972664-949e-4025-9f3d-48b3484674cd	51
335	05e9531d-e7e7-45c8-ae5a-91a2eb8acfa8	51
255	e6aad620-bbaf-4510-96f0-d2e8086c256d	51
336	3f4534e3-1544-41e7-8655-f2355e6bbc9a	21
337	2e99eeeb-fec0-4fd0-a704-97c36071b9b8	21
338	732c7acd-ef1a-4538-b72c-27effc5fbb1f	21
339	238955ce-ceb5-49e5-8028-4abfd1ba1dd5	21
340	7b96cd18-e1d3-4383-b2ef-c33e31312b6a	21
341	39bb625c-2c72-4ab2-a094-36675d9d2d8d	21
342	baf2750e-91fa-43b1-89c2-790af7bb505b	21
343	01dff60a-f6b1-438c-abec-43ffbe590475	21
344	4316e543-e764-48ba-af45-6f9462a6141d	21
345	15958065-3655-46f9-9063-b9a5ab38a232	21
346	f05087b2-4f8a-42c6-9a9c-b175c64adb4e	21
347	1da8fcb4-90b3-47ac-ab9e-3b1a011f418d	21
348	2899394a-4176-433a-80bc-057bf61d9350	21
349	02cf4b1d-7d6a-4630-b927-9b5d0ecdfaa5	21
101	a9abbe53-91fe-45a5-bc9e-bdb0f66bf0ed	21
350	a7d96802-7dfe-4ce7-9998-40b0d1fdda7a	42
351	8991291e-3091-4afe-8b46-a55f1afc5189	42
352	cef61098-a738-4088-90c3-345fcdde437c	42
353	5ef1d70f-1724-4f6c-a336-cb45de67a1c0	42
354	091a2e49-9676-475a-a971-ff44319e88dc	42
355	311e06f4-5903-4256-914f-fc6c760fe16b	42
356	809bfd80-f8d8-42dd-b70f-1dc1417a941d	42
357	739c8619-130c-4685-839c-5c10ab2089ce	42
358	60735be9-8d78-449c-9ce9-95d8e7fb475c	42
359	a2e3c3f1-784f-4c1f-915b-a1d6f212ed22	42
360	d527c806-2f13-4f60-bc5c-9d5584d35c93	42
361	2101add1-3609-4e3d-821d-488490cdc6d4	42
362	b660ad53-14e5-4ada-8b0c-f3563de89bd6	54
363	75d88d7d-40c0-4584-9247-08518fbcd418	54
364	4c9d915d-5e3a-46db-af33-05cbfaefeab3	54
365	aad60255-4659-4f43-b5a9-04ca334f1597	54
366	c27c5257-6165-4a52-b9c0-c60eb475a303	54
367	2710e9ce-3455-4987-a24d-9e008884472a	54
368	8aab2375-3792-460e-a3ce-61ece499e63f	54
369	e77fc30f-d216-4e91-868b-3bf7ed6c35ba	54
370	b88f4133-d7c7-45e0-aabd-ca48131a5b72	54
371	30ce85f3-70f0-4d2e-a370-450af8fa130f	54
372	dedcadd1-bbb1-4680-9fc1-41185a369f40	54
373	17392fed-d847-48a7-9e6d-018a6e8fc18b	54
374	d9bcee64-af7e-4c9f-8f0d-976cc8b6bf9f	10
375	a69d4ac6-d6bb-4c09-a7bc-4efd83f5edd6	10
376	d40c2c71-1d87-42bd-ba73-e3f5a0923cf8	10
377	bbe07916-8f81-4116-9f51-7db2aeba8c8d	10
378	4d940428-e35e-4ace-8d23-2a23d6c6520e	10
379	aa5e2a6a-51c9-40c0-85ff-97b83dad7321	10
380	5489901b-a1b1-44eb-92e4-c12dc06bfe78	10
381	ef8b7683-6add-409f-8211-bf9636b3e24e	10
382	253ed1c1-3cb5-46e9-8d38-c345d3c6092f	10
383	ac3fedac-1240-444e-b9d7-4c183e34d50d	10
384	5256b0a0-ef98-4389-924d-01b2ed6347d4	10
385	ffd007f0-4232-4d9e-9dae-68111b051cfc	10
386	bf2c3a79-7dab-435a-b2e8-faaf32b1c3e4	10
387	f8a1be80-f3d8-4fe6-aecf-21e76ba52661	10
388	1916fa49-5e91-4b12-9bb8-7d66588b8539	19
389	139725fe-8eb0-4290-8d54-1952cd13c08d	19
390	a824c875-bd11-4cec-ad50-275bf5f08da1	19
391	04a2c6e9-cde6-451c-9e01-b519c1719de1	19
392	333c6ec1-eb4f-4be4-96bc-d3fef78b16a9	19
393	4b2cbbaa-c17b-4aa0-a6a0-13d394a63a4f	19
394	721d340c-c317-452a-907b-5a7bae4aed56	19
395	65022472-03a8-402f-8a02-cc0aa9c7b275	19
396	e3944202-9ad3-468c-96fc-36ab710237ba	19
397	e74a482a-8e98-4d97-9bad-ce7998713f2d	19
398	2ae0e3df-1e4a-40cc-ba8a-ef5c5c79fbfe	19
399	ffb9ca46-744b-4cb0-8b29-6a9035134271	19
400	56f3e9ad-a5f1-4f19-9965-654357c84db1	19
401	00d5024b-0853-4e09-ad5a-4981a968f0ad	19
402	9c305126-3310-4c3a-8a83-90e4c45cc846	19
403	03af509b-cf23-4131-a930-e2128a7c4ca2	22
404	bfebb3e2-44fc-42d2-8791-024e9ecacbcc	22
405	612a7635-75d2-49c4-ba49-39dd48931f7f	22
406	bb702d78-7f58-4599-a40a-c396dccfdd6b	22
407	16c73abc-acca-41ac-bf05-56ddff423e03	22
408	e88cf3c6-43c5-4837-984f-bb9a1138ed92	22
409	378a3ecf-fb9a-4d7c-87a5-c3abd75c996a	22
410	afe21447-7588-48a7-b5f8-f7bfbe161133	22
411	76da5490-a99d-49c8-a3b7-d21ed86622f5	22
412	3f83ccab-a11c-419d-bb9d-caa9bec2066c	22
413	c4b01fc6-cf01-4a37-9ad5-243624426ace	22
414	9379c390-daa9-4533-acfd-25f0a27cfebb	22
415	25995327-329d-4cca-8b5d-36e8fb4ff870	22
416	ced27f3b-3a28-44dd-a617-9c6366dc0ef2	22
417	c5c86073-c8c1-4ea8-b6d0-182e0518e447	22
190	2b32188f-56d9-478c-aae2-25400c25e5ed	34
418	270c4e8d-bf5c-4e60-bf20-9add63d900f4	38
419	7a0dd3a2-ab98-469e-946b-8f29426b690a	38
420	e9274ae1-2eb9-4e72-af54-88c0a20c7959	38
421	6489d032-9a0d-4737-b1a5-14dff7bfdc5e	38
422	0613eb13-6c71-4309-b833-ba2fa6412df1	38
423	11484a7c-33e2-4742-b912-c9313d2cd22b	38
424	fd98e184-7339-487a-b74c-3290031afa51	38
425	28b6dbec-8530-4999-a088-baab4008039e	38
426	922b1d35-bb06-4991-bf7e-518d9c413dc7	38
427	7d813a68-ba3f-4d7c-92d6-ebc5220bab6f	38
428	6079ba37-2e42-494e-9975-6fafbdb2fc56	38
429	90fbe39a-4726-4341-8567-65ab4b6ef13b	38
430	2b5699be-768e-480e-a837-2318706f87ed	38
431	d9453347-1660-426d-ba4f-717578674593	38
432	3578ecdd-d181-4a07-adf1-e41b5061a653	38
433	3614b73e-1a12-43cf-a34f-1da37078951a	28
434	d0c5ca41-8ce3-465e-a448-4a17293cde66	28
435	da21bd78-8d94-4b34-8c67-bd03fc4948e5	28
436	c5cb8bc0-2576-4400-b481-602cf86f5307	28
437	c2d6ec89-aec9-47f9-8f3e-2dd4927210a1	28
438	dc09a0ee-b17a-4643-bdb2-a4b1c9537c2d	28
439	cf785d70-c342-486d-8907-db45ae0eb18e	28
440	f560e86b-56c8-4aa0-a5c0-04425de8ac70	28
441	9a602bc2-14f5-4c9d-81e6-3e1366e87c0f	28
442	d38f352a-3b21-45d4-92f7-b4ef8bbb6ce3	28
443	4d9a84cd-583f-44d2-9473-4787cc913dbb	28
444	3157abd8-3a05-4ef3-afe3-e109c3476651	28
445	dc10a366-cef3-416e-8944-598cd318d09a	28
446	1cd0f1f9-ea49-47e6-bbc5-7eec8a89f4c4	28
447	3baea51f-ec38-470a-8928-b2f463695cf4	28
448	86bf67e2-af7d-4f57-89c5-2cecc0b983be	9
449	c6e609a3-f3d9-4af7-aaf7-c50850d8cafc	9
450	f46ca246-5d50-4c01-83c0-bfd765e99235	9
451	3c04ed97-d324-48d7-bb35-ec956f5b9f3f	9
452	e5c7e52d-0849-4e4c-b723-5466d3197112	9
453	065b340a-2fbc-4ee4-a186-173c40cb8fc2	9
454	2a295c8c-446b-463c-8433-a7753cfdc5eb	9
455	75bde93d-518d-4a7b-bbf1-50cab08d5330	9
456	4b3ebfe7-181b-455a-9173-c15c2b44857c	9
457	f461625b-739b-40e3-a584-f6cc90de80d2	9
458	2e148b67-5083-4f89-98d4-c5706fb6f4e9	9
459	9dd6dc5f-6632-47a2-9bf3-9fc6f6b348c4	9
460	2362bd57-0ebb-4ebb-a3a5-3041792926ed	9
461	ce60383a-6b41-464f-a02d-6f2b43678cae	30
462	8e142368-c61b-43f7-9597-0692b0fd7e92	30
463	eb289b02-1f84-4e9d-9085-749eba939a04	30
464	d11d883a-c9ae-497c-b5d6-50d2f81af1e7	30
465	84765c33-3678-4354-b722-a8b804f65b1b	30
466	6e154e97-b99d-40d7-8f3d-fd9cb09d2c45	30
467	53c476f5-543f-46e4-952a-39078ed54535	30
468	2abccb3e-1a0c-4905-98fc-43f567cc975c	30
469	464307fb-5e6b-4048-9660-968ddd7c79a3	30
470	9c74acd7-257d-4d87-8b97-4855fe2b6304	30
471	80635d24-4fb4-4b8a-ba6c-fabe6a545eef	30
472	46f17fa4-f2ef-41ef-9ede-00929c043ebe	30
473	e76450a1-a8df-46f6-96dc-6416dbfa03fe	30
474	d099476b-b195-4d05-ac5e-38d87d48dacc	30
475	1d9ae6b9-55c1-492a-bb0a-bbe7bade4c80	15
476	20d2e51a-2c82-415a-9e2c-6c04793eb30a	15
477	268d622b-1f42-4933-a781-e11271cd3463	15
478	4562d053-5acc-4228-aa29-1a4ffba6a643	15
479	7cd03c45-e067-4302-92bf-d69387bd29a5	15
480	3e1339fc-ce3b-4237-bcc4-a94446e97125	15
481	84ec7271-9cb0-46b7-8329-1759033874a8	15
482	6df21ec8-69bd-43f4-b8ec-fa9cb76ec74a	15
483	e67e1d1a-0b8f-4389-bc9a-6e438b3349ed	15
484	98c71b0b-0621-45d1-b365-27f9743c11be	15
485	06c49ec3-7a0c-4a48-a579-9e11163ffa16	15
486	53a05755-95ac-4567-9de8-0f47c87f8a33	15
487	54b4c573-e279-4fc5-af5c-7a4010187d6b	15
488	3988058a-946b-4955-a453-a42a94bd395b	15
489	100b2034-4c3e-4fa3-bf87-aca4c99b30a2	12
490	05607db7-59cf-4acb-aa83-f352584bf668	12
491	d442b3bc-7ba3-4ad9-91ba-2b856212419d	12
492	cc87f6e5-bc5a-42fb-b858-746bc1690528	12
493	d9a034e0-94bc-4656-8a4d-1459786308e5	12
494	4908d76e-8c92-41bc-8683-e95ff80e9400	12
495	df54dac1-721f-4197-b366-5649dfa8d31f	12
496	dccdb33b-862a-4d03-9f47-9b0f596a5525	12
497	89eebd47-1360-456e-82c6-30f603b611c5	12
498	e5ac19f4-2942-4e6d-8eda-1beca4e1388c	12
499	089f468c-d6fb-4458-adea-ba30c6965d97	12
500	0529bbee-e403-48c4-90d6-dc6b434799a6	12
501	b937265e-4475-481d-a598-7e027ebc425b	12
502	d72fde4a-2ed1-49af-b346-e1afd5be6484	12
503	476e617c-7ca2-4952-a420-7b7c94c1b1dc	12
504	871f0882-0a67-4fc9-aa65-c980f2f2dacd	40
505	fe5eefcc-017c-4994-bbeb-703e56951796	40
506	8b5257ff-9e94-4616-92c3-d0795f2737db	40
507	3644ad13-070b-40b0-afac-58bfd65dd1df	40
508	fe9b4c59-cc95-4d33-bae1-437dc024c644	40
509	ee91e78e-d444-47e8-8159-8e5836613a01	40
510	27d7fdaa-2b4f-4975-b727-309dbc76bcb6	40
511	90132602-2aab-4ac7-b97d-0fef9e034350	40
512	9f925164-88da-49fa-a704-ddfccae9e3a5	40
513	1ac5f6be-e662-4d0a-bd85-5e308a08ce52	40
514	26fe3c8e-216c-433d-9562-be92da490c1e	40
515	0faa402c-e6c8-41ed-9bb6-b282c5faeea9	40
516	0affdcc6-87ee-4554-8032-40f82d93fece	40
517	320deb05-37b7-4427-b670-c53e7fd3f744	40
518	2ea09a98-61b2-4944-b760-45521cf58867	40
519	2158cc5b-8a73-4b57-b94e-11d4924653f6	60
520	48b1b6b3-9cd3-4ba9-994e-6e683c0835ab	60
521	947526b4-ef31-4f90-bf40-798b762b2d14	60
522	f62832ca-ae40-4665-b656-8cc1d505fab4	60
523	77b8b88e-340a-41bf-a168-66ae8e7f1942	60
524	f74c5b3e-417e-46f3-a9ff-2ec9d54e2596	60
525	35568bb9-513b-4d8d-b863-0275683fbf9d	60
526	1137b780-b2a8-41b9-8748-ac2fc51c2af4	60
527	ec2c4504-0722-4e81-8680-6eaae821deaf	60
528	f6703798-2d38-423b-b4ea-ea7a786f994f	60
529	69632ae5-db8b-40e7-a858-a8cadbdec767	60
530	87faa628-2d0c-4cf5-9271-500715bf79f8	60
531	e1fdd7c9-02c2-4b25-8c83-6325970768d8	60
532	0a5ad96c-53f9-477e-95f0-cd456176b00a	60
533	e24fff4c-a509-4fb5-80bc-bc95aa9ab09a	60
534	2b5e3daf-719f-4ded-87ee-097b0f99f86d	14
535	57df450a-5125-483b-953d-b2e71b1859dc	14
536	5123bb8a-d2af-420d-9156-6b2735d44850	14
537	011419f4-1a16-45f1-b308-105f7b673090	14
538	8f8f93f2-46af-4142-ac13-7dc534fb5891	14
539	28be6c50-b1f4-4ce6-9860-86901a3d3d9d	14
540	cd5be605-b6f3-43f5-83f2-cbd48895a0fc	14
541	349984d3-a858-4756-ad63-f77dd97c81ea	14
542	c50c4944-f00b-4207-b7e9-fe2fcd89da26	14
543	21c73b6a-bb6e-43e5-a58a-8ccdb50c5d2d	14
544	a2eea7a6-4779-402d-9968-897b616131df	14
545	98e0bf4a-dad8-4817-8ece-05f1d5f943c0	14
546	dd92b86d-813c-4fd3-8286-680614001cfe	14
547	5386936c-0fb7-4484-8f2e-d2e4394dadcf	14
548	e2135cc1-8b12-470e-8de0-94c503776e57	35
549	71882a6b-8d3b-46a1-9e3e-51512bbb780b	35
550	1a5f3ddb-d6cb-404e-9b44-ac539e309ba1	35
551	f354dcae-a85f-45b8-a926-18872a77e1e2	35
552	89228027-f127-428b-8409-f7828a8342c0	35
553	95f09252-6f0a-4218-bce7-bde576d28998	35
554	73e01826-3d28-48ad-9883-a5acaf767f19	35
555	6b7cb3b6-bfb8-4638-8776-913777155072	35
556	34058912-d9a6-41f3-baa9-edab82100225	35
557	13037b8b-7a76-4d2a-9721-ea7d5f770c37	35
558	ac2902ee-49c8-4a84-9dde-30c2fa68f910	35
559	63bf6a82-d3dc-4cd3-8df9-5a55348cb50e	35
560	12e7f75b-fc51-479d-a0df-8fb55398560f	35
33	1b434a0c-70e8-4cb6-a283-517129f46349	6
561	91305a1b-adda-4020-9970-aa935efed693	27
562	703eae22-db9d-4129-9a05-2aa36ac65211	27
563	5350812f-61b0-4801-945f-0c8865453717	27
564	c313230b-0e9f-40b2-a667-ea09bb27d057	27
565	f5c57c7d-16f8-4c8c-819b-4d3b7bbfe9a3	27
566	2c296921-30b0-4b3f-9710-f0db0d56add8	27
567	9cb29902-3d97-4d74-b63a-8284de864f26	27
568	5e53b903-b620-4346-86a9-146ce00ea41e	27
569	240d588f-e541-4b2f-864b-863632b1460d	27
570	df53a3dc-d4f5-4844-aa9b-47581f43ac83	27
571	d11618a3-20ff-47ac-ab22-f61509d9b5b3	27
572	166fe22e-bc84-4d01-9924-dfacc2251bae	27
573	eec8c2fc-e599-4eb0-8bb4-ceb229b706c0	27
574	ddcba74e-8269-49be-a581-8bda7350fc5d	63
575	4bfc4f52-35f9-493d-bda1-171daa426a15	63
576	428b8a16-61c4-413a-a8e8-069efa78f8a9	63
577	4feed4c2-a965-45b1-b857-c2f1e2c77771	63
578	6cc91b42-78e1-47ab-b574-acc4b70cd933	63
579	f7e2539d-e237-46ff-a3be-0ba6b4cb46bb	63
580	e0a8585b-8d6b-446a-b6f6-67c4884b01d1	63
581	6d2ad37c-e74a-44c5-9db5-a6bba295bf29	63
582	ef78d200-84e8-43c8-b5f2-9527b7b65a6a	63
583	66e4c0fc-b75c-4ecb-a0fb-2c4459807237	63
584	287823a1-bd7e-4e77-b54d-6e0c4cbc49ba	63
585	3543954e-b2db-49a5-955a-4281c1e4c5f5	63
586	f29fc024-b6a3-43ff-9446-cd222a65f190	63
587	f1620754-ba0c-42b4-94cd-33615963224a	63
588	17d48893-149b-4772-92cc-dc778fd2a18b	63
\.


--
-- Name: games_markets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('games_markets_id_seq', 588, true);


--
-- Data for Name: market_orders; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY market_orders (id, market_id, roster_id, action, player_id, price, rejected, rejected_reason, created_at, updated_at) FROM stdin;
\.


--
-- Name: market_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('market_orders_id_seq', 1, false);


--
-- Data for Name: market_players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY market_players (id, market_id, player_id, shadow_bets, bets, locked_at, initial_shadow_bets, locked, score, player_stats_id) FROM stdin;
\.


--
-- Name: market_players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('market_players_id_seq', 1, false);


--
-- Data for Name: markets; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY markets (id, name, shadow_bets, shadow_bet_rate, opened_at, closed_at, created_at, updated_at, published_at, state, total_bets, sport_id, initial_shadow_bets, price_multiplier, started_at) FROM stdin;
1		1000	0.750000	2013-08-04 00:00:00	2013-08-10 23:25:00	2013-09-14 23:48:10.802635	2013-09-14 23:48:10.802641	2013-08-04 00:00:00		0	1	\N	1	2013-08-10 23:25:00
2		1000	0.750000	2013-09-02 00:00:00	2013-09-09 00:25:00	2013-09-14 23:48:10.842239	2013-09-14 23:48:10.842242	2013-09-02 00:00:00		0	1	\N	1	2013-09-08 16:55:00
3		1000	0.750000	2013-10-04 00:00:00	2013-10-11 00:20:00	2013-09-14 23:48:11.512097	2013-09-14 23:48:11.512101	2013-10-04 00:00:00		0	1	\N	1	2013-10-11 00:20:00
4		1000	0.750000	2013-12-16 00:00:00	2013-12-23 01:25:00	2013-09-14 23:48:11.568743	2013-09-14 23:48:11.568745	2013-12-16 00:00:00		0	1	\N	1	2013-12-22 17:55:00
5		1000	0.750000	2013-12-06 00:00:00	2013-12-13 01:20:00	2013-09-14 23:48:12.26275	2013-09-14 23:48:12.262753	2013-12-06 00:00:00		0	1	\N	1	2013-12-13 01:20:00
7		1000	0.750000	2013-08-10 00:00:00	2013-08-16 23:55:00	2013-09-14 23:48:13.114726	2013-09-14 23:48:13.11473	2013-08-10 00:00:00		0	1	\N	1	2013-08-16 22:55:00
8		1000	0.750000	2013-09-06 00:00:00	2013-09-13 00:20:00	2013-09-14 23:48:13.283482	2013-09-14 23:48:13.283483	2013-09-06 00:00:00		0	1	\N	1	2013-09-13 00:20:00
11		1000	0.750000	2013-11-25 00:00:00	2013-12-02 01:25:00	2013-09-14 23:48:13.390843	2013-09-14 23:48:13.390844	2013-11-25 00:00:00		0	1	\N	1	2013-12-01 17:55:00
13		1000	0.750000	2013-12-09 00:00:00	2013-12-16 01:25:00	2013-09-14 23:48:13.892971	2013-09-14 23:48:13.892975	2013-12-09 00:00:00		0	1	\N	1	2013-12-15 17:55:00
16		1000	0.750000	2013-10-25 00:00:00	2013-11-01 00:20:00	2013-09-14 23:48:14.668886	2013-09-14 23:48:14.668887	2013-10-25 00:00:00		0	1	\N	1	2013-11-01 00:20:00
17		1000	0.750000	2013-11-15 00:00:00	2013-11-22 01:20:00	2013-09-14 23:48:14.704864	2013-09-14 23:48:14.704865	2013-11-15 00:00:00		0	1	\N	1	2013-11-22 01:20:00
18		1000	0.750000	2013-11-18 00:00:00	2013-11-25 01:25:00	2013-09-14 23:48:14.737701	2013-09-14 23:48:14.737703	2013-11-18 00:00:00		0	1	\N	1	2013-11-24 17:55:00
20		1000	0.750000	2013-09-13 00:00:00	2013-09-20 00:20:00	2013-09-14 23:48:15.228487	2013-09-14 23:48:15.22849	2013-09-13 00:00:00		0	1	\N	1	2013-09-20 00:20:00
23		1000	0.750000	2013-09-23 00:00:00	2013-09-30 00:25:00	2013-09-14 23:48:15.356733	2013-09-14 23:48:15.356736	2013-09-23 00:00:00		0	1	\N	1	2013-09-29 16:55:00
24		1000	0.750000	2013-09-30 00:00:00	2013-10-07 00:25:00	2013-09-14 23:48:15.880003	2013-09-14 23:48:15.880007	2013-09-30 00:00:00		0	1	\N	1	2013-10-06 16:55:00
25		1000	0.750000	2013-10-21 00:00:00	2013-10-28 00:25:00	2013-09-14 23:48:16.44906	2013-09-14 23:48:16.449064	2013-10-21 00:00:00		0	1	\N	1	2013-10-27 16:55:00
26		1000	0.750000	2013-10-28 00:00:00	2013-11-04 01:25:00	2013-09-14 23:48:17.048619	2013-09-14 23:48:17.048621	2013-10-28 00:00:00		0	1	\N	1	2013-11-03 17:55:00
29		1000	0.750000	2013-10-07 00:00:00	2013-10-14 00:25:00	2013-09-14 23:48:17.74553	2013-09-14 23:48:17.745532	2013-10-07 00:00:00		0	1	\N	1	2013-10-13 16:55:00
31		1000	0.750000	2013-08-03 00:00:00	2013-08-10 01:55:00	2013-09-14 23:48:18.299578	2013-09-14 23:48:18.299579	2013-08-03 00:00:00		0	1	\N	1	2013-08-09 23:25:00
32		1000	0.750000	2013-08-11 00:00:00	2013-08-18 01:55:00	2013-09-14 23:48:18.625408	2013-09-14 23:48:18.625412	2013-08-11 00:00:00		0	1	\N	1	2013-08-17 20:25:00
33		1000	0.750000	2013-08-16 00:00:00	2013-08-22 23:55:00	2013-09-14 23:48:18.864741	2013-09-14 23:48:18.864742	2013-08-16 00:00:00		0	1	\N	1	2013-08-22 23:25:00
36		1000	0.750000	2013-11-22 00:00:00	2013-11-29 01:25:00	2013-09-14 23:48:19.979815	2013-09-14 23:48:19.979817	2013-11-22 00:00:00		0	1	\N	1	2013-11-28 17:25:00
37		1000	0.750000	2013-08-17 00:00:00	2013-08-24 01:55:00	2013-09-14 23:48:20.074288	2013-09-14 23:48:20.074289	2013-08-17 00:00:00		0	1	\N	1	2013-08-23 23:55:00
39		1000	0.750000	2013-09-27 00:00:00	2013-10-04 00:20:00	2013-09-14 23:48:20.163669	2013-09-14 23:48:20.163671	2013-09-27 00:00:00		0	1	\N	1	2013-10-04 00:20:00
43		1000	0.750000	2013-12-02 00:00:00	2013-12-09 01:25:00	2013-09-14 23:48:20.295744	2013-09-14 23:48:20.295748	2013-12-02 00:00:00		0	1	\N	1	2013-12-08 17:55:00
44		1000	0.750000	2013-09-16 00:00:00	2013-09-23 00:25:00	2013-09-14 23:48:21.008325	2013-09-14 23:48:21.008329	2013-09-16 00:00:00		0	1	\N	1	2013-09-22 16:55:00
45		1000	0.750000	2013-10-14 00:00:00	2013-10-21 00:25:00	2013-09-14 23:48:21.6765	2013-09-14 23:48:21.676505	2013-10-14 00:00:00		0	1	\N	1	2013-10-20 16:55:00
46		1000	0.750000	2013-11-08 00:00:00	2013-11-15 01:20:00	2013-09-14 23:48:22.294288	2013-09-14 23:48:22.294291	2013-11-08 00:00:00		0	1	\N	1	2013-11-15 01:20:00
47		1000	0.750000	2013-08-30 00:00:00	2013-09-06 00:25:00	2013-09-14 23:48:22.358081	2013-09-14 23:48:22.358085	2013-08-30 00:00:00		0	1	\N	1	2013-09-06 00:25:00
48		1000	0.750000	2013-10-11 00:00:00	2013-10-18 00:20:00	2013-09-14 23:48:22.408585	2013-09-14 23:48:22.408586	2013-10-11 00:00:00		0	1	\N	1	2013-10-18 00:20:00
49		1000	0.750000	2013-11-29 00:00:00	2013-12-06 01:20:00	2013-09-14 23:48:22.441702	2013-09-14 23:48:22.441702	2013-11-29 00:00:00		0	1	\N	1	2013-12-06 01:20:00
50		1000	0.750000	2013-08-12 00:00:00	2013-08-18 22:55:00	2013-09-14 23:48:22.468761	2013-09-14 23:48:22.468762	2013-08-12 00:00:00		0	1	\N	1	2013-08-18 22:55:00
52		1000	0.750000	2013-09-09 00:00:00	2013-09-16 00:25:00	2013-09-14 23:48:22.560071	2013-09-14 23:48:22.560073	2013-09-09 00:00:00		0	1	\N	1	2013-09-15 16:55:00
53		1000	0.750000	2013-10-18 00:00:00	2013-10-25 00:20:00	2013-09-14 23:48:23.10966	2013-09-14 23:48:23.109663	2013-10-18 00:00:00		0	1	\N	1	2013-10-25 00:20:00
55		1000	0.750000	2013-11-11 00:00:00	2013-11-18 01:25:00	2013-09-14 23:48:23.235291	2013-09-14 23:48:23.235295	2013-11-11 00:00:00		0	1	\N	1	2013-11-17 17:55:00
56		1000	0.750000	2013-08-09 00:00:00	2013-08-15 23:55:00	2013-09-14 23:48:23.85256	2013-09-14 23:48:23.852565	2013-08-09 00:00:00		0	1	\N	1	2013-08-15 23:25:00
57		1000	0.750000	2013-09-20 00:00:00	2013-09-27 00:20:00	2013-09-14 23:48:24.086201	2013-09-14 23:48:24.086206	2013-09-20 00:00:00		0	1	\N	1	2013-09-27 00:20:00
58		1000	0.750000	2013-11-01 00:00:00	2013-11-08 01:20:00	2013-09-14 23:48:24.143405	2013-09-14 23:48:24.143409	2013-11-01 00:00:00		0	1	\N	1	2013-11-08 01:20:00
59		1000	0.750000	2013-08-02 00:00:00	2013-08-09 01:55:00	2013-09-14 23:48:24.179438	2013-09-14 23:48:24.17944	2013-08-02 00:00:00		0	1	\N	1	2013-08-08 23:25:00
61		1000	0.750000	2013-08-18 00:00:00	2013-08-25 01:55:00	2013-09-14 23:48:24.425984	2013-09-14 23:48:24.425986	2013-08-18 00:00:00		0	1	\N	1	2013-08-24 20:25:00
62		1000	0.750000	2013-11-04 00:00:00	2013-11-11 01:25:00	2013-09-14 23:48:24.762559	2013-09-14 23:48:24.76256	2013-11-04 00:00:00		0	1	\N	1	2013-11-10 17:55:00
41	Week 0	1000	0.750000	2013-07-29 00:00:00	2013-08-04 23:55:00	2013-09-14 23:48:20.236	2013-09-14 23:48:20.236	2013-07-29 00:00:00		0	1	\N	1	2013-08-04 23:55:00
51	Week 1	1000	0.750000	2013-09-03 00:00:00	2013-09-10 02:15:00	2013-09-14 23:48:22.494	2013-09-14 23:48:22.495	2013-09-03 00:00:00		0	1	\N	1	2013-09-09 22:50:00
21	Week 4	1000	0.750000	2013-09-24 00:00:00	2013-10-01 00:35:00	2013-09-14 23:48:15.271	2013-09-14 23:48:15.271	2013-09-24 00:00:00		0	1	\N	1	2013-10-01 00:35:00
42	Week 8	1000	0.750000	2013-10-22 00:00:00	2013-10-29 00:35:00	2013-09-14 23:48:20.262	2013-09-14 23:48:20.262	2013-10-22 00:00:00		0	1	\N	1	2013-10-29 00:35:00
54	Week 9	1000	0.750000	2013-10-29 00:00:00	2013-11-05 01:35:00	2013-09-14 23:48:23.177	2013-09-14 23:48:23.177	2013-10-29 00:00:00		0	1	\N	1	2013-11-05 01:35:00
10	Week 11	1000	0.750000	2013-11-12 00:00:00	2013-11-19 01:35:00	2013-09-14 23:48:13.355	2013-09-14 23:48:13.355	2013-11-12 00:00:00		0	1	\N	1	2013-11-19 01:35:00
19	Week 16	1000	0.750000	2013-12-17 00:00:00	2013-12-24 01:35:00	2013-09-14 23:48:15.181	2013-09-14 23:48:15.181	2013-12-17 00:00:00		0	1	\N	1	2013-12-24 01:35:00
22	Week 2	1000	0.750000	2013-08-13 00:00:00	2013-08-19 23:55:00	2013-09-14 23:48:15.318	2013-09-14 23:48:15.318	2013-08-13 00:00:00		0	1	\N	1	2013-08-19 23:55:00
34	Week 4	1000	0.750000	2013-08-23 00:00:00	2013-08-30 01:55:00	2013-09-14 23:48:18.952	2013-09-14 23:48:18.952	2013-08-23 00:00:00		0	1	\N	1	2013-08-29 22:55:00
38	Week 2	1000	0.750000	2013-09-10 00:00:00	2013-09-17 00:35:00	2013-09-14 23:48:20.12	2013-09-14 23:48:20.12	2013-09-10 00:00:00		0	1	\N	1	2013-09-17 00:35:00
28	Week 3	1000	0.750000	2013-09-17 00:00:00	2013-09-24 00:35:00	2013-09-14 23:48:17.705	2013-09-14 23:48:17.705	2013-09-17 00:00:00		0	1	\N	1	2013-09-24 00:35:00
9	Week 5	1000	0.750000	2013-10-01 00:00:00	2013-10-08 00:35:00	2013-09-14 23:48:13.321	2013-09-14 23:48:13.321	2013-10-01 00:00:00		0	1	\N	1	2013-10-08 00:35:00
30	Week 6	1000	0.750000	2013-10-08 00:00:00	2013-10-15 00:35:00	2013-09-14 23:48:18.245	2013-09-14 23:48:18.245	2013-10-08 00:00:00		0	1	\N	1	2013-10-15 00:35:00
15	Week 7	1000	0.750000	2013-10-15 00:00:00	2013-10-22 00:35:00	2013-09-14 23:48:14.622	2013-09-14 23:48:14.622	2013-10-15 00:00:00		0	1	\N	1	2013-10-22 00:35:00
12	Week 14	1000	0.750000	2013-12-03 00:00:00	2013-12-10 01:35:00	2013-09-14 23:48:13.844	2013-09-14 23:48:13.844	2013-12-03 00:00:00		0	1	\N	1	2013-12-10 01:35:00
40	Week 15	1000	0.750000	2013-12-10 00:00:00	2013-12-17 01:35:00	2013-09-14 23:48:20.206	2013-09-14 23:48:20.206	2013-12-10 00:00:00		0	1	\N	1	2013-12-17 01:35:00
60	Week 1	1000	0.750000	2013-08-05 00:00:00	2013-08-11 17:25:00	2013-09-14 23:48:24.381	2013-09-14 23:48:24.381	2013-08-05 00:00:00		0	1	\N	1	2013-08-11 17:25:00
14	Week 3	1000	0.750000	2013-08-19 00:00:00	2013-08-25 23:55:00	2013-09-14 23:48:14.51	2013-09-14 23:48:14.51	2013-08-19 00:00:00		0	1	\N	1	2013-08-25 19:55:00
35	Week 12	1000	0.750000	2013-11-19 00:00:00	2013-11-26 01:35:00	2013-09-14 23:48:19.917	2013-09-14 23:48:19.917	2013-11-19 00:00:00		0	1	\N	1	2013-11-26 01:35:00
6	Week 17	1000	0.750000	2013-12-23 00:00:00	2013-12-29 21:20:00	2013-09-14 23:48:12.316	2013-09-14 23:48:12.316	2013-12-23 00:00:00		0	1	\N	1	2013-12-29 17:55:00
27	Week 10	1000	0.750000	2013-11-05 00:00:00	2013-11-12 01:35:00	2013-09-14 23:48:17.648	2013-09-14 23:48:17.648	2013-11-05 00:00:00		0	1	\N	1	2013-11-12 01:35:00
63	Week 13	1000	0.750000	2013-11-26 00:00:00	2013-12-03 01:35:00	2013-09-14 23:48:25.353	2013-09-14 23:48:25.353	2013-11-26 00:00:00		0	1	\N	1	2013-12-03 01:35:00
\.


--
-- Name: markets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('markets_id_seq', 63, true);


--
-- Data for Name: players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY players (id, stats_id, sport_id, name, name_abbr, birthdate, height, weight, college, "position", jersey_number, status, total_games, total_points, created_at, updated_at, team) FROM stdin;
1	64419234-82af-49fb-9c7a-098388e745b3	1	Nick Mangold	N.Mangold	1984-01-13	76	307	Ohio State	C	74	ACT	0	0	2013-09-14 23:47:57.834362	2013-09-14 23:47:57.834363	NYJ
2	50916d8f-c6d0-4dc6-ab0d-33f309c26bce	1	John Griffin	J.Griffin	1988-12-17	71	208	Massachusetts	RB	24	IR	0	0	2013-09-14 23:47:57.839077	2013-09-14 23:47:57.839087	NYJ
3	859a34fe-86c3-42dc-940f-5856a671fe02	1	Santonio Holmes	S.Holmes	1984-03-03	71	192	Ohio State	WR	10	ACT	0	0	2013-09-14 23:47:57.842146	2013-09-14 23:47:57.842147	NYJ
4	b19237b0-6d3c-4ef7-912d-7785aff470dc	1	Caleb Schlauderaff	C.Schlauderaff	1987-11-07	76	302	Utah	G	72	ACT	0	0	2013-09-14 23:47:57.845159	2013-09-14 23:47:57.845161	NYJ
5	26dd8e50-8f7a-43d6-8a98-addaaeb8194b	1	Clyde Gates	C.Gates	1986-06-13	72	197	Abilene Christian	WR	19	ACT	0	0	2013-09-14 23:47:57.848399	2013-09-14 23:47:57.848401	NYJ
6	37554760-5609-4cc2-8de2-379f2ba528b3	1	Brady Quinn	B.Quinn	1984-10-27	75	235	Notre Dame	QB	9	ACT	0	0	2013-09-14 23:47:57.851444	2013-09-14 23:47:57.851446	NYJ
7	0426fa87-ca2b-4028-b561-7bef06e7f9e4	1	Alex Green	A.Green	1988-06-23	72	220	Hawaii	RB	25	ACT	0	0	2013-09-14 23:47:57.853941	2013-09-14 23:47:57.853942	NYJ
8	d2edaf8f-9f00-4dba-adab-9399c7185614	1	Antonio Allen	A.Allen	1988-09-23	73	210	South Carolina	SS	39	ACT	0	0	2013-09-14 23:47:57.856413	2013-09-14 23:47:57.856423	NYJ
9	7e413ee7-e01c-4f5a-8e12-b7587e88e653	1	Mike Goodson	M.Goodson	1987-05-23	72	210	Texas A&M	RB	23	SUS	0	0	2013-09-14 23:47:57.860229	2013-09-14 23:47:57.860232	NYJ
10	1bdb2a2a-62bc-4043-8c80-f9b501d2003d	1	Brian Winters	B.Winters	1991-07-10	76	320	Kent State	G	67	ACT	0	0	2013-09-14 23:47:57.864431	2013-09-14 23:47:57.864433	NYJ
11	72f5a27a-544f-468a-b10b-89a1fc5d0e9f	1	Chris Ivory	C.Ivory	1988-03-22	72	222	Tiffin University	RB	33	ACT	0	0	2013-09-14 23:47:57.868391	2013-09-14 23:47:57.868393	NYJ
12	40652b42-2017-47ac-a6c3-336715bda1b7	1	Ryan Spadola	R.Spadola		75	200	Lehigh	WR	85	ACT	0	0	2013-09-14 23:47:57.872228	2013-09-14 23:47:57.87223	NYJ
13	07a68177-0b79-455b-b8a4-8107cc1c3be0	1	Konrad Reuland	K.Reuland	1987-04-04	77	260	Stanford	TE	88	ACT	0	0	2013-09-14 23:47:57.874814	2013-09-14 23:47:57.874814	NYJ
14	b37c621e-1125-4c35-bea0-fcabb1527060	1	Nick Folk	N.Folk	1984-11-05	73	222	Arizona	K	2	ACT	0	0	2013-09-14 23:47:57.87601	2013-09-14 23:47:57.876011	NYJ
15	111e5aa8-9e68-48fb-917f-e05007d99d28	1	Aaron Berry	A.Berry	1988-06-25	71	180	Pittsburgh	DB	22	IR	0	0	2013-09-14 23:47:57.877144	2013-09-14 23:47:57.877145	NYJ
16	512c64d9-c14a-404a-bd33-7f9a90e53d9a	1	Stephen Hill	S.Hill	1991-04-25	76	215	Georgia Tech	WR	84	ACT	0	0	2013-09-14 23:47:57.878346	2013-09-14 23:47:57.878347	NYJ
17	d5b2ad50-53f7-4f89-b3b1-027c127b14a8	1	Ben Obomanu	B.Obomanu	1983-10-30	73	204	Auburn	WR	15	ACT	0	0	2013-09-14 23:47:57.879496	2013-09-14 23:47:57.879497	NYJ
18	769d7178-df4e-4127-8166-8116165921e8	1	Jeremy Kerley	J.Kerley	1988-11-08	69	188	Texas Christian	WR	11	ACT	0	0	2013-09-14 23:47:57.880673	2013-09-14 23:47:57.880673	NYJ
19	061d9bb4-3fb7-4413-b43d-6ce50880c769	1	Michael Campbell	M.Campbell	1989-08-12	74	205	Temple	WR	16	PRA	0	0	2013-09-14 23:47:57.88183	2013-09-14 23:47:57.881831	NYJ
20	a6155092-1005-4b4c-8e37-21422ce93b42	1	Matt Simms	M.Simms	1988-09-27	75	210	Tennessee	QB	5	ACT	0	0	2013-09-14 23:47:57.88295	2013-09-14 23:47:57.882951	NYJ
21	432afa02-d07c-4dc0-a06a-41a22ec4a350	1	Jaiquawn Jarrett	J.Jarrett	1989-09-21	72	196	Temple	SAF	37	ACT	0	0	2013-09-14 23:47:57.884342	2013-09-14 23:47:57.884343	NYJ
22	2aff4c73-8b5b-4b71-8959-c73b8013dffc	1	Josh Bush	J.Bush	1989-03-06	71	205	Wake Forest	SAF	32	ACT	0	0	2013-09-14 23:47:57.885472	2013-09-14 23:47:57.885473	NYJ
23	6edf1c3e-bf89-4148-b827-cc4e50888c18	1	Vladimir Ducasse	V.Ducasse	1987-10-15	77	325	Massachusetts	OL	62	ACT	0	0	2013-09-14 23:47:57.886691	2013-09-14 23:47:57.886691	NYJ
24	4b749c57-0fbe-46b3-8d71-81c35e0de672	1	Ben Ijalana	B.Ijalana	1989-08-06	76	322	Villanova	T	71	ACT	0	0	2013-09-14 23:47:57.887801	2013-09-14 23:47:57.887802	NYJ
25	614b6a41-94bf-4a6c-8635-079ff791fd4f	1	D'Brickashaw Ferguson	D.Ferguson	1983-12-10	78	310	Virginia	OT	60	ACT	0	0	2013-09-14 23:47:57.889016	2013-09-14 23:47:57.889017	NYJ
26	2f0c3d76-eda4-4bac-8a0e-8efeba75a08f	1	Dawan Landry	D.Landry	1982-12-30	73	212	Georgia Tech	SAF	26	ACT	0	0	2013-09-14 23:47:57.890168	2013-09-14 23:47:57.890169	NYJ
27	c9d63c44-e306-466b-97e5-403d633d4d22	1	Willie Colon	W.Colon	1983-04-09	75	315	Hofstra	OT	66	ACT	0	0	2013-09-14 23:47:57.891311	2013-09-14 23:47:57.891312	NYJ
28	d46e3db5-f89f-4211-b8a7-baeb1a35df46	1	Oday Aboushi	O.Aboushi	1991-06-05	77	308	Virginia	T	75	ACT	0	0	2013-09-14 23:47:57.892435	2013-09-14 23:47:57.892436	NYJ
29	4b16d0ae-be52-46c8-9f0a-4577f757d3f2	1	Kellen Winslow	K.Winslow	1983-07-21	76	240	Miami (FL))	TE	81	ACT	0	0	2013-09-14 23:47:57.893607	2013-09-14 23:47:57.893608	NYJ
30	18f42166-c579-411e-975e-ca45e5cd0a40	1	Vidal Hazelton	V.Hazelton	1988-01-29	74	209	Cincinnati	WR	18	IR	0	0	2013-09-14 23:47:57.894766	2013-09-14 23:47:57.894766	NYJ
31	2fc398c0-2e7c-47ad-bf3f-803c2dcf11ce	1	Austin Howard	A.Howard	1987-03-22	79	333	Northern Iowa	T	77	ACT	0	0	2013-09-14 23:47:57.895985	2013-09-14 23:47:57.895986	NYJ
32	880ead7a-cbae-494e-8f72-3f3d90c71392	1	William Campbell	W.Campbell	1991-07-06	76	311	Michigan	G	65	ACT	0	0	2013-09-14 23:47:57.897102	2013-09-14 23:47:57.897102	NYJ
33	cfc93f5e-105e-4a5e-88d3-f4279893cfa8	1	Geno Smith	G.Smith	1990-10-12	75	221	West Virginia	QB	7	ACT	0	0	2013-09-14 23:47:57.898347	2013-09-14 23:47:57.898347	NYJ
34	f7b1117b-4975-4084-bd6f-f5bfe4c3b769	1	Lex Hilliard	L.Hilliard	1984-07-30	71	235	Montana	RB	36	IR	0	0	2013-09-14 23:47:57.899457	2013-09-14 23:47:57.899458	NYJ
35	97c96dce-9b33-4d0e-ba01-5eb629192d19	1	Tommy Bohanon	T.Bohanon	1990-09-10	73	247	Wake Forest	FB	40	ACT	0	0	2013-09-14 23:47:57.900579	2013-09-14 23:47:57.90058	NYJ
36	406a7386-83b6-4c25-8998-6968073d89c4	1	Jeff Cumberland	J.Cumberland	1987-05-02	76	260	Illinois	TE	87	ACT	0	0	2013-09-14 23:47:57.9017	2013-09-14 23:47:57.901701	NYJ
37	4a38cda2-e92f-47f8-b324-0c34e09d83f2	1	Bilal Powell	B.Powell	1988-10-27	70	204	Louisville	RB	29	ACT	0	0	2013-09-14 23:47:57.90292	2013-09-14 23:47:57.902921	NYJ
38	e6c40f79-1bbd-4f62-9391-7f535f110c0d	1	Mark Sanchez	M.Sanchez	1986-11-11	74	225	USC	QB	6	IR	0	0	2013-09-14 23:47:57.904044	2013-09-14 23:47:57.904044	NYJ
39	DEF-NYJ	1	NYJ Defense	NYJ		0	0		DEF	0	ACT	0	0	2013-09-14 23:47:57.905166	2013-09-14 23:47:57.905167	NYJ
40	99b8d78e-6d23-4e85-8eef-d286ba5ddc0c	1	Marcus Cannon	M.Cannon	1988-05-06	77	335	Texas Christian	OL	61	ACT	0	0	2013-09-14 23:47:58.269716	2013-09-14 23:47:58.26972	NE
41	600ae879-d95a-4ac4-ae4e-72c05a05f1ad	1	Shane Vereen	S.Vereen	1989-03-02	70	205	California	RB	34	IR	0	0	2013-09-14 23:47:58.274176	2013-09-14 23:47:58.274178	NE
42	2602b60c-31b1-43fd-b507-9b803fbfbc84	1	T.J. Moe	T.Moe		72	200	Missouri	WR	84	IR	0	0	2013-09-14 23:47:58.278079	2013-09-14 23:47:58.278082	NE
43	a527b7db-0b52-4379-9e4c-2e08c1fe1bed	1	Stephen Gostkowski	S.Gostkowski	1984-01-28	73	215	Memphis	K	3	ACT	0	0	2013-09-14 23:47:58.281908	2013-09-14 23:47:58.281911	NE
44	5b0ed7fc-21ed-426f-b8b6-145116cbc9ee	1	Sebastian Vollmer	S.Vollmer	1984-07-10	80	320	Houston	OT	76	ACT	0	0	2013-09-14 23:47:58.286409	2013-09-14 23:47:58.286411	NE
45	f5d20030-d934-45e3-8282-e34c6c83ad84	1	LeGarrette Blount	L.Blount	1986-12-05	72	250	Oregon	RB	29	ACT	0	0	2013-09-14 23:47:58.291294	2013-09-14 23:47:58.291294	NE
46	9d404288-65c5-414f-8ea5-ceb97eccaea0	1	Matt Slater	M.Slater	1985-09-09	72	210	UCLA	WR	18	ACT	0	0	2013-09-14 23:47:58.294393	2013-09-14 23:47:58.294393	NE
47	2bb70d56-a79a-4fa1-ae37-99858a3ffd55	1	Julian Edelman	J.Edelman	1986-05-22	70	198	Kent State	WR	11	ACT	0	0	2013-09-14 23:47:58.296955	2013-09-14 23:47:58.296956	NE
48	2142a164-48ad-47d6-bb27-0bc58c6b2e62	1	Rob Gronkowski	R.Gronkowski	1989-05-14	78	265	Arizona	TE	87	ACT	0	0	2013-09-14 23:47:58.299651	2013-09-14 23:47:58.299652	NE
49	cbe81592-1ee2-4bf1-870a-2578c4c8267e	1	Tavon Wilson	T.Wilson	1990-03-19	72	215	Illinois	DB	27	ACT	0	0	2013-09-14 23:47:58.30213	2013-09-14 23:47:58.302131	NE
50	74e93dc0-514a-4ebe-9fe4-45445f0b4f98	1	Logan Mankins	L.Mankins	1982-03-10	76	308	Fresno State	G	70	ACT	0	0	2013-09-14 23:47:58.304696	2013-09-14 23:47:58.304697	NE
51	23cc596c-3ffa-4ce8-8f59-e8dbba656ada	1	Will Svitek	W.Svitek	1982-01-08	78	310	Stanford	OT	74	ACT	0	0	2013-09-14 23:47:58.307678	2013-09-14 23:47:58.307681	NE
52	170b4c5f-a345-4899-8d81-e8982b0f3d65	1	Stevan Ridley	S.Ridley	1989-01-27	71	220	LSU	RB	22	ACT	0	0	2013-09-14 23:47:58.311463	2013-09-14 23:47:58.311467	NE
53	bd080c6f-c43c-4766-99ea-64f07926ed82	1	Chris Barker	C.Barker	1990-08-03	74	310	Nevada	G	64	ACT	0	0	2013-09-14 23:47:58.315374	2013-09-14 23:47:58.315376	NE
54	93927d6e-9271-4c1e-8239-cc20fd788ba9	1	Nate Ebner	N.Ebner	1988-12-14	72	210	Ohio State	DB	43	ACT	0	0	2013-09-14 23:47:58.319235	2013-09-14 23:47:58.319238	NE
55	10616740-2c72-4207-b8ed-9da09ecba854	1	Ryan Wendell	R.Wendell	1986-03-04	74	300	Fresno State	OL	62	ACT	0	0	2013-09-14 23:47:58.323069	2013-09-14 23:47:58.323072	NE
56	2b4e17f2-27b8-4c98-9b27-1d4c0d7949de	1	Kenbrell Thompkins	K.Thompkins		72	195	Cincinnati	WR	85	ACT	0	0	2013-09-14 23:47:58.326856	2013-09-14 23:47:58.326859	NE
57	44810f37-f2d0-4386-a955-6a77c9c2b043	1	Brice Schwab	B.Schwab	1990-03-27	79	302	Arizona State	T	60	IR	0	0	2013-09-14 23:47:58.33086	2013-09-14 23:47:58.330862	NE
58	b077b3b2-2fed-4c9f-9b8f-c4ff50a4f911	1	Nate Solder	N.Solder	1988-04-12	80	320	Colorado	OT	77	ACT	0	0	2013-09-14 23:47:58.334758	2013-09-14 23:47:58.334761	NE
59	a2802951-e573-4e8f-ad31-14b9ae5f8e7c	1	Duron Harmon	D.Harmon	1991-01-24	73	205	Rutgers	DB	30	ACT	0	0	2013-09-14 23:47:58.33812	2013-09-14 23:47:58.338122	NE
60	566dc8de-b2ab-4796-992e-a0a93e0dcc38	1	Markus Zusevics	M.Zusevics	1989-04-25	77	300	Iowa	T	66	IR	0	0	2013-09-14 23:47:58.34157	2013-09-14 23:47:58.341572	NE
61	41c44740-d0f6-44ab-8347-3b5d515e5ecf	1	Tom Brady	T.Brady	1977-08-03	76	225	Michigan	QB	12	ACT	0	0	2013-09-14 23:47:58.345283	2013-09-14 23:47:58.345285	NE
62	dba5e3ec-2c77-4f65-ad6e-cee246f816ef	1	Brandon Bolden	B.Bolden	1990-01-26	71	220	Mississippi	RB	38	ACT	0	0	2013-09-14 23:47:58.349253	2013-09-14 23:47:58.349255	NE
63	c6555772-de3c-4310-a046-5b6b9faf6580	1	Adrian Wilson	A.Wilson	1979-10-12	75	230	North Carolina State	SAF	24	IR	0	0	2013-09-14 23:47:58.353092	2013-09-14 23:47:58.353094	NE
64	88d2dbf4-3b9f-43ea-bac6-a8722cb24f43	1	Devin McCourty	D.McCourty	1987-08-13	70	195	Rutgers	DB	32	ACT	0	0	2013-09-14 23:47:58.356931	2013-09-14 23:47:58.356934	NE
65	a78b6faa-0606-445c-901b-b79c1f2771bd	1	Leon Washington	L.Washington	1982-08-29	68	192	Florida State	RB	33	ACT	0	0	2013-09-14 23:47:58.360833	2013-09-14 23:47:58.360835	NE
66	b30e620b-1f67-450f-a499-95f59808baac	1	Dan Connolly	D.Connolly	1982-09-02	76	305	Southeast Missouri State	OL	63	ACT	0	0	2013-09-14 23:47:58.364627	2013-09-14 23:47:58.364629	NE
67	1789597d-7344-4afb-bb7d-0d0124b5810a	1	Matthew Mulligan	M.Mulligan	1985-01-18	76	267	Maine	TE	88	ACT	0	0	2013-09-14 23:47:58.368482	2013-09-14 23:47:58.368484	NE
68	9d04accc-a404-406f-b93c-0878410e55a6	1	James Develin	J.Develin	1988-07-23	75	255	Brown	RB	46	ACT	0	0	2013-09-14 23:47:58.372267	2013-09-14 23:47:58.37227	NE
69	3144b871-b1b8-40c5-9a5c-1495d68a1e0a	1	Steve Gregory	S.Gregory	1983-01-08	71	200	Syracuse	SAF	28	ACT	0	0	2013-09-14 23:47:58.376332	2013-09-14 23:47:58.376335	NE
70	f82d4ebb-cda9-4b79-ade0-9ef468d2c101	1	Ryan Mallett	R.Mallett	1988-06-05	78	245	Arkansas	QB	15	ACT	0	0	2013-09-14 23:47:58.380033	2013-09-14 23:47:58.380035	NE
71	5b59a91a-3a9c-4473-b2eb-7673c8ec80b8	1	Josh Boyce	J.Boyce	1990-01-22	71	205	Texas Christian	WR	82	ACT	0	0	2013-09-14 23:47:58.383814	2013-09-14 23:47:58.383817	NE
72	a02fe2cf-3446-4a03-883c-314494087086	1	Zach Sudfeld	Z.Sudfeld	1989-04-17	79	260	Nevada	TE	44	ACT	0	0	2013-09-14 23:47:58.387676	2013-09-14 23:47:58.387678	NE
73	973bfe3c-6d0d-4130-a79c-f860650b1da6	1	Danny Amendola	D.Amendola	1985-11-02	71	195	Texas Tech	WR	80	ACT	0	0	2013-09-14 23:47:58.391647	2013-09-14 23:47:58.39165	NE
74	e35971ad-5efa-44aa-bbb0-b386e126c6de	1	Tyronne Green	T.Green	1986-04-06	74	316	Auburn	G	68	IR	0	0	2013-09-14 23:47:58.395209	2013-09-14 23:47:58.395211	NE
75	ac673b16-3268-43df-a521-4dfd864698cc	1	Aaron Dobson	A.Dobson	1991-06-13	75	200	Marshall	WR	17	ACT	0	0	2013-09-14 23:47:58.398817	2013-09-14 23:47:58.39882	NE
76	bd71e5e9-5b0e-41d0-a55d-076370b129ff	1	Mark Harrison	M.Harrison	1990-12-11	75	230	Rutgers	WR	13	NON	0	0	2013-09-14 23:47:58.403074	2013-09-14 23:47:58.403076	NE
77	add7a245-2444-491f-bdfb-b1b0d76f6a28	1	Michael Hoomanawanui	M.Hoomanawanui	1988-07-04	76	260	Illinois	TE	47	ACT	0	0	2013-09-14 23:47:58.407245	2013-09-14 23:47:58.407247	NE
78	DEF-NE	1	NE Defense	NE		0	0		DEF	0	ACT	0	0	2013-09-14 23:47:58.410624	2013-09-14 23:47:58.410626	NE
79	d3c2dddb-d73d-4014-96a8-2cc24e838201	1	Marcus Easley	M.Easley	1987-11-02	74	217	Connecticut	WR	81	ACT	0	0	2013-09-14 23:47:58.716582	2013-09-14 23:47:58.716584	BUF
80	058c99fc-470c-4579-a165-03e043335cc1	1	Dustin Hopkins	D.Hopkins	1990-10-01	74	193	Florida State	K	5	ACT	0	0	2013-09-14 23:47:58.721242	2013-09-14 23:47:58.721244	BUF
81	92018cf6-b194-44a9-bf07-0e20861bc6b8	1	Jairus Byrd	J.Byrd	1986-10-07	70	203	Oregon	FS	31	ACT	0	0	2013-09-14 23:47:58.725625	2013-09-14 23:47:58.725627	BUF
82	1eb8ad96-b4f3-461e-81a3-0a4e08844f73	1	Nickell Robey	N.Robey	1992-01-17	68	165	Southern California	DB	37	ACT	0	0	2013-09-14 23:47:58.729902	2013-09-14 23:47:58.729904	BUF
83	becd2875-f4c1-45a5-8676-f6fb25b30fe9	1	Aaron Williams	A.Williams	1990-04-23	72	199	Texas	SAF	23	ACT	0	0	2013-09-14 23:47:58.734204	2013-09-14 23:47:58.734206	BUF
84	4acba470-5c7f-4d6b-8967-851dcc2e94e7	1	Jim Leonhard	J.Leonhard	1982-10-27	68	188	Wisconsin	FS	35	ACT	0	0	2013-09-14 23:47:58.742312	2013-09-14 23:47:58.742315	BUF
85	7d2f7624-2876-4e64-b29c-005fa1e08232	1	Mana Silva	M.Silva	1988-08-17	72	206	Hawaii	DB	30	EXE	0	0	2013-09-14 23:47:58.746161	2013-09-14 23:47:58.746164	BUF
86	a86e72e2-24cb-4ff9-bb0e-2f49d5eecf99	1	Frank Summers	F.Summers	1985-09-06	69	248	Nevada-Las Vegas	FB	38	ACT	0	0	2013-09-14 23:47:58.749776	2013-09-14 23:47:58.749778	BUF
87	c3028465-9dce-4e8f-9f1b-2da73bce2d14	1	Jonathan Meeks	J.Meeks	1989-11-08	73	210	Clemson	DB	36	ACT	0	0	2013-09-14 23:47:58.753336	2013-09-14 23:47:58.753338	BUF
88	4d5777f6-1902-4128-8fe7-5e4cd15475b0	1	Duke Williams	D.Williams	1990-10-15	72	190	Nevada	SAF	27	ACT	0	0	2013-09-14 23:47:58.757127	2013-09-14 23:47:58.757129	BUF
89	c4a16e1e-f0c8-4716-9884-f5a2983616db	1	Kevin Kolb	K.Kolb	1984-08-24	75	218	Houston	QB	4	IR	0	0	2013-09-14 23:47:58.761137	2013-09-14 23:47:58.761139	BUF
90	cf23126f-055b-4617-819b-bb4bcb84541a	1	Lee Smith	L.Smith	1987-11-21	78	265	Marshall	TE	85	ACT	0	0	2013-09-14 23:47:58.764738	2013-09-14 23:47:58.764741	BUF
91	1cabe80e-c549-45e9-b37c-547d513cef84	1	Brandon Burton	B.Burton	1989-07-31	71	190	Utah	DB	29	ACT	0	0	2013-09-14 23:47:58.768333	2013-09-14 23:47:58.768335	BUF
92	8fc65820-f565-44e2-8635-3e1cdf165bf6	1	Chris Hogan	C.Hogan	1988-10-24	73	220	Monmouth (NJ)	WR	15	ACT	0	0	2013-09-14 23:47:58.771885	2013-09-14 23:47:58.771887	BUF
93	39af9fa1-2ede-4596-90c4-7e1052300496	1	Brad Smith	B.Smith	1983-12-12	74	213	Missouri	WR	16	IR	0	0	2013-09-14 23:47:58.775393	2013-09-14 23:47:58.775395	BUF
94	f28f45f8-a617-4caa-8332-ccfff0dddc07	1	Sam Young	S.Young	1987-06-24	80	316	Notre Dame	OT	71	ACT	0	0	2013-09-14 23:47:58.778795	2013-09-14 23:47:58.778797	BUF
95	e9f7f380-e7b2-4a68-af71-9483240fc748	1	Doug Legursky	D.Legursky	1986-06-09	73	315	Marshall	G	59	ACT	0	0	2013-09-14 23:47:58.78236	2013-09-14 23:47:58.782362	BUF
96	64d9a11b-2d05-4173-ac72-4f9e63fb4aa6	1	C.J. Spiller	C.Spiller	1987-08-05	71	200	Clemson	RB	28	ACT	0	0	2013-09-14 23:47:58.785775	2013-09-14 23:47:58.785778	BUF
97	6d6784cf-95b7-421c-aacb-26f58a7def9f	1	Eric Wood	E.Wood	1986-03-18	76	310	Louisville	C	70	ACT	0	0	2013-09-14 23:47:58.789255	2013-09-14 23:47:58.789257	BUF
98	309d4132-39f1-4a5b-b251-125dadf9b1b5	1	Colin Brown	C.Brown	1985-08-29	79	326	Missouri	C	74	ACT	0	0	2013-09-14 23:47:58.792727	2013-09-14 23:47:58.792729	BUF
99	c7c6dc46-a58a-4cfc-b626-2360434671cb	1	Stephon Gilmore	S.Gilmore	1990-09-19	72	190	South Carolina	DB	24	ACT	0	0	2013-09-14 23:47:58.796403	2013-09-14 23:47:58.796405	BUF
100	c2187fda-5e33-4854-b3f8-c0c1c5fbfb35	1	Cordy Glenn	C.Glenn	1989-09-18	77	343	Georgia	T	77	ACT	0	0	2013-09-14 23:47:58.799935	2013-09-14 23:47:58.799937	BUF
101	db72d154-5534-4160-b293-d0c4b239a677	1	Fred Jackson	F.Jackson	1981-02-20	73	216	Coe	RB	22	ACT	0	0	2013-09-14 23:47:58.803439	2013-09-14 23:47:58.803441	BUF
102	19d00799-4271-40ac-b5c4-4ea8b410a704	1	EJ Manuel	E.Manuel	1990-03-19	77	240	Florida State	QB	3	ACT	0	0	2013-09-14 23:47:58.807238	2013-09-14 23:47:58.80724	BUF
103	bf52ff53-35a6-4696-ac6d-3fa952dc2c87	1	Marquise Goodwin	M.Goodwin	1990-11-19	69	177	Texas	WR	88	ACT	0	0	2013-09-14 23:47:58.810954	2013-09-14 23:47:58.810956	BUF
104	d944ce13-2c90-4655-890c-5dac028a130c	1	Dan Carpenter	D.Carpenter	1985-11-25	74	225	Montana	K	2	ACT	0	0	2013-09-14 23:47:58.814558	2013-09-14 23:47:58.814561	BUF
105	cc546741-0993-4bf9-8338-47e715e25a91	1	Thomas Welch	T.Welch	1987-06-19	78	300	Vanderbilt	OT	66	ACT	0	0	2013-09-14 23:47:58.818138	2013-09-14 23:47:58.818141	BUF
106	36521d92-2c2c-4ae4-9b60-9928c3167e30	1	Chris Gragg	C.Gragg	1990-06-30	75	244	Arkansas	TE	89	ACT	0	0	2013-09-14 23:47:58.82153	2013-09-14 23:47:58.821532	BUF
107	4d4c91ac-4744-44aa-8115-0cf3127404ef	1	Tashard Choice	T.Choice	1984-11-20	70	210	Georgia Tech	RB	20	ACT	0	0	2013-09-14 23:47:58.824842	2013-09-14 23:47:58.824844	BUF
108	db1af021-0d38-4b01-86e8-8b4cc1126064	1	Scott Chandler	S.Chandler	1985-07-23	79	260	Iowa	TE	84	ACT	0	0	2013-09-14 23:47:58.828496	2013-09-14 23:47:58.828499	BUF
109	a4600df5-9f1f-40ba-b4a2-07cdffaf3969	1	Kraig Urbik	K.Urbik	1985-09-23	77	324	Wisconsin	G	60	ACT	0	0	2013-09-14 23:47:58.83206	2013-09-14 23:47:58.832062	BUF
110	a2ceffa6-0ff7-4158-858f-8c01fea175f2	1	Jeff Tuel	J.Tuel		75	221	Washington State	QB	8	ACT	0	0	2013-09-14 23:47:58.835689	2013-09-14 23:47:58.835694	BUF
111	d0840d54-b383-4e26-9055-5a57067951e5	1	Da'Norris Searcy	D.Searcy	1988-11-16	71	216	North Carolina	SS	25	ACT	0	0	2013-09-14 23:47:58.839394	2013-09-14 23:47:58.839396	BUF
112	49c818d2-4e3d-4825-995c-44bcdb240f66	1	Dan Carpenter	D.Carpenter		74	228	Montana	K	2	DUP	0	0	2013-09-14 23:47:58.842742	2013-09-14 23:47:58.842744	BUF
113	9279e6a7-1805-46db-a78a-19b78a58eaf2	1	Kevin Elliott	K.Elliott	1988-12-21	75	215	Florida A&M	WR	18	IR	0	0	2013-09-14 23:47:58.846131	2013-09-14 23:47:58.846134	BUF
114	c1b5db36-a2e2-4bbc-87c1-cdd216b4474c	1	Stevie Johnson	S.Johnson	1986-07-22	74	207	Kentucky	WR	13	ACT	0	0	2013-09-14 23:47:58.850017	2013-09-14 23:47:58.850019	BUF
115	618bedee-9259-4536-b0ff-fec98d2a20de	1	Robert Woods	R.Woods	1992-04-10	72	190	USC	WR	10	ACT	0	0	2013-09-14 23:47:58.853709	2013-09-14 23:47:58.853711	BUF
116	dc310df5-3ada-4b4f-8f79-2db2cc603ff8	1	Erik Pears	E.Pears	1982-06-25	80	316	Colorado State	OT	79	ACT	0	0	2013-09-14 23:47:58.858493	2013-09-14 23:47:58.858495	BUF
117	26f82a1b-2f90-4e82-8c6b-8036912a6d20	1	T.J. Graham	T.Graham	1989-07-27	72	180	North Carolina State	WR	11	ACT	0	0	2013-09-14 23:47:58.862225	2013-09-14 23:47:58.862227	BUF
118	ea307f9e-a72e-4577-b4d3-fd1dbaf0e57a	1	Chris Hairston	C.Hairston	1989-04-26	78	330	Clemson	T	75	NON	0	0	2013-09-14 23:47:58.866276	2013-09-14 23:47:58.866278	BUF
119	DEF-BUF	1	BUF Defense	BUF		0	0		DEF	0	ACT	0	0	2013-09-14 23:47:58.870201	2013-09-14 23:47:58.870203	BUF
120	24a6423a-0c3f-4cfb-b25a-fc05c04c9f7f	1	Brian Hartline	B.Hartline	1986-11-22	74	199	Ohio State	WR	82	ACT	0	0	2013-09-14 23:47:59.185045	2013-09-14 23:47:59.185046	MIA
121	1540d25f-4758-44d8-a4eb-276845326620	1	John Jerry	J.Jerry	1986-06-14	77	345	Mississippi	G	74	ACT	0	0	2013-09-14 23:47:59.187998	2013-09-14 23:47:59.188	MIA
122	969a4d68-1d76-4e64-bfff-e898a9ac6bd4	1	Rishard Matthews	R.Matthews	1989-10-12	72	210	Nevada	WR	18	ACT	0	0	2013-09-14 23:47:59.19043	2013-09-14 23:47:59.190432	MIA
123	596c4000-ede5-45b0-8336-33efeb686d2b	1	Caleb Sturgis	C.Sturgis	1989-08-09	69	188	Florida	K	9	ACT	0	0	2013-09-14 23:47:59.193	2013-09-14 23:47:59.193002	MIA
124	a28c10be-01ab-44f1-bb21-c29bcbc8cd57	1	Will Yeatman	W.Yeatman	1988-04-10	78	315	Maryland	OT	72	ACT	0	0	2013-09-14 23:47:59.195717	2013-09-14 23:47:59.195718	MIA
125	05cdefdb-1055-420e-a94b-e3ed364719e1	1	Chris Clemons	C.Clemons	1985-09-15	73	214	Clemson	SAF	30	ACT	0	0	2013-09-14 23:47:59.198422	2013-09-14 23:47:59.198423	MIA
126	09041afd-73c5-409a-bf4d-f4f29ff40cf8	1	Tyson Clabo	T.Clabo	1981-10-17	78	329	Wake Forest	OT	77	ACT	0	0	2013-09-14 23:47:59.201269	2013-09-14 23:47:59.201271	MIA
127	08d772b0-b87e-4345-b66a-ab13b3da262a	1	Marcus Thigpen	M.Thigpen	1986-05-15	69	195	Indiana	RB	34	ACT	0	0	2013-09-14 23:47:59.203221	2013-09-14 23:47:59.203223	MIA
128	efabb355-b184-4e46-8f7e-dd85ca0d43d6	1	Nate Garner	N.Garner	1985-01-18	79	325	Arkansas	OG	75	ACT	0	0	2013-09-14 23:47:59.205174	2013-09-14 23:47:59.205176	MIA
129	76d7615e-8eb5-4761-b6a6-1e895d01baf3	1	Matt Moore	M.Moore	1984-08-09	75	216	Oregon State	QB	8	ACT	0	0	2013-09-14 23:47:59.209787	2013-09-14 23:47:59.209788	MIA
130	76f95387-3bc1-4756-a714-a4b1a93f23ff	1	Reshad Jones	R.Jones	1988-02-25	73	210	Georgia	SAF	20	ACT	0	0	2013-09-14 23:47:59.21185	2013-09-14 23:47:59.211852	MIA
131	b37b5be9-4771-4368-988f-fb936f4fc0ad	1	Mike Wallace	M.Wallace	1986-08-01	72	199	Mississippi	WR	11	ACT	0	0	2013-09-14 23:47:59.213628	2013-09-14 23:47:59.213629	MIA
132	dac5d4e1-1558-4955-9494-b06a451687be	1	Danny Watkins	D.Watkins	1984-11-06	75	310	Baylor	G	62	ACT	0	0	2013-09-14 23:47:59.215828	2013-09-14 23:47:59.21583	MIA
133	04ca4fb9-194e-47fe-8fc8-adb5790a8e78	1	Charles Clay	C.Clay	1989-02-13	75	250	Tulsa	FB	42	ACT	0	0	2013-09-14 23:47:59.218179	2013-09-14 23:47:59.218182	MIA
134	d08da2a3-8296-4038-bb46-ab1feca4bbd4	1	Mike Gillislee	M.Gillislee	1990-11-01	71	208	Florida	RB	23	ACT	0	0	2013-09-14 23:47:59.221447	2013-09-14 23:47:59.221449	MIA
135	9c04a540-cb7c-41dc-8e7c-50b7af29a3a2	1	Dion Sims	D.Sims	1991-02-18	78	262	Michigan State	TE	80	ACT	0	0	2013-09-14 23:47:59.224828	2013-09-14 23:47:59.22483	MIA
136	5f8ecc8b-ea5b-424f-88e7-b47c77bac783	1	Brandon Gibson	B.Gibson	1987-08-13	72	205	Washington State	WR	10	ACT	0	0	2013-09-14 23:47:59.22854	2013-09-14 23:47:59.228542	MIA
137	58b30f9c-384f-4e36-9e79-d4442ce8bb31	1	Richie Incognito	R.Incognito	1983-07-05	75	319	Nebraska	G	68	ACT	0	0	2013-09-14 23:47:59.23175	2013-09-14 23:47:59.231753	MIA
138	49902713-45f2-4853-a508-f944c9808ebb	1	Dustin Keller	D.Keller	1984-09-25	74	250	Purdue	TE	81	IR	0	0	2013-09-14 23:47:59.235243	2013-09-14 23:47:59.235245	MIA
139	cb96a5c5-d178-43c0-b0df-a78c71818060	1	Tyler Clutts	T.Clutts	1984-11-09	74	254	Fresno State	FB	40	ACT	0	0	2013-09-14 23:47:59.238979	2013-09-14 23:47:59.238981	MIA
140	11f099aa-48e9-4f78-a3cc-e0d2730a3872	1	Michael Egnew	M.Egnew	1989-11-01	77	255	Missouri	TE	84	ACT	0	0	2013-09-14 23:47:59.242597	2013-09-14 23:47:59.2426	MIA
141	edbc58f3-86c0-40d9-9e55-25b19df79d4d	1	Daniel Thomas	D.Thomas	1987-10-29	73	233	Kansas State	RB	33	ACT	0	0	2013-09-14 23:47:59.246793	2013-09-14 23:47:59.246795	MIA
142	041c36ad-0d7d-4ed1-8157-95092b3027a4	1	Mike Pouncey	M.Pouncey	1989-07-24	77	303	Florida	C	51	ACT	0	0	2013-09-14 23:47:59.250758	2013-09-14 23:47:59.250761	MIA
143	a212c5d8-67f8-48b9-99be-2c121ee56366	1	Lamar Miller	L.Miller	1991-04-25	70	218	Miami (FL)	RB	26	ACT	0	0	2013-09-14 23:47:59.254148	2013-09-14 23:47:59.25415	MIA
144	22b30e9f-e24b-4fa1-a038-77e8f6d9f2f9	1	Kelcie McCray	K.McCray	1988-09-21	73	200	Arkansas State	SAF	37	ACT	0	0	2013-09-14 23:47:59.257741	2013-09-14 23:47:59.257743	MIA
145	5f6d1cf2-00ea-4316-81db-eb4651465f78	1	Pat Devlin	P.Devlin	1988-04-12	75	225	Delaware	QB	7	ACT	0	0	2013-09-14 23:47:59.261498	2013-09-14 23:47:59.2615	MIA
146	5812204c-6dae-4450-8011-99e0f72864ac	1	Ryan Tannehill	R.Tannehill	1988-07-27	76	222	Texas A&M	QB	17	ACT	0	0	2013-09-14 23:47:59.264864	2013-09-14 23:47:59.264866	MIA
147	a8a0f86e-84c0-4a26-9991-f3d83d6bba98	1	Dallas Thomas	D.Thomas	1989-10-30	77	306	Tennessee	T	70	ACT	0	0	2013-09-14 23:47:59.268516	2013-09-14 23:47:59.268519	MIA
148	25cec667-f621-49da-8edb-666470d63250	1	Jimmy Wilson	J.Wilson	1986-07-30	71	205	Montana	SAF	27	ACT	0	0	2013-09-14 23:47:59.272097	2013-09-14 23:47:59.2721	MIA
149	c4886b28-cb8b-468d-aaff-b0b2ce9aeffa	1	Jonathan Martin	J.Martin	1989-08-19	77	312	Stanford	T	71	ACT	0	0	2013-09-14 23:47:59.275616	2013-09-14 23:47:59.275619	MIA
150	DEF-MIA	1	MIA Defense	MIA		0	0		DEF	0	ACT	0	0	2013-09-14 23:47:59.279317	2013-09-14 23:47:59.279319	MIA
151	ae0de04e-f10b-46ba-b650-2a5c30d48cd9	1	Johnson Bademosi	J.Bademosi	1990-07-23	72	200	Stanford	DB	24	ACT	0	0	2013-09-14 23:47:59.587434	2013-09-14 23:47:59.587437	CLE
152	3d3da3db-ce96-4e59-ba40-7975e69d0dde	1	Keavon Milton	K.Milton		76	293	Louisiana-Monroe	TE	83	ACT	0	0	2013-09-14 23:47:59.59191	2013-09-14 23:47:59.591912	CLE
153	e2ef7b61-cf9d-47ab-927a-77759412ceb1	1	Leon McFadden	L.McFadden	1990-10-26	69	195	San Diego State	DB	29	ACT	0	0	2013-09-14 23:47:59.596289	2013-09-14 23:47:59.596292	CLE
154	39e77504-5ae3-4de9-b07f-0b48fe2830dd	1	Martin Wallace	M.Wallace	1990-04-22	78	305	Temple	OL	64	ACT	0	0	2013-09-14 23:47:59.60044	2013-09-14 23:47:59.600442	CLE
155	8cf11162-ffe7-44ad-b5d6-8eef717b5ac2	1	Mitchell Schwartz	M.Schwartz	1989-06-08	77	320	California	OT	72	ACT	0	0	2013-09-14 23:47:59.60458	2013-09-14 23:47:59.604583	CLE
156	4f0053fc-5559-4551-bd81-dcd1cdf3a9ec	1	Travis Benjamin	T.Benjamin	1989-12-29	70	175	Miami (FL)	WR	80	ACT	0	0	2013-09-14 23:47:59.609191	2013-09-14 23:47:59.609193	CLE
157	fda00e5c-b7df-487a-9a24-5e4087c575e1	1	MarQueis Gray	M.Gray	1989-11-07	76	250	Minnesota	TE	47	ACT	0	0	2013-09-14 23:47:59.612983	2013-09-14 23:47:59.612986	CLE
158	b228c353-bb1f-4ba8-aa6d-d18ecf297259	1	Josh Gordon	J.Gordon	1991-04-13	75	225	Baylor	WR	12	SUS	0	0	2013-09-14 23:47:59.616855	2013-09-14 23:47:59.616858	CLE
159	3bee2864-e024-46ce-a762-427a1820f1a2	1	Jason Pinkston	J.Pinkston	1987-09-05	76	305	Pittsburgh	OL	62	IR	0	0	2013-09-14 23:47:59.620532	2013-09-14 23:47:59.620535	CLE
160	cca4c795-7fa2-479c-9395-dff76a0abb20	1	T.J. Ward	T.Ward	1986-12-12	70	210	Oregon	DB	43	ACT	0	0	2013-09-14 23:47:59.624589	2013-09-14 23:47:59.624592	CLE
161	6400f37f-ca97-4637-867e-1630f1a83b50	1	Oniel Cousins	O.Cousins	1984-06-29	76	315	Texas-El Paso	OL	75	ACT	0	0	2013-09-14 23:47:59.628835	2013-09-14 23:47:59.628837	CLE
162	44257544-0a90-4bca-b759-e589a70cf168	1	Jordan Cameron	J.Cameron	1988-08-08	77	245	USC	TE	84	ACT	0	0	2013-09-14 23:47:59.632828	2013-09-14 23:47:59.63283	CLE
163	020cf3d6-745a-4418-a3dc-7dda7a86d0bf	1	Trent Richardson	T.Richardson	1991-07-10	69	225	Alabama	RB	33	ACT	0	0	2013-09-14 23:47:59.636723	2013-09-14 23:47:59.636726	CLE
164	8fa562d4-d598-4d3a-bb01-d6cbd06f29de	1	Jason Campbell	J.Campbell	1981-12-31	77	230	Auburn	QB	17	ACT	0	0	2013-09-14 23:47:59.640519	2013-09-14 23:47:59.640521	CLE
165	a54b32de-57a0-4ebb-9eca-059d956fee22	1	John Greco	J.Greco	1985-03-24	76	315	Toledo	OL	77	ACT	0	0	2013-09-14 23:47:59.644264	2013-09-14 23:47:59.644266	CLE
166	46217a1a-fda1-441b-b218-8fde5a4cd788	1	Chris Ogbonnaya	C.Ogbonnaya	1986-05-20	72	225	Texas	RB	25	ACT	0	0	2013-09-14 23:47:59.64793	2013-09-14 23:47:59.647933	CLE
167	b3c47050-43ed-47ac-ae2d-77526bdba3a1	1	Tori Gurley	T.Gurley	1987-11-22	76	232	South Carolina	WR	81	ACT	0	0	2013-09-14 23:47:59.651376	2013-09-14 23:47:59.651379	CLE
168	b25ba2bd-80bd-4295-9034-cf9242fb207b	1	Dion Lewis	D.Lewis	1990-09-27	68	195	Pittsburgh	RB	28	IR	0	0	2013-09-14 23:47:59.655026	2013-09-14 23:47:59.655029	CLE
169	5fc8485a-e32a-451b-a16f-5d6a655b7e14	1	Billy Cundiff	B.Cundiff	1980-03-30	73	212	Drake	K	8	ACT	0	0	2013-09-14 23:47:59.658585	2013-09-14 23:47:59.658587	CLE
170	26e8d107-3fe6-4d28-b3a0-5f2e352112b6	1	Chris Faulk	C.Faulk	1990-01-21	78	330	Louisiana State	OL	70	NON	0	0	2013-09-14 23:47:59.662327	2013-09-14 23:47:59.662329	CLE
171	6a1b2504-153c-441d-ba17-f78457d58b9c	1	Shawn Lauvao	S.Lauvao	1987-10-26	75	315	Arizona State	OL	66	ACT	0	0	2013-09-14 23:47:59.666064	2013-09-14 23:47:59.666066	CLE
172	01291a8d-d97c-4d88-b497-b5ad4b72f626	1	Brandon Weeden	B.Weeden	1983-10-14	75	220	Oklahoma State	QB	3	ACT	0	0	2013-09-14 23:47:59.669613	2013-09-14 23:47:59.669616	CLE
173	cf15d191-0c05-46ea-811f-4d990a167805	1	Greg Little	G.Little	1989-05-30	74	220	North Carolina	WR	18	ACT	0	0	2013-09-14 23:47:59.676739	2013-09-14 23:47:59.676742	CLE
174	ae013e04-53b5-4abd-823d-c9dda4720ddf	1	Garrett Gilkey	G.Gilkey	1990-07-09	78	320	Chadron State	T	65	ACT	0	0	2013-09-14 23:47:59.680645	2013-09-14 23:47:59.680648	CLE
175	639ff90f-285c-44a7-ba8d-6a47d0ecff71	1	Buster Skrine	B.Skrine	1989-04-26	69	185	Tennessee-Chattanooga	DB	22	ACT	0	0	2013-09-14 23:47:59.684182	2013-09-14 23:47:59.684184	CLE
176	3e97f3b8-3b42-4854-9116-e311c2bd04e9	1	Josh Aubrey	J.Aubrey	1991-04-09	70	200	Stephen F. Austin	DB	37	ACT	0	0	2013-09-14 23:47:59.687762	2013-09-14 23:47:59.687764	CLE
177	d5efd828-7339-43a7-ad7e-6f936dbbabb2	1	Tashaun Gipson	T.Gipson	1990-08-07	71	205	Wyoming	DB	39	ACT	0	0	2013-09-14 23:47:59.691309	2013-09-14 23:47:59.691311	CLE
178	42f540da-79c6-4b7a-beb6-cd1e6fccf8c5	1	Chris Owens	C.Owens	1986-12-01	69	180	San Jose State	DB	21	ACT	0	0	2013-09-14 23:47:59.695136	2013-09-14 23:47:59.695138	CLE
179	878f2957-283a-457f-b266-c6e9cf9d99fd	1	Patrick Lewis	P.Lewis	1991-01-30	73	311	Texas A&M	C	60	ACT	0	0	2013-09-14 23:47:59.698873	2013-09-14 23:47:59.698875	CLE
180	e0976f2f-b5f4-4c4d-a251-a2847fc4acfc	1	Davone Bess	D.Bess	1985-09-13	70	190	Hawaii	WR	15	ACT	0	0	2013-09-14 23:47:59.703213	2013-09-14 23:47:59.703215	CLE
181	55db1016-2acd-4e21-a1de-fe4b7e334565	1	Rashad Butler	R.Butler	1983-02-10	76	310	Miami (FL)	OT	79	ACT	0	0	2013-09-14 23:47:59.706701	2013-09-14 23:47:59.706703	CLE
182	318b9670-1dde-4e65-a92f-65df6e80824d	1	Joe Thomas	J.Thomas	1984-12-04	78	312	Wisconsin	OT	73	ACT	0	0	2013-09-14 23:47:59.710531	2013-09-14 23:47:59.710533	CLE
183	3ec2ad5e-f4e0-474a-98a9-0bde4ff5aab9	1	Joe Haden	J.Haden	1989-04-14	71	190	Florida	DB	23	ACT	0	0	2013-09-14 23:47:59.714346	2013-09-14 23:47:59.714348	CLE
184	58c7f4a0-510f-4f7b-b86a-85723dc858ec	1	Josh Cooper	J.Cooper	1989-01-08	70	190	Oklahoma State	WR	88	ACT	0	0	2013-09-14 23:47:59.718247	2013-09-14 23:47:59.718251	CLE
185	c5da1132-2198-4ad0-af83-89642b424574	1	Gary Barnidge	G.Barnidge	1985-09-22	77	250	Louisville	TE	82	ACT	0	0	2013-09-14 23:47:59.72186	2013-09-14 23:47:59.721862	CLE
186	af4ba620-2f00-4b00-9111-7897f2b1cde8	1	Brian Hoyer	B.Hoyer	1985-10-13	74	215	Michigan State	QB	6	ACT	0	0	2013-09-14 23:47:59.725357	2013-09-14 23:47:59.72536	CLE
187	56185079-5d0a-416d-9dd8-932a58bc9df7	1	Bobby Rainey	B.Rainey	1987-10-16	68	212	Western Kentucky	RB	34	ACT	0	0	2013-09-14 23:47:59.729154	2013-09-14 23:47:59.729156	CLE
188	7cfc5f12-e344-4a41-8f54-52a5c2bbd52d	1	Alex Mack	A.Mack	1985-11-19	76	311	California	OL	55	ACT	0	0	2013-09-14 23:47:59.732725	2013-09-14 23:47:59.732728	CLE
189	6d099c7c-4a42-4952-a116-537189834b4d	1	Montario Hardesty	M.Hardesty	1987-02-01	72	225	Tennessee	RB	20	IR	0	0	2013-09-14 23:47:59.73644	2013-09-14 23:47:59.736442	CLE
190	DEF-CLE	1	CLE Defense	CLE		0	0		DEF	0	ACT	0	0	2013-09-14 23:47:59.739941	2013-09-14 23:47:59.739943	CLE
191	f1ce3e7d-6afc-4db4-94f0-475bd63507b3	1	Andrew Whitworth	A.Whitworth	1981-12-12	79	335	LSU	OT	77	ACT	0	0	2013-09-14 23:48:00.016782	2013-09-14 23:48:00.016786	CIN
192	73e133bf-d3f7-4fda-bd25-2fde66cb8ee1	1	Josh Johnson	J.Johnson	1986-05-15	75	205	San Diego	QB	8	ACT	0	0	2013-09-14 23:48:00.021202	2013-09-14 23:48:00.021205	CIN
193	1a2fbc23-e6db-4d2f-a152-2c774341b7c4	1	Marvin Jones	M.Jones	1990-03-12	74	195	California	WR	82	ACT	0	0	2013-09-14 23:48:00.025144	2013-09-14 23:48:00.025148	CIN
194	f1d063d5-bbcb-43fe-869b-88c26a34523b	1	Dennis Roland	D.Roland	1983-03-10	81	322	Georgia	OT	74	ACT	0	0	2013-09-14 23:48:00.029542	2013-09-14 23:48:00.029544	CIN
195	a877e5f6-37c5-4c7c-9f23-9e3a9f9d0d84	1	Clint Boling	C.Boling	1989-05-09	77	311	Georgia	G	65	ACT	0	0	2013-09-14 23:48:00.033048	2013-09-14 23:48:00.033051	CIN
196	29c7af89-652f-439b-b916-dd8f44d70a22	1	Zac Robinson	Z.Robinson	1986-09-29	75	208	Oklahoma State	QB	5	PUP	0	0	2013-09-14 23:48:00.037016	2013-09-14 23:48:00.037019	CIN
197	17a056be-39c0-4913-bacf-1663f3ac4a56	1	Andre Smith	A.Smith	1987-01-25	76	335	Alabama	OT	71	ACT	0	0	2013-09-14 23:48:00.04063	2013-09-14 23:48:00.040632	CIN
198	24cf6148-f0af-4103-a215-e06956764953	1	Giovani Bernard	G.Bernard	1991-11-22	69	208	North Carolina	RB	25	ACT	0	0	2013-09-14 23:48:00.044627	2013-09-14 23:48:00.044631	CIN
199	7f73e63f-6875-4883-9113-baee8fb7bd5c	1	BenJarvus Green-Ellis	B.Green-Ellis	1985-07-02	71	220	Mississippi	RB	42	ACT	0	0	2013-09-14 23:48:00.049207	2013-09-14 23:48:00.04921	CIN
200	e017e12b-07a7-4a35-b837-2faa9ffe3ce8	1	Mike Nugent	M.Nugent	1982-03-02	70	190	Ohio State	K	2	ACT	0	0	2013-09-14 23:48:00.053301	2013-09-14 23:48:00.053304	CIN
201	9ad039f5-fe77-4fa4-8342-e9022ab7d629	1	Kyle Cook	K.Cook	1983-07-25	75	310	Michigan State	C	64	ACT	0	0	2013-09-14 23:48:00.057029	2013-09-14 23:48:00.057031	CIN
202	1726a359-9444-4761-a1f2-cb35ee6fa60e	1	Mohamed Sanu	M.Sanu	1989-08-22	74	210	Rutgers	WR	12	ACT	0	0	2013-09-14 23:48:00.060712	2013-09-14 23:48:00.060714	CIN
203	86d12627-9ee1-42a5-9974-13cea2cb1fe7	1	Mike Pollak	M.Pollak	1985-02-16	75	300	Arizona State	G	67	ACT	0	0	2013-09-14 23:48:00.06453	2013-09-14 23:48:00.064534	CIN
204	4a99b4bf-e03e-4253-8b9b-c070ef796daf	1	Ryan Whalen	R.Whalen	1989-07-26	73	202	Stanford	WR	88	ACT	0	0	2013-09-14 23:48:00.06851	2013-09-14 23:48:00.068512	CIN
205	b44773b9-af17-4d6c-a453-132e20849712	1	Jermaine Gresham	J.Gresham	1988-06-16	77	260	Oklahoma	TE	84	ACT	0	0	2013-09-14 23:48:00.072309	2013-09-14 23:48:00.072311	CIN
206	9029830c-1394-494f-a92c-e192697913cf	1	Reggie Nelson	R.Nelson	1983-09-21	71	210	Florida	SAF	20	ACT	0	0	2013-09-14 23:48:00.076268	2013-09-14 23:48:00.07627	CIN
207	2aa0f66e-52c1-4606-a1ea-242c61c04534	1	Chris Pressley	C.Pressley	1986-08-08	71	256	Wisconsin	FB	36	PUP	0	0	2013-09-14 23:48:00.080088	2013-09-14 23:48:00.08009	CIN
208	1a316ec7-47cc-4cc4-b624-bbbf276da7b9	1	Cedric Peerman	C.Peerman	1986-10-10	70	211	Virginia	RB	30	ACT	0	0	2013-09-14 23:48:00.083898	2013-09-14 23:48:00.083901	CIN
209	14ecf9dd-3a77-4847-8e62-407cd1182f1c	1	Tyler Eifert	T.Eifert	1990-09-08	78	251	Notre Dame	TE	85	ACT	0	0	2013-09-14 23:48:00.087507	2013-09-14 23:48:00.08751	CIN
210	c9e9bbc5-2aeb-4f72-9b7c-1a688fb235fb	1	Shawn Williams	S.Williams	1991-05-13	72	213	Georgia	SS	40	ACT	0	0	2013-09-14 23:48:00.09145	2013-09-14 23:48:00.091452	CIN
211	f6cbde33-a78b-49bf-a41f-112caba8e556	1	Dane Sanzenbacher	D.Sanzenbacher	1988-10-13	71	184	Ohio State	WR	11	ACT	0	0	2013-09-14 23:48:00.095271	2013-09-14 23:48:00.095273	CIN
212	2b9494e4-953a-4aac-afe7-edd2d7be27da	1	George Iloka	G.Iloka	1990-03-31	76	217	Boise State	SAF	43	ACT	0	0	2013-09-14 23:48:00.0991	2013-09-14 23:48:00.099102	CIN
213	1ab63530-c678-4fec-86a5-b8b509abf7b7	1	Trevor Robinson	T.Robinson	1990-05-16	77	300	Notre Dame	G	66	ACT	0	0	2013-09-14 23:48:00.102966	2013-09-14 23:48:00.102969	CIN
214	b6325c85-c313-4cfb-a299-9884d5e9e389	1	Orson Charles	O.Charles	1991-01-27	75	245	Georgia	TE	80	ACT	0	0	2013-09-14 23:48:00.106823	2013-09-14 23:48:00.106825	CIN
215	bd8052bd-0898-430b-99c9-2529e895ae79	1	Rex Burkhead	R.Burkhead	1990-07-02	70	218	Nebraska	RB	33	ACT	0	0	2013-09-14 23:48:00.11058	2013-09-14 23:48:00.110583	CIN
216	3289f9ce-e1d1-40ed-9d3f-242a1712c586	1	Brandon Tate	B.Tate	1987-10-05	73	195	North Carolina	WR	19	ACT	0	0	2013-09-14 23:48:00.11446	2013-09-14 23:48:00.114464	CIN
217	d2a0e5af-3850-4f16-8e40-a0b1d15c2ce1	1	Andy Dalton	A.Dalton	1987-10-29	74	220	Texas Christian	QB	14	ACT	0	0	2013-09-14 23:48:00.11826	2013-09-14 23:48:00.118262	CIN
218	9e70c666-9371-4659-b075-2d52e303ef4a	1	Jeromy Miles	J.Miles	1987-07-20	74	214	Massachusetts	SAF	45	ACT	0	0	2013-09-14 23:48:00.125842	2013-09-14 23:48:00.125844	CIN
219	00df8f1d-199c-43a1-a929-849e9c844c8c	1	Anthony Collins	A.Collins	1985-11-02	77	315	Kansas	OT	73	ACT	0	0	2013-09-14 23:48:00.129261	2013-09-14 23:48:00.129264	CIN
220	b3e1206d-38e3-4ad3-be9e-8bf3daa62cad	1	Kevin Zeitler	K.Zeitler	1990-03-08	76	315	Wisconsin	G	68	ACT	0	0	2013-09-14 23:48:00.132709	2013-09-14 23:48:00.132711	CIN
221	c9701373-23f6-4058-9189-8d9c085f3c49	1	A.J. Green	A.Green	1988-07-31	76	207	Georgia	WR	18	ACT	0	0	2013-09-14 23:48:00.136527	2013-09-14 23:48:00.136529	CIN
222	20b3705b-5cc4-4759-9315-d4230b4a7872	1	Tanner Hawkinson	T.Hawkinson		77	300	Kansas	T	72	ACT	0	0	2013-09-14 23:48:00.140517	2013-09-14 23:48:00.140519	CIN
223	049632f6-5a72-473f-9dd9-652a78eeb077	1	Taylor Mays	T.Mays	1988-02-07	75	220	USC	SAF	26	ACT	0	0	2013-09-14 23:48:00.144715	2013-09-14 23:48:00.144719	CIN
224	64c70db3-74ff-4fe5-a136-74c5f394447f	1	Bernard Scott	B.Scott	1984-02-10	70	195	Abilene Christian	RB	28	PUP	0	0	2013-09-14 23:48:00.148583	2013-09-14 23:48:00.148585	CIN
225	308cde80-c1e5-46a8-8df4-19a191b49c95	1	Andrew Hawkins	A.Hawkins	1986-03-10	67	180	Toledo	WR	16	IR	0	0	2013-09-14 23:48:00.152539	2013-09-14 23:48:00.152541	CIN
226	55a668a4-8ce1-464b-a686-47eac2e9b9a5	1	Alex Smith	A.Smith	1982-05-22	76	250	Stanford	TE	81	ACT	0	0	2013-09-14 23:48:00.156151	2013-09-14 23:48:00.156153	CIN
227	DEF-CIN	1	CIN Defense	CIN		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:00.160161	2013-09-14 23:48:00.160165	CIN
228	c5dfc54e-fd64-468f-81a8-073918776412	1	Bernard Pierce	B.Pierce	1990-05-10	72	218	Temple	RB	30	ACT	0	0	2013-09-14 23:48:00.423779	2013-09-14 23:48:00.423781	BAL
229	46bb9a85-523c-4530-95c3-2c2a9737e65f	1	Ed Dickson	E.Dickson	1987-07-25	76	255	Oregon	TE	84	ACT	0	0	2013-09-14 23:48:00.427011	2013-09-14 23:48:00.427013	BAL
230	36e8d27f-0dae-42a9-9d57-f34fbd325a6f	1	Tandon Doss	T.Doss	1989-09-22	74	205	Indiana	WR	17	ACT	0	0	2013-09-14 23:48:00.430114	2013-09-14 23:48:00.430116	BAL
231	7363ca26-1f1d-4706-9b6a-67e8e969eaea	1	Billy Bajema	B.Bajema	1982-10-31	76	259	Oklahoma State	TE	86	ACT	0	0	2013-09-14 23:48:00.432962	2013-09-14 23:48:00.432963	BAL
232	3d6d3bab-67d8-4c08-ac5a-0cd80405e3c6	1	Brynden Trawick	B.Trawick	1989-10-23	74	215	Troy	SAF	28	ACT	0	0	2013-09-14 23:48:00.435551	2013-09-14 23:48:00.435553	BAL
233	7f3ef024-eb34-46af-8b9e-544cdf09378f	1	Tyrod Taylor	T.Taylor	1989-08-03	73	215	Virginia Tech	QB	2	ACT	0	0	2013-09-14 23:48:00.43798	2013-09-14 23:48:00.437982	BAL
234	5b4b39d4-97e1-4a97-a1e5-764ec6d3bedd	1	Bryant McKinnie	B.McKinnie	1979-09-23	80	360	Miami (FL)	OT	78	ACT	0	0	2013-09-14 23:48:00.440424	2013-09-14 23:48:00.440425	BAL
235	bcce08ec-736e-40c1-bb8d-ebe2d489f331	1	Shaun Draughn	S.Draughn	1987-12-07	72	205	North Carolina	RB	38	ACT	0	0	2013-09-14 23:48:00.442904	2013-09-14 23:48:00.442905	BAL
236	ffec1b11-6b1b-482d-86f0-3bf4f6391dbf	1	Marlon Brown	M.Brown	1991-04-22	77	205	Georgia	WR	14	ACT	0	0	2013-09-14 23:48:00.445275	2013-09-14 23:48:00.445276	BAL
237	50287cd3-afea-47f4-aa56-98a82aa87cf0	1	Ryan Jensen	R.Jensen	1991-05-27	75	304	Colorado State-Pueblo	C	77	ACT	0	0	2013-09-14 23:48:00.447722	2013-09-14 23:48:00.447723	BAL
238	ce4d7d70-307f-4093-bf54-432b8b405eb4	1	Jacoby Jones	J.Jones	1984-07-11	74	212	Lane	WR	12	ACT	0	0	2013-09-14 23:48:00.450706	2013-09-14 23:48:00.450707	BAL
239	c323cdb9-74bc-4d68-9358-609f80eedbb7	1	Deonte Thompson	D.Thompson	1989-02-14	72	200	Florida	WR	83	ACT	0	0	2013-09-14 23:48:00.453312	2013-09-14 23:48:00.453314	BAL
240	f7163bae-d4da-4d38-847e-e0315605b9d0	1	A.Q. Shipley	A.Shipley	1986-05-22	73	309	Penn State	C	68	ACT	0	0	2013-09-14 23:48:00.455572	2013-09-14 23:48:00.455573	BAL
241	4be70f75-f978-4e90-92fd-70927c672931	1	Matt Elam	M.Elam	1991-09-21	70	206	Florida	FS	26	ACT	0	0	2013-09-14 23:48:00.457971	2013-09-14 23:48:00.457973	BAL
242	45fe5280-b366-4c8a-8f2e-99fa5a4ff631	1	Kelechi Osemele	K.Osemele	1989-06-24	77	333	Iowa State	T	72	ACT	0	0	2013-09-14 23:48:00.460149	2013-09-14 23:48:00.46015	BAL
243	cef0560a-22e8-4049-a48f-496328550aa2	1	Michael Huff	M.Huff	1983-03-06	72	211	Texas	SAF	29	ACT	0	0	2013-09-14 23:48:00.462348	2013-09-14 23:48:00.462349	BAL
244	2dff7d82-426e-42d6-8c7c-170ad3a24ad6	1	Rick Wagner	R.Wagner	1989-10-21	78	308	Wisconsin	T	71	ACT	0	0	2013-09-14 23:48:00.464567	2013-09-14 23:48:00.464568	BAL
245	b7b58f9b-49c2-4d68-a331-ed66e901bb40	1	Dallas Clark	D.Clark	1979-06-12	75	252	Iowa	TE	87	ACT	0	0	2013-09-14 23:48:00.467133	2013-09-14 23:48:00.467134	BAL
246	64797df2-efd3-4b27-86ee-1d48f7edb09f	1	Joe Flacco	J.Flacco	1985-01-16	78	245	Delaware	QB	5	ACT	0	0	2013-09-14 23:48:00.469564	2013-09-14 23:48:00.469566	BAL
247	7e3c0631-1bff-49af-b6bc-9c66c59a579d	1	Gino Gradkowski	G.Gradkowski	1988-11-05	75	300	Delaware	G	66	ACT	0	0	2013-09-14 23:48:00.471833	2013-09-14 23:48:00.471834	BAL
248	bf46fb03-b257-413f-af21-6823e00c81b5	1	James Ihedigbo	J.Ihedigbo	1983-12-03	73	214	Massachusetts	SS	32	ACT	0	0	2013-09-14 23:48:00.474055	2013-09-14 23:48:00.474057	BAL
249	67da5b5c-0db9-4fbc-b98d-7eb8e97b69f6	1	Kyle Juszczyk	K.Juszczyk	1991-04-23	73	248	Harvard	FB	40	ACT	0	0	2013-09-14 23:48:00.476354	2013-09-14 23:48:00.476356	BAL
250	f01c7712-3887-458e-8351-1c3e31c67091	1	Christian Thompson	C.Thompson	1990-06-04	72	211	South Carolina State	SAF	33	SUS	0	0	2013-09-14 23:48:00.478542	2013-09-14 23:48:00.478543	BAL
251	20a0bad2-d530-4ff4-a2df-5c0a21a1f5db	1	Justin Tucker	J.Tucker	1989-11-21	72	180	Texas	K	9	ACT	0	0	2013-09-14 23:48:00.480702	2013-09-14 23:48:00.480704	BAL
252	29c9a73e-f66f-437d-8dce-3cbc76aee835	1	Brandon Stokley	B.Stokley	1976-06-23	72	194	Louisiana-Lafayette	WR	80	ACT	0	0	2013-09-14 23:48:00.483177	2013-09-14 23:48:00.483179	BAL
253	fafd2927-7e17-4e85-afa2-aa2c019229ed	1	Marshal Yanda	M.Yanda	1984-09-15	75	315	Iowa	G	73	ACT	0	0	2013-09-14 23:48:00.485447	2013-09-14 23:48:00.485449	BAL
254	4a6ed95c-3cc6-4914-97e4-da2171d7c93b	1	Vonta Leach	V.Leach	1981-11-06	72	260	East Carolina	FB	44	ACT	0	0	2013-09-14 23:48:00.487694	2013-09-14 23:48:00.487695	BAL
255	e2577abf-7f24-4987-89f5-51676c39c2f6	1	Dennis Pitta	D.Pitta	1985-06-29	76	245	Brigham Young	TE	88	IR	0	0	2013-09-14 23:48:00.490107	2013-09-14 23:48:00.490108	BAL
256	712617bb-3379-46e9-86c6-af1c098e0a72	1	Ray Rice	R.Rice	1987-01-22	68	212	Rutgers	RB	27	ACT	0	0	2013-09-14 23:48:00.492361	2013-09-14 23:48:00.492362	BAL
257	d820c4d6-c312-4318-b528-65fe1b63dfaf	1	Aaron Mellette	A.Mellette	1989-12-28	74	217	Elon	WR	13	IR	0	0	2013-09-14 23:48:00.494629	2013-09-14 23:48:00.494632	BAL
258	98a87efc-1bdd-49fd-8dd1-d03d41e6e374	1	Michael Oher	M.Oher	1986-05-28	76	315	Mississippi	OT	74	ACT	0	0	2013-09-14 23:48:00.496944	2013-09-14 23:48:00.496946	BAL
259	04e8ea8f-8424-4196-a0fd-7dff3740c734	1	Anthony Levine	A.Levine	1987-03-27	71	199	Tennessee State	SAF	41	ACT	0	0	2013-09-14 23:48:00.499268	2013-09-14 23:48:00.499269	BAL
260	a735765c-3ca8-4557-b06e-a30fd415982c	1	Torrey Smith	T.Smith	1989-01-26	72	205	Maryland	WR	82	ACT	0	0	2013-09-14 23:48:00.502097	2013-09-14 23:48:00.502099	BAL
261	a135ab63-8b05-48b0-b0df-98b67c27e10d	1	Jah Reid	J.Reid	1988-07-21	79	335	Central Florida	OT	76	ACT	0	0	2013-09-14 23:48:00.505592	2013-09-14 23:48:00.505595	BAL
262	DEF-BAL	1	BAL Defense	BAL		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:00.512961	2013-09-14 23:48:00.512964	BAL
263	adeb92c4-bbf2-4cfa-8c76-55b1d30d1c1b	1	Cody Wallace	C.Wallace	1984-11-26	76	300	Texas A&M	C	72	ACT	0	0	2013-09-14 23:48:00.79644	2013-09-14 23:48:00.796442	PIT
264	8930ffc2-369e-47eb-ac09-906d8bf8506d	1	Derek Moye	D.Moye	1988-08-12	77	210	Penn State	WR	14	ACT	0	0	2013-09-14 23:48:00.799725	2013-09-14 23:48:00.799726	PIT
265	0ee7e81d-478c-4094-950f-f1478cb9c55c	1	Will Johnson	W.Johnson	1989-11-14	74	238	West Virginia	RB	46	ACT	0	0	2013-09-14 23:48:00.802136	2013-09-14 23:48:00.802137	PIT
266	ecb0a97f-f70b-4ea7-a741-e1d4e764edfb	1	Shamarko Thomas	S.Thomas		69	217	Syracuse	SS	29	ACT	0	0	2013-09-14 23:48:00.80512	2013-09-14 23:48:00.805122	PIT
267	a69e4ff7-5c39-4e2e-a90c-f4fafb749147	1	Plaxico Burress	P.Burress	1977-08-12	77	232	Michigan State	WR	80	IR	0	0	2013-09-14 23:48:00.807822	2013-09-14 23:48:00.807824	PIT
268	4e8927ad-8a0d-4057-a340-e433ccdac5c9	1	LaRod Stephens-Howling	L.Stephens-Howling	1987-04-26	67	185	Pittsburgh	RB	34	IR	0	0	2013-09-14 23:48:00.810356	2013-09-14 23:48:00.810358	PIT
269	21324436-47e6-4e7e-9f57-6e343cf5aa07	1	Shayne Graham	S.Graham	1977-12-09	72	210	Virginia Tech	K	17	ACT	0	0	2013-09-14 23:48:00.812752	2013-09-14 23:48:00.812755	PIT
270	d4dd3d0b-5023-415d-ad15-94f294c561b1	1	Landry Jones	L.Jones	1989-04-04	75	221	Oklahoma	QB	3	ACT	0	0	2013-09-14 23:48:00.81549	2013-09-14 23:48:00.815492	PIT
271	16e33176-b73e-49b7-b0aa-c405b47a706e	1	Antonio Brown	A.Brown	1988-07-10	70	186	Central Michigan	WR	84	ACT	0	0	2013-09-14 23:48:00.81778	2013-09-14 23:48:00.817781	PIT
272	12815867-476b-4c85-a2eb-6a6a54cf563e	1	Bruce Gradkowski	B.Gradkowski	1983-01-27	73	220	Toledo	QB	5	ACT	0	0	2013-09-14 23:48:00.819995	2013-09-14 23:48:00.819997	PIT
273	7735c02a-ee75-447c-86e6-6c2168500050	1	Le'Veon Bell	L.Bell	1992-02-18	73	244	Michigan State	RB	26	ACT	0	0	2013-09-14 23:48:00.822245	2013-09-14 23:48:00.822247	PIT
274	d96246d7-aa2c-4d05-9c58-8d6bc5e20cdf	1	Kelvin Beachum	K.Beachum	1989-06-08	75	303	Southern Methodist	G	68	ACT	0	0	2013-09-14 23:48:00.826405	2013-09-14 23:48:00.826407	PIT
275	1290b569-2481-41fc-a4bb-bcc2317d1399	1	Michael Palmer	M.Palmer	1988-01-18	77	252	Clemson	TE	82	ACT	0	0	2013-09-14 23:48:00.830268	2013-09-14 23:48:00.83027	PIT
276	ea357add-1a41-4a8b-8f34-bbfade7f4d98	1	Ben Roethlisberger	B.Roethlisberger	1982-03-02	77	241	Miami (OH)	QB	7	ACT	0	0	2013-09-14 23:48:00.83456	2013-09-14 23:48:00.834563	PIT
277	ad9ee614-b181-41ba-b6ba-50ef9fe9df55	1	Justin Cheadle	J.Cheadle	1989-03-11	75	305	California	OL	72	IR	0	0	2013-09-14 23:48:00.838048	2013-09-14 23:48:00.838051	PIT
278	d2875f6b-4c40-46da-858b-9e56b3420c49	1	David Paulson	D.Paulson	1989-02-22	76	246	Oregon	TE	81	ACT	0	0	2013-09-14 23:48:00.842184	2013-09-14 23:48:00.842187	PIT
279	f0085214-6339-4843-a6c9-8ae118422284	1	Felix Jones	F.Jones	1987-05-08	70	215	Arkansas	RB	23	ACT	0	0	2013-09-14 23:48:00.846185	2013-09-14 23:48:00.846188	PIT
280	fd4e8681-f2f4-47c7-b954-a72be9b1ca00	1	Emmanuel Sanders	E.Sanders	1987-03-17	71	180	Southern Methodist	WR	88	ACT	0	0	2013-09-14 23:48:00.849898	2013-09-14 23:48:00.8499	PIT
281	acb6e6a0-6ebc-481c-a8f5-4114230ffa16	1	Mike Adams	M.Adams	1990-03-10	79	323	Ohio State	T	76	ACT	0	0	2013-09-14 23:48:00.85362	2013-09-14 23:48:00.853623	PIT
282	c6ac349a-b159-449c-80c7-f9b6138b48af	1	Heath Miller	H.Miller	1982-10-22	77	256	Virginia	TE	83	ACT	0	0	2013-09-14 23:48:00.857708	2013-09-14 23:48:00.85771	PIT
283	169418c0-09b8-4807-b696-d98de0cfa690	1	Fernando Velasco	F.Velasco	1985-02-22	76	312	Georgia	C	61	ACT	0	0	2013-09-14 23:48:00.862014	2013-09-14 23:48:00.862016	PIT
284	a2579c70-73d2-477a-b7f6-4ff09aa75364	1	David Johnson	D.Johnson	1987-08-26	74	260	Arkansas State	TE	85	ACT	0	0	2013-09-14 23:48:00.866058	2013-09-14 23:48:00.86606	PIT
285	e15c91fe-34cb-484d-9d0d-335a333f626f	1	Da'Mon Cromartie-Smith	D.Cromartie-Smith	1987-02-17	74	203	Texas-El Paso	SAF	42	ACT	0	0	2013-09-14 23:48:00.870056	2013-09-14 23:48:00.870058	PIT
286	c291367c-c4e6-4a2a-8ee4-e3e2e4ccbbb6	1	Jonathan Dwyer	J.Dwyer	1989-07-26	71	229	Georgia Tech	RB	27	ACT	0	0	2013-09-14 23:48:00.873885	2013-09-14 23:48:00.873887	PIT
287	cb332cbe-4490-48c6-9a21-046475206e07	1	Marcus Gilbert	M.Gilbert	1988-02-15	78	330	Florida	T	77	ACT	0	0	2013-09-14 23:48:00.87798	2013-09-14 23:48:00.877982	PIT
288	21476f5d-51db-444e-afdd-f6b144de16dc	1	Guy Whimper	G.Whimper	1983-05-21	77	315	East Carolina	OT	78	ACT	0	0	2013-09-14 23:48:00.881412	2013-09-14 23:48:00.881416	PIT
289	a2536b67-fdd3-4806-b801-4ba1d190afa9	1	Ryan Clark	R.Clark	1979-10-12	71	205	LSU	FS	25	ACT	0	0	2013-09-14 23:48:00.885237	2013-09-14 23:48:00.88524	PIT
290	77f923a3-67cd-4957-931d-b3865bdd3f6e	1	Robert Golden	R.Golden	1990-09-13	71	202	Arizona	SAF	21	ACT	0	0	2013-09-14 23:48:00.888933	2013-09-14 23:48:00.888937	PIT
291	f9036897-99d5-4d9a-8965-0c7e0f9e43bd	1	Markus Wheaton	M.Wheaton	1991-02-07	71	182	Oregon State	WR	11	ACT	0	0	2013-09-14 23:48:00.892829	2013-09-14 23:48:00.892831	PIT
292	30b70aad-fc6c-4c35-a375-afc10efa6a43	1	Troy Polamalu	T.Polamalu	1981-04-19	70	207	USC	SS	43	ACT	0	0	2013-09-14 23:48:00.896606	2013-09-14 23:48:00.896608	PIT
293	f7e3c1cb-6ec1-45fa-ad64-6b01957c34b1	1	David Decastro	D.Decastro	1990-01-11	77	316	Stanford	G	66	ACT	0	0	2013-09-14 23:48:00.900417	2013-09-14 23:48:00.900419	PIT
294	ecba564a-738e-431c-9407-f3cc047d1fbe	1	Curtis Brown	C.Brown	1988-09-24	72	185	Texas	DB	31	ACT	0	0	2013-09-14 23:48:00.904168	2013-09-14 23:48:00.904171	PIT
295	d1a06132-76d1-4654-af3e-633c5f07a4b4	1	Shaun Suisham	S.Suisham	1981-12-29	72	200	Bowling Green State	K	6	ACT	0	0	2013-09-14 23:48:00.907754	2013-09-14 23:48:00.907756	PIT
296	6c2c4e4c-82f0-46e2-bcfb-3ed5f452266b	1	Maurkice Pouncey	M.Pouncey	1989-07-24	76	304	Florida	C	53	IR	0	0	2013-09-14 23:48:00.91166	2013-09-14 23:48:00.911662	PIT
297	dc99b6a9-4825-40c1-858d-252a4061c289	1	Ramon Foster	R.Foster	1986-01-07	78	325	Tennessee	G	73	ACT	0	0	2013-09-14 23:48:00.915829	2013-09-14 23:48:00.915832	PIT
298	dc2b3e27-0bc1-4ea7-b80e-f9ef81cab2c9	1	Jerricho Cotchery	J.Cotchery	1982-06-16	73	200	North Carolina State	WR	89	ACT	0	0	2013-09-14 23:48:00.919922	2013-09-14 23:48:00.919925	PIT
299	1cf82686-f3aa-4f59-9615-64d02f4819a5	1	Nik Embernate	N.Embernate	1990-11-03	76	304	San Diego State	G	67	IR	0	0	2013-09-14 23:48:00.924263	2013-09-14 23:48:00.924265	PIT
300	58f0ece9-38e8-49b4-82e2-aec3ff352728	1	Isaac Redman	I.Redman	1984-11-10	72	230	Bowie State	RB	33	ACT	0	0	2013-09-14 23:48:00.928021	2013-09-14 23:48:00.928024	PIT
301	0a40642d-f976-4077-9494-c627e28571de	1	Matt Spaeth	M.Spaeth	1983-11-24	79	270	Minnesota	TE	87	IR	0	0	2013-09-14 23:48:00.931681	2013-09-14 23:48:00.931683	PIT
302	DEF-PIT	1	PIT Defense	PIT		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:00.935897	2013-09-14 23:48:00.935899	PIT
303	1f09583f-dcc1-43e8-a7fc-f063d2c96508	1	Matt Schaub	M.Schaub	1981-06-25	77	235	Virginia	QB	8	ACT	0	0	2013-09-14 23:48:01.244553	2013-09-14 23:48:01.244556	HOU
304	20170818-32ab-4892-987e-ea75efcd8c4f	1	T.J. Yates	T.Yates	1987-05-28	76	217	North Carolina	QB	13	ACT	0	0	2013-09-14 23:48:01.246959	2013-09-14 23:48:01.246959	HOU
305	044d5384-6a9f-4843-ad3e-909d362381f6	1	Derek Newton	D.Newton	1987-11-16	78	313	Arkansas State	T	75	ACT	0	0	2013-09-14 23:48:01.248185	2013-09-14 23:48:01.248186	HOU
306	5486420b-b40c-4e7c-ab47-9d70b1673c3b	1	D.J. Swearinger	D.Swearinger		70	208	South Carolina	SS	36	ACT	0	0	2013-09-14 23:48:01.250387	2013-09-14 23:48:01.250391	HOU
307	d89d2aef-c383-4ddf-bed8-3761aed35b10	1	Arian Foster	A.Foster	1986-08-24	73	234	Tennessee	RB	23	ACT	0	0	2013-09-14 23:48:01.25311	2013-09-14 23:48:01.253111	HOU
308	9dd8978c-53cc-4bd2-af51-c272618b800a	1	Lestar Jean	L.Jean	1988-02-05	75	202	Florida Atlantic	WR	18	ACT	0	0	2013-09-14 23:48:01.255639	2013-09-14 23:48:01.25564	HOU
309	1b3d350a-478b-4542-a430-d12cc96adc22	1	Case Keenum	C.Keenum	1988-02-17	73	205	Houston	QB	7	ACT	0	0	2013-09-14 23:48:01.25759	2013-09-14 23:48:01.257591	HOU
310	848b34eb-1ca8-435c-a805-957aa71d4883	1	Andre Johnson	A.Johnson	1981-07-11	75	230	Miami (FL)	WR	80	ACT	0	0	2013-09-14 23:48:01.25972	2013-09-14 23:48:01.259721	HOU
311	743f8917-e781-4345-a1ca-0a7d07b91a08	1	Ed Reed	E.Reed	1978-09-11	71	205	Miami (FL)	FS	20	ACT	0	0	2013-09-14 23:48:01.261593	2013-09-14 23:48:01.261594	HOU
312	9fe21c07-823a-47a1-a4dd-0c611c0280c5	1	Brandon Brooks	B.Brooks	1989-08-19	77	335	Miami (OH)	G	79	ACT	0	0	2013-09-14 23:48:01.263385	2013-09-14 23:48:01.263386	HOU
313	4b6a70aa-3123-4ac4-939d-00f81fde0e33	1	Eddie Pleasant	E.Pleasant	1988-12-17	70	210	Oregon	DB	35	ACT	0	0	2013-09-14 23:48:01.265839	2013-09-14 23:48:01.26584	HOU
314	37c05a5b-aead-4e8e-ac3d-47c8570f6a96	1	Cierre Wood	C.Wood	1991-02-21	71	215	Notre Dame	RB	41	ACT	0	0	2013-09-14 23:48:01.268228	2013-09-14 23:48:01.268229	HOU
315	cb1df42c-b59c-4e23-a9a2-fbfc2b39ef71	1	Ryan Griffin	R.Griffin	1990-09-20	78	254	Connecticut	TE	84	ACT	0	0	2013-09-14 23:48:01.271306	2013-09-14 23:48:01.271307	HOU
316	aec7c02c-00c9-4449-a710-5693e7ae1b65	1	Greg Jones	G.Jones	1981-05-09	73	251	Florida State	FB	33	ACT	0	0	2013-09-14 23:48:01.274439	2013-09-14 23:48:01.274442	HOU
317	b180e643-9f63-41ed-b491-ba3c81e48f39	1	Cody White	C.White	1988-07-01	75	303	Illinois State	G	67	ACT	0	0	2013-09-14 23:48:01.277542	2013-09-14 23:48:01.277544	HOU
318	b99a4918-8664-4664-878e-8f583a5e423f	1	Wade Smith	W.Smith	1981-04-26	76	295	Memphis	G	74	ACT	0	0	2013-09-14 23:48:01.280989	2013-09-14 23:48:01.280991	HOU
319	e08060d3-ed70-4d3e-9692-baa92ec1199f	1	Brennan Williams	B.Williams	1991-02-05	78	310	North Carolina	T	73	IR	0	0	2013-09-14 23:48:01.284363	2013-09-14 23:48:01.284365	HOU
320	5c48ade7-4b9a-4757-9643-87a6e3839e2b	1	DeAndre Hopkins	D.Hopkins	1992-06-06	73	218	Clemson	WR	10	ACT	0	0	2013-09-14 23:48:01.288079	2013-09-14 23:48:01.288081	HOU
321	fa9d0178-a2a7-402f-ad11-c7bea0b80705	1	Ben Jones	B.Jones	1989-07-02	74	308	Georgia	C	60	ACT	0	0	2013-09-14 23:48:01.291499	2013-09-14 23:48:01.291501	HOU
322	d2a7d37d-045a-4086-bbee-48d2cfb43a19	1	Alan Bonner	A.Bonner	1990-11-05	70	191	Jacksonville State	WR	16	IR	0	0	2013-09-14 23:48:01.294873	2013-09-14 23:48:01.294876	HOU
323	f26bd260-a1eb-42ab-8768-bc8ad24e4f9e	1	Duane Brown	D.Brown	1985-08-30	76	303	Virginia Tech	OT	76	ACT	0	0	2013-09-14 23:48:01.298448	2013-09-14 23:48:01.29845	HOU
324	9d99148c-0898-4ba1-9454-c5efbdc01f33	1	DeVier Posey	D.Posey	1990-03-15	73	210	Ohio State	WR	11	ACT	0	0	2013-09-14 23:48:01.302401	2013-09-14 23:48:01.302404	HOU
325	496680c4-2432-481b-883c-6f311da3a4a3	1	David Quessenberry	D.Quessenberry	1990-08-24	77	306	San Jose State	T	77	IR	0	0	2013-09-14 23:48:01.306418	2013-09-14 23:48:01.306421	HOU
326	59ae165a-f7ae-4c36-829d-81d031fc3061	1	Garrett Graham	G.Graham	1986-08-04	75	243	Wisconsin	TE	88	ACT	0	0	2013-09-14 23:48:01.310207	2013-09-14 23:48:01.31021	HOU
327	f7b49d9d-2ce4-459f-8065-fa3b52d28069	1	Kareem Jackson	K.Jackson	1988-04-10	70	188	Alabama	DB	25	ACT	0	0	2013-09-14 23:48:01.31407	2013-09-14 23:48:01.314072	HOU
328	3d916bd3-e7f2-4607-9ad7-32e04935fd86	1	Keshawn Martin	K.Martin	1990-03-15	71	194	Michigan State	WR	82	ACT	0	0	2013-09-14 23:48:01.318076	2013-09-14 23:48:01.318079	HOU
329	fc41b323-9ab9-4ea3-ae4f-fb0b3c5a4a8e	1	Alec Lemon	A.Lemon		73	203	Syracuse	WR	17	IR	0	0	2013-09-14 23:48:01.321999	2013-09-14 23:48:01.322002	HOU
330	a1a28375-1dcf-43d5-974f-bd6b42d05875	1	Shiloh Keo	S.Keo	1987-12-17	71	208	Idaho	SAF	31	ACT	0	0	2013-09-14 23:48:01.325461	2013-09-14 23:48:01.325463	HOU
331	75b812dc-cb66-43a8-93b5-b989c5dd073e	1	Andrew Gardner	A.Gardner	1986-04-04	78	308	Georgia Tech	OT	66	ACT	0	0	2013-09-14 23:48:01.3291	2013-09-14 23:48:01.329102	HOU
332	38c79072-f438-4c96-8aff-3981bf399fbd	1	Danieal Manning	D.Manning	1982-08-09	71	212	Abilene Christian	SAF	38	ACT	0	0	2013-09-14 23:48:01.332396	2013-09-14 23:48:01.332398	HOU
333	7e5ce2d0-6487-4a9f-83b6-634886ee78f3	1	Owen Daniels	O.Daniels	1982-11-09	75	249	Wisconsin	TE	81	ACT	0	0	2013-09-14 23:48:01.33599	2013-09-14 23:48:01.335993	HOU
334	c5516d6a-bee1-435e-b45c-73492683e2a5	1	Chris Myers	C.Myers	1981-09-15	76	286	Miami (FL)	C	55	ACT	0	0	2013-09-14 23:48:01.340309	2013-09-14 23:48:01.340311	HOU
335	c7d8781f-b9f6-4e0f-b0b6-29fce3985f3e	1	Randy Bullock	R.Bullock	1989-12-16	69	206	Texas A&M	K	4	ACT	0	0	2013-09-14 23:48:01.344154	2013-09-14 23:48:01.344156	HOU
336	9a8a3b4d-3e5c-4a65-a96e-cb9f0221b0e3	1	Ryan Harris	R.Harris	1985-03-11	77	302	Notre Dame	OT	68	ACT	0	0	2013-09-14 23:48:01.347602	2013-09-14 23:48:01.347604	HOU
337	c8e9990a-9d89-411c-9d99-c0afa7eaef8c	1	Ben Tate	B.Tate	1988-08-21	71	217	Auburn	RB	44	ACT	0	0	2013-09-14 23:48:01.351558	2013-09-14 23:48:01.35156	HOU
338	DEF-HOU	1	HOU Defense	HOU		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:01.355212	2013-09-14 23:48:01.355215	HOU
339	901a3f95-ae8a-4f1f-8321-11ec42b8b198	1	Jeff Linkenbach	J.Linkenbach	1987-06-09	78	325	Cincinnati	OT	72	ACT	0	0	2013-09-14 23:48:01.652865	2013-09-14 23:48:01.652867	IND
340	a766cfd8-0aaf-4935-bd1b-b6f4d7b225f7	1	Justin Anderson	J.Anderson	1988-04-15	77	340	Georgia	G	79	IR	0	0	2013-09-14 23:48:01.658075	2013-09-14 23:48:01.658079	IND
341	7a2612f3-ea18-444c-95ee-f1ca597d6fb0	1	Antoine Bethea	A.Bethea	1984-07-07	71	206	Howard	SAF	41	ACT	0	0	2013-09-14 23:48:01.660643	2013-09-14 23:48:01.660643	IND
342	d552daac-a3c9-42e0-84f9-cbbe42b8be01	1	Gosder Cherilus	G.Cherilus	1984-06-28	79	314	Boston College	OT	78	ACT	0	0	2013-09-14 23:48:01.663644	2013-09-14 23:48:01.663647	IND
343	1bec10bf-8eae-4018-b2a5-2d623e1bbbc1	1	Donald Brown	D.Brown	1987-04-11	70	207	Connecticut	RB	31	ACT	0	0	2013-09-14 23:48:01.667266	2013-09-14 23:48:01.667268	IND
344	1400c086-a5b0-45b1-a0f8-7cdc9e803917	1	Joe Reitz	J.Reitz	1985-08-24	79	323	Western Michigan	G	76	ACT	0	0	2013-09-14 23:48:01.671293	2013-09-14 23:48:01.671296	IND
345	5ae43ebf-f94d-4ce9-8278-84c1df6eb969	1	Donald Thomas	D.Thomas	1985-09-25	76	306	Connecticut	G	66	ACT	0	0	2013-09-14 23:48:01.674829	2013-09-14 23:48:01.674831	IND
346	3a4f8a1f-8425-4109-9ba3-9899f79f2532	1	Vick Ballard	V.Ballard	1990-07-16	70	224	Mississippi State	RB	33	IR	0	0	2013-09-14 23:48:01.677999	2013-09-14 23:48:01.678001	IND
347	b8426cea-f8b9-4061-8d56-e70d1230103e	1	T.Y. Hilton	T.Y.Hilton	1989-11-14	69	179	Florida International	WR	13	ACT	0	0	2013-09-14 23:48:01.681498	2013-09-14 23:48:01.6815	IND
348	34150f4d-5646-4027-a85f-e74ed7eebfca	1	LaRon Landry	L.Landry	1984-10-14	72	226	LSU	SAF	30	ACT	0	0	2013-09-14 23:48:01.685285	2013-09-14 23:48:01.685287	IND
349	cc745cc3-d52a-454b-98c8-ac9155a9405c	1	Dwayne Allen	D.Allen	1990-02-24	75	265	Clemson	TE	83	ACT	0	0	2013-09-14 23:48:01.689067	2013-09-14 23:48:01.689069	IND
350	c879fa29-f881-4557-86a2-c9d6cee627a6	1	Dominique Jones	D.Jones	1987-08-15	75	270	Shepherd	TE	46	ACT	0	0	2013-09-14 23:48:01.693012	2013-09-14 23:48:01.693015	IND
351	17fea896-24a4-451a-bb03-78c14d9723b2	1	Dan Moore	D.Moore	1990-02-01	71	240	Montana	RB	48	IR	0	0	2013-09-14 23:48:01.696618	2013-09-14 23:48:01.696621	IND
352	b28f7867-8f2a-444b-b6d1-3264497bf963	1	Mike McGlynn	M.McGlynn	1985-03-08	76	325	Pittsburgh	OG	75	ACT	0	0	2013-09-14 23:48:01.699942	2013-09-14 23:48:01.699946	IND
353	051ac116-6d32-4e77-91da-e0ce27d202da	1	Kerwynn Williams	K.Williams	1991-06-09	68	198	Utah State	RB	37	ACT	0	0	2013-09-14 23:48:01.703681	2013-09-14 23:48:01.703684	IND
354	05f8aa7b-3df8-4091-963d-1d4eabb56fa9	1	Khaled Holmes	K.Holmes	1990-01-19	75	319	USC	C	62	ACT	0	0	2013-09-14 23:48:01.707801	2013-09-14 23:48:01.707803	IND
355	e3181493-6a2a-4e95-aa6f-3fc1ddeb7512	1	Andrew Luck	A.Luck	1989-09-12	76	239	Stanford	QB	12	ACT	0	0	2013-09-14 23:48:01.711813	2013-09-14 23:48:01.711815	IND
356	b565f20f-6fac-4efe-84d3-9082f86da25a	1	Samson Satele	S.Satele	1984-11-29	75	300	Hawaii	C	64	ACT	0	0	2013-09-14 23:48:01.715331	2013-09-14 23:48:01.715333	IND
357	9ecf8040-10f9-4a5c-92da-1b4d77bd6760	1	Adam Vinatieri	A.Vinatieri	1972-12-28	72	208	South Dakota State	K	4	ACT	0	0	2013-09-14 23:48:01.718837	2013-09-14 23:48:01.718839	IND
358	94fc7e6c-8c37-4713-abef-68154ac41d06	1	Reggie Wayne	R.Wayne	1978-11-17	72	200	Miami (FL)	WR	87	ACT	0	0	2013-09-14 23:48:01.722392	2013-09-14 23:48:01.722394	IND
359	bd0fd245-64ec-45ee-ac8d-b0072239ea63	1	Sergio Brown	S.Brown	1988-05-22	74	217	Notre Dame	SAF	38	ACT	0	0	2013-09-14 23:48:01.726497	2013-09-14 23:48:01.7265	IND
360	15b3cceb-1696-49cf-9b7a-bb8f5ad8d32b	1	LaVon Brazill	L.Brazill	1989-03-15	71	194	Ohio	WR	15	SUS	0	0	2013-09-14 23:48:01.730666	2013-09-14 23:48:01.730668	IND
361	9102665d-a658-4264-81c3-b9810776ddf0	1	Coby Fleener	C.Fleener	1988-09-20	78	247	Stanford	TE	80	ACT	0	0	2013-09-14 23:48:01.734469	2013-09-14 23:48:01.734471	IND
362	4d079a3a-eaf1-4a78-961d-4e187f7bfbe8	1	Griff Whalen	G.Whalen	1990-03-01	71	197	Stanford	WR	17	ACT	0	0	2013-09-14 23:48:01.738455	2013-09-14 23:48:01.738458	IND
363	7d8eba61-208d-4d91-86cd-704ad05cb7f4	1	Matt Hasselbeck	M.Hasselbeck	1975-09-25	76	235	Boston College	QB	8	ACT	0	0	2013-09-14 23:48:01.742764	2013-09-14 23:48:01.742769	IND
364	b44fa657-e4ea-4cc8-9581-33740bc417e6	1	Anthony Castonzo	A.Castonzo	1988-08-09	79	307	Boston College	T	74	ACT	0	0	2013-09-14 23:48:01.746317	2013-09-14 23:48:01.746321	IND
365	2db8a161-7b3a-4a3c-b915-c5be5b3cd39b	1	Hugh Thornton	H.Thornton	1991-06-28	75	334	Illinois	G	69	ACT	0	0	2013-09-14 23:48:01.749973	2013-09-14 23:48:01.749975	IND
366	5ea7b90f-1e47-45a7-bfdd-b069d26ee53e	1	David Reed	D.Reed	1987-03-22	72	195	Utah	WR	85	ACT	0	0	2013-09-14 23:48:01.753621	2013-09-14 23:48:01.753624	IND
367	c1bf6448-7cbc-4014-b9ce-6a73e44a5d71	1	Stanley Havili	S.Havili	1987-11-14	72	243	USC	FB	39	ACT	0	0	2013-09-14 23:48:01.757646	2013-09-14 23:48:01.757648	IND
368	3a2134f2-8598-48d8-8874-7c92825424c4	1	Delano Howell	D.Howell	1989-11-17	71	196	Stanford	SAF	26	ACT	0	0	2013-09-14 23:48:01.761866	2013-09-14 23:48:01.761869	IND
369	bd413539-9351-454e-9d61-4e8635d7e9f5	1	Jack Doyle	J.Doyle		78	258	Western Kentucky	TE	84	ACT	0	0	2013-09-14 23:48:01.765692	2013-09-14 23:48:01.765694	IND
370	8f22eb36-5282-407a-b6f9-f9b62e5f7318	1	Ahmad Bradshaw	A.Bradshaw	1986-03-19	70	214	Marshall	RB	44	ACT	0	0	2013-09-14 23:48:01.769694	2013-09-14 23:48:01.769696	IND
371	c456e060-d4d8-46cb-acf4-296edfb4f7bd	1	Darrius Heyward-Bey	D.Heyward-Bey	1987-02-26	74	219	Maryland	WR	81	ACT	0	0	2013-09-14 23:48:01.773354	2013-09-14 23:48:01.773356	IND
372	04c9c78a-dea5-4a9b-b813-4dec898108cf	1	Joe Lefeged	J.Lefeged	1988-06-02	72	204	Rutgers	SAF	35	ACT	0	0	2013-09-14 23:48:01.776729	2013-09-14 23:48:01.776731	IND
373	DEF-IND	1	IND Defense	IND		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:01.780073	2013-09-14 23:48:01.780075	IND
374	1899df56-d4be-44cf-97be-6d3b484d45ac	1	Nate Washington	N.Washington	1983-08-28	73	183	Tiffin	WR	85	ACT	0	0	2013-09-14 23:48:02.099967	2013-09-14 23:48:02.099969	TEN
375	5f5fef98-874a-4f97-b833-272e36a850ef	1	Daimion Stafford	D.Stafford	1991-02-18	72	218	Nebraska	SS	39	ACT	0	0	2013-09-14 23:48:02.103895	2013-09-14 23:48:02.103897	TEN
376	e5e0c7f9-c4e3-4de4-8052-d9c083393a99	1	Chris Johnson	C.Johnson	1985-09-23	71	203	East Carolina	RB	28	ACT	0	0	2013-09-14 23:48:02.1073	2013-09-14 23:48:02.107302	TEN
377	7cc50283-9349-49cf-8d6f-b4b388c0e41d	1	Brandon Barden	B.Barden	1989-03-15	77	253	Vanderbilt	TE	81	IR	0	0	2013-09-14 23:48:02.111332	2013-09-14 23:48:02.111335	TEN
378	8e8b22b2-9c58-4a24-9d5a-daded760e1f3	1	Rob Bironas	R.Bironas	1978-01-29	72	205	Georgia Southern	K	2	ACT	0	0	2013-09-14 23:48:02.115197	2013-09-14 23:48:02.115201	TEN
379	c2c65162-07df-48fb-93ce-86f340afb688	1	Taylor Thompson	T.Thompson	1989-10-19	78	268	Southern Methodist	TE	84	ACT	0	0	2013-09-14 23:48:02.119267	2013-09-14 23:48:02.119269	TEN
380	71b9b180-93be-4bbc-bc9f-c48b53933c7c	1	Craig Stevens	C.Stevens	1984-09-01	75	263	California	TE	88	ACT	0	0	2013-09-14 23:48:02.123303	2013-09-14 23:48:02.123305	TEN
381	1bf13fc6-cf27-4b22-ad99-2c72eedd37a6	1	Marc Mariani	M.Mariani	1987-05-02	73	187	Montana	WR	83	IR	0	0	2013-09-14 23:48:02.127312	2013-09-14 23:48:02.127314	TEN
382	763abcf1-e18a-4437-ad3d-9ba0b7e99c69	1	Damian Williams	D.Williams	1988-05-26	73	193	USC	WR	17	ACT	0	0	2013-09-14 23:48:02.130964	2013-09-14 23:48:02.130967	TEN
383	6933ba63-c32c-435b-9943-9a36ede4cc2b	1	Chris Spencer	C.Spencer	1982-03-28	75	308	Mississippi	G	60	ACT	0	0	2013-09-14 23:48:02.134578	2013-09-14 23:48:02.13458	TEN
384	ccce5e8e-52ca-4f0f-a40f-fe5e7227d156	1	Delanie Walker	D.Walker	1984-08-12	72	248	Central Missouri State	TE	82	ACT	0	0	2013-09-14 23:48:02.138155	2013-09-14 23:48:02.138157	TEN
385	9fc81b73-dfe6-41ed-b713-045bea4724ad	1	Darius Reynaud	D.Reynaud	1984-12-29	69	208	West Virginia	RB	25	ACT	0	0	2013-09-14 23:48:02.141906	2013-09-14 23:48:02.141908	TEN
386	0ecd0d32-5e18-40bb-b8bc-278b6206657a	1	Andy Levitre	A.Levitre	1986-05-15	74	303	Oregon State	G	67	ACT	0	0	2013-09-14 23:48:02.149387	2013-09-14 23:48:02.149389	TEN
387	de4a28b3-0abe-41fd-bc76-95ad57f0dcc2	1	Kevin Walter	K.Walter	1981-08-04	75	216	Eastern Michigan	WR	87	PUP	0	0	2013-09-14 23:48:02.152792	2013-09-14 23:48:02.152794	TEN
388	06ed4b06-29d4-49a4-8bba-1bb63184255a	1	Alterraun Verner	A.Verner	1988-12-13	70	186	UCLA	DB	20	ACT	0	0	2013-09-14 23:48:02.156468	2013-09-14 23:48:02.156471	TEN
389	34d8af21-6e0c-4f06-89e5-15c28b1bc0f9	1	Byron Stingily	B.Stingily	1988-09-09	77	318	Louisville	T	68	ACT	0	0	2013-09-14 23:48:02.160184	2013-09-14 23:48:02.160186	TEN
390	a6025030-596c-4829-9138-8281df21d841	1	Brian Schwenke	B.Schwenke	1991-03-22	75	318	California	C	62	ACT	0	0	2013-09-14 23:48:02.163644	2013-09-14 23:48:02.163647	TEN
391	0d506aa9-0e99-4b87-bd15-87b75079009c	1	Bernard Pollard	B.Pollard	1984-12-23	73	226	Purdue	SAF	31	ACT	0	0	2013-09-14 23:48:02.167397	2013-09-14 23:48:02.167399	TEN
392	a7a09040-0fcc-41fe-a1ef-08963913be5f	1	Michael Griffin	M.Griffin	1985-01-04	72	215	Texas	SAF	33	ACT	0	0	2013-09-14 23:48:02.171214	2013-09-14 23:48:02.171216	TEN
393	1d7cdd99-b57b-42e2-8255-eb496e3bd65d	1	David Stewart	D.Stewart	1982-08-28	79	313	Mississippi State	OT	76	ACT	0	0	2013-09-14 23:48:02.174628	2013-09-14 23:48:02.174631	TEN
394	2e39e693-7ba3-41d4-81a2-ff2ddc77ef0f	1	Michael Roos	M.Roos	1982-10-05	79	313	Eastern Washington	OT	71	ACT	0	0	2013-09-14 23:48:02.178426	2013-09-14 23:48:02.178428	TEN
395	869882c4-728a-4349-8294-ffa32b5a4f31	1	Kenny Britt	K.Britt	1988-09-19	75	223	Rutgers	WR	18	ACT	0	0	2013-09-14 23:48:02.182206	2013-09-14 23:48:02.182208	TEN
396	1503ad4b-a2f6-4220-970c-c2018ab3ee11	1	Tommie Campbell	T.Campbell	1987-09-19	75	198	California (PA)	DB	37	ACT	0	0	2013-09-14 23:48:02.186268	2013-09-14 23:48:02.18627	TEN
397	7f6ec436-5fcf-4326-9327-fb2de6687ebd	1	Jake Locker	J.Locker	1988-06-15	75	223	Washington	QB	10	ACT	0	0	2013-09-14 23:48:02.190194	2013-09-14 23:48:02.190197	TEN
398	f3a2dfe6-3a57-45bc-afed-1c1881946ea4	1	Shonn Greene	S.Greene	1985-08-21	71	233	Iowa	RB	23	ACT	0	0	2013-09-14 23:48:02.193986	2013-09-14 23:48:02.193989	TEN
399	fc769a47-957d-4048-b322-73a9e79384d2	1	Mike Otto	M.Otto	1983-07-24	77	308	Purdue	OT	66	ACT	0	0	2013-09-14 23:48:02.197893	2013-09-14 23:48:02.197895	TEN
400	0742d2ea-1cf2-49a6-a150-77ba6e034d8c	1	Ryan Fitzpatrick	R.Fitzpatrick	1982-11-24	74	223	Harvard	QB	4	ACT	0	0	2013-09-14 23:48:02.201665	2013-09-14 23:48:02.201668	TEN
401	8ec84057-a244-491c-8f5e-36252a8ca70e	1	Michael Preston	M.Preston	1989-06-01	77	213	Heidelberg	WR	14	ACT	0	0	2013-09-14 23:48:02.205184	2013-09-14 23:48:02.205186	TEN
402	192e6f3d-c0d0-474e-b102-7b6a9c5743d3	1	Jackie Battle	J.Battle	1983-10-01	74	240	Houston	RB	22	ACT	0	0	2013-09-14 23:48:02.209008	2013-09-14 23:48:02.20901	TEN
403	3870fda6-c4da-460b-9b82-cdac45c5e1a2	1	George Wilson	G.Wilson	1981-03-14	72	210	Arkansas	SS	21	ACT	0	0	2013-09-14 23:48:02.212595	2013-09-14 23:48:02.212597	TEN
404	cf45fa8d-13e0-4c16-a9eb-301b090ef83a	1	Chance Warmack	C.Warmack	1991-09-14	74	323	Alabama	G	70	ACT	0	0	2013-09-14 23:48:02.216041	2013-09-14 23:48:02.216043	TEN
405	f636d7ce-05f9-43d7-b63f-351acb5c2a70	1	Justin Hunter	J.Hunter	1991-05-20	76	203	Tennessee	WR	15	ACT	0	0	2013-09-14 23:48:02.219465	2013-09-14 23:48:02.219467	TEN
406	34c53ab4-4f21-4b02-9012-6f97b7451075	1	Rob Turner	R.Turner	1984-08-20	76	308	New Mexico	C	59	ACT	0	0	2013-09-14 23:48:02.223129	2013-09-14 23:48:02.223131	TEN
407	441e8866-33f1-4820-9fa3-3aa2c7535975	1	Kendall Wright	K.Wright	1989-11-12	70	191	Baylor	WR	13	ACT	0	0	2013-09-14 23:48:02.226404	2013-09-14 23:48:02.226406	TEN
408	a1a073ac-48bb-44e5-8631-852c70970296	1	Collin Mooney	C. Mooney	1986-04-03	70	247	Army	FB	42	ACT	0	0	2013-09-14 23:48:02.229602	2013-09-14 23:48:02.229605	TEN
409	DEF-TEN	1	TEN Defense	TEN		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:02.233527	2013-09-14 23:48:02.233529	TEN
410	26f507c9-6d5d-454a-a381-7ec1fd2e0fb1	1	D.J. Williams	D.Williams	1988-09-10	74	245	Arkansas	TE	85	ACT	0	0	2013-09-14 23:48:02.574471	2013-09-14 23:48:02.574472	JAC
411	bb7f4f60-57a4-437d-9541-a42abb1d1f53	1	Johnathan Cyprien	J.Cyprien	1990-07-29	72	217	Florida International	SAF	37	ACT	0	0	2013-09-14 23:48:02.577799	2013-09-14 23:48:02.5778	JAC
412	a39de973-a990-49a3-b90c-f1c0c99eca2e	1	Cecil Shorts III	C.Shorts III	1987-12-22	72	202	Mount Union	WR	84	ACT	0	0	2013-09-14 23:48:02.580848	2013-09-14 23:48:02.58085	JAC
413	979ecdc4-5e0d-48f7-ad50-db330aee2c2c	1	Allen Reisner	A.Reisner	1988-09-29	75	253	Iowa	TE	87	ACT	0	0	2013-09-14 23:48:02.583762	2013-09-14 23:48:02.583764	JAC
414	000bc6c6-c9a8-4631-92d6-1cea5aaa1644	1	Austin Pasztor	A.Pasztor	1990-11-26	79	308	Virginia	OL	67	ACT	0	0	2013-09-14 23:48:02.586386	2013-09-14 23:48:02.586388	JAC
415	1a47e408-75ee-4333-b2ef-d44dd1a7459c	1	Taylor Price	T.Price	1987-10-08	73	195	Ohio	WR	15	IR	0	0	2013-09-14 23:48:02.589038	2013-09-14 23:48:02.58904	JAC
416	f20d4a79-b8ca-4922-b276-29f46985bb3b	1	Maurice Jones-Drew	M.Jones-Drew	1985-03-23	67	210	UCLA	RB	32	ACT	0	0	2013-09-14 23:48:02.592757	2013-09-14 23:48:02.59276	JAC
417	cbdebfef-c68d-4756-bc04-b4d724e42412	1	Jeremy Ebert	J.Ebert	1989-04-06	72	195	Northwestern	WR	80	ACT	0	0	2013-09-14 23:48:02.597269	2013-09-14 23:48:02.597271	JAC
418	d579af24-53b8-42bf-b767-c50944afb7ec	1	Clay Harbor	C.Harbor	1987-07-02	75	255	Missouri State	TE	86	ACT	0	0	2013-09-14 23:48:02.60158	2013-09-14 23:48:02.601583	JAC
419	470c7f4b-0839-4290-a8cd-ff185ae350f3	1	Mike Brown	M.Brown	1989-02-09	70	200	Liberty	WR	12	ACT	0	0	2013-09-14 23:48:02.605335	2013-09-14 23:48:02.605337	JAC
420	ed29fd68-0d5d-4636-8010-31436a78c9c6	1	Josh Scobee	J.Scobee	1982-06-23	73	210	Louisiana Tech	K	10	ACT	0	0	2013-09-14 23:48:02.609881	2013-09-14 23:48:02.609884	JAC
421	f55053e4-4bfd-495d-981a-d62e3662f01b	1	Chad Henne	C.Henne	1985-07-02	75	230	Michigan	QB	7	ACT	0	0	2013-09-14 23:48:02.614322	2013-09-14 23:48:02.614326	JAC
422	2145b99f-3f0f-4a0a-ab77-4182fc333b29	1	Stephen Burton	S.Burton	1989-12-11	73	224	West Texas A&M	WR	15	ACT	0	0	2013-09-14 23:48:02.618269	2013-09-14 23:48:02.618271	JAC
423	de816e24-8442-49a4-99cd-dde7e7c05863	1	Blaine Gabbert	B.Gabbert	1989-10-15	76	235	Missouri	QB	11	ACT	0	0	2013-09-14 23:48:02.622375	2013-09-14 23:48:02.622379	JAC
424	9c21e9af-681c-41ef-9b00-fbc9e1668ed1	1	Marcedes Lewis	M.Lewis	1984-05-19	78	272	UCLA	TE	89	ACT	0	0	2013-09-14 23:48:02.626262	2013-09-14 23:48:02.626265	JAC
425	14af64f4-90a6-4f56-8624-6a313966cc31	1	Eugene Monroe	E.Monroe	1987-04-18	77	306	Virginia	OT	75	ACT	0	0	2013-09-14 23:48:02.630423	2013-09-14 23:48:02.630425	JAC
426	1c32d032-ed97-4c70-8655-eecdb0fe9ccf	1	Ricky Stanzi	R.Stanzi	1987-09-03	76	228	Iowa	QB	6	ACT	0	0	2013-09-14 23:48:02.634531	2013-09-14 23:48:02.634533	JAC
427	a686927a-781f-4814-a4ef-a5ab34a09062	1	Jordan Todman	J.Todman	1990-02-24	70	198	Connecticut	RB	30	ACT	0	0	2013-09-14 23:48:02.638071	2013-09-14 23:48:02.638073	JAC
428	ccd799f0-09ad-4694-92d6-1270c34d2b51	1	Will Rackley	W.Rackley	1989-10-11	75	310	Lehigh	G	65	ACT	0	0	2013-09-14 23:48:02.641773	2013-09-14 23:48:02.641776	JAC
429	5bd91ec9-3d48-48c1-b36e-78462044acfc	1	Will Blackmon	W.Blackmon	1984-10-27	72	210	Boston College	DB	24	ACT	0	0	2013-09-14 23:48:02.645293	2013-09-14 23:48:02.645295	JAC
430	f47c5503-ed7f-4d09-8bc2-6bcac572e5a9	1	Dwight Lowery	D.Lowery	1986-01-23	71	212	San Jose State	DB	25	ACT	0	0	2013-09-14 23:48:02.648521	2013-09-14 23:48:02.648523	JAC
431	1fcd8651-364a-4f64-86da-8cb6c1cdd34a	1	Luke Joeckel	L.Joeckel	1991-11-06	78	306	Texas A&M	T	76	ACT	0	0	2013-09-14 23:48:02.655727	2013-09-14 23:48:02.655729	JAC
432	86a8cf97-21b2-4efb-9d26-650d979b1f22	1	Brad Meester	B.Meester	1977-03-23	75	292	Northern Iowa	C	63	ACT	0	0	2013-09-14 23:48:02.659886	2013-09-14 23:48:02.659888	JAC
433	70ec5e1b-b753-4d12-814d-7ea10c8241c1	1	Stephane Milhim	S.Milhim	1990-11-20	77	315	Massachusetts	G	61	IR	0	0	2013-09-14 23:48:02.663752	2013-09-14 23:48:02.663755	JAC
434	203e67cc-fac1-4903-b888-98899c3a44b7	1	Chris Prosinski	C.Prosinski	1987-04-28	73	208	Wyoming	SAF	42	ACT	0	0	2013-09-14 23:48:02.667475	2013-09-14 23:48:02.667478	JAC
435	edb6712f-cf3f-4fa2-8dcf-03488334e037	1	Mike Brewster	M.Brewster	1989-07-27	76	305	Ohio State	C	60	ACT	0	0	2013-09-14 23:48:02.671631	2013-09-14 23:48:02.671633	JAC
436	6e3e9355-311b-421d-b9cc-7db8da220431	1	Uche Nwaneri	U.Nwaneri	1984-03-20	75	310	Purdue	G	77	ACT	0	0	2013-09-14 23:48:02.675193	2013-09-14 23:48:02.675195	JAC
437	e506364d-fe69-48c7-8b84-a49603b0a7b6	1	Ace Sanders	A.Sanders	1991-11-11	67	178	South Carolina	WR	18	ACT	0	0	2013-09-14 23:48:02.678714	2013-09-14 23:48:02.678716	JAC
438	0cbf2c4e-2869-496f-9205-fa0dbefa91f7	1	Will Ta'ufo'ou	W.Ta'ufo'ou	1986-06-19	71	247	California	FB	45	ACT	0	0	2013-09-14 23:48:02.682208	2013-09-14 23:48:02.68221	JAC
439	8b927dbe-a45e-4c5a-a756-4048a58befcf	1	Josh Evans	J.Evans		72	205	Florida	SAF	26	ACT	0	0	2013-09-14 23:48:02.685878	2013-09-14 23:48:02.68588	JAC
440	69ad2b65-7d43-4915-a60c-151f3b26ebf3	1	Cameron Bradfield	C.Bradfield	1987-09-14	76	308	Grand Valley State	OL	78	ACT	0	0	2013-09-14 23:48:02.689247	2013-09-14 23:48:02.689249	JAC
441	c122fac9-b0fd-4d25-a0c5-e1e29a0a144c	1	Winston Guy	W.Guy	1990-04-23	73	218	Kentucky	SS	22	ACT	0	0	2013-09-14 23:48:02.693556	2013-09-14 23:48:02.693559	JAC
442	1d352cd4-86c0-4741-9d8b-c131e05997cc	1	Justin Blackmon	J.Blackmon	1990-01-09	73	210	Oklahoma State	WR	14	SUS	0	0	2013-09-14 23:48:02.697518	2013-09-14 23:48:02.69752	JAC
443	b45f0ca8-9f84-4893-86d7-b86bb6a588a7	1	Denard Robinson	D.Robinson	1990-09-22	72	197	Michigan	WR	16	ACT	0	0	2013-09-14 23:48:02.701226	2013-09-14 23:48:02.701229	JAC
444	5e5c57a2-f141-4fd7-848d-ea48e8d96a6e	1	Justin Forsett	J.Forsett	1985-10-14	68	194	California	RB	21	ACT	0	0	2013-09-14 23:48:02.704595	2013-09-14 23:48:02.704597	JAC
445	DEF-JAC	1	JAC Defense	JAC		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:02.7082	2013-09-14 23:48:02.708204	JAC
446	0045a36c-f464-49e0-a25a-9210edc94bc1	1	Chase Daniel	C.Daniel	1986-10-07	72	225	Missouri	QB	10	ACT	0	0	2013-09-14 23:48:03.022343	2013-09-14 23:48:03.022345	KC
447	b13ba4c3-5761-40fb-aa6a-935f09c39a6b	1	Tyler Bray	T.Bray	1991-12-27	78	215	Tennessee	QB	9	ACT	0	0	2013-09-14 23:48:03.026519	2013-09-14 23:48:03.026522	KC
448	9b80f314-0cd8-4a35-918f-a405b680e879	1	Brad McDougald	B.McDougald	1990-11-15	73	209	Kansas	SAF	48	ACT	0	0	2013-09-14 23:48:03.030541	2013-09-14 23:48:03.030543	KC
449	1c4cf2d1-5bcf-457a-9f5b-34e4949edfcd	1	Husain Abdullah	H.Abdullah	1985-07-27	72	204	Washington State	SAF	39	ACT	0	0	2013-09-14 23:48:03.034143	2013-09-14 23:48:03.034146	KC
450	54be4c73-6678-4dc9-90eb-a60e8f307c43	1	Jon Asamoah	J.Asamoah	1988-07-21	76	305	Illinois	G	73	ACT	0	0	2013-09-14 23:48:03.03785	2013-09-14 23:48:03.037852	KC
451	5b3f26e8-4500-47c0-b985-5b5b1eed6098	1	Sean McGrath	S.McGrath	1987-12-03	77	247	Henderson State	TE	84	ACT	0	0	2013-09-14 23:48:03.041875	2013-09-14 23:48:03.041877	KC
452	ecc4f0c1-64e0-46cc-9b58-91c2b215e62a	1	Ryan Succop	R.Succop	1986-09-19	74	218	South Carolina	K	6	ACT	0	0	2013-09-14 23:48:03.046059	2013-09-14 23:48:03.046062	KC
453	f841a9ef-d286-407e-9113-092b0503837a	1	Chad Hall	C.Hall	1986-05-23	68	187	Air Force	WR	14	ACT	0	0	2013-09-14 23:48:03.049651	2013-09-14 23:48:03.049653	KC
454	83fac4ad-a729-4774-a44e-20713aa01319	1	Jeff Allen	J.Allen	1990-01-08	76	307	Illinois	G	71	ACT	0	0	2013-09-14 23:48:03.053434	2013-09-14 23:48:03.053436	KC
455	2fda010a-8c62-4c07-b601-4ba03f57e6af	1	Alex Smith	A.Smith	1984-05-07	76	217	Utah	QB	11	ACT	0	0	2013-09-14 23:48:03.05743	2013-09-14 23:48:03.057432	KC
456	04eb8101-538f-44ac-ba09-ce30b5344fc2	1	Anthony Fasano	A.Fasano	1984-04-20	76	255	Notre Dame	TE	80	ACT	0	0	2013-09-14 23:48:03.061355	2013-09-14 23:48:03.061357	KC
457	aca06a5e-0e3a-4285-a025-199f8fa0376f	1	Jamaal Charles	J.Charles	1986-12-27	71	199	Texas	RB	25	ACT	0	0	2013-09-14 23:48:03.065009	2013-09-14 23:48:03.065011	KC
458	c3859e06-5f23-4302-a71b-04820a899d5f	1	Travis Kelce	T.Kelce	1989-10-05	78	260	Cincinnati	TE	87	ACT	0	0	2013-09-14 23:48:03.069168	2013-09-14 23:48:03.06917	KC
459	569ff94c-e066-4d78-accf-6141a879a621	1	Junior Hemingway	J.Hemingway	1988-12-27	73	225	Michigan	WR	88	ACT	0	0	2013-09-14 23:48:03.073395	2013-09-14 23:48:03.073398	KC
460	e75d1c7c-d4df-4d17-82a9-57c97cd63d02	1	Cyrus Gray	C.Gray	1989-11-18	70	206	Texas A&M	RB	32	ACT	0	0	2013-09-14 23:48:03.077434	2013-09-14 23:48:03.077438	KC
461	58f2138a-0772-435d-8444-85b35e97172e	1	A.J. Jenkins	A.Jenkins	1989-09-30	72	200	Illinois	WR	15	ACT	0	0	2013-09-14 23:48:03.081311	2013-09-14 23:48:03.081314	KC
462	6e8964e3-bc64-4cff-acdf-b984f9b28811	1	Eric Berry	E.Berry	1988-12-29	72	211	Tennessee	SAF	29	ACT	0	0	2013-09-14 23:48:03.085642	2013-09-14 23:48:03.085644	KC
463	1d2be514-b036-4032-ba35-0f4c0003affc	1	Geoff Schwartz	G.Schwartz	1986-07-11	78	340	Oregon	G	74	ACT	0	0	2013-09-14 23:48:03.089518	2013-09-14 23:48:03.089521	KC
464	54f4146b-cec8-4fba-a00e-eac7e31ac07c	1	Dexter McCluster	D.McCluster	1988-08-25	68	170	Mississippi	WR	22	ACT	0	0	2013-09-14 23:48:03.093164	2013-09-14 23:48:03.093166	KC
465	868a2028-46f6-4263-91ca-e7907cbdf5e7	1	Branden Albert	B.Albert	1984-11-04	77	316	Virginia	OT	76	ACT	0	0	2013-09-14 23:48:03.097016	2013-09-14 23:48:03.097019	KC
466	2e35b163-2fef-4659-b9d8-5916dbe06179	1	Dwayne Bowe	D.Bowe	1984-09-21	74	221	LSU	WR	82	ACT	0	0	2013-09-14 23:48:03.100772	2013-09-14 23:48:03.100774	KC
467	d3cde6a6-f635-40d8-adc6-f1a7892f8683	1	Eric Kush	E.Kush		76	313	California (PA)	C	64	ACT	0	0	2013-09-14 23:48:03.104411	2013-09-14 23:48:03.104413	KC
468	10bc7a15-0e66-4cdc-bec3-5a60b0b39159	1	Eric Fisher	E.Fisher	1991-01-05	79	306	Central Michigan	OT	72	ACT	0	0	2013-09-14 23:48:03.108125	2013-09-14 23:48:03.108127	KC
469	a0e27c0c-0b7e-4da4-b228-1a366b09596e	1	Knile Davis	K.Davis	1991-10-05	70	227	Arkansas	RB	34	ACT	0	0	2013-09-14 23:48:03.111886	2013-09-14 23:48:03.111889	KC
470	07ab211c-4733-4336-b59a-2137f3efe5e8	1	Kendrick Lewis	K.Lewis	1988-06-16	72	198	Mississippi	SAF	23	ACT	0	0	2013-09-14 23:48:03.11553	2013-09-14 23:48:03.115532	KC
471	7868cc7a-fb8a-4c57-b73a-a8449ffe1737	1	Donald Stephenson	D.Stephenson	1988-09-30	78	312	Oklahoma	T	79	ACT	0	0	2013-09-14 23:48:03.119933	2013-09-14 23:48:03.119935	KC
472	f701832d-046b-4aa7-bfbb-259a2313dec6	1	Quintin Demps	Q.Demps	1985-06-29	71	208	Texas-El Paso	SAF	35	ACT	0	0	2013-09-14 23:48:03.124108	2013-09-14 23:48:03.12411	KC
473	1f0d9995-7ace-44ab-8d61-2f3924d5b75d	1	Rodney Hudson	R.Hudson	1989-07-12	74	299	Florida State	C	61	ACT	0	0	2013-09-14 23:48:03.127825	2013-09-14 23:48:03.127827	KC
474	e033ce15-9fc5-430b-90e2-90dfe52b21c1	1	Anthony Sherman	A.Sherman	1988-12-11	70	242	Connecticut	FB	42	ACT	0	0	2013-09-14 23:48:03.131699	2013-09-14 23:48:03.131702	KC
475	87ff59eb-66e3-4fe6-8c99-8c18b4c0eb36	1	Donnie Avery	D.Avery	1984-06-12	71	200	Houston	WR	17	ACT	0	0	2013-09-14 23:48:03.135448	2013-09-14 23:48:03.135451	KC
476	DEF-KC	1	KC Defense	KC		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:03.139202	2013-09-14 23:48:03.139204	KC
477	f35de60c-6841-4f8a-835e-02ba528be416	1	Eric Decker	E.Decker	1987-03-15	75	214	Minnesota	WR	87	ACT	0	0	2013-09-14 23:48:03.449533	2013-09-14 23:48:03.449534	DEN
478	d7ed32dc-b05b-4a90-b29c-7fcb4527d2c5	1	Knowshon Moreno	K.Moreno	1987-07-16	71	220	Georgia	RB	27	ACT	0	0	2013-09-14 23:48:03.453268	2013-09-14 23:48:03.453268	DEN
479	55f094bf-4d4f-492f-b1de-7c4d6aec66a8	1	Manny Ramirez	M.Ramirez	1983-02-13	75	320	Texas Tech	OG	66	ACT	0	0	2013-09-14 23:48:03.456329	2013-09-14 23:48:03.456332	DEN
480	2ba94880-d59e-4efb-8de9-abb432286614	1	J.D. Walton	J.Walton	1987-03-24	75	305	Baylor	C	50	PUP	0	0	2013-09-14 23:48:03.459904	2013-09-14 23:48:03.459907	DEN
481	67f5e782-f91c-4536-9818-cf4a0e7e821d	1	Matt Prater	M.Prater	1984-08-10	70	195	Central Florida	K	5	ACT	0	0	2013-09-14 23:48:03.463742	2013-09-14 23:48:03.463745	DEN
482	de587dab-dcc9-4e33-8ddf-90f581fae2ec	1	Wes Welker	W.Welker	1981-05-01	69	185	Texas Tech	WR	83	ACT	0	0	2013-09-14 23:48:03.467315	2013-09-14 23:48:03.467317	DEN
483	483242d7-57c0-4d7e-921b-d836df3a0abb	1	Greg Orton	G.Orton	1986-12-07	75	199	Purdue	WR	89	IR	0	0	2013-09-14 23:48:03.471071	2013-09-14 23:48:03.471073	DEN
484	65578d87-d998-4de3-8866-90bbdb43faa9	1	Chris Clark	C.Clark	1985-10-01	77	305	Southern Mississippi	OT	75	ACT	0	0	2013-09-14 23:48:03.474848	2013-09-14 23:48:03.474851	DEN
485	40a19e4d-a6c1-4bee-a7b4-5ed61ae75323	1	Zac Dysert	Z.Dysert	1990-02-08	75	221	Miami (OH)	QB	2	ACT	0	0	2013-09-14 23:48:03.478263	2013-09-14 23:48:03.478265	DEN
486	0f0ff562-af1c-4be8-8011-1f71e8441e00	1	Mike Adams	M.Adams	1981-03-24	71	200	Delaware	SAF	20	ACT	0	0	2013-09-14 23:48:03.481984	2013-09-14 23:48:03.481986	DEN
487	919805f1-5497-43dd-b477-de3b0b835e5e	1	Joel Dreessen	J.Dreessen	1982-07-26	76	245	Colorado State	TE	81	ACT	0	0	2013-09-14 23:48:03.4857	2013-09-14 23:48:03.485704	DEN
488	6d54b233-5b67-4e16-9b4d-7e32f28abd07	1	Rahim Moore	R.Moore	1990-02-11	73	195	UCLA	SAF	26	ACT	0	0	2013-09-14 23:48:03.489589	2013-09-14 23:48:03.489592	DEN
489	87f6826a-f35a-4b49-9673-da54ccb9becd	1	Julius Thomas	J.Thomas	1988-06-27	77	250	Portland State	TE	80	ACT	0	0	2013-09-14 23:48:03.493073	2013-09-14 23:48:03.493075	DEN
490	4fea49d2-1024-4019-8312-d9d3113055cd	1	Quinton Carter	Q.Carter	1988-07-20	73	200	Oklahoma	SAF	28	IR	0	0	2013-09-14 23:48:03.496433	2013-09-14 23:48:03.496435	DEN
491	c3a7ec5c-db82-44ae-ab74-b5220448375a	1	David Bruton	D.Bruton	1987-07-23	74	217	Notre Dame	SAF	30	ACT	0	0	2013-09-14 23:48:03.499962	2013-09-14 23:48:03.499965	DEN
492	aae6d92e-5f28-43ee-b0dc-522e80e99f76	1	Peyton Manning	P.Manning	1976-03-24	77	230	Tennessee	QB	18	ACT	0	0	2013-09-14 23:48:03.503585	2013-09-14 23:48:03.503587	DEN
493	5997e86a-8bee-44ae-b640-7688815e12d7	1	Orlando Franklin	O.Franklin	1987-12-16	79	320	Miami (FL)	OT	74	ACT	0	0	2013-09-14 23:48:03.507227	2013-09-14 23:48:03.507229	DEN
494	2a30e8a3-682d-44d3-80b0-7ced588a9e73	1	Chris Kuper	C.Kuper	1982-12-19	76	303	North Dakota	G	73	ACT	0	0	2013-09-14 23:48:03.510926	2013-09-14 23:48:03.510928	DEN
495	f9c87103-362b-4c00-9453-a0b4dc963a06	1	Steve Vallos	S.Vallos	1983-12-28	75	310	Wake Forest	C	60	ACT	0	0	2013-09-14 23:48:03.51486	2013-09-14 23:48:03.514863	DEN
496	6ef43c53-53d7-4b0f-ad99-17664d663ae8	1	Virgil Green	V.Green	1988-08-03	77	255	Nevada-Reno	TE	85	ACT	0	0	2013-09-14 23:48:03.51833	2013-09-14 23:48:03.518333	DEN
497	2386681b-ea65-4d13-a668-f2dbafe8790e	1	Dan Koppen	D.Koppen	1979-09-12	74	300	Boston College	C	67	IR	0	0	2013-09-14 23:48:03.522098	2013-09-14 23:48:03.5221	DEN
498	a9217999-fa6d-4474-a176-1cf9013224ea	1	Zane Beadles	Z.Beadles	1986-11-19	76	305	Utah	G	68	ACT	0	0	2013-09-14 23:48:03.525886	2013-09-14 23:48:03.525888	DEN
499	c80dc191-dcf3-4adc-a9da-57bc70f75ae6	1	Ryan Clady	R.Clady	1986-09-06	78	315	Boise State	OT	78	ACT	0	0	2013-09-14 23:48:03.529281	2013-09-14 23:48:03.529284	DEN
500	b33de0e6-973c-40b3-a9c6-1a7e6cb1b540	1	Justin Boren	J.Boren	1988-04-28	74	315	Ohio State	G	72	IR	0	0	2013-09-14 23:48:03.533012	2013-09-14 23:48:03.533015	DEN
501	81fed5e8-2a1a-4f77-904e-78912a4a91bb	1	Duke Ihenacho	D.Ihenacho	1989-06-16	73	207	San Jose State	SAF	33	ACT	0	0	2013-09-14 23:48:03.536921	2013-09-14 23:48:03.536923	DEN
502	6e024d51-d5fb-40cc-8a07-495f81347ad1	1	Ronnie Hillman	R.Hillman	1991-09-14	70	195	San Diego State	RB	21	ACT	0	0	2013-09-14 23:48:03.540996	2013-09-14 23:48:03.540998	DEN
503	1b102bf3-d9b0-47eb-b862-a0240362bf23	1	Trindon Holliday	T.Holliday	1986-04-27	65	170	LSU	WR	11	ACT	0	0	2013-09-14 23:48:03.544725	2013-09-14 23:48:03.544728	DEN
504	428258ce-f7ac-4e8b-a665-485beb03aa73	1	Omar Bolden	O. Bolden	1988-12-20	70	195	Arizona State	SAF	31	ACT	0	0	2013-09-14 23:48:03.54829	2013-09-14 23:48:03.548292	DEN
505	f7841baa-9284-4c03-b698-442570651c6c	1	C.J. Anderson	C.Anderson	1991-02-10	68	224	California	RB	22	ACT	0	0	2013-09-14 23:48:03.552006	2013-09-14 23:48:03.552009	DEN
506	042f89b0-2442-420f-888a-cb10d188903d	1	Louis Vasquez	L.Vasquez	1987-04-11	77	335	Texas Tech	G	65	ACT	0	0	2013-09-14 23:48:03.555457	2013-09-14 23:48:03.555459	DEN
507	e89bed19-f222-41b6-9b85-cc6cccddcd5b	1	Jacob Tamme	J.Tamme	1985-03-15	75	230	Kentucky	TE	84	ACT	0	0	2013-09-14 23:48:03.55927	2013-09-14 23:48:03.559272	DEN
508	0847010c-9a77-4f0b-9d63-c8b4b224d263	1	Brock Osweiler	B.Osweiler	1990-11-22	80	240	Arizona State	QB	17	ACT	0	0	2013-09-14 23:48:03.56298	2013-09-14 23:48:03.562983	DEN
509	6e444737-a1e1-4ddd-b963-cd6a9496fde0	1	Demaryius Thomas	D.Thomas	1987-12-25	75	229	Georgia Tech	WR	88	ACT	0	0	2013-09-14 23:48:03.566548	2013-09-14 23:48:03.56655	DEN
510	fbcbda6b-3c05-4c8e-82f8-e5e851262a07	1	Andre Caldwell	A.Caldwell	1985-04-15	72	200	Florida	WR	12	ACT	0	0	2013-09-14 23:48:03.569992	2013-09-14 23:48:03.569994	DEN
511	e1156c37-6175-4a40-a4d1-8a5b77f9da28	1	Montee Ball	M.Ball	1990-12-05	70	215	Wisconsin	RB	28	ACT	0	0	2013-09-14 23:48:03.573422	2013-09-14 23:48:03.573424	DEN
512	53f7e9ec-9819-4364-9875-a987a190f098	1	John Moffitt	J.Moffitt	1986-10-28	76	319	Wisconsin	G	72	ACT	0	0	2013-09-14 23:48:03.576732	2013-09-14 23:48:03.576734	DEN
513	DEF-DEN	1	DEN Defense	DEN		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:03.579981	2013-09-14 23:48:03.579983	DEN
514	8d3038d8-f2af-4414-a90b-d1ccc8a1ae80	1	Tony Pashos	T.Pashos	1980-08-03	78	325	Illinois	OT	79	ACT	0	0	2013-09-14 23:48:03.838857	2013-09-14 23:48:03.838858	OAK
515	84740b88-9a98-45f5-a0b8-f42a2903e87b	1	Matt McCants	M.McCants	1989-08-18	77	309	Alabama-Birmingham	T	73	ACT	0	0	2013-09-14 23:48:03.840555	2013-09-14 23:48:03.840556	OAK
516	11911216-200c-4c0a-81cf-ebfc4161e090	1	Willie Smith	W.Smith	1986-11-13	77	310	East Carolina	T	79	IR	0	0	2013-09-14 23:48:03.842174	2013-09-14 23:48:03.842175	OAK
517	5a20a439-bebc-4ef7-8b9f-30e1d677a26b	1	Jamize Olawale	J.Olawale	1989-04-17	73	240	North Texas	RB	49	ACT	0	0	2013-09-14 23:48:03.844316	2013-09-14 23:48:03.844316	OAK
518	996974b8-2e0a-47d9-90a7-c3455192d06b	1	Andre Holmes	A.Holmes	1988-06-16	77	223	Hillsdale	WR	18	SUS	0	0	2013-09-14 23:48:03.846358	2013-09-14 23:48:03.846359	OAK
519	e584c525-2f4e-4d29-95c5-1d16138834e5	1	Menelik Watson	M.Watson	1988-12-22	77	315	Florida State	T	71	ACT	0	0	2013-09-14 23:48:03.848575	2013-09-14 23:48:03.848576	OAK
520	7cfe0c9f-d5cf-49d9-ba8e-d88f41ae7415	1	Mike Brisiel	M.Brisiel	1983-03-14	77	310	Colorado State	G	65	ACT	0	0	2013-09-14 23:48:03.850818	2013-09-14 23:48:03.85082	OAK
521	d2cad5f8-b35f-4cf4-9567-57c387ba6225	1	Rod Streater	R.Streater	1988-02-09	75	200	Temple	WR	80	ACT	0	0	2013-09-14 23:48:03.85358	2013-09-14 23:48:03.853581	OAK
522	af48c3f0-040b-40f9-95ab-6ebcb4c16cf8	1	Terrelle Pryor	T. Pryor	1989-06-20	76	233	Ohio State	QB	2	ACT	0	0	2013-09-14 23:48:03.856293	2013-09-14 23:48:03.856294	OAK
523	99399f7f-5560-46a9-a4e1-7bfd4fa6465f	1	Antoine McClain	A.McClain	1989-12-06	77	336	Clemson	G	74	ACT	0	0	2013-09-14 23:48:03.859063	2013-09-14 23:48:03.859065	OAK
524	9c9c6cfc-20b1-4ee4-87e5-1e5acf47fb36	1	Denarius Moore	D.Moore	1988-12-09	72	190	Tennessee	WR	17	ACT	0	0	2013-09-14 23:48:03.86169	2013-09-14 23:48:03.861692	OAK
525	ce572d82-6f54-4317-8a1a-1c9c917972cc	1	Tyvon Branch	T.Branch	1986-12-11	72	210	Connecticut	SAF	33	ACT	0	0	2013-09-14 23:48:03.863076	2013-09-14 23:48:03.863077	OAK
526	fd3ad5d6-d24d-48f9-ba9b-dddbfefbda3b	1	Juron Criner	J.Criner	1989-12-12	75	221	Arizona	WR	84	ACT	0	0	2013-09-14 23:48:03.86472	2013-09-14 23:48:03.864722	OAK
527	26b9c11d-c557-4bef-b990-65498858df47	1	Brice Butler	B.Butler	1990-01-29	75	213	San Diego State	WR	19	ACT	0	0	2013-09-14 23:48:03.866592	2013-09-14 23:48:03.866592	OAK
528	540f8b30-900e-4d17-8756-c262ba5fa039	1	Latavius Murray	L.Murray	1991-02-21	75	230	Central Florida	RB	34	IR	0	0	2013-09-14 23:48:03.868952	2013-09-14 23:48:03.868954	OAK
529	adadafa1-dc37-486d-8538-7db1e1b5f71e	1	Taiwan Jones	T.Jones	1988-07-26	72	197	Eastern Washington	RB	22	ACT	0	0	2013-09-14 23:48:03.871676	2013-09-14 23:48:03.871677	OAK
530	65006631-45b1-4920-b0a3-f00277119f1e	1	Stefen Wisniewski	S.Wisniewski	1989-03-22	75	307	Penn State	C	61	ACT	0	0	2013-09-14 23:48:03.87422	2013-09-14 23:48:03.874221	OAK
531	a24e3058-dea2-44ef-bf23-72e0af500164	1	Jeron Mastrud	J.Mastrud	1987-12-17	78	255	Kansas State	TE	85	ACT	0	0	2013-09-14 23:48:03.875376	2013-09-14 23:48:03.875377	OAK
532	0f8fbebb-00d6-4390-ae7d-144158f6c372	1	Luke Nix	L.Nix	1989-09-28	77	320	Pittsburgh	G	76	ACT	0	0	2013-09-14 23:48:03.876554	2013-09-14 23:48:03.876555	OAK
533	294acd0c-63a9-429e-afaa-2bfeb00d7988	1	Tony Bergstrom	T.Bergstrom	1986-08-08	77	310	Utah	OG	70	IR	0	0	2013-09-14 23:48:03.87787	2013-09-14 23:48:03.877871	OAK
534	8d0e85c6-a77b-4e2c-97da-3ce6dbe34d34	1	Rashad Jennings	R.Jennings	1985-03-26	73	231	Liberty	RB	27	ACT	0	0	2013-09-14 23:48:03.879907	2013-09-14 23:48:03.879908	OAK
535	80eb851e-3b2c-4c0f-bf35-92e1ec91b013	1	Mychal Rivera	M.Rivera	1990-09-08	75	245	Tennessee	TE	81	ACT	0	0	2013-09-14 23:48:03.882056	2013-09-14 23:48:03.882056	OAK
536	6fbc9af8-1917-41b1-9d4c-1ccc73ed92aa	1	Jacoby Ford	J.Ford	1987-07-27	69	190	Clemson	WR	12	ACT	0	0	2013-09-14 23:48:03.883253	2013-09-14 23:48:03.883254	OAK
537	2214528d-0f8a-49bc-afd1-59d88d64f74b	1	David Ausberry	D.Ausberry	1987-09-25	76	258	USC	TE	86	ACT	0	0	2013-09-14 23:48:03.885217	2013-09-14 23:48:03.885218	OAK
538	52366445-a41d-4b7c-bd42-1ea4cb940695	1	Jared Veldheer	J.Veldheer	1987-06-14	80	321	Hillsdale	OT	68	ACT	0	0	2013-09-14 23:48:03.886599	2013-09-14 23:48:03.886599	OAK
539	578db999-6f6c-4b31-851c-9adb585e1c5a	1	Nick Kasa	N.Kasa	1990-11-05	78	265	Colorado	TE	88	ACT	0	0	2013-09-14 23:48:03.887746	2013-09-14 23:48:03.887747	OAK
540	ab502cd5-aafc-4a70-a715-1d4a4c9f8a83	1	Usama Young	U.Young	1985-05-08	72	200	Kent State	FS	26	ACT	0	0	2013-09-14 23:48:03.888943	2013-09-14 23:48:03.888944	OAK
541	ae7c8cbc-33e8-4b0c-bf01-6319aab3316f	1	Andre Gurode	A.Gurode	1979-03-06	76	320	Colorado	C	64	ACT	0	0	2013-09-14 23:48:03.890349	2013-09-14 23:48:03.89035	OAK
542	814418e3-4db9-4baa-8b48-f66264d6ba38	1	Marcel Reece	M.Reece	1985-06-23	73	255	Washington	FB	45	ACT	0	0	2013-09-14 23:48:03.891535	2013-09-14 23:48:03.891537	OAK
543	53e3389f-6db2-41d6-bddf-e1246cb776fb	1	Matt Flynn	M.Flynn	1985-06-20	74	230	LSU	QB	15	ACT	0	0	2013-09-14 23:48:03.893179	2013-09-14 23:48:03.893181	OAK
544	480277d1-47c9-44df-969e-038a84cd0fea	1	Sebastian Janikowski	S.Janikowski	1978-03-02	73	258	Florida State	K	11	ACT	0	0	2013-09-14 23:48:03.895004	2013-09-14 23:48:03.895005	OAK
545	c4c49249-3d52-4b7a-a111-0bf6e75c8ddc	1	Eddy Carmona	E.Carmona	1988-09-04	70	205	Harding	K	3	IR	0	0	2013-09-14 23:48:03.896203	2013-09-14 23:48:03.896204	OAK
546	663b69e5-1fc2-404b-9a3f-f153c650ee89	1	Matthew McGloin	M.McGloin	1989-12-02	73	210	Penn State	QB	14	ACT	0	0	2013-09-14 23:48:03.897533	2013-09-14 23:48:03.897534	OAK
547	a5bfdc4f-8f40-4b71-ae30-7283dce19238	1	Khalif Barnes	K.Barnes	1982-04-21	78	321	Washington	OT	69	ACT	0	0	2013-09-14 23:48:03.899191	2013-09-14 23:48:03.899192	OAK
548	97132012-53f4-44c8-96da-88f0e8a819e8	1	Darren McFadden	D.McFadden	1987-08-27	73	218	Arkansas	RB	20	ACT	0	0	2013-09-14 23:48:03.900886	2013-09-14 23:48:03.900888	OAK
549	4a6f5f02-fbdd-41f5-ac76-5bb9dc765307	1	Jeremy Stewart	J.Stewart	1989-02-17	71	215	Stanford	RB	32	ACT	0	0	2013-09-14 23:48:03.902512	2013-09-14 23:48:03.902514	OAK
550	DEF-OAK	1	OAK Defense	OAK		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:03.904088	2013-09-14 23:48:03.904089	OAK
551	34cc7f47-9f14-4661-b9af-c9d3b2fc873a	1	Charlie Whitehurst	C.Whitehurst	1982-08-06	77	226	Clemson	QB	6	ACT	0	0	2013-09-14 23:48:04.175369	2013-09-14 23:48:04.175372	SD
552	b2c89b10-76a0-422e-876a-db6b2968fd76	1	Ronnie Brown	R.Brown	1981-12-12	72	223	Auburn	RB	23	ACT	0	0	2013-09-14 23:48:04.178607	2013-09-14 23:48:04.178608	SD
553	82da09c2-e542-4f7d-87d9-24dfd8e014de	1	Antonio Gates	A.Gates	1980-06-18	76	255	Kent State	TE	85	ACT	0	0	2013-09-14 23:48:04.180857	2013-09-14 23:48:04.180857	SD
554	a3855ea8-e71c-4028-86fb-5a1abbd94488	1	D.J. Fluker	D.Fluker	1991-03-13	77	339	Alabama	T	76	ACT	0	0	2013-09-14 23:48:04.183121	2013-09-14 23:48:04.183123	SD
555	a1ce63c0-2a3f-4c9b-97bd-f9fe4f1ce940	1	Brandon Taylor	B.Taylor	1990-01-29	71	205	LSU	SS	28	ACT	0	0	2013-09-14 23:48:04.18554	2013-09-14 23:48:04.185542	SD
556	c66754c7-a259-4ebb-86d5-b3d68340ad18	1	Eddie Royal	E.Royal	1986-05-21	70	185	Virginia Tech	WR	11	ACT	0	0	2013-09-14 23:48:04.188007	2013-09-14 23:48:04.188009	SD
557	5759b58f-6d8b-4b62-96e2-ff894f39fa76	1	Nick Hardwick	N.Hardwick	1981-09-02	76	305	Purdue	C	61	ACT	0	0	2013-09-14 23:48:04.190928	2013-09-14 23:48:04.19093	SD
558	55200cbf-e475-44fa-a875-a51998c20457	1	Ryan Mathews	R.Mathews	1987-10-10	72	220	Fresno State	RB	24	ACT	0	0	2013-09-14 23:48:04.196438	2013-09-14 23:48:04.19644	SD
559	e005ee7b-3fb4-4219-8de3-a9b0302cb2dc	1	Jahleel Addae	J.Addae	1990-01-24	70	195	Central Michigan	SAF	37	ACT	0	0	2013-09-14 23:48:04.199738	2013-09-14 23:48:04.199741	SD
560	ca6654f0-e647-4dc1-9731-19f05a321659	1	Rich Ohrnberger	R.Ohrnberger	1986-02-14	74	300	Penn State	G	74	ACT	0	0	2013-09-14 23:48:04.203726	2013-09-14 23:48:04.203729	SD
561	44ac9500-8fd8-4512-a5af-d63bc00aea7f	1	Fozzy Whittaker	F.Whittaker	1989-02-02	70	202	Texas	RB	34	ACT	0	0	2013-09-14 23:48:04.207539	2013-09-14 23:48:04.207542	SD
562	7bc7f249-a2ed-4dd9-acd2-c223778955ad	1	Vincent Brown	V.Brown	1989-01-25	71	190	San Diego State	WR	86	ACT	0	0	2013-09-14 23:48:04.211541	2013-09-14 23:48:04.211546	SD
563	ed29a999-303a-454a-a696-2f43dcc23f0a	1	King Dunlap	K.Dunlap	1985-09-14	81	330	Auburn	OT	77	ACT	0	0	2013-09-14 23:48:04.215421	2013-09-14 23:48:04.215424	SD
564	23a08c82-042e-4289-bd39-97e8f030bfae	1	Seyi Ajirotutu	S.Ajirotutu	1987-06-12	75	215	Fresno State	WR	16	ACT	0	0	2013-09-14 23:48:04.219023	2013-09-14 23:48:04.219026	SD
565	26138e8b-b776-492a-9684-b1c07e51b25c	1	Eric Weddle	E.Weddle	1985-01-04	71	200	Utah	FS	32	ACT	0	0	2013-09-14 23:48:04.223164	2013-09-14 23:48:04.223166	SD
566	7ee060f9-4c69-4611-9d6d-3b139e06c82a	1	Ladarius Green	L.Green	1990-05-29	78	240	Louisiana-Lafayette	TE	89	ACT	0	0	2013-09-14 23:48:04.226842	2013-09-14 23:48:04.226844	SD
567	5f424505-f29f-433c-b3f2-1a143a04a010	1	Keenan Allen	K.Allen	1992-04-27	74	211	California	WR	13	ACT	0	0	2013-09-14 23:48:04.23015	2013-09-14 23:48:04.230152	SD
568	3eeebce7-5c47-48fb-a14d-5bef2aad61e2	1	Le'Ron McClain	L.McClain	1984-12-27	72	260	Alabama	RB	33	ACT	0	0	2013-09-14 23:48:04.234048	2013-09-14 23:48:04.23405	SD
569	7429eaaa-0124-4ba6-820b-60239387d5b1	1	Malcom Floyd	M.Floyd	1981-09-08	77	225	Wyoming	WR	80	ACT	0	0	2013-09-14 23:48:04.238028	2013-09-14 23:48:04.238031	SD
570	c6345d52-4a43-4bc2-80bb-d25480f10527	1	Brad Sorensen	B.Sorensen		77	230	Southern Utah	QB	4	ACT	0	0	2013-09-14 23:48:04.242499	2013-09-14 23:48:04.242502	SD
571	6a7c8fb3-2d21-4fc2-a2d5-bee1ab74f21b	1	Mike Harris	M.Harris	1988-12-05	77	318	UCLA	T	79	ACT	0	0	2013-09-14 23:48:04.24772	2013-09-14 23:48:04.247724	SD
572	b66acf1d-a43a-46af-bc51-7595c5add61b	1	Danny Woodhead	D.Woodhead	1985-01-25	68	200	Chadron State	RB	39	ACT	0	0	2013-09-14 23:48:04.252472	2013-09-14 23:48:04.252475	SD
573	c43cf6a1-8faa-4f95-aa2a-f1aac3ffe103	1	John Phillips	J.Phillips	1987-06-11	77	251	Virginia	TE	83	ACT	0	0	2013-09-14 23:48:04.256787	2013-09-14 23:48:04.256791	SD
574	837d7d6f-a00e-472a-8183-d706ed994cd5	1	Johnnie Troutman	J.Troutman	1987-11-11	76	330	Penn State	G	63	ACT	0	0	2013-09-14 23:48:04.258905	2013-09-14 23:48:04.258906	SD
575	e47706c7-e14d-41fb-b13b-83a835a1f3bc	1	Philip Rivers	P.Rivers	1981-12-08	77	228	North Carolina State	QB	17	ACT	0	0	2013-09-14 23:48:04.26161	2013-09-14 23:48:04.261612	SD
576	1b2e9ee4-d9d1-4059-9a88-dd75e97d3b27	1	Darrell Stuckey	D.Stuckey	1987-06-16	71	212	Kansas	SAF	25	ACT	0	0	2013-09-14 23:48:04.263978	2013-09-14 23:48:04.263979	SD
577	47cfc2a1-2b81-430e-8b30-ff5129e5c601	1	Nick Novak	N.Novak	1981-08-21	72	198	Maryland	K	9	ACT	0	0	2013-09-14 23:48:04.265303	2013-09-14 23:48:04.265304	SD
578	bf9f315d-49a8-4faf-98c1-410f6f85011b	1	Chad Rinehart	C.Rinehart	1985-05-04	77	321	Northern Iowa	G	78	ACT	0	0	2013-09-14 23:48:04.266505	2013-09-14 23:48:04.266505	SD
579	3ca67dd6-690c-43fe-b047-90dbfc76cbe5	1	Jeromey Clary	J.Clary	1983-11-05	78	320	Kansas State	OT	66	ACT	0	0	2013-09-14 23:48:04.267735	2013-09-14 23:48:04.267736	SD
580	5af8661e-c596-4651-b4e1-376e037ace21	1	Danario Alexander	D.Alexander	1988-08-07	77	217	Missouri	WR	84	IR	0	0	2013-09-14 23:48:04.268959	2013-09-14 23:48:04.26896	SD
581	DEF-SD	1	SD Defense	SD		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:04.270183	2013-09-14 23:48:04.270184	SD
582	bd10efdf-d8e7-4e23-ab1a-1e42fb65131b	1	Alfred Morris	A.Morris	1988-12-12	70	218	Florida Atlantic	RB	46	ACT	0	0	2013-09-14 23:48:04.537705	2013-09-14 23:48:04.537706	WAS
583	dfbf3f25-3c42-484e-8859-16b159c0146c	1	Phillip Thomas	P.Thomas	1989-03-01	72	208	Fresno State	SS	41	IR	0	0	2013-09-14 23:48:04.542433	2013-09-14 23:48:04.542435	WAS
584	a25feaa2-93f5-4236-9d07-696b371af3d6	1	Chris Chester	C.Chester	1983-01-12	75	309	Oklahoma	G	66	ACT	0	0	2013-09-14 23:48:04.546316	2013-09-14 23:48:04.546317	WAS
585	3c551b79-cd83-475b-924a-20c63c901947	1	Jordan Pugh	J.Pugh	1988-01-29	71	210	Texas A&M	SAF	32	ACT	0	0	2013-09-14 23:48:04.547557	2013-09-14 23:48:04.547557	WAS
586	f0fff5db-14db-45b8-8956-7f59b62c14b2	1	Dezmon Briscoe	D.Briscoe	1989-08-31	74	210	Kansas	WR	19	IR	0	0	2013-09-14 23:48:04.549029	2013-09-14 23:48:04.549032	WAS
587	8cef3644-bd81-4645-b5d0-0a15ea8d6548	1	Santana Moss	S.Moss	1979-06-01	70	189	Miami (FL)	WR	89	ACT	0	0	2013-09-14 23:48:04.551864	2013-09-14 23:48:04.551864	WAS
588	7f7b2a5a-be4e-40d1-9cd0-9a7dd225a8c0	1	Kory Lichtensteiger	K.Lichtensteiger	1985-03-22	74	284	Bowling Green State	G	78	ACT	0	0	2013-09-14 23:48:04.555507	2013-09-14 23:48:04.555509	WAS
589	1133c99a-972c-440e-a969-95c46565d033	1	Will Montgomery	W.Montgomery	1983-02-13	75	304	Virginia Tech	C	63	ACT	0	0	2013-09-14 23:48:04.558793	2013-09-14 23:48:04.558794	WAS
590	b070601c-7985-4a1c-b71a-9f72bb5dbc59	1	Trent Williams	T.Williams	1988-07-19	77	328	Oklahoma	OT	71	ACT	0	0	2013-09-14 23:48:04.561172	2013-09-14 23:48:04.561173	WAS
591	e174b76d-323a-41c5-be68-e766aa060d5c	1	Darrel Young	D.Young	1987-04-08	71	251	Villanova	FB	36	ACT	0	0	2013-09-14 23:48:04.563748	2013-09-14 23:48:04.563748	WAS
592	3dde6cbb-35f7-4618-91ac-d16d87ea7e70	1	Tanard Jackson	T.Jackson	1985-07-21	72	196	Syracuse	FS	34	SUS	0	0	2013-09-14 23:48:04.566078	2013-09-14 23:48:04.566082	WAS
593	7964133e-9987-4a74-a700-afe2dbe2a62a	1	Reed Doughty	R.Doughty	1982-11-04	73	206	Northern Colorado	SAF	37	ACT	0	0	2013-09-14 23:48:04.569296	2013-09-14 23:48:04.569296	WAS
594	8b5b9714-9533-4c7d-aa30-3ad3da3452aa	1	Rex Grossman	R.Grossman	1980-08-23	73	225	Florida	QB	8	ACT	0	0	2013-09-14 23:48:04.572311	2013-09-14 23:48:04.572312	WAS
595	38f5843a-8318-4eb7-b517-c83d415e77a4	1	Niles Paul	N.Paul	1989-08-09	73	233	Nebraska	WR	84	ACT	0	0	2013-09-14 23:48:04.574748	2013-09-14 23:48:04.574749	WAS
596	e461d721-5ca5-4896-8fe5-12e452a003b3	1	Josh Leribeus	J.Leribeus	1989-07-02	75	315	Southern Methodist	G	67	ACT	0	0	2013-09-14 23:48:04.577011	2013-09-14 23:48:04.577012	WAS
597	5514afb6-bd43-49a8-9bf7-b8baaaecdabe	1	Kai Forbath	K.Forbath	1987-09-02	71	197	UCLA	K	2	ACT	0	0	2013-09-14 23:48:04.579456	2013-09-14 23:48:04.579457	WAS
598	675c0338-159b-403b-8d62-39356e193519	1	Fred Davis	F.Davis	1986-01-15	76	247	USC	TE	83	ACT	0	0	2013-09-14 23:48:04.581925	2013-09-14 23:48:04.58193	WAS
599	32e4b488-5109-4186-963e-ce7907dfc9e1	1	Brandon Meriweather	B.Meriweather	1984-01-14	71	197	Miami (FL)	FS	31	ACT	0	0	2013-09-14 23:48:04.586381	2013-09-14 23:48:04.586384	WAS
600	bbd0942c-6f77-4f83-a6d0-66ec6548019e	1	Kirk Cousins	K.Cousins	1988-08-19	75	209	Michigan State	QB	12	ACT	0	0	2013-09-14 23:48:04.590654	2013-09-14 23:48:04.590656	WAS
601	455347a8-81f8-477b-908d-4e22a71723ae	1	Roy Helu	R.Helu	1988-12-07	71	215	Nebraska	RB	29	ACT	0	0	2013-09-14 23:48:04.59497	2013-09-14 23:48:04.594972	WAS
602	5f39061b-a32f-4b8a-b8d5-3e26afffd723	1	John Potter	J.Potter	1990-01-24	73	219	Western Michigan	K	1	ACT	0	0	2013-09-14 23:48:04.599093	2013-09-14 23:48:04.599095	WAS
603	9798d4cd-516f-4b1a-b388-cafe570db95b	1	Tyler Polumbus	T.Polumbus	1985-04-10	80	305	Colorado	OT	74	ACT	0	0	2013-09-14 23:48:04.603016	2013-09-14 23:48:04.603018	WAS
604	0cb97421-cccf-4cce-ac0f-92d47986defc	1	Adam Gettis	A.Gettis	1988-12-09	74	292	Iowa	G	73	ACT	0	0	2013-09-14 23:48:04.613249	2013-09-14 23:48:04.613253	WAS
605	81c637e8-8f81-4455-887c-9763f1d18b15	1	Bacarri Rambo	B.Rambo	1990-06-27	72	211	Georgia	SS	24	ACT	0	0	2013-09-14 23:48:04.617326	2013-09-14 23:48:04.617328	WAS
606	0366fd06-19a3-4b69-8448-6bfbfad1250b	1	Chris Thompson	C.Thompson	1990-10-20	67	192	Florida State	RB	25	ACT	0	0	2013-09-14 23:48:04.621151	2013-09-14 23:48:04.621154	WAS
607	ad83d795-455f-4f3e-bdad-bf4fa7b6eabc	1	Josh Morgan	J.Morgan	1985-06-20	73	220	Virginia Tech	WR	15	ACT	0	0	2013-09-14 23:48:04.624856	2013-09-14 23:48:04.624858	WAS
608	c3bf8d3e-3b2e-4f9e-ad74-c0a684035f17	1	Jordan Reed	J.Reed	1990-07-03	74	236	Florida	TE	86	ACT	0	0	2013-09-14 23:48:04.628556	2013-09-14 23:48:04.628558	WAS
609	8dfb370d-460c-4bfc-9d62-888687248783	1	Robert Griffin III	R.Griffin III	1990-02-12	74	217	Baylor	QB	10	ACT	0	0	2013-09-14 23:48:04.632538	2013-09-14 23:48:04.632541	WAS
610	1c1f0577-f9c7-4406-b2ab-b9e42ddb1af3	1	Tom Compton	T.Compton	1989-05-10	78	314	South Dakota	T	68	ACT	0	0	2013-09-14 23:48:04.636334	2013-09-14 23:48:04.636336	WAS
611	f60331a0-29ac-4cde-96c7-270154ff7d48	1	Evan Royster	E.Royster	1987-11-26	72	216	Penn State	RB	22	ACT	0	0	2013-09-14 23:48:04.640016	2013-09-14 23:48:04.640018	WAS
612	a824d9ff-12a4-4ed2-812d-404b0b4e52f9	1	Pierre Garcon	P.Garcon	1986-08-08	72	212	Mount Union	WR	88	ACT	0	0	2013-09-14 23:48:04.642724	2013-09-14 23:48:04.642725	WAS
613	34d11cb2-9493-47a3-8085-aee23542cc79	1	Jose Gumbs	J.Gumbs	1988-04-20	70	210	Monmouth (N.J.)	SAF	48	ACT	0	0	2013-09-14 23:48:04.643832	2013-09-14 23:48:04.643833	WAS
614	b030b668-0f41-484f-8e94-9fc576b8af63	1	Aldrick Robinson	A.Robinson	1988-09-24	70	181	Southern Methodist	WR	11	ACT	0	0	2013-09-14 23:48:04.644917	2013-09-14 23:48:04.644918	WAS
615	7fdb82e6-e6db-4314-820a-633351a8675a	1	Maurice Hurt	M.Hurt	1987-09-08	75	329	Florida	G	79	PUP	0	0	2013-09-14 23:48:04.646935	2013-09-14 23:48:04.646936	WAS
616	7877c393-beb4-4f40-a6c5-d864ca6e5172	1	Leonard Hankerson	L.Hankerson	1989-01-30	74	211	Miami (FL)	WR	85	ACT	0	0	2013-09-14 23:48:04.649488	2013-09-14 23:48:04.649491	WAS
617	518c96c5-65bb-4559-8074-9cdb2ca32f99	1	Logan Paulsen	L.Paulsen	1987-02-26	77	261	UCLA	TE	82	ACT	0	0	2013-09-14 23:48:04.652035	2013-09-14 23:48:04.652037	WAS
618	DEF-WAS	1	WAS Defense	WAS		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:04.654407	2013-09-14 23:48:04.65441	WAS
619	da7cb0cc-543e-47d5-b29a-2ba2b341bd14	1	Matt Barkley	M.Barkley	1990-09-08	74	227	USC	QB	2	ACT	0	0	2013-09-14 23:48:04.918819	2013-09-14 23:48:04.91882	PHI
620	d184bc5e-7221-463e-a5b4-08967489685c	1	Alex Henery	A.Henery	1987-08-18	73	177	Nebraska	K	6	ACT	0	0	2013-09-14 23:48:04.920306	2013-09-14 23:48:04.920306	PHI
621	f1cff356-8de9-4589-8522-40922fecfad7	1	Kurt Coleman	K.Coleman	1988-07-01	71	195	Ohio State	SAF	42	ACT	0	0	2013-09-14 23:48:04.921773	2013-09-14 23:48:04.921774	PHI
622	58ddefee-8abc-4421-856b-9bb72b0d202c	1	James Casey	J.Casey	1984-09-22	75	243	Rice	TE	85	ACT	0	0	2013-09-14 23:48:04.926038	2013-09-14 23:48:04.926039	PHI
623	21c07256-4cd8-4bf0-abcf-0d2682af2538	1	Allen Barbre	A.Barbre	1984-06-22	76	305	Missouri Southern State	OT	76	ACT	0	0	2013-09-14 23:48:04.929041	2013-09-14 23:48:04.929044	PHI
624	645a8bf9-2079-4df4-904a-3d8f08438b85	1	Brent Celek	B.Celek	1985-01-25	76	255	Cincinnati	TE	87	ACT	0	0	2013-09-14 23:48:04.931192	2013-09-14 23:48:04.931193	PHI
625	36bb2c46-33d3-4e86-bb12-63b658cf8f7f	1	Matt Tobin	M.Tobin	1990-06-05	78	290	Iowa	T	64	ACT	0	0	2013-09-14 23:48:04.932241	2013-09-14 23:48:04.932241	PHI
626	84dd5076-eeb2-4ec4-be37-43194b37b164	1	Julian Vandervelde	J.Vandervelde	1987-10-07	74	300	Iowa	G	61	ACT	0	0	2013-09-14 23:48:04.934712	2013-09-14 23:48:04.934713	PHI
627	b797d6fa-1520-4b3d-a212-157afd4a3bd0	1	Michael Vick	M.Vick	1980-06-26	72	215	Virginia Tech	QB	7	ACT	0	0	2013-09-14 23:48:04.936994	2013-09-14 23:48:04.936994	PHI
628	1306d6f4-5de3-4bec-9c86-3e5ab8e2d081	1	Dennis Kelly	D.Kelly	1990-01-16	80	321	Purdue	T	67	ACT	0	0	2013-09-14 23:48:04.938989	2013-09-14 23:48:04.938989	PHI
629	8971384e-c1b0-4c00-b464-48b429d0c9b7	1	Jeff Maehl	J.Maehl	1989-03-16	72	185	Oregon	WR	88	ACT	0	0	2013-09-14 23:48:04.941432	2013-09-14 23:48:04.941435	PHI
630	3d0f5d99-b488-42b1-b3a3-71778304fc47	1	Evan Mathis	E.Mathis	1981-11-01	77	302	Alabama	G	69	ACT	0	0	2013-09-14 23:48:04.943275	2013-09-14 23:48:04.943276	PHI
631	931650e1-49dd-4d38-a5e7-d45a11529d00	1	Jason Avant	J.Avant	1983-04-20	72	212	Michigan	WR	81	ACT	0	0	2013-09-14 23:48:04.944403	2013-09-14 23:48:04.944404	PHI
632	f2bbef7c-e87a-48bd-9418-576650842edd	1	Todd Herremans	T.Herremans	1982-10-13	78	321	Saginaw Valley State	T	79	ACT	0	0	2013-09-14 23:48:04.945477	2013-09-14 23:48:04.945477	PHI
633	075b9b42-4797-47c7-b21f-1500f6dbe96e	1	Damaris Johnson	D.Johnson	1989-11-22	68	175	Tulsa	WR	13	ACT	0	0	2013-09-14 23:48:04.946594	2013-09-14 23:48:04.946595	PHI
634	1d02b5a6-fe2e-4131-a9ab-6ed3558f4026	1	Jason Kelce	J.Kelce	1987-11-05	75	282	Cincinnati	C	62	ACT	0	0	2013-09-14 23:48:04.947707	2013-09-14 23:48:04.947708	PHI
635	8de6e793-6b06-41c1-91eb-ed0682455cd6	1	Arrelious Benn	A.Benn	1988-09-08	74	220	Illinois	WR	17	IR	0	0	2013-09-14 23:48:04.948909	2013-09-14 23:48:04.948909	PHI
636	0fe335a8-e061-4d48-9c3e-e5736fcd5a40	1	Bryce Brown	B.Brown	1991-05-14	72	223	Kansas State	RB	34	ACT	0	0	2013-09-14 23:48:04.950328	2013-09-14 23:48:04.950331	PHI
637	3e618eb6-41f2-4f20-ad70-2460f9366f43	1	DeSean Jackson	D.Jackson	1986-12-01	70	175	California	WR	10	ACT	0	0	2013-09-14 23:48:04.952799	2013-09-14 23:48:04.952801	PHI
638	3c57a63e-cdce-48ab-9dfc-66c6e809697c	1	Colt Anderson	C.Anderson	1985-10-25	70	194	Montana	SAF	30	ACT	0	0	2013-09-14 23:48:04.956187	2013-09-14 23:48:04.956192	PHI
639	5f05de83-f15d-42f1-8271-284ca54f63de	1	Jeremy Maclin	J.Maclin	1988-05-11	72	198	Missouri	WR	18	IR	0	0	2013-09-14 23:48:04.95941	2013-09-14 23:48:04.959411	PHI
640	64e89f8b-3e8f-4e07-bb73-c48f2a1dd8e2	1	Patrick Chung	P.Chung	1987-08-19	71	212	Oregon	SAF	23	ACT	0	0	2013-09-14 23:48:04.961279	2013-09-14 23:48:04.96128	PHI
641	f09abd01-9f5a-4f2c-ae39-55c2e613b114	1	Emil Igwenagu	E.Igwenagu	1989-03-27	74	245	Massachusetts	TE	82	ACT	0	0	2013-09-14 23:48:04.963528	2013-09-14 23:48:04.963532	PHI
642	c8232b55-6617-4dd9-a7cf-cf14cd9a29ab	1	Nick Foles	N.Foles	1989-01-20	78	243	Arizona	QB	9	ACT	0	0	2013-09-14 23:48:04.965837	2013-09-14 23:48:04.965838	PHI
643	166292fc-629e-4c7b-b7bf-f572ca9eeb43	1	LeSean McCoy	L.McCoy	1988-07-12	71	208	Pittsburgh	RB	25	ACT	0	0	2013-09-14 23:48:04.968474	2013-09-14 23:48:04.968477	PHI
644	3edf64e6-603b-4437-a3be-53fe030c6f56	1	Lane Johnson	L.Johnson	1990-05-08	78	303	Oklahoma	T	65	ACT	0	0	2013-09-14 23:48:04.971922	2013-09-14 23:48:04.971924	PHI
645	384dbb20-9765-4cfb-9384-8c062e14d47f	1	Riley Cooper	R.Cooper	1987-09-09	75	222	Florida	WR	14	ACT	0	0	2013-09-14 23:48:04.97539	2013-09-14 23:48:04.975393	PHI
646	de3421f7-2147-4835-89a5-724e87bad463	1	Zach Ertz	Z.Ertz	1990-11-10	77	249	Stanford	TE	86	ACT	0	0	2013-09-14 23:48:04.979117	2013-09-14 23:48:04.979119	PHI
647	80ced4c0-5edb-4632-aeae-942b1703c20c	1	Chris Polk	C.Polk	1989-12-16	71	222	Washington	RB	32	ACT	0	0	2013-09-14 23:48:04.982428	2013-09-14 23:48:04.98243	PHI
648	46aab8e6-3ca9-4213-a6cb-87db90786f6b	1	Jason Peters	J.Peters	1982-01-22	76	328	Arkansas	OT	71	ACT	0	0	2013-09-14 23:48:04.985945	2013-09-14 23:48:04.985947	PHI
649	e04051a6-8172-4135-b038-af99fb8cb486	1	Earl Wolff	E.Wolff		71	209	North Carolina State	SS	28	ACT	0	0	2013-09-14 23:48:04.989538	2013-09-14 23:48:04.98954	PHI
650	3f20dc71-e54d-469b-98db-53669c373cf6	1	Nate Allen	N.Allen	1987-11-30	73	210	South Florida	SAF	29	ACT	0	0	2013-09-14 23:48:04.993406	2013-09-14 23:48:04.993409	PHI
651	DEF-PHI	1	PHI Defense	PHI		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:05.001321	2013-09-14 23:48:05.001323	PHI
652	78876382-0752-4fe9-b6a6-a9a830df7312	1	Will Allen	W.Allen	1982-06-17	73	200	Ohio State	SAF	26	ACT	0	0	2013-09-14 23:48:05.283004	2013-09-14 23:48:05.283007	DAL
653	e290f4f4-b089-42a7-b17a-b57f3516d23e	1	Brian Waters	B.Waters	1977-02-18	75	320	North Texas	G	64	ACT	0	0	2013-09-14 23:48:05.287549	2013-09-14 23:48:05.287551	DAL
654	6e29f0a3-cdae-4841-9971-73a69d3bd4e1	1	Andre Smith	A.Smith	1988-09-26	77	267	Virginia Tech	TE	87	ACT	0	0	2013-09-14 23:48:05.291795	2013-09-14 23:48:05.291797	DAL
655	0d91e0a9-232f-4e27-b6a5-e7f7e1d3fc6c	1	Jermey Parnell	J.Parnell	1986-07-20	78	305	Mississippi	OT	78	ACT	0	0	2013-09-14 23:48:05.295618	2013-09-14 23:48:05.29562	DAL
656	62c8ee28-9301-4d5e-aacc-2b59698abe4b	1	Ryan Cook	R.Cook	1983-05-08	78	328	New Mexico	G	63	IR	0	0	2013-09-14 23:48:05.299635	2013-09-14 23:48:05.299638	DAL
657	beb64618-614c-49f7-a3aa-c0c75b7839ea	1	Dan Bailey	D.Bailey	1988-01-26	72	188	Oklahoma State	K	5	ACT	0	0	2013-09-14 23:48:05.303588	2013-09-14 23:48:05.303591	DAL
658	2768da89-2265-4e20-aafc-0261fca287bc	1	Darrion Weems	D.Weems	1988-09-11	77	302	Oregon	T	75	ACT	0	0	2013-09-14 23:48:05.307768	2013-09-14 23:48:05.30777	DAL
659	715a8a5c-7f1f-43ba-8d89-5a481735c85c	1	Phil Costa	P.Costa	1987-07-11	75	314	Maryland	C	67	ACT	0	0	2013-09-14 23:48:05.311317	2013-09-14 23:48:05.311319	DAL
660	b84fb536-9705-45a9-b652-92a33578ac48	1	Dez Bryant	D.Bryant	1988-11-04	74	218	Oklahoma State	WR	88	ACT	0	0	2013-09-14 23:48:05.315127	2013-09-14 23:48:05.315129	DAL
661	30a193de-13a3-4e22-a1a5-ce240f498280	1	Jeff Heath	J.Heath	1991-05-14	73	170	Saginaw Valley State	DB	38	ACT	0	0	2013-09-14 23:48:05.318635	2013-09-14 23:48:05.318637	DAL
662	f4ebaa64-aebe-4a32-b11e-f4f47f511770	1	J.J. Wilcox	J.Wilcox	1991-02-14	72	213	Georgia Southern	FS	27	ACT	0	0	2013-09-14 23:48:05.322619	2013-09-14 23:48:05.322622	DAL
663	478ae115-d220-424e-af45-56137f163d3a	1	DeMarco Murray	D.Murray	1988-02-12	72	215	Oklahoma	RB	29	ACT	0	0	2013-09-14 23:48:05.326564	2013-09-14 23:48:05.326566	DAL
664	dea8f688-602c-4b48-946f-e634fb81d737	1	Travis Frederick	T.Frederick	1991-01-01	76	312	Wisconsin	C	72	ACT	0	0	2013-09-14 23:48:05.330208	2013-09-14 23:48:05.33021	DAL
665	9f0f0495-b5b8-45c2-866b-02d9f96087f7	1	Lance Dunbar	L.Dunbar	1990-01-25	68	191	North Texas	RB	25	ACT	0	0	2013-09-14 23:48:05.333637	2013-09-14 23:48:05.33364	DAL
666	e38c9b1b-7c51-48a2-ac1d-a752502e8930	1	Jason Witten	J.Witten	1982-05-06	77	265	Tennessee	TE	82	ACT	0	0	2013-09-14 23:48:05.337377	2013-09-14 23:48:05.337379	DAL
667	c3f2ea91-98d6-4d37-b5bd-3c7ac07e5b24	1	Tyron Smith	T.Smith	1990-12-12	77	308	USC	T	77	ACT	0	0	2013-09-14 23:48:05.340922	2013-09-14 23:48:05.340925	DAL
668	dcb30c96-f1de-44be-9ef6-4b967d17eb30	1	Joseph Randle	J.Randle	1991-12-29	72	204	Oklahoma State	RB	35	ACT	0	0	2013-09-14 23:48:05.344458	2013-09-14 23:48:05.344461	DAL
669	d688ad2a-0c21-4749-99c6-4e6da588e6a8	1	James Hanna	J.Hanna	1989-07-14	76	249	Oklahoma	TE	84	ACT	0	0	2013-09-14 23:48:05.347983	2013-09-14 23:48:05.347985	DAL
670	7092bb09-a161-4ab9-8d19-fdcf1a91bb3d	1	Cole Beasley	C.Beasley	1989-04-26	68	177	Southern Methodist	WR	11	ACT	0	0	2013-09-14 23:48:05.351844	2013-09-14 23:48:05.351846	DAL
671	e210223b-fd36-4cc2-a5e3-16578ea0d17d	1	Danny McCray	D.McCray	1988-03-10	73	222	LSU	SAF	40	ACT	0	0	2013-09-14 23:48:05.355492	2013-09-14 23:48:05.355495	DAL
672	e2bcd797-862d-4c38-abc3-267fc4d555e2	1	Phillip Tanner	P.Tanner	1988-08-08	72	218	Middle Tennessee State	RB	34	ACT	0	0	2013-09-14 23:48:05.359031	2013-09-14 23:48:05.359036	DAL
673	c32d8200-2b85-4638-8db3-9a52fb86b207	1	Tony Romo	T.Romo	1980-04-21	74	230	Eastern Illinois	QB	9	ACT	0	0	2013-09-14 23:48:05.362902	2013-09-14 23:48:05.362905	DAL
674	1b51ed47-793f-43ef-8776-dd2823ab427e	1	Matt Johnson	M.Johnson	1989-07-22	73	215	Eastern Washington	SAF	37	IR	0	0	2013-09-14 23:48:05.366627	2013-09-14 23:48:05.366629	DAL
675	ef068d71-d18f-4b67-a7b4-71c416a14cba	1	Kyle Orton	K.Orton	1982-11-14	76	225	Purdue	QB	18	ACT	0	0	2013-09-14 23:48:05.370107	2013-09-14 23:48:05.370111	DAL
676	acf68a6a-3439-4ad6-8937-2562f4eba62b	1	Miles Austin	M.Austin	1984-06-30	74	215	Monmouth (NJ)	WR	19	ACT	0	0	2013-09-14 23:48:05.373871	2013-09-14 23:48:05.373873	DAL
677	3c2db5b7-77bf-4c52-bb77-b0fe3cf89e5e	1	Terrance Williams	T.Williams	1989-09-18	74	208	Baylor	WR	83	ACT	0	0	2013-09-14 23:48:05.37767	2013-09-14 23:48:05.377672	DAL
678	ad9a6262-7df3-41a8-9753-b89866f5cd0e	1	Barry Church	B.Church	1988-02-11	74	220	Toledo	SAF	42	ACT	0	0	2013-09-14 23:48:05.38118	2013-09-14 23:48:05.381182	DAL
679	1d127c62-d7f3-4fe5-b30d-9b7a9cef6637	1	Ronald Leary	R.Leary	1989-04-29	75	324	Memphis	T	65	ACT	0	0	2013-09-14 23:48:05.384789	2013-09-14 23:48:05.384792	DAL
680	e14a4c78-9a55-4d84-ab7c-d9c7121a6ae1	1	David Arkin	D.Arkin	1987-10-07	76	306	Missouri State	G	62	ACT	0	0	2013-09-14 23:48:05.388412	2013-09-14 23:48:05.388414	DAL
681	433587a5-dabc-4b1b-9545-66e570f806a7	1	Gavin Escobar	G.Escobar	1991-02-03	78	254	San Diego State	TE	89	ACT	0	0	2013-09-14 23:48:05.391856	2013-09-14 23:48:05.391858	DAL
682	477d9f2f-b570-4f66-aa0b-1d83943b5ea5	1	Jeff Olson	J.Olson		76	300	TCU	OG	69	IR	0	0	2013-09-14 23:48:05.395222	2013-09-14 23:48:05.395224	DAL
683	b3eadf6a-2c55-4b53-b5be-74fdb6700627	1	Doug Free	D.Free	1984-01-06	78	323	Northern Illinois	OT	68	ACT	0	0	2013-09-14 23:48:05.398925	2013-09-14 23:48:05.398927	DAL
684	5ed2cea8-e0c6-482c-9ee1-548c06612226	1	Dwayne Harris	D.Harris	1987-09-16	70	200	East Carolina	WR	17	ACT	0	0	2013-09-14 23:48:05.403038	2013-09-14 23:48:05.403041	DAL
685	8720973c-9bde-4e66-a88e-66e933a99683	1	Mackenzy Bernadeau	M.Bernadeau	1986-01-03	76	320	Bentley	G	73	ACT	0	0	2013-09-14 23:48:05.406516	2013-09-14 23:48:05.406518	DAL
686	DEF-DAL	1	DAL Defense	DAL		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:05.410175	2013-09-14 23:48:05.410177	DAL
687	a230a959-4fba-43cd-92a0-6552766c2bbf	1	David Wilson	D.Wilson	1991-06-15	70	205	Virginia Tech	RB	22	ACT	0	0	2013-09-14 23:48:05.691555	2013-09-14 23:48:05.691556	NYG
688	ab4ae658-8c63-4af9-b6a8-0741bcbae5a9	1	Will Beatty	W.Beatty	1985-03-02	78	319	Connecticut	OT	65	ACT	0	0	2013-09-14 23:48:05.693123	2013-09-14 23:48:05.693123	NYG
689	51545c6d-3132-4477-8f51-df5c29ed971e	1	Victor Cruz	V.Cruz	1986-11-11	72	204	Massachusetts	WR	80	ACT	0	0	2013-09-14 23:48:05.694779	2013-09-14 23:48:05.69478	NYG
690	b8425853-7426-4ac1-bc1b-4978d6c8e684	1	Jim Cordle	J.Cordle	1987-08-22	75	320	Ohio State	C	63	ACT	0	0	2013-09-14 23:48:05.69781	2013-09-14 23:48:05.697867	NYG
691	a407f190-fe42-4f3d-b73d-1a922d388915	1	Curtis Painter	C.Painter	1985-06-24	76	230	Purdue	QB	17	ACT	0	0	2013-09-14 23:48:05.7021	2013-09-14 23:48:05.702102	NYG
692	89fab76c-282e-4bd9-b281-8603da9f8424	1	Louis Murphy	L.Murphy	1987-05-11	74	200	Florida	WR	18	ACT	0	0	2013-09-14 23:48:05.70527	2013-09-14 23:48:05.705271	NYG
693	9e207df9-c9d2-405b-b70f-782fc8ba1c8e	1	Will Hill	W.Hill	1990-03-07	73	207	Florida	DB	25	SUS	0	0	2013-09-14 23:48:05.70821	2013-09-14 23:48:05.708213	NYG
694	4177c51b-e802-4c8a-bbe8-ca444ecd847e	1	David Diehl	D.Diehl	1980-09-15	77	304	Illinois	OT	66	ACT	0	0	2013-09-14 23:48:05.711496	2013-09-14 23:48:05.711499	NYG
695	6c218456-f94f-4235-b21a-8ffd87c82949	1	Larry Donnell	L.Donnell	1988-11-01	78	269	Grambling State	TE	84	ACT	0	0	2013-09-14 23:48:05.715054	2013-09-14 23:48:05.715058	NYG
696	2cb0ddf8-32c3-415b-bd23-2d6c56e76100	1	Brandon Myers	B.Myers	1985-09-04	76	250	Iowa	TE	83	ACT	0	0	2013-09-14 23:48:05.719114	2013-09-14 23:48:05.719117	NYG
697	fa11008e-e199-4bbb-a440-7874bd6e3f3e	1	James Brewer	J.Brewer	1987-12-23	78	330	Indiana	T	73	ACT	0	0	2013-09-14 23:48:05.723063	2013-09-14 23:48:05.723066	NYG
698	f5e1f35d-9f17-4890-964c-396e76ae0d31	1	Josh Brown	J.Brown	1979-04-29	72	202	Nebraska	K	3	ACT	0	0	2013-09-14 23:48:05.727161	2013-09-14 23:48:05.727163	NYG
699	a68521b6-cdfc-4a31-b4fa-ecb3c8eeb390	1	Jerrel Jernigan	J.Jernigan	1989-06-14	68	189	Troy	WR	12	ACT	0	0	2013-09-14 23:48:05.73092	2013-09-14 23:48:05.730922	NYG
700	6cb6226e-f08c-4192-95f1-69709ed686c6	1	Eli Manning	E.Manning	1981-01-03	76	218	Mississippi	QB	10	ACT	0	0	2013-09-14 23:48:05.734823	2013-09-14 23:48:05.734825	NYG
701	23d7cd82-d526-4fd8-8f8a-97885f2bc926	1	Hakeem Nicks	H.Nicks	1988-01-14	73	210	North Carolina	WR	88	ACT	0	0	2013-09-14 23:48:05.738814	2013-09-14 23:48:05.738817	NYG
702	0d32975b-1c83-43c0-8232-d57b8f092390	1	Brandon Jacobs	B.Jacobs	1982-07-06	76	264	Southern Illinois	RB	34	ACT	0	0	2013-09-14 23:48:05.742442	2013-09-14 23:48:05.742444	NYG
703	56223a1a-cf12-473c-8f54-2f3f3fab579d	1	Rueben Randle	R.Randle	1991-05-07	74	208	LSU	WR	82	ACT	0	0	2013-09-14 23:48:05.745748	2013-09-14 23:48:05.74575	NYG
704	08d08fda-f75f-48cc-9927-ae68a4ec2e64	1	Kevin Boothe	K.Boothe	1983-07-05	77	320	Cornell	G	77	ACT	0	0	2013-09-14 23:48:05.749513	2013-09-14 23:48:05.749516	NYG
705	b6fe2eb8-3692-450a-98b3-11e47c8b6711	1	Justin Pugh	J.Pugh		76	307	Syracuse	T	72	ACT	0	0	2013-09-14 23:48:05.75343	2013-09-14 23:48:05.753433	NYG
706	fe74dd16-c439-4cf9-89c2-958929fb6fa8	1	Bear Pascoe	B.Pascoe	1986-02-23	77	283	Fresno State	TE	86	ACT	0	0	2013-09-14 23:48:05.757026	2013-09-14 23:48:05.757029	NYG
707	ff6f5ff1-e368-4869-bf6a-22087f27ee9f	1	Chris Snee	C.Snee	1982-01-18	75	305	Boston College	G	76	ACT	0	0	2013-09-14 23:48:05.760807	2013-09-14 23:48:05.760809	NYG
708	53747116-98f0-4405-91da-f25b1d938813	1	Andre Brown	A.Brown	1986-12-15	72	227	North Carolina State	RB	35	IR	0	0	2013-09-14 23:48:05.765029	2013-09-14 23:48:05.765031	NYG
709	ebd852f5-2c94-4db4-aa1d-d13c6beb9ec1	1	Ryan Mundy	R.Mundy	1985-02-11	73	209	West Virginia	FS	21	ACT	0	0	2013-09-14 23:48:05.76883	2013-09-14 23:48:05.768832	NYG
710	6c6de94b-4a6b-4a6d-9f6b-837022e99c02	1	Michael Cox	M.Cox	1988-11-14	73	214	Massachusetts	RB	29	ACT	0	0	2013-09-14 23:48:05.772351	2013-09-14 23:48:05.772353	NYG
711	3dc5943d-8e34-45f0-92da-7889641d1c74	1	Brandon Mosley	B.Mosley	1988-12-21	77	318	Auburn	T	67	ACT	0	0	2013-09-14 23:48:05.775949	2013-09-14 23:48:05.775953	NYG
712	9b6f28b0-7329-495b-a0a5-6c5fb975a057	1	Da'Rel Scott	D.Scott	1988-05-26	71	208	Maryland	RB	33	ACT	0	0	2013-09-14 23:48:05.779683	2013-09-14 23:48:05.779685	NYG
713	f8762994-f688-4fba-9efe-95504972ad69	1	Adrien Robinson	A.Robinson	1988-09-23	76	264	Cincinnati	TE	81	ACT	0	0	2013-09-14 23:48:05.783345	2013-09-14 23:48:05.783347	NYG
714	5cc16769-2495-4aca-b2d8-22f999238846	1	Stevie Brown	S.Brown	1987-07-17	71	221	Michigan	DB	27	IR	0	0	2013-09-14 23:48:05.786921	2013-09-14 23:48:05.786923	NYG
715	cb6e47f1-ace7-44c7-893e-1d6d37fc46bd	1	Ryan Nassib	R.Nassib	1990-03-10	74	227	Syracuse	QB	9	ACT	0	0	2013-09-14 23:48:05.790743	2013-09-14 23:48:05.790745	NYG
716	54a60e5b-3a55-4381-a2a8-3063795d5070	1	David Baas	D.Baas	1981-09-28	76	312	Michigan	C	64	ACT	0	0	2013-09-14 23:48:05.79421	2013-09-14 23:48:05.794212	NYG
717	bea4b40e-a963-4e48-97b1-8e3ac61c0624	1	Cooper Taylor	C.Taylor	1990-04-04	76	228	Richmond	SAF	30	ACT	0	0	2013-09-14 23:48:05.79756	2013-09-14 23:48:05.797562	NYG
718	84d8e40d-8123-4c0e-a3c1-3d86013d48c9	1	Antrel Rolle	A.Rolle	1982-12-16	72	206	Miami (FL)	SAF	26	ACT	0	0	2013-09-14 23:48:05.800979	2013-09-14 23:48:05.800981	NYG
719	d3ed4b39-7858-405d-b021-348bd57832dd	1	Henry Hynoski	H.Hynoski	1988-12-30	73	266	Pittsburgh	RB	45	ACT	0	0	2013-09-14 23:48:05.804287	2013-09-14 23:48:05.804288	NYG
720	DEF-NYG	1	NYG Defense	NYG		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:05.807894	2013-09-14 23:48:05.807897	NYG
721	8365cba5-5a5d-49da-8423-92a48d5f4880	1	DeJon Gomes	D.Gomes	1989-11-17	72	201	Nebraska	SAF	24	ACT	0	0	2013-09-14 23:48:06.102071	2013-09-14 23:48:06.102074	DET
722	4c77f50b-99e5-4d40-bb2f-f648880cb05f	1	Patrick Edwards	P.Edwards	1988-10-25	69	175	Houston	WR	83	ACT	0	0	2013-09-14 23:48:06.106794	2013-09-14 23:48:06.106796	DET
723	72a4593f-3cd3-4d70-899c-325d7df3c794	1	John Wendling	J.Wendling	1983-06-04	73	222	Wyoming	SAF	29	ACT	0	0	2013-09-14 23:48:06.111345	2013-09-14 23:48:06.111348	DET
724	8259ba2b-d4ae-4290-964f-903fa09b1c4f	1	David Akers	D.Akers	1974-12-09	70	200	Louisville	K	2	ACT	0	0	2013-09-14 23:48:06.115595	2013-09-14 23:48:06.115598	DET
725	b0368b8c-023f-4d85-ab53-3a5740d6ce99	1	Michael Williams	M.Williams	1990-09-20	77	278	Alabama	TE	89	IR	0	0	2013-09-14 23:48:06.118616	2013-09-14 23:48:06.118617	DET
726	52b14c80-ffc5-4fd6-9a32-d07b261f0841	1	Shaun Hill	S.Hill	1980-01-09	75	220	Maryland	QB	14	ACT	0	0	2013-09-14 23:48:06.119819	2013-09-14 23:48:06.11982	DET
727	8048bdd1-62cf-4d01-8257-741a585dae8e	1	Riley Reiff	R.Reiff	1988-12-01	78	313	Iowa	OT	71	ACT	0	0	2013-09-14 23:48:06.121185	2013-09-14 23:48:06.121186	DET
728	737b3cc8-9def-4ecc-b1f2-b7c1037b3fde	1	Corey Hilliard	C.Hilliard	1985-04-26	78	300	Oklahoma State	OT	78	ACT	0	0	2013-09-14 23:48:06.122463	2013-09-14 23:48:06.122464	DET
729	10705556-cdb5-4b20-a26a-d1b48bcaf51b	1	Dominic Raiola	D.Raiola	1978-12-30	73	295	Nebraska	C	51	ACT	0	0	2013-09-14 23:48:06.123638	2013-09-14 23:48:06.123638	DET
730	742a4673-9df8-4a79-938f-edef65087075	1	Kellen Moore	K.Moore	1989-07-12	72	197	Boise State	QB	17	ACT	0	0	2013-09-14 23:48:06.124837	2013-09-14 23:48:06.124837	DET
731	7d35421a-f68b-4de2-8152-d5830f5cca3e	1	Louis Delmas	L.Delmas	1987-04-12	71	202	Western Michigan	SAF	26	ACT	0	0	2013-09-14 23:48:06.126122	2013-09-14 23:48:06.126123	DET
732	2c56748d-6e13-495c-bec2-de67a8683fa0	1	Calvin Johnson	C.Johnson	1985-09-29	77	236	Georgia Tech	WR	81	ACT	0	0	2013-09-14 23:48:06.127368	2013-09-14 23:48:06.127369	DET
733	fdb9ea3f-04d0-4151-a255-4e087d3467f5	1	Montell Owens	M.Owens	1984-05-04	70	225	Maine	RB	34	IR	0	0	2013-09-14 23:48:06.128568	2013-09-14 23:48:06.128569	DET
734	c2ad11c2-4b7f-4964-bfe1-043974d06e3a	1	Rob Sims	R.Sims	1983-12-06	75	312	Ohio State	G	67	ACT	0	0	2013-09-14 23:48:06.131132	2013-09-14 23:48:06.131132	DET
735	62d4e94c-443f-44ed-9404-c6d6bdd9aa64	1	Theo Riddick	T.Riddick	1991-05-04	70	201	Notre Dame	RB	41	ACT	0	0	2013-09-14 23:48:06.132368	2013-09-14 23:48:06.132368	DET
736	3583d71d-db14-49d3-a9ec-6ee9f49a2693	1	Tony Scheffler	T.Scheffler	1983-02-15	77	255	Western Michigan	TE	85	ACT	0	0	2013-09-14 23:48:06.133607	2013-09-14 23:48:06.133608	DET
737	c0cb57ed-b7dc-470a-8769-c161dad25de6	1	Don Carey	D.Carey	1987-02-14	71	192	Norfolk State	SAF	32	ACT	0	0	2013-09-14 23:48:06.134949	2013-09-14 23:48:06.13495	DET
738	4625f808-72d9-47b7-b645-1df3723ef24b	1	Mikel Leshoure	M.Leshoure	1990-03-30	72	227	Illinois	RB	25	ACT	0	0	2013-09-14 23:48:06.136306	2013-09-14 23:48:06.136307	DET
739	2a678c7f-2dd9-4be2-9636-b4ff2b267402	1	Joseph Fauria	J.Fauria	1990-01-16	79	255	UCLA	TE	80	ACT	0	0	2013-09-14 23:48:06.137544	2013-09-14 23:48:06.137544	DET
740	a84c6342-3333-4af7-bf29-ea954e156835	1	Ryan Broyles	R.Broyles	1988-04-09	70	188	Oklahoma	WR	84	ACT	0	0	2013-09-14 23:48:06.13879	2013-09-14 23:48:06.138791	DET
741	1bedceda-238d-4943-ad4e-6ba8d1ae0449	1	Kris Durham	K.Durham	1988-03-17	78	216	Georgia	WR	18	ACT	0	0	2013-09-14 23:48:06.139991	2013-09-14 23:48:06.139992	DET
742	be9c9570-0c2f-4ea8-bcd4-cf298b7f14a8	1	Joique Bell	J.Bell	1986-08-04	71	220	Wayne State (Mich.)	RB	35	ACT	0	0	2013-09-14 23:48:06.142736	2013-09-14 23:48:06.142737	DET
743	f4f9983e-2334-4c10-afac-449ea4e83a90	1	Micheal Spurlock	M.Spurlock	1983-01-31	71	200	Mississippi	WR	15	ACT	0	0	2013-09-14 23:48:06.145596	2013-09-14 23:48:06.145596	DET
744	12d0402f-2d7d-4934-8c83-1a9b51bdb68b	1	Dylan Gandy	D.Gandy	1982-03-08	75	295	Texas Tech	G	65	ACT	0	0	2013-09-14 23:48:06.148034	2013-09-14 23:48:06.148035	DET
745	ada19a02-e5e2-4294-ab0a-7716893a7e65	1	Brandon Pettigrew	B.Pettigrew	1985-02-23	77	265	Oklahoma State	TE	87	ACT	0	0	2013-09-14 23:48:06.150327	2013-09-14 23:48:06.150327	DET
746	8d9cf581-fb97-448a-a0de-b4dd41927bc8	1	Jason Fox	J.Fox	1988-05-02	79	303	Miami (FL)	OT	70	ACT	0	0	2013-09-14 23:48:06.152872	2013-09-14 23:48:06.152872	DET
747	d54a562d-0571-4960-a903-6e98415ead6a	1	Larry Warford	L.Warford	1991-06-18	75	332	Kentucky	G	75	ACT	0	0	2013-09-14 23:48:06.15544	2013-09-14 23:48:06.155441	DET
748	3a654db7-46c2-4fe0-9f3a-98984e48a3b3	1	Leroy Harris	L.Harris	1984-06-06	75	303	North Carolina State	G	64	ACT	0	0	2013-09-14 23:48:06.157863	2013-09-14 23:48:06.157864	DET
749	adc1b9ae-0b59-4399-bfba-959f694dde3d	1	Glover Quin	G.Quin	1986-01-15	72	209	New Mexico	SS	27	ACT	0	0	2013-09-14 23:48:06.16156	2013-09-14 23:48:06.161562	DET
750	0acdcd3b-5442-4311-a139-ae7c506faf88	1	Reggie Bush	R.Bush	1985-03-02	72	203	USC	RB	21	ACT	0	0	2013-09-14 23:48:06.165499	2013-09-14 23:48:06.165501	DET
751	a3365ad4-f2cd-4342-9488-146e44aa9d18	1	Nate Burleson	N.Burleson	1981-08-19	72	198	Nevada-Reno	WR	13	ACT	0	0	2013-09-14 23:48:06.169144	2013-09-14 23:48:06.169148	DET
752	ade43b1a-0601-4672-83b6-d246bc066a19	1	Matthew Stafford	M.Stafford	1988-02-07	75	232	Georgia	QB	9	ACT	0	0	2013-09-14 23:48:06.17373	2013-09-14 23:48:06.173733	DET
753	45039bcf-634a-48a7-8102-f0131491cf66	1	LaAdrian Waddle	L.Waddle	1991-07-21	78	332	Texas Tech	T	66	ACT	0	0	2013-09-14 23:48:06.178048	2013-09-14 23:48:06.178052	DET
754	DEF-DET	1	DET Defense	DET		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:06.182483	2013-09-14 23:48:06.182486	DET
755	d4ace3ac-094b-4a3d-b526-9962c8b90bc8	1	Dante Rosario	D.Rosario	1984-10-25	76	242	Oregon	TE	88	ACT	0	0	2013-09-14 23:48:06.498491	2013-09-14 23:48:06.498495	CHI
756	5c529c33-8a1d-413a-b635-880ac86f30c1	1	Alshon Jeffery	A.Jeffery	1990-02-14	75	216	South Carolina	WR	17	ACT	0	0	2013-09-14 23:48:06.502922	2013-09-14 23:48:06.502924	CHI
757	b018cbb8-78e3-4532-bed8-15b872d46b9a	1	Anthony Walters	A.Walters	1988-09-19	73	207	Delaware	SAF	37	ACT	0	0	2013-09-14 23:48:06.507074	2013-09-14 23:48:06.507076	CHI
758	dbdd3f14-29a4-4060-a04e-2af906eaab8b	1	Taylor Boggs	T.Boggs	1987-02-20	75	285	Humboldt State	C	60	ACT	0	0	2013-09-14 23:48:06.511039	2013-09-14 23:48:06.511042	CHI
759	bbca096b-fd15-498a-86c2-feb44737363f	1	Brandon Marshall	B.Marshall	1984-03-23	76	230	Central Florida	WR	15	ACT	0	0	2013-09-14 23:48:06.514516	2013-09-14 23:48:06.514518	CHI
760	c10e08b6-33a7-4233-8628-29b40d1183ea	1	Chris Conte	C.Conte	1989-02-23	74	203	California	FS	47	ACT	0	0	2013-09-14 23:48:06.518094	2013-09-14 23:48:06.518097	CHI
761	eb20eb69-4290-4a6f-b588-aa91d8f55fec	1	James Brown	J.Brown	1988-11-30	76	306	Troy	T	78	ACT	0	0	2013-09-14 23:48:06.521955	2013-09-14 23:48:06.521958	CHI
762	be9c22d3-26ee-41b9-bb27-0a6b78cd4c32	1	Major Wright	M.Wright	1988-07-01	71	204	Florida	SAF	21	ACT	0	0	2013-09-14 23:48:06.525869	2013-09-14 23:48:06.525873	CHI
763	87935190-fa32-488f-b2a1-daa9b9ce1496	1	Michael Bush	M.Bush	1984-06-16	73	245	Louisville	RB	29	ACT	0	0	2013-09-14 23:48:06.529971	2013-09-14 23:48:06.529973	CHI
764	1a5a14e3-0299-4926-b232-a0a109a5f5db	1	Eric Weems	E.Weems	1985-07-04	69	195	Bethune-Cookman	WR	14	ACT	0	0	2013-09-14 23:48:06.534561	2013-09-14 23:48:06.534563	CHI
765	2e163812-31e4-42be-a724-3ab919caf782	1	Michael Ford	M.Ford	1990-05-27	69	210	LSU	RB	32	ACT	0	0	2013-09-14 23:48:06.53867	2013-09-14 23:48:06.538672	CHI
766	abd73d50-ce60-47f1-b37f-2f9a05b0d7b9	1	Robbie Gould	R.Gould	1981-12-30	72	185	Penn State	K	9	ACT	0	0	2013-09-14 23:48:06.54219	2013-09-14 23:48:06.542192	CHI
767	667fb823-5d18-48df-8628-d53986903b83	1	Eben Britton	E.Britton	1987-10-14	78	308	Arizona	OL	62	ACT	0	0	2013-09-14 23:48:06.546016	2013-09-14 23:48:06.546018	CHI
768	8e6af99d-a697-4be5-ae7f-f1ddc12bd15a	1	Kyle Long	K.Long	1988-12-05	78	313	Oregon	G	75	ACT	0	0	2013-09-14 23:48:06.549549	2013-09-14 23:48:06.549551	CHI
769	315b3789-a2ab-46ca-a9ce-097132d880e0	1	Roberto Garza	R.Garza	1979-03-26	74	310	Texas A&M-Kingsville	G	63	ACT	0	0	2013-09-14 23:48:06.553393	2013-09-14 23:48:06.553395	CHI
770	a261fd0a-b096-4db7-bd51-2f13bde485da	1	Josh McCown	J.McCown	1979-07-04	76	213	Sam Houston State	QB	12	ACT	0	0	2013-09-14 23:48:06.557359	2013-09-14 23:48:06.557362	CHI
771	2a884429-364b-430b-919e-f8547053404b	1	Devin Hester	D.Hester	1982-11-04	71	190	Miami (FL)	WR	23	ACT	0	0	2013-09-14 23:48:06.561067	2013-09-14 23:48:06.561069	CHI
772	ecd3bc0f-04dd-4945-9454-3fc4722fa5a8	1	Jay Cutler	J.Cutler	1983-04-29	75	220	Vanderbilt	QB	6	ACT	0	0	2013-09-14 23:48:06.565051	2013-09-14 23:48:06.565054	CHI
773	a4970b66-6eea-4d9a-9f96-15b528161b57	1	Matt Forte	M.Forte	1985-12-10	74	218	Tulane	RB	22	ACT	0	0	2013-09-14 23:48:06.569298	2013-09-14 23:48:06.5693	CHI
774	9ba25753-6af9-4ce9-a1b1-5dd4e720733f	1	Craig Steltz	C.Steltz	1986-05-07	73	210	LSU	SAF	20	ACT	0	0	2013-09-14 23:48:06.57364	2013-09-14 23:48:06.573643	CHI
775	5fbfe48a-11ee-4141-8f8d-6bef67d3ea69	1	Matt Slauson	M.Slauson	1986-02-18	77	315	Nebraska	G	68	ACT	0	0	2013-09-14 23:48:06.577628	2013-09-14 23:48:06.577632	CHI
776	4c189482-0d32-4145-a819-d7267a1ee1c2	1	Jonathan Scott	J.Scott	1983-01-10	78	318	Texas	OT	0	ACT	0	0	2013-09-14 23:48:06.581184	2013-09-14 23:48:06.581188	CHI
777	d8fe880c-a9d8-4041-ac0f-4626bb2a23dd	1	Marquess Wilson	M.Wilson	1992-09-14	75	194	Washington State	WR	10	ACT	0	0	2013-09-14 23:48:06.585451	2013-09-14 23:48:06.585454	CHI
778	357595e6-58ea-4688-824e-8056df67b503	1	Joe Anderson	J.Anderson	1988-11-21	73	196	Texas Southern	WR	19	ACT	0	0	2013-09-14 23:48:06.589103	2013-09-14 23:48:06.589106	CHI
779	b31b2a6b-1464-4c78-a19c-1f6ae627d519	1	Jermon Bushrod	J.Bushrod	1984-08-19	77	315	Towson	OT	74	ACT	0	0	2013-09-14 23:48:06.592749	2013-09-14 23:48:06.592752	CHI
780	1d5182e8-a2f9-4748-b602-4cc8271e8bd5	1	Earl Bennett	E.Bennett	1987-03-23	72	206	Vanderbilt	WR	80	ACT	0	0	2013-09-14 23:48:06.596731	2013-09-14 23:48:06.596734	CHI
781	0ca741f8-58bd-4933-9d5c-0e04de3f4cff	1	Martellus Bennett	M.Bennett	1987-03-10	78	265	Texas A&M	TE	83	ACT	0	0	2013-09-14 23:48:06.605101	2013-09-14 23:48:06.605103	CHI
782	4a47113b-8180-45fe-ba48-8ae4d3e1d181	1	Tony Fiammetta	T.Fiammetta	1986-08-22	72	242	Syracuse	FB	43	ACT	0	0	2013-09-14 23:48:06.608708	2013-09-14 23:48:06.60871	CHI
783	cf881df8-d5a0-4736-be01-eb72767366b0	1	Jordan Mills	J.Mills	1990-12-24	77	316	Louisiana Tech	T	67	ACT	0	0	2013-09-14 23:48:06.612661	2013-09-14 23:48:06.612663	CHI
784	0268a19e-6227-4fba-83fd-6aa52176dc3a	1	Steve Maneri	S.Maneri	1988-03-20	78	280	Temple	TE	87	ACT	0	0	2013-09-14 23:48:06.616221	2013-09-14 23:48:06.616223	CHI
785	DEF-CHI	1	CHI Defense	CHI		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:06.620023	2013-09-14 23:48:06.620025	CHI
786	3fd6bc25-acc1-40c1-b813-610be538a736	1	Jerome Simpson	J.Simpson	1986-02-04	74	190	Coastal Carolina	WR	81	ACT	0	0	2013-09-14 23:48:06.903072	2013-09-14 23:48:06.903075	MIN
787	407f1923-6659-4564-800f-25b8746d6d3e	1	Harrison Smith	H.Smith	1989-02-02	74	214	Notre Dame	SAF	22	ACT	0	0	2013-09-14 23:48:06.907498	2013-09-14 23:48:06.907502	MIN
788	8204c701-b2a6-479a-9be6-0b03854bebf8	1	Charlie Johnson	C.Johnson	1984-05-02	76	305	Oklahoma State	OT	74	ACT	0	0	2013-09-14 23:48:06.91183	2013-09-14 23:48:06.911832	MIN
789	bcce626d-b0b5-4b1a-98a8-e6021d5af145	1	Jamarca Sanford	J.Sanford	1985-08-27	70	200	Mississippi	SAF	33	ACT	0	0	2013-09-14 23:48:06.915733	2013-09-14 23:48:06.915735	MIN
790	d9168af9-6bf7-47de-ba56-19d6a3a4548b	1	Matt Kalil	M.Kalil	1989-07-06	79	295	USC	OT	75	ACT	0	0	2013-09-14 23:48:06.9194	2013-09-14 23:48:06.919402	MIN
791	1ed30e79-c25f-4ce1-a17f-94a4bf6d3686	1	J'Marcus Webb	J.Webb	1988-08-08	79	333	West Texas A&M	OT	73	ACT	0	0	2013-09-14 23:48:06.92313	2013-09-14 23:48:06.923133	MIN
792	3467ae3e-4ddf-450d-8f36-b741ea3a2564	1	Christian Ponder	C.Ponder	1988-02-25	74	229	Florida State	QB	7	ACT	0	0	2013-09-14 23:48:06.926834	2013-09-14 23:48:06.926836	MIN
793	1059e9dc-97df-4643-9116-883a0573d8b1	1	Kyle Rudolph	K.Rudolph	1989-11-09	78	259	Notre Dame	TE	82	ACT	0	0	2013-09-14 23:48:06.930356	2013-09-14 23:48:06.930358	MIN
794	6499ef2a-c7a9-4f14-abeb-8cc165333249	1	Brandon Fusco	B.Fusco	1988-07-26	76	306	Slippery Rock	OL	63	ACT	0	0	2013-09-14 23:48:06.93411	2013-09-14 23:48:06.934112	MIN
795	8ceab66f-c5eb-4d5a-970f-8210e3e20f7f	1	John Carlson	J.Carlson	1984-05-12	77	251	Notre Dame	TE	89	ACT	0	0	2013-09-14 23:48:06.938039	2013-09-14 23:48:06.938042	MIN
796	cccc9f16-9508-434f-b7a4-9a29cb0cacf9	1	Rhett Ellison	R.Ellison	1988-10-03	77	250	USC	TE	40	ACT	0	0	2013-09-14 23:48:06.942169	2013-09-14 23:48:06.942171	MIN
797	e9dd371e-fb41-4a6b-9ebc-714e0cd7ce96	1	DeMarcus Love	D.Love	1988-03-07	76	315	Arkansas	T	73	SUS	0	0	2013-09-14 23:48:06.946103	2013-09-14 23:48:06.946106	MIN
798	8263e101-aa33-435f-bf0f-388e1c4eeb59	1	Matt Cassel	M.Cassel	1982-05-17	76	230	USC	QB	16	ACT	0	0	2013-09-14 23:48:06.949735	2013-09-14 23:48:06.949738	MIN
799	8c5067dc-1617-42fa-82eb-0596392ab20a	1	Zach Line	Z.Line		72	232	Southern Methodist	RB	48	ACT	0	0	2013-09-14 23:48:06.953315	2013-09-14 23:48:06.953317	MIN
800	9163afa3-2f7d-4fc0-bf96-f5d8f618969a	1	Joe Berger	J.Berger	1982-05-25	77	315	Michigan Tech	OL	61	ACT	0	0	2013-09-14 23:48:06.95747	2013-09-14 23:48:06.957475	MIN
801	39ee3bee-1177-49cd-a78b-7a790ffd0b84	1	Andrew Sendejo	A.Sendejo	1987-09-09	73	225	Rice	SAF	34	ACT	0	0	2013-09-14 23:48:06.961618	2013-09-14 23:48:06.96162	MIN
802	ff937065-a20f-4968-a138-8ecd3a8b7cdb	1	Greg Jennings	G.Jennings	1983-09-21	71	198	Western Michigan	WR	15	ACT	0	0	2013-09-14 23:48:06.965245	2013-09-14 23:48:06.965248	MIN
803	d1b9ef33-5b6e-4fb8-b253-aee9b2893ddd	1	Jeff Baca	J.Baca	1990-01-10	75	302	UCLA	G	60	ACT	0	0	2013-09-14 23:48:06.968589	2013-09-14 23:48:06.968592	MIN
804	7f87c105-e608-4911-8897-31cc5a443175	1	John Sullivan	J.Sullivan	1985-08-08	76	301	Notre Dame	C	65	ACT	0	0	2013-09-14 23:48:06.972346	2013-09-14 23:48:06.972348	MIN
805	ab58c0ac-a747-47e6-9b3c-505e41d2bd3d	1	Adrian Peterson	A.Peterson	1985-03-21	73	217	Oklahoma	RB	28	ACT	0	0	2013-09-14 23:48:06.975909	2013-09-14 23:48:06.975911	MIN
806	8bfeffe7-99e3-4db0-8f18-cbc0f64ec24b	1	Mistral Raymond	M.Raymond	1987-09-07	73	202	South Florida	SAF	41	ACT	0	0	2013-09-14 23:48:06.979456	2013-09-14 23:48:06.979458	MIN
807	250199f2-1387-4b55-b96f-17fedea6db7f	1	Joe Webb	J.Webb	1986-11-14	76	220	Alabama-Birmingham	QB	14	ACT	0	0	2013-09-14 23:48:06.982781	2013-09-14 23:48:06.982783	MIN
808	da85107c-365c-4d58-90ab-479d97d798b4	1	Cordarrelle Patterson	C.Patterson	1991-03-17	74	216	Tennessee	WR	84	ACT	0	0	2013-09-14 23:48:06.986402	2013-09-14 23:48:06.986404	MIN
809	6a11f09e-268c-4e5a-9b0f-cc0f4bc353c3	1	Jarius Wright	J.Wright	1989-11-25	70	180	Arkansas	WR	17	ACT	0	0	2013-09-14 23:48:06.990277	2013-09-14 23:48:06.99028	MIN
810	9a776cbe-2400-49bb-8b02-4708167ef674	1	Greg Childs	G.Childs	1990-03-10	75	217	Arkansas	WR	85	PUP	0	0	2013-09-14 23:48:06.993795	2013-09-14 23:48:06.993798	MIN
811	afac3e25-d72d-43f7-be4b-d33ed91a0bf8	1	Blair Walsh	B.Walsh	1990-01-08	70	192	Georgia	K	3	ACT	0	0	2013-09-14 23:48:06.997483	2013-09-14 23:48:06.997485	MIN
812	08747f6d-ce8f-4510-bf10-98451dab51e1	1	McLeod Bethel-Thompson	M.Bethel-Thompson	1988-07-03	76	230	Sacramento State	QB	4	ACT	0	0	2013-09-14 23:48:07.001149	2013-09-14 23:48:07.001151	MIN
813	5bcf4917-b164-4873-b2ca-0ec150749753	1	Phil Loadholt	P.Loadholt	1986-01-21	80	343	Oklahoma	OT	71	ACT	0	0	2013-09-14 23:48:07.004985	2013-09-14 23:48:07.004988	MIN
814	5db03086-c670-4adb-98ed-b6a59a4f9270	1	Robert Blanton	R.Blanton	1989-09-07	73	200	Notre Dame	SAF	36	ACT	0	0	2013-09-14 23:48:07.008859	2013-09-14 23:48:07.008862	MIN
815	865740d9-3838-4733-a0eb-52193f101c32	1	Jerome Felton	J.Felton	1986-07-03	72	246	Furman	FB	42	SUS	0	0	2013-09-14 23:48:07.012984	2013-09-14 23:48:07.012986	MIN
816	65b991ed-ad0c-41d8-bbe0-95fc147c9441	1	Matt Asiata	M.Asiata	1987-07-24	71	220	Utah	RB	44	ACT	0	0	2013-09-14 23:48:07.017259	2013-09-14 23:48:07.017261	MIN
817	06669e1d-f9f7-4774-abc2-6ed2f7e7647f	1	Toby Gerhart	T.Gerhart	1987-03-28	72	231	Stanford	RB	32	ACT	0	0	2013-09-14 23:48:07.021399	2013-09-14 23:48:07.021402	MIN
818	DEF-MIN	1	MIN Defense	MIN		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:07.024946	2013-09-14 23:48:07.024948	MIN
819	ac45cfcf-6a9b-477c-8b49-45f624831d8c	1	Jeremy Ross	J.Ross	1988-03-16	71	222	California	WR	10	ACT	0	0	2013-09-14 23:48:07.319316	2013-09-14 23:48:07.319317	GB
820	651366dc-4297-484d-9e20-308c3bbca8b8	1	Ryan Taylor	R.Taylor	1987-11-16	75	254	North Carolina	TE	82	ACT	0	0	2013-09-14 23:48:07.322866	2013-09-14 23:48:07.32287	GB
821	4cf02857-f50c-4a6f-b94d-ff12d8f701b0	1	Don Barclay	D.Barclay	1989-04-18	76	305	West Virginia	G	67	ACT	0	0	2013-09-14 23:48:07.326526	2013-09-14 23:48:07.326529	GB
822	409377a4-293c-4eee-a9d1-02a46449a540	1	Morgan Burnett	M.Burnett	1989-01-13	73	209	Georgia Tech	SAF	42	ACT	0	0	2013-09-14 23:48:07.328936	2013-09-14 23:48:07.328938	GB
823	b5584569-4a6d-4739-a810-eec2b5edeea4	1	James Jones	J.Jones	1984-03-31	73	208	San Jose State	WR	89	ACT	0	0	2013-09-14 23:48:07.332577	2013-09-14 23:48:07.332579	GB
824	e0856548-6fd5-4f83-9aa0-91f1bf4cbbd8	1	Mason Crosby	M.Crosby	1984-09-03	73	207	Colorado	K	2	ACT	0	0	2013-09-14 23:48:07.336525	2013-09-14 23:48:07.336527	GB
825	2f80e90d-dbff-4395-81c9-4e61c247d0f1	1	Bryan Bulaga	B.Bulaga	1989-03-21	77	314	Iowa	OT	75	IR	0	0	2013-09-14 23:48:07.340794	2013-09-14 23:48:07.340796	GB
826	a750e7ca-12ab-4d7c-bc65-f58793c3ed16	1	David Bakhtiari	D.Bakhtiari	1991-09-30	76	300	Colorado	T	69	ACT	0	0	2013-09-14 23:48:07.344604	2013-09-14 23:48:07.344606	GB
827	0dfd5d3f-ebb5-4efe-8df1-2ebda0e5185e	1	Marshall Newhouse	M.Newhouse	1988-09-29	76	319	Texas Christian	OT	74	ACT	0	0	2013-09-14 23:48:07.348145	2013-09-14 23:48:07.348147	GB
828	de070f62-4494-4a98-8a76-0929c19be685	1	James Starks	J.Starks	1986-02-25	74	218	Buffalo	RB	44	ACT	0	0	2013-09-14 23:48:07.351511	2013-09-14 23:48:07.351514	GB
829	e030ef2b-1dcc-4c66-b8de-0016ca0d52d2	1	Micah Hyde	M.Hyde	1990-12-31	72	197	Iowa	FS	33	ACT	0	0	2013-09-14 23:48:07.355562	2013-09-14 23:48:07.355565	GB
830	04cc9dd3-de57-4d20-ad28-ff2be479937f	1	Sederrick Cunningham	S.Cunningham	1989-07-14	71	192	Furman	WR	13	IR	0	0	2013-09-14 23:48:07.359055	2013-09-14 23:48:07.359057	GB
831	9f2aebe4-b654-4f0e-a437-ec46f20b6bfe	1	Jordy Nelson	J.Nelson	1985-05-31	75	217	Kansas State	WR	87	ACT	0	0	2013-09-14 23:48:07.362807	2013-09-14 23:48:07.36281	GB
832	8eafc2b1-3e22-4416-b690-9a1232669f62	1	Andrew Quarless	A.Quarless	1988-10-06	76	252	Penn State	TE	81	ACT	0	0	2013-09-14 23:48:07.366439	2013-09-14 23:48:07.366441	GB
833	2c80e71d-c173-4c07-aeda-69371e969591	1	Evan Dietrich-Smith	E.Dietrich-Smith	1986-07-19	74	308	Idaho State	C	62	ACT	0	0	2013-09-14 23:48:07.370251	2013-09-14 23:48:07.370253	GB
834	f59c0b26-a651-408c-b8d4-efe9ffa333c8	1	Kevin Dorsey	K.Dorsey	1990-02-23	75	210	Maryland	WR	16	IR	0	0	2013-09-14 23:48:07.374174	2013-09-14 23:48:07.374176	GB
835	9c2bf2fc-d6cb-479d-8ece-f2ab4d1cda91	1	Josh Sitton	J.Sitton	1986-06-06	75	318	Central Florida	G	71	ACT	0	0	2013-09-14 23:48:07.378116	2013-09-14 23:48:07.378118	GB
836	f9ec0e39-86d2-4f99-84d6-b4e7bb387d8b	1	Lane Taylor	L.Taylor	1989-11-22	75	324	Oklahoma State	G	65	ACT	0	0	2013-09-14 23:48:07.382005	2013-09-14 23:48:07.382008	GB
837	e804ffee-597a-434f-8e72-7db5893225d6	1	Brandon Bostick	B.Bostick	1989-05-03	75	245	Newberry College	TE	86	ACT	0	0	2013-09-14 23:48:07.385788	2013-09-14 23:48:07.385791	GB
838	0ce48193-e2fa-466e-a986-33f751add206	1	Aaron Rodgers	A.Rodgers	1983-12-02	74	225	California	QB	12	ACT	0	0	2013-09-14 23:48:07.390045	2013-09-14 23:48:07.390047	GB
839	b24e6d69-1482-499d-970f-10b64b5ecb8d	1	M.D. Jennings	M.Jennings	1988-07-25	72	195	Arkansas State	SAF	43	ACT	0	0	2013-09-14 23:48:07.393672	2013-09-14 23:48:07.393675	GB
840	a7152c92-426c-4c6b-9629-da63f5c60ff8	1	John Kuhn	J.Kuhn	1982-09-09	72	250	Shippensburg	FB	30	ACT	0	0	2013-09-14 23:48:07.397487	2013-09-14 23:48:07.397489	GB
841	6c7704c2-f833-46aa-9f9c-d975d5ad1297	1	Chris Banjo	C.Banjo	1990-02-26	70	204	Southern Methodist	DB	32	ACT	0	0	2013-09-14 23:48:07.400846	2013-09-14 23:48:07.400848	GB
842	6d7ca819-8c58-4c41-bba7-643ba9553eb8	1	Greg Van Roten	G.Van Roten	1990-02-26	76	295	Penn	G	64	ACT	0	0	2013-09-14 23:48:07.404632	2013-09-14 23:48:07.404634	GB
843	eec73720-d572-44cc-8f60-be5099b6c4b2	1	Seneca Wallace	S.Wallace	1980-08-06	71	205	Iowa State	QB	9	ACT	0	0	2013-09-14 23:48:07.40846	2013-09-14 23:48:07.408462	GB
844	fed730f2-4d9c-4797-86a5-5668147d6150	1	Jermichael Finley	J.Finley	1987-03-26	77	247	Texas	TE	88	ACT	0	0	2013-09-14 23:48:07.412165	2013-09-14 23:48:07.412167	GB
845	671d2fd7-41bb-457a-8e93-904ee7d94eb1	1	J.C. Tretter	J.Tretter		76	307	Cornell	T	73	PUP	0	0	2013-09-14 23:48:07.416293	2013-09-14 23:48:07.416296	GB
846	356b9d62-d732-4110-b2b5-1b2d74f7640c	1	Johnathan Franklin	J.Franklin	1989-10-23	70	205	UCLA	RB	23	ACT	0	0	2013-09-14 23:48:07.420228	2013-09-14 23:48:07.42023	GB
847	3283f152-d373-43b3-b88f-f6f261c48e81	1	Randall Cobb	R.Cobb	1990-08-22	70	192	Kentucky	WR	18	ACT	0	0	2013-09-14 23:48:07.424318	2013-09-14 23:48:07.42432	GB
848	8920894c-dc0e-4ed6-96e5-b96eadcf2092	1	Jarrett Boykin	J.Boykin	1989-11-04	74	218	Virginia Tech	WR	11	ACT	0	0	2013-09-14 23:48:07.428124	2013-09-14 23:48:07.428127	GB
849	e1551780-84cb-48a4-b5c8-268c437bd671	1	Jerron McMillian	J.McMillian	1989-04-02	71	203	Maine	SAF	22	ACT	0	0	2013-09-14 23:48:07.4317	2013-09-14 23:48:07.431703	GB
850	030f508b-be11-478e-bf68-d21e70fcff7b	1	Eddie Lacy	E.Lacy	1991-01-01	71	231	Alabama	RB	27	ACT	0	0	2013-09-14 23:48:07.43534	2013-09-14 23:48:07.435344	GB
851	7ea2fcfd-0099-4e62-8f6e-efa0197bbb99	1	DuJuan Harris	D.Harris	1988-09-03	67	197	Troy	RB	26	IR	0	0	2013-09-14 23:48:07.439149	2013-09-14 23:48:07.439152	GB
852	3ebbc479-fec5-4463-8eb1-b9b09b0d3bc2	1	T.J. Lang	T.Lang	1987-09-20	76	318	Eastern Michigan	G	70	ACT	0	0	2013-09-14 23:48:07.443383	2013-09-14 23:48:07.443386	GB
853	7ff9bc26-5cbf-4891-b7c8-3a3e804e77cb	1	Derek Sherrod	D.Sherrod	1989-04-23	77	321	Mississippi State	OT	78	PUP	0	0	2013-09-14 23:48:07.447058	2013-09-14 23:48:07.44706	GB
854	f03e7491-7eff-45bb-b4a0-03e89b8cdc8d	1	Sean Richardson	S.Richardson	1990-01-21	74	216	Vanderbilt	SAF	28	PUP	0	0	2013-09-14 23:48:07.450553	2013-09-14 23:48:07.450555	GB
855	DEF-GB	1	GB Defense	GB		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:07.454274	2013-09-14 23:48:07.454277	GB
856	a9af3f0f-44a9-4f46-b4c7-de5767b7f425	1	DeAngelo Williams	D.Williams	1983-04-25	69	217	Memphis	RB	34	ACT	0	0	2013-09-14 23:48:07.761451	2013-09-14 23:48:07.761453	CAR
857	b6cca4b9-a1f4-45f1-a042-259da4d2d7db	1	Brandon Williams	B.Williams		76	250	Oregon	TE	86	ACT	0	0	2013-09-14 23:48:07.766123	2013-09-14 23:48:07.766125	CAR
858	22b17923-9927-42ad-9c57-d9e89c5dd61b	1	Amini Silatolu	A.Silatolu	1988-09-16	76	314	Midwestern State	G	66	ACT	0	0	2013-09-14 23:48:07.770287	2013-09-14 23:48:07.77029	CAR
859	e5a5eef9-aa87-430b-bc67-ab77323de5f9	1	Armond Smith	A.Smith	1986-05-07	69	194	Union College (KY)	RB	36	ACT	0	0	2013-09-14 23:48:07.774471	2013-09-14 23:48:07.774473	CAR
860	9c7c607f-7123-4d49-87f6-c928dc0e6d66	1	Garry Williams	G.Williams	1986-08-20	75	320	Kentucky	OT	65	IR	0	0	2013-09-14 23:48:07.778656	2013-09-14 23:48:07.778659	CAR
861	a69419b7-3cdc-48b9-b3a3-c50f2bf4e6f1	1	Steve Smith	S.Smith	1979-05-12	69	185	Utah	WR	89	ACT	0	0	2013-09-14 23:48:07.782215	2013-09-14 23:48:07.782219	CAR
862	1c1a6937-9267-497e-9386-00562e5fb399	1	Byron Bell	B.Bell	1989-01-17	77	339	New Mexico	T	77	ACT	0	0	2013-09-14 23:48:07.786309	2013-09-14 23:48:07.786311	CAR
863	d90adc80-8e8e-4484-92a3-00bf274e6a9d	1	Chris Scott	C.Scott	1987-08-04	76	319	Tennessee	OT	75	ACT	0	0	2013-09-14 23:48:07.792102	2013-09-14 23:48:07.792106	CAR
864	b431c14b-7447-4fa1-bc0c-405720bdfa63	1	Jordan Gross	J.Gross	1980-07-20	76	305	Utah	OT	69	ACT	0	0	2013-09-14 23:48:07.799869	2013-09-14 23:48:07.799869	CAR
865	4fe9411c-41e9-4030-92bb-79f0fb95735c	1	Kealoha Pilares	K.Pilares	1988-02-20	70	201	Hawaii	WR	81	IR	0	0	2013-09-14 23:48:07.802591	2013-09-14 23:48:07.802592	CAR
866	180e654c-6b1a-4ef5-a365-c43a007f6bd6	1	Travelle Wharton	T.Wharton	1981-05-19	76	312	South Carolina	G	70	ACT	0	0	2013-09-14 23:48:07.804989	2013-09-14 23:48:07.80499	CAR
867	214e55e4-a089-412d-9598-a16495df0d25	1	Cam Newton	C.Newton	1989-05-11	77	244	Auburn	QB	1	ACT	0	0	2013-09-14 23:48:07.807638	2013-09-14 23:48:07.807638	CAR
868	ca8815bc-c68f-4d18-80fc-f61e4a2053b8	1	Mike Mitchell	M.Mitchell	1987-06-10	73	220	Ohio	SAF	21	ACT	0	0	2013-09-14 23:48:07.810549	2013-09-14 23:48:07.810552	CAR
869	f4a9197a-d31a-46d0-9ec9-2e76eb5b651f	1	R.J. Webb	R.Webb	1987-08-24	74	201	Furman	WR	17	IR	0	0	2013-09-14 23:48:07.813172	2013-09-14 23:48:07.813173	CAR
870	5707d2b0-ea9e-4a5e-8289-9d52197301d9	1	Brandon LaFell	B.LaFell	1986-11-04	74	211	LSU	WR	11	ACT	0	0	2013-09-14 23:48:07.816064	2013-09-14 23:48:07.816064	CAR
871	22eeb9ce-32a5-4728-bf30-06bd300b9365	1	Domenik Hixon	D.Hixon	1984-10-08	74	197	Akron	WR	87	ACT	0	0	2013-09-14 23:48:07.818834	2013-09-14 23:48:07.818836	CAR
872	72fbe462-91c5-4c84-9640-e8ad7cad6447	1	Derek Anderson	D.Anderson	1983-06-15	78	230	Oregon State	QB	3	ACT	0	0	2013-09-14 23:48:07.82234	2013-09-14 23:48:07.822343	CAR
873	1c918980-f2fb-4b34-b0ad-ca801a828fbb	1	Mike Tolbert	M.Tolbert	1985-11-23	69	243	Coastal Carolina	FB	35	ACT	0	0	2013-09-14 23:48:07.826076	2013-09-14 23:48:07.826079	CAR
874	41210d3e-884d-4c62-9a3b-c8b89007b4a6	1	Michael Zordich	M.Zordich	1989-10-29	73	240	Penn State	FB	39	IR	0	0	2013-09-14 23:48:07.830236	2013-09-14 23:48:07.830238	CAR
875	63f8a401-f308-4463-9d0b-4335b98da682	1	Graham Gano	G.Gano	1987-04-09	74	200	Florida State	K	9	ACT	0	0	2013-09-14 23:48:07.833973	2013-09-14 23:48:07.833975	CAR
876	01654256-1c2b-4729-a166-dd54358a71da	1	Jimmy Clausen	J.Clausen	1987-09-21	74	215	Notre Dame	QB	7	IR	0	0	2013-09-14 23:48:07.838034	2013-09-14 23:48:07.838036	CAR
877	ef446cdd-1179-4245-bdd5-41d2c470d678	1	Bruce Campbell	B.Campbell	1988-05-25	78	315	Maryland	G	73	IR	0	0	2013-09-14 23:48:07.842154	2013-09-14 23:48:07.842158	CAR
878	ee2649fa-62cf-4832-bf67-fc11d3681fef	1	Richie Brockel	R.Brockel	1986-07-24	73	255	Boise State	TE	47	ACT	0	0	2013-09-14 23:48:07.846469	2013-09-14 23:48:07.846471	CAR
879	7a52979c-602d-41e7-b266-427d353670a0	1	Edmund Kugbila	E.Kugbila	1990-09-21	76	317	Valdosta State	G	71	IR	0	0	2013-09-14 23:48:07.850802	2013-09-14 23:48:07.850804	CAR
880	1016d675-7f23-4744-8632-7b4ea8115f5a	1	Charles Godfrey	C.Godfrey	1985-11-15	71	205	Iowa	SAF	30	ACT	0	0	2013-09-14 23:48:07.854556	2013-09-14 23:48:07.85456	CAR
881	a72b5fae-3e1b-4697-82ef-421bfa36aa00	1	Ben Hartsock	B.Hartsock	1980-07-05	76	260	Ohio State	TE	84	ACT	0	0	2013-09-14 23:48:07.858611	2013-09-14 23:48:07.858614	CAR
882	e048388b-8cf9-4b35-9686-871ab3ce1322	1	Armanti Edwards	A.Edwards	1988-03-08	71	190	Appalachian State	WR	14	ACT	0	0	2013-09-14 23:48:07.862448	2013-09-14 23:48:07.862452	CAR
883	d503e3cf-861d-4b06-8de8-f66b1b72a3bf	1	Ryan Kalil	R.Kalil	1985-03-29	74	295	USC	C	67	ACT	0	0	2013-09-14 23:48:07.865863	2013-09-14 23:48:07.865866	CAR
884	5ec072b3-2837-4cf1-bb4f-ecd873949626	1	Kenjon Barner	K.Barner	1989-04-28	69	196	Oregon	RB	25	ACT	0	0	2013-09-14 23:48:07.870818	2013-09-14 23:48:07.870821	CAR
885	3aef6950-1c19-4454-a3d0-0afe9634ea9f	1	Ted Ginn	T.Ginn	1985-04-12	71	180	Ohio State	WR	19	ACT	0	0	2013-09-14 23:48:07.874689	2013-09-14 23:48:07.874693	CAR
886	fc506583-7edf-4e40-8047-83f60bea67a2	1	Colin Jones	C.Jones	1987-10-27	72	205	Texas Christian	SAF	42	ACT	0	0	2013-09-14 23:48:07.878629	2013-09-14 23:48:07.878631	CAR
887	b88e61f8-2573-40c1-90d4-85a8a4eeb6e1	1	Jeff Byers	J.Byers	1985-09-07	76	310	Southern California	C	62	ACT	0	0	2013-09-14 23:48:07.882072	2013-09-14 23:48:07.882075	CAR
888	220fbd2e-10a8-4757-a6f4-6aab0327846a	1	Brian Folkerts	B.Folkerts	1990-01-30	76	303	Washburn	C	64	ACT	0	0	2013-09-14 23:48:07.885635	2013-09-14 23:48:07.885637	CAR
889	28adf83b-4f7e-461b-9a9f-91215741e100	1	Quintin Mikell	Q.Mikell	1980-09-16	70	204	Boise State	SS	27	ACT	0	0	2013-09-14 23:48:07.889156	2013-09-14 23:48:07.889159	CAR
890	96a1fc85-5af7-49fa-a5ac-ddc06c205ced	1	Jonathan Stewart	J.Stewart	1987-03-21	70	235	Oregon	RB	28	PUP	0	0	2013-09-14 23:48:07.893447	2013-09-14 23:48:07.89345	CAR
891	587d0a98-7ec5-45a5-adba-8af26e8f256b	1	Greg Olsen	G.Olsen	1985-03-11	77	255	Miami (FL)	TE	88	ACT	0	0	2013-09-14 23:48:07.897072	2013-09-14 23:48:07.897074	CAR
892	DEF-CAR	1	CAR Defense	CAR		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:07.90099	2013-09-14 23:48:07.900992	CAR
893	b4ce3e07-7848-4da2-a33e-4f04ce540ba5	1	Travaris Cadet	T.Cadet	1989-02-01	73	210	Appalachian State	RB	39	ACT	0	0	2013-09-14 23:48:08.189943	2013-09-14 23:48:08.189945	NO
894	cf301e4c-f4e9-4f7a-aed6-61880af7fd16	1	Tim Lelito	T.Lelito		76	315	Grand Valley State	G	68	ACT	0	0	2013-09-14 23:48:08.194717	2013-09-14 23:48:08.194721	NO
895	9ef3f249-6ff4-442e-84f4-b915f96aeb28	1	Ben Grubbs	B.Grubbs	1984-03-10	75	310	Auburn	G	66	ACT	0	0	2013-09-14 23:48:08.198839	2013-09-14 23:48:08.198842	NO
896	d81844de-54c3-42ee-9850-072dc4131b6f	1	Benjamin Watson	B.Watson	1980-12-18	75	255	Georgia	TE	82	ACT	0	0	2013-09-14 23:48:08.20292	2013-09-14 23:48:08.202922	NO
897	682a7396-9280-487f-aabf-561d0334bddd	1	Roman Harper	R.Harper	1982-12-11	73	200	Alabama	SAF	41	ACT	0	0	2013-09-14 23:48:08.206791	2013-09-14 23:48:08.206801	NO
898	67f976f5-1f14-4f5f-a5f1-917cf6c3b807	1	Jed Collins	J.Collins	1986-03-03	73	255	Washington State	FB	45	ACT	0	0	2013-09-14 23:48:08.210625	2013-09-14 23:48:08.210627	NO
899	83f8a30f-829f-4928-9816-7497ce6339c7	1	Garrett Hartley	G.Hartley	1986-05-16	68	195	Oklahoma	K	5	ACT	0	0	2013-09-14 23:48:08.214443	2013-09-14 23:48:08.214446	NO
900	927301a1-5905-4a22-a85f-acc56db126c9	1	Joe Morgan	J.Morgan	1988-03-28	73	184	Walsh	WR	13	IR	0	0	2013-09-14 23:48:08.217993	2013-09-14 23:48:08.217996	NO
901	5f512278-4956-476d-b5ca-73ecd58d79c1	1	Khiry Robinson	K.Robinson		72	220	West Texas A&M	RB	29	ACT	0	0	2013-09-14 23:48:08.221523	2013-09-14 23:48:08.221526	NO
902	31305637-a7a6-4d38-a617-2d928a9ce425	1	Luke McCown	L.McCown	1981-07-12	76	217	Louisiana Tech	QB	7	ACT	0	0	2013-09-14 23:48:08.225556	2013-09-14 23:48:08.225559	NO
903	65ec05af-e851-4988-86f4-62c4f775a1a3	1	Lance Moore	L.Moore	1983-08-31	69	190	Toledo	WR	16	ACT	0	0	2013-09-14 23:48:08.229765	2013-09-14 23:48:08.229767	NO
904	9717d017-54da-40b8-b8c4-b2e122623beb	1	Chris Givens	C.Givens	1989-01-28	74	203	Miami (OH)	WR	17	IR	0	0	2013-09-14 23:48:08.234041	2013-09-14 23:48:08.234043	NO
905	e2782d05-3e61-4c4f-93a6-70eed054e5ba	1	Pierre Thomas	P.Thomas	1984-12-18	71	215	Illinois	RB	23	ACT	0	0	2013-09-14 23:48:08.237711	2013-09-14 23:48:08.237713	NO
906	1cf89a44-0b07-4eaf-87b6-face89587820	1	Isa Abdul-Quddus	I.Abdul-Quddus	1988-12-04	73	220	Fordham	SAF	42	ACT	0	0	2013-09-14 23:48:08.241201	2013-09-14 23:48:08.241205	NO
907	5d88da46-b21f-4af6-ae0d-4f7f6c569530	1	Brian de la Puente	B.de la Puente	1985-05-13	75	306	California	G	60	ACT	0	0	2013-09-14 23:48:08.244937	2013-09-14 23:48:08.244939	NO
908	e6a5db0e-375b-4e6e-8fd7-46023c088242	1	Bryce Harris	B.Harris	1989-01-16	78	300	Fresno State	T	79	ACT	0	0	2013-09-14 23:48:08.248619	2013-09-14 23:48:08.248622	NO
909	23d258b7-24bb-4b39-982e-cfb9a6f7bab6	1	Robert Meachem	R.Meachem	1984-09-28	74	215	Tennessee	WR	17	ACT	0	0	2013-09-14 23:48:08.256697	2013-09-14 23:48:08.256699	NO
910	31e05e3b-3d84-4075-918b-41f676a74868	1	Zach Strief	Z.Strief	1983-09-22	79	320	Northwestern	OT	64	ACT	0	0	2013-09-14 23:48:08.260985	2013-09-14 23:48:08.260987	NO
911	a59206be-6b68-4aa9-9fdd-424aa16b90ea	1	Jahri Evans	J.Evans	1983-08-22	76	318	Bloomsburg	G	73	ACT	0	0	2013-09-14 23:48:08.265255	2013-09-14 23:48:08.265257	NO
912	30702243-7831-43fe-a0a1-335dd6a2f989	1	Charles Brown	C.Brown	1987-04-10	77	297	USC	OT	71	ACT	0	0	2013-09-14 23:48:08.268915	2013-09-14 23:48:08.268917	NO
913	4734f8dc-2ca4-4437-88f2-c8b8974abefc	1	Kenny Stills	K.Stills	1992-04-22	72	194	Oklahoma	WR	84	ACT	0	0	2013-09-14 23:48:08.27268	2013-09-14 23:48:08.272682	NO
914	422f9f66-97d7-4bae-9840-24b3a24655e8	1	Rafael Bush	R.Bush	1987-05-12	71	200	South Carolina State	SAF	25	ACT	0	0	2013-09-14 23:48:08.276234	2013-09-14 23:48:08.276236	NO
915	fd85786d-3900-4dc0-9b30-334ee30413ed	1	Jimmy Graham	J.Graham	1986-11-24	79	264	Miami (FL)	TE	80	ACT	0	0	2013-09-14 23:48:08.280337	2013-09-14 23:48:08.28034	NO
916	0cb6209d-2397-4be2-9cb7-f990bfb67e69	1	Terron Armstead	T.Armstead		77	306	Arkansas-Pine-Bluff	T	72	ACT	0	0	2013-09-14 23:48:08.283908	2013-09-14 23:48:08.283912	NO
917	687cdc33-bd0d-4b70-adb3-33f97dc26a3c	1	Josh Hill	J.Hill	1990-05-12	77	229	Idaho State	TE	89	ACT	0	0	2013-09-14 23:48:08.287528	2013-09-14 23:48:08.28753	NO
918	f336567d-44a9-4245-8452-1dd485fd70fb	1	Mark Ingram	M.Ingram	1989-12-21	69	215	Alabama	RB	22	ACT	0	0	2013-09-14 23:48:08.29121	2013-09-14 23:48:08.291213	NO
919	bb5957e6-ce7d-47ab-8036-22191ffc1c44	1	Drew Brees	D.Brees	1979-01-15	72	209	Purdue	QB	9	ACT	0	0	2013-09-14 23:48:08.296499	2013-09-14 23:48:08.296503	NO
920	15b156b5-30cc-4070-b60a-1c09e62c5a9b	1	Darren Sproles	D.Sproles	1983-06-20	66	190	Kansas State	RB	43	ACT	0	0	2013-09-14 23:48:08.300724	2013-09-14 23:48:08.300726	NO
921	a2270ced-ae01-4dee-a177-9dca7c5b20cc	1	Kenny Vaccaro	K.Vaccaro	1991-02-15	72	214	Texas	SS	32	ACT	0	0	2013-09-14 23:48:08.304632	2013-09-14 23:48:08.304636	NO
922	0a4c5237-08a4-41d5-873d-18f70c025149	1	Malcolm Jenkins	M.Jenkins	1987-12-20	72	204	Ohio State	SAF	27	ACT	0	0	2013-09-14 23:48:08.308663	2013-09-14 23:48:08.308665	NO
923	690e864b-2483-4cd0-b34b-f9f190d114a1	1	Nick Toon	N.Toon	1988-11-11	76	218	Wisconsin	WR	88	ACT	0	0	2013-09-14 23:48:08.312375	2013-09-14 23:48:08.312377	NO
924	d106f1b6-e6c5-4978-adc0-8742b5c1c459	1	Marques Colston	M.Colston	1983-06-05	76	225	Hofstra	WR	12	PUP	0	0	2013-09-14 23:48:08.316056	2013-09-14 23:48:08.316058	NO
925	DEF-NO	1	NO Defense	NO		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:08.319536	2013-09-14 23:48:08.319538	NO
926	5b712aed-201c-43dd-b978-b7b6ef91178e	1	Luke Stocker	L.Stocker	1988-07-17	78	253	Tennessee	TE	88	ACT	0	0	2013-09-14 23:48:08.586187	2013-09-14 23:48:08.58619	TB
927	fcaa51ea-0923-4afc-a7cf-22e47a14acf4	1	Jeremy Zuttah	J.Zuttah	1986-06-01	76	308	Rutgers	C	76	ACT	0	0	2013-09-14 23:48:08.590804	2013-09-14 23:48:08.590808	TB
928	953a5bf1-9ba6-4e51-92d8-b731c46b09e4	1	Erik Lorig	E.Lorig	1986-11-17	76	250	Stanford	FB	41	ACT	0	0	2013-09-14 23:48:08.594939	2013-09-14 23:48:08.594941	TB
929	4c773e81-e73f-41db-be6d-1ad03aba1439	1	Carl Nicks	C.Nicks	1985-05-14	77	349	Nebraska	G	77	ACT	0	0	2013-09-14 23:48:08.599054	2013-09-14 23:48:08.599057	TB
930	c442ca48-a25a-476d-a74f-dd7bf18551e9	1	Mike James	M.James	1989-12-05	70	223	Miami (FL)	RB	25	ACT	0	0	2013-09-14 23:48:08.603395	2013-09-14 23:48:08.603397	TB
931	ac2ab3a9-9a1f-4197-ac96-3de277dbcf6c	1	Jamon Meredith	J.Meredith	1986-05-11	77	312	South Carolina	OT	79	ACT	0	0	2013-09-14 23:48:08.607726	2013-09-14 23:48:08.607729	TB
932	0052ea25-2f96-4eb4-a14e-4a672ac309a6	1	Gabe Carimi	G.Carimi	1988-06-13	79	316	Wisconsin	OT	72	ACT	0	0	2013-09-14 23:48:08.611558	2013-09-14 23:48:08.611562	TB
933	f3d63188-8684-464d-bd85-d46c0502bbf1	1	Ahmad Black	A.Black	1989-12-12	69	190	Florida	SAF	43	ACT	0	0	2013-09-14 23:48:08.615598	2013-09-14 23:48:08.6156	TB
934	8c7cd76d-74a0-4440-885a-07f92f9a75d7	1	Josh Freeman	J.Freeman	1988-01-13	78	248	Kansas State	QB	5	ACT	0	0	2013-09-14 23:48:08.619224	2013-09-14 23:48:08.619226	TB
935	002a02ca-e569-410e-867d-e317bad07fd1	1	Demar Dotson	D.Dotson	1985-10-11	81	315	Southern Mississippi	OT	69	ACT	0	0	2013-09-14 23:48:08.622618	2013-09-14 23:48:08.62262	TB
936	97cebfd1-f7d0-4fc7-b3d8-6d2308e992e3	1	Lawrence Tynes	L.Tynes	1978-06-03	73	194	Troy	K	1	NON	0	0	2013-09-14 23:48:08.626164	2013-09-14 23:48:08.626167	TB
937	6310d6aa-02d4-46de-8839-9251cb319dea	1	Tim Wright	T.Wright	1990-04-07	76	220	Rutgers	WR	81	ACT	0	0	2013-09-14 23:48:08.62966	2013-09-14 23:48:08.629662	TB
938	a4c9f534-dc79-47f4-ab46-6ad262f9ecc5	1	Anthony Gaitor	A.Gaitor	1988-10-09	70	182	Florida International	DB	26	IR	0	0	2013-09-14 23:48:08.633051	2013-09-14 23:48:08.633053	TB
939	b3f527c8-5744-4751-8f54-1677fbb32aca	1	Brian Leonard	B.Leonard	1984-02-03	73	225	Rutgers	RB	30	ACT	0	0	2013-09-14 23:48:08.636693	2013-09-14 23:48:08.636696	TB
940	50bcb5d3-62fb-45ac-b25b-5dffbff0cb0c	1	Donald Penn	D.Penn	1983-04-27	77	340	Utah State	OT	70	ACT	0	0	2013-09-14 23:48:08.640486	2013-09-14 23:48:08.640488	TB
941	4869b8db-2e38-4327-af11-cc1e17ef3490	1	Connor Barth	C.Barth	1986-04-11	71	200	North Carolina	K	10	NON	0	0	2013-09-14 23:48:08.644056	2013-09-14 23:48:08.644058	TB
942	bbfcacdd-b6ae-48df-8911-764bb7e0fcdb	1	Dan Orlovsky	D.Orlovsky	1983-08-18	77	230	Connecticut	QB	6	ACT	0	0	2013-09-14 23:48:08.647773	2013-09-14 23:48:08.647777	TB
943	3b538234-9a42-40ba-b4af-5cabc113794c	1	Vincent Jackson	V.Jackson	1983-01-14	77	230	Northern Colorado	WR	83	ACT	0	0	2013-09-14 23:48:08.651607	2013-09-14 23:48:08.651609	TB
944	5c2a0c83-e18a-43dd-bd65-704771157e42	1	Doug Martin	D.Martin	1989-01-13	69	223	Boise State	RB	22	ACT	0	0	2013-09-14 23:48:08.655157	2013-09-14 23:48:08.655159	TB
945	98c7ad4f-8e63-4028-b3ca-84dd37a5ae64	1	Mark Barron	M.Barron	1989-10-27	73	213	Alabama	SAF	23	ACT	0	0	2013-09-14 23:48:08.658755	2013-09-14 23:48:08.65876	TB
946	765cbbca-14b0-4765-bd26-9b1af79a86ee	1	Davin Joseph	D.Joseph	1983-11-22	75	313	Oklahoma	G	75	ACT	0	0	2013-09-14 23:48:08.662453	2013-09-14 23:48:08.662456	TB
947	f07fcd37-8671-4f9d-9659-455114a6b345	1	Rian Lindell	R.Lindell	1977-01-20	75	227	Washington State	K	4	ACT	0	0	2013-09-14 23:48:08.666789	2013-09-14 23:48:08.666791	TB
948	93fa7b69-04f5-4251-906d-d943c4923cb8	1	Tom Crabtree	T.Crabtree	1985-11-04	76	245	Miami (OH)	TE	84	ACT	0	0	2013-09-14 23:48:08.670756	2013-09-14 23:48:08.67076	TB
949	e1235f1e-26ce-438c-8168-3b1ded4ab893	1	Mike Glennon	M.Glennon	1989-12-12	79	225	North Carolina State	QB	8	ACT	0	0	2013-09-14 23:48:08.674389	2013-09-14 23:48:08.674391	TB
950	6195ddc9-ab2b-469a-b824-a890736d6db7	1	Russell Shepard	R.Shepard	1990-09-17	73	195	LSU	WR	89	ACT	0	0	2013-09-14 23:48:08.677868	2013-09-14 23:48:08.67787	TB
951	815a511f-40d9-4e6a-b178-54aedc1e0420	1	Deveron Carr	D.Carr	1990-09-10	71	190	Arizona State	DB	33	ACT	0	0	2013-09-14 23:48:08.68124	2013-09-14 23:48:08.681242	TB
952	8a7a1ca6-4aa7-40bb-b4f8-5fcf12584bf5	1	Michael Smith	M.Smith	1988-08-09	69	205	Utah State	RB	34	IR	0	0	2013-09-14 23:48:08.684803	2013-09-14 23:48:08.684805	TB
953	2c48a13f-bac4-46f8-b405-7ada72dd543e	1	Ted Larsen	T.Larsen	1987-06-13	74	305	North Carolina State	C	62	ACT	0	0	2013-09-14 23:48:08.688523	2013-09-14 23:48:08.688525	TB
954	8fd45946-17e7-4e01-91df-bb866f268309	1	Dashon Goldson	D.Goldson	1984-09-18	74	200	Washington	SAF	38	ACT	0	0	2013-09-14 23:48:08.692078	2013-09-14 23:48:08.69208	TB
955	8d10b45b-8847-4c16-bfab-c8122e5f57e2	1	Mike Williams	M.Williams	1987-05-18	73	212	Syracuse	WR	19	ACT	0	0	2013-09-14 23:48:08.696082	2013-09-14 23:48:08.696086	TB
956	5649ae74-aac1-433f-8f0f-ea812a285fac	1	Kevin Ogletree	K.Ogletree	1987-08-05	73	198	Virginia	WR	85	ACT	0	0	2013-09-14 23:48:08.704515	2013-09-14 23:48:08.704517	TB
957	20b43016-a174-423d-9551-7f62ababad3c	1	Rashaan Melvin	R.Melvin	1989-10-02	74	193	Northern Illinois	DB	28	ACT	0	0	2013-09-14 23:48:08.708758	2013-09-14 23:48:08.708761	TB
958	e576d602-7d9c-41fa-a665-630054496047	1	Nate Byham	N.Byham	1988-06-27	76	264	Pittsburgh	TE	82	ACT	0	0	2013-09-14 23:48:08.712483	2013-09-14 23:48:08.712485	TB
959	a030c3d5-5d5b-41a8-98ec-e35595350b13	1	Eric Page	E.Page	1991-09-23	70	180	Toledo	WR	17	ACT	0	0	2013-09-14 23:48:08.716423	2013-09-14 23:48:08.716426	TB
960	774ddf9f-99f5-429f-9c7c-b8799047f672	1	Jeff Demps	J.Demps	1990-01-08	67	190	Florida	RB	28	ACT	0	0	2013-09-14 23:48:08.720123	2013-09-14 23:48:08.720126	TB
961	a34a5944-33c4-4965-b404-6772f4b7f1ab	1	Peyton Hillis	P.Hillis	1986-01-21	74	250	Arkansas	RB	33	ACT	0	0	2013-09-14 23:48:08.723728	2013-09-14 23:48:08.723732	TB
962	DEF-TB	1	TB Defense	TB		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:08.727826	2013-09-14 23:48:08.727829	TB
963	e4039abe-35b3-4b78-9752-e714ef01cecd	1	Kemal Ishmael	K.Ishmael		71	206	Central Florida	DB	36	ACT	0	0	2013-09-14 23:48:09.025673	2013-09-14 23:48:09.025676	ATL
964	7e648a0b-fdc8-4661-a587-5826f2cac11b	1	Matt Ryan	M.Ryan	1985-05-17	76	220	Boston College	QB	2	ACT	0	0	2013-09-14 23:48:09.030392	2013-09-14 23:48:09.030394	ATL
965	3d980847-dec6-4fc1-a4bb-63bd0bfcb078	1	Steven Jackson	S.Jackson	1983-07-22	74	240	Oregon State	RB	39	ACT	0	0	2013-09-14 23:48:09.034839	2013-09-14 23:48:09.034842	ATL
966	67d56171-7522-430c-b7d9-8f7e2b6624d3	1	Levine Toilolo	L.Toilolo	1991-07-01	80	260	Stanford	TE	80	ACT	0	0	2013-09-14 23:48:09.03877	2013-09-14 23:48:09.038772	ATL
967	0b3217b9-ba37-4222-95cb-a7a222441e8b	1	Julio Jones	J.Jones	1989-02-03	75	220	Alabama	WR	11	ACT	0	0	2013-09-14 23:48:09.042789	2013-09-14 23:48:09.042793	ATL
968	382154cf-7cc6-494c-8426-9f78aa4c4b90	1	Tony Gonzalez	T.Gonzalez	1976-02-27	77	243	California	TE	88	ACT	0	0	2013-09-14 23:48:09.047199	2013-09-14 23:48:09.047201	ATL
969	e2524e8f-d304-4c8b-8165-55a09daa4801	1	Justin Blalock	J.Blalock	1983-12-20	76	329	Texas	G	63	ACT	0	0	2013-09-14 23:48:09.05111	2013-09-14 23:48:09.051112	ATL
970	c2dfb0f8-67e7-47d0-b4c5-997af6c36417	1	Peter Konz	P.Konz	1989-06-09	77	314	Wisconsin	G	66	ACT	0	0	2013-09-14 23:48:09.055113	2013-09-14 23:48:09.055116	ATL
971	221fb65c-a55f-4673-9445-19d090c3ecdf	1	Shann Schillinger	S.Schillinger	1986-05-22	72	202	Montana	SAF	29	ACT	0	0	2013-09-14 23:48:09.058902	2013-09-14 23:48:09.058905	ATL
972	008ebc66-7148-4f73-ac09-516f86c38cda	1	Josh Vaughan	J.Vaughan	1986-12-03	72	232	Richmond	RB	30	ACT	0	0	2013-09-14 23:48:09.062466	2013-09-14 23:48:09.062468	ATL
973	51e470b5-73ea-49b2-ae83-c26256a30812	1	Roddy White	R.White	1981-11-02	72	212	Alabama-Birmingham	WR	84	ACT	0	0	2013-09-14 23:48:09.066078	2013-09-14 23:48:09.066081	ATL
974	fde420b8-93ab-478d-8f27-817409f33652	1	Jason Snelling	J.Snelling	1983-12-29	71	223	Virginia	RB	44	ACT	0	0	2013-09-14 23:48:09.070171	2013-09-14 23:48:09.070174	ATL
975	8104d1e0-15c1-4ad5-b2e2-95e6b932b151	1	Drew Davis	D.Davis	1989-01-04	73	205	Oregon	WR	19	ACT	0	0	2013-09-14 23:48:09.07387	2013-09-14 23:48:09.073873	ATL
976	fa59e399-7416-4217-8285-9f7df2d10ad9	1	Dominique Davis	D.Davis	1989-07-17	75	198	East Carolina	QB	4	ACT	0	0	2013-09-14 23:48:09.077925	2013-09-14 23:48:09.077928	ATL
977	af883091-fc4e-4fcc-8092-8d12e6bb5609	1	Antone Smith	A.Smith	1985-09-17	69	190	Florida State	RB	35	ACT	0	0	2013-09-14 23:48:09.081599	2013-09-14 23:48:09.081601	ATL
978	59b3f179-beb9-4c31-82ba-b4aea4e3b6f2	1	Mike Johnson	M.Johnson	1987-04-02	77	312	Alabama	G	79	IR	0	0	2013-09-14 23:48:09.085085	2013-09-14 23:48:09.085088	ATL
979	38d4d3fa-4539-4eb5-98b6-fe7bba5ff281	1	Sam Baker	S.Baker	1985-05-30	77	307	USC	OT	72	ACT	0	0	2013-09-14 23:48:09.088759	2013-09-14 23:48:09.088764	ATL
980	3cb58404-6768-43a6-9ead-78972ac1f10b	1	Harland Gunn	H.Gunn	1989-08-30	74	324	Miami (FL)	G	69	ACT	0	0	2013-09-14 23:48:09.092523	2013-09-14 23:48:09.092526	ATL
981	e4ba7c28-6942-411e-a528-1dc1a8a8ccc7	1	Harry Douglas	H.Douglas	1984-09-16	72	182	Louisville	WR	83	ACT	0	0	2013-09-14 23:48:09.097143	2013-09-14 23:48:09.097145	ATL
982	49f6d095-101f-4e58-aed0-59925ac04c8a	1	Jeremy Trueblood	J.Trueblood	1983-05-10	80	320	Boston College	OT	65	ACT	0	0	2013-09-14 23:48:09.10074	2013-09-14 23:48:09.100742	ATL
983	cad3dc25-68fe-4115-b72c-41e59a674a99	1	Joe Hawley	J.Hawley	1988-10-22	75	297	Nevada-Las Vegas	G	61	ACT	0	0	2013-09-14 23:48:09.104471	2013-09-14 23:48:09.104473	ATL
984	1f026b72-5d1a-4c7b-a1ef-1ef89b054e56	1	Kevin Cone	K.Cone	1988-03-20	74	216	Georgia Tech	WR	15	ACT	0	0	2013-09-14 23:48:09.108113	2013-09-14 23:48:09.108115	ATL
985	15de0eca-4c32-4d62-91ab-fd4104513c46	1	Bradie Ewing	B.Ewing	1989-12-26	71	239	Wisconsin	FB	34	ACT	0	0	2013-09-14 23:48:09.112249	2013-09-14 23:48:09.112251	ATL
986	5fdee77b-5578-4f91-a3e1-4ea7b57bf1eb	1	Garrett Reynolds	G.Reynolds	1987-07-01	79	317	North Carolina	T	75	ACT	0	0	2013-09-14 23:48:09.116136	2013-09-14 23:48:09.116138	ATL
987	95fcde43-6d48-4468-8986-86e951d25fe5	1	Adam Nissley	A.Nissley	1988-05-06	78	267	Central Florida	TE	86	IR	0	0	2013-09-14 23:48:09.120039	2013-09-14 23:48:09.120041	ATL
988	218d1644-603e-4da3-9ce1-48ce3927494f	1	Matt Bryant	M.Bryant	1975-05-29	69	203	Baylor	K	3	ACT	0	0	2013-09-14 23:48:09.123582	2013-09-14 23:48:09.123585	ATL
989	c3d73869-aa05-4c6c-8bb0-b7630bc495a9	1	Lamar Holmes	L.Holmes	1989-07-08	78	323	Southern Mississippi	T	76	ACT	0	0	2013-09-14 23:48:09.127405	2013-09-14 23:48:09.127408	ATL
990	9ea8eb0a-32f3-4eab-992f-71e607ec65eb	1	Sean Renfree	S.Renfree	1990-04-28	75	219	Duke	QB	12	IR	0	0	2013-09-14 23:48:09.130735	2013-09-14 23:48:09.130737	ATL
991	e965df63-0d31-42d7-b93e-3f2778647a61	1	Ryan Schraeder	R.Schraeder		79	300	Valdosta State	T	73	ACT	0	0	2013-09-14 23:48:09.13416	2013-09-14 23:48:09.134162	ATL
992	4f092f1b-57c9-4f96-902c-0f0ad4d7b03f	1	Andrew Szczerba	A.Szczerba	1988-07-16	78	260	Penn State	TE	85	IR	0	0	2013-09-14 23:48:09.138041	2013-09-14 23:48:09.138044	ATL
993	f6fd0d1f-9d12-4d37-a65d-3d34a47331bc	1	William Moore	W.Moore	1985-05-18	72	218	Missouri	SAF	25	ACT	0	0	2013-09-14 23:48:09.141587	2013-09-14 23:48:09.141589	ATL
994	8cd72bd8-13bc-4593-90e2-d96e8ffa1840	1	Thomas DeCoud	T.DeCoud	1985-03-19	72	193	California	SAF	28	ACT	0	0	2013-09-14 23:48:09.145397	2013-09-14 23:48:09.145401	ATL
995	424dda80-1a85-4339-bc1a-8175f528bef8	1	Chase Coffman	C.Coffman	1986-11-10	78	250	Missouri	TE	86	ACT	0	0	2013-09-14 23:48:09.148965	2013-09-14 23:48:09.148967	ATL
996	91a95850-9514-49d5-b2b0-f8e21156daa0	1	Jacquizz Rodgers	J.Rodgers	1990-02-06	66	196	Oregon State	RB	32	ACT	0	0	2013-09-14 23:48:09.152598	2013-09-14 23:48:09.1526	ATL
997	67a54559-a3e2-477f-9701-56da8984289a	1	Zeke Motta	Z.Motta	1990-05-14	74	213	Notre Dame	SS	41	ACT	0	0	2013-09-14 23:48:09.156174	2013-09-14 23:48:09.156176	ATL
998	DEF-ATL	1	ATL Defense	ATL		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:09.159866	2013-09-14 23:48:09.159868	ATL
999	e0a63251-5428-43a1-88c1-c000215ac5ce	1	Derrick Coleman	D.Coleman	1990-10-18	73	240	UCLA	RB	40	ACT	0	0	2013-09-14 23:48:09.450438	2013-09-14 23:48:09.45044	SEA
1000	fddbbbff-19a2-4982-b4af-d8cbccbe2215	1	Sidney Rice	S.Rice	1986-09-01	76	202	South Carolina	WR	18	ACT	0	0	2013-09-14 23:48:09.453687	2013-09-14 23:48:09.453689	SEA
1001	63fd9abe-4bdf-4611-9497-0c67e030ce01	1	Robert Turbin	R.Turbin	1989-12-02	70	222	Utah State	RB	22	ACT	0	0	2013-09-14 23:48:09.456568	2013-09-14 23:48:09.45657	SEA
1002	09cbfefb-2ef4-4d07-8ac3-fafccc9a2106	1	Zach Miller	Z.Miller	1985-12-11	77	255	Arizona State	TE	86	ACT	0	0	2013-09-14 23:48:09.459375	2013-09-14 23:48:09.459377	SEA
1003	be62bf39-c737-416f-a1ea-6b9d61684a62	1	J.R. Sweezy	J.Sweezy	1989-04-08	77	298	North Carolina State	G	64	ACT	0	0	2013-09-14 23:48:09.462192	2013-09-14 23:48:09.462194	SEA
1004	16c67c97-ffd9-4f92-917d-ad6124ce1f6e	1	Luke Willson	L.Willson	1990-01-15	77	251	Rice	TE	82	ACT	0	0	2013-09-14 23:48:09.4651	2013-09-14 23:48:09.465102	SEA
1005	82bce0be-9a87-4b6d-a85b-623bf8d1674e	1	Marshawn Lynch	M.Lynch	1986-04-22	71	215	California	RB	24	ACT	0	0	2013-09-14 23:48:09.467559	2013-09-14 23:48:09.467561	SEA
1006	53b0a001-2efe-4009-8ff1-572b687d4397	1	James Carpenter	J.Carpenter	1989-03-22	77	321	Alabama	OT	77	ACT	0	0	2013-09-14 23:48:09.469848	2013-09-14 23:48:09.469849	SEA
1007	bbb63a36-8613-4675-8e5e-34200d245ff0	1	Spencer Ware	S.Ware	1991-11-23	70	228	LSU	RB	44	ACT	0	0	2013-09-14 23:48:09.472334	2013-09-14 23:48:09.472335	SEA
1008	40cda44b-2ee3-4ad1-834e-995e30db84d4	1	Steven Hauschka	S.Hauschka	1985-06-29	76	210	North Carolina State	K	4	ACT	0	0	2013-09-14 23:48:09.475054	2013-09-14 23:48:09.475056	SEA
1009	3752af7b-f40d-4f82-8072-4fb84d15090d	1	Percy Harvin	P.Harvin	1988-05-28	71	184	Florida	WR	11	PUP	0	0	2013-09-14 23:48:09.477558	2013-09-14 23:48:09.47756	SEA
1010	38293bdb-87d5-4219-be46-44fea6741483	1	Russell Okung	R.Okung	1987-10-07	77	310	Oklahoma State	OT	76	ACT	0	0	2013-09-14 23:48:09.480032	2013-09-14 23:48:09.480033	SEA
1011	b1674df8-2270-4ade-a168-00159259c0b8	1	Max Unger	M.Unger	1986-04-14	77	305	Oregon	C	60	ACT	0	0	2013-09-14 23:48:09.482465	2013-09-14 23:48:09.482467	SEA
1012	ab0c4c63-df42-4825-8921-3fd1a842c3df	1	Anthony McCoy	A.McCoy	1987-12-28	77	259	USC	TE	85	IR	0	0	2013-09-14 23:48:09.484984	2013-09-14 23:48:09.484986	SEA
1013	1f49b95a-97cb-426e-8bd0-aeeb4b5b0ad1	1	Kam Chancellor	K.Chancellor	1988-04-03	75	232	Virginia Tech	SAF	31	ACT	0	0	2013-09-14 23:48:09.487526	2013-09-14 23:48:09.487528	SEA
1014	70ff9d3e-4339-46da-908f-4aed688f4a1f	1	Stephen Williams	S.Williams	1986-06-29	77	208	Toledo	WR	83	ACT	0	0	2013-09-14 23:48:09.489907	2013-09-14 23:48:09.489909	SEA
1015	cf8e8522-6220-4612-a8a1-72c496dac536	1	Christine Michael	C.Michael	1990-11-09	70	220	Texas A&M	RB	33	ACT	0	0	2013-09-14 23:48:09.492304	2013-09-14 23:48:09.492306	SEA
1016	41d6830d-9512-4f40-bd74-2125b2f84416	1	Tarvaris Jackson	T.Jackson	1983-04-21	74	225	Alabama State	QB	7	ACT	0	0	2013-09-14 23:48:09.494656	2013-09-14 23:48:09.494658	SEA
1017	409d4cac-ee90-4470-9710-ebe671678339	1	Russell Wilson	R.Wilson	1988-11-29	71	206	Wisconsin	QB	3	ACT	0	0	2013-09-14 23:48:09.496855	2013-09-14 23:48:09.496856	SEA
1018	e1b29179-074b-4c91-8797-763b76ac618a	1	Doug Baldwin	D.Baldwin	1988-09-21	70	189	Stanford	WR	89	ACT	0	0	2013-09-14 23:48:09.499082	2013-09-14 23:48:09.499084	SEA
1019	a5210045-10f8-4f59-9547-675fd0f27840	1	Kellen Davis	K.Davis	1985-10-11	79	265	Michigan State	TE	87	ACT	0	0	2013-09-14 23:48:09.502175	2013-09-14 23:48:09.502177	SEA
1020	4094730d-a3ad-4c7e-a899-a3c8001748d9	1	Earl Thomas	E.Thomas	1989-05-07	70	202	Texas	FS	29	ACT	0	0	2013-09-14 23:48:09.505686	2013-09-14 23:48:09.505687	SEA
1021	af867ba7-f44e-4c1f-a4b3-61a9b5a7065d	1	Alvin Bailey	A.Bailey	1991-08-26	75	320	Arkansas	T	78	ACT	0	0	2013-09-14 23:48:09.509158	2013-09-14 23:48:09.50916	SEA
1022	2790db28-d487-43fa-a65e-0c80da7cb9c8	1	Breno Giacomini	B.Giacomini	1985-09-27	79	318	Louisville	OT	68	ACT	0	0	2013-09-14 23:48:09.512738	2013-09-14 23:48:09.512739	SEA
1023	c88d9352-b835-45ed-a909-1cfec09a58bc	1	Golden Tate	G.Tate	1988-08-02	70	202	Notre Dame	WR	81	ACT	0	0	2013-09-14 23:48:09.516512	2013-09-14 23:48:09.516514	SEA
1024	7e5b8212-df93-4069-b3f0-be4b5cb47389	1	Jermaine Kearse	J.Kearse	1990-02-06	73	209	Washington	WR	15	ACT	0	0	2013-09-14 23:48:09.520128	2013-09-14 23:48:09.520131	SEA
1025	d58339ad-6ec1-41cd-98d7-964ac47d7225	1	Jeron Johnson	J.Johnson	1988-06-12	70	212	Boise State	SAF	32	ACT	0	0	2013-09-14 23:48:09.523568	2013-09-14 23:48:09.52357	SEA
1026	7fe2ad54-5650-4019-aab9-0f9b82c796f4	1	Paul McQuistan	P.McQuistan	1983-04-30	78	315	Weber State	T	67	ACT	0	0	2013-09-14 23:48:09.527444	2013-09-14 23:48:09.527446	SEA
1027	0ec13c88-ecfd-437b-a84a-36ce94b51a8f	1	Lemuel Jeanpierre	L.Jeanpierre	1987-05-19	75	301	South Carolina	G	61	ACT	0	0	2013-09-14 23:48:09.531276	2013-09-14 23:48:09.531278	SEA
1028	dfd8f952-5326-4f54-8914-c588c0cdacfb	1	Michael Bowie	M.Bowie	1991-09-25	77	330	NE Oklahoma State	T	73	ACT	0	0	2013-09-14 23:48:09.534884	2013-09-14 23:48:09.534886	SEA
1029	DEF-SEA	1	SEA Defense	SEA		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:09.539127	2013-09-14 23:48:09.539129	SEA
1030	5187d73c-4072-4620-a152-342b648e8e85	1	Levi Brown	L.Brown	1984-03-16	78	324	Penn State	OT	75	ACT	0	0	2013-09-14 23:48:09.811858	2013-09-14 23:48:09.81186	ARI
1031	ba294ab5-616a-4c26-8e9a-bc09d3680610	1	Rashard Mendenhall	R.Mendenhall	1987-06-19	70	225	Illinois	RB	28	ACT	0	0	2013-09-14 23:48:09.816733	2013-09-14 23:48:09.816736	ARI
1032	d7e0401b-31c1-4a8d-b108-4f439cd87ee2	1	Kory Sperry	K.Sperry	1985-04-10	77	250	Colorado State	TE	83	ACT	0	0	2013-09-14 23:48:09.821366	2013-09-14 23:48:09.821368	ARI
1033	dce64b29-6b56-45f4-81dc-b7bfa167bcc9	1	Nate Potter	N.Potter	1988-05-16	78	300	Boise State	T	76	ACT	0	0	2013-09-14 23:48:09.825521	2013-09-14 23:48:09.825523	ARI
1034	9691f874-be36-4529-a7eb-dde22ee4a848	1	Andre Roberts	A.Roberts	1988-01-09	71	195	The Citadel	WR	12	ACT	0	0	2013-09-14 23:48:09.829653	2013-09-14 23:48:09.829655	ARI
1035	86c5152c-c823-4127-97e6-2fedf532e8e8	1	Bobby Massie	B.Massie	1989-08-01	78	316	Mississippi	T	70	ACT	0	0	2013-09-14 23:48:09.833611	2013-09-14 23:48:09.833613	ARI
1036	07f5c9ca-fdcd-4f76-ba60-28b4da8c1327	1	Rashad Johnson	R.Johnson	1986-01-02	71	204	Alabama	SAF	49	ACT	0	0	2013-09-14 23:48:09.837608	2013-09-14 23:48:09.837611	ARI
1037	51952c7b-11c5-4229-baf9-08d4694cc2ad	1	Jaron Brown	J.Brown	1990-01-08	74	205	Clemson	WR	13	ACT	0	0	2013-09-14 23:48:09.841545	2013-09-14 23:48:09.841547	ARI
1038	0d9ed7eb-7787-4672-842e-e734d400dc84	1	Yeremiah Bell	Y.Bell	1978-03-03	72	205	Eastern Kentucky	SAF	37	ACT	0	0	2013-09-14 23:48:09.845437	2013-09-14 23:48:09.84544	ARI
1039	e21e34c8-fb8b-4974-8974-84cdb761f8c3	1	Mike Gibson	M.Gibson	1985-11-18	76	305	California	G	69	ACT	0	0	2013-09-14 23:48:09.853092	2013-09-14 23:48:09.853095	ARI
1040	f6244333-6b6a-4e61-bc2c-cb6ffc2f318a	1	Earl Watford	E.Watford		75	300	James Madison	OG	78	ACT	0	0	2013-09-14 23:48:09.857191	2013-09-14 23:48:09.857193	ARI
1041	eccdeff9-fbcc-4871-8348-7b72e78d1bda	1	Jay Feely	J.Feely	1976-05-23	70	208	Michigan	K	4	ACT	0	0	2013-09-14 23:48:09.86129	2013-09-14 23:48:09.861292	ARI
1042	02fc4471-d92b-491a-9daf-6ec35ae09c3b	1	Kerry Taylor	K.Taylor	1989-02-20	72	200	Arizona State	WR	18	ACT	0	0	2013-09-14 23:48:09.865379	2013-09-14 23:48:09.865381	ARI
1043	3a9e9871-20c3-42b3-ad2c-a2bfec176c7d	1	Paul Fanaika	P.Fanaika	1986-04-09	77	327	Arizona State	G	74	ACT	0	0	2013-09-14 23:48:09.869139	2013-09-14 23:48:09.869142	ARI
1044	b80f5604-dcbf-42e5-aaab-0e996b318002	1	Bradley Sowell	B.Sowell	1989-06-06	79	320	Mississippi	T	79	ACT	0	0	2013-09-14 23:48:09.872795	2013-09-14 23:48:09.872798	ARI
1045	7690ab6a-2ae0-4449-abd5-74ec54403f2e	1	Tony Jefferson	T.Jefferson	1992-01-27	71	213	Oklahoma	FS	36	ACT	0	0	2013-09-14 23:48:09.877142	2013-09-14 23:48:09.877146	ARI
1046	22fb2b54-4936-4e8a-a48d-62096c0c9bb1	1	Drew Stanton	D.Stanton	1984-05-07	75	243	Michigan State	QB	5	ACT	0	0	2013-09-14 23:48:09.880851	2013-09-14 23:48:09.880853	ARI
1047	edd44db5-5649-4e81-a5dd-c4f77d53b011	1	Daryn Colledge	D.Colledge	1982-02-11	76	308	Boise State	G	71	ACT	0	0	2013-09-14 23:48:09.884454	2013-09-14 23:48:09.884457	ARI
1048	0848ad7c-8553-4007-8e01-1f19c81deaba	1	Jeff King	J.King	1983-02-19	75	260	Virginia Tech	TE	87	IR	0	0	2013-09-14 23:48:09.888522	2013-09-14 23:48:09.888525	ARI
1049	47fd7d9a-2726-43d8-be94-fd50d634292f	1	Alfonso Smith	A.Smith	1987-01-23	73	208	Kentucky	RB	29	ACT	0	0	2013-09-14 23:48:09.891991	2013-09-14 23:48:09.891993	ARI
1050	a432666c-9ffd-4094-9071-a9d49d0e20c1	1	Ryan Lindley	R.Lindley	1989-06-22	76	230	San Diego State	QB	14	ACT	0	0	2013-09-14 23:48:09.895974	2013-09-14 23:48:09.895976	ARI
1051	81e6e16c-ef1b-4898-b75a-7bb25741234f	1	Lyle Sendlein	L.Sendlein	1984-03-16	75	308	Texas	C	63	ACT	0	0	2013-09-14 23:48:09.900143	2013-09-14 23:48:09.900145	ARI
1052	f403d099-29d4-43cd-bf79-4aeeb8dc6cd3	1	Justin Bethel	J.Bethel	1990-06-17	72	190	Presbyterian	SAF	31	ACT	0	0	2013-09-14 23:48:09.904129	2013-09-14 23:48:09.904133	ARI
1053	d6aea7ed-2c24-4be5-b789-41e3ba0c2137	1	Jonathan Cooper	J.Cooper	1990-01-19	74	311	North Carolina	G	61	IR	0	0	2013-09-14 23:48:09.90771	2013-09-14 23:48:09.907713	ARI
1054	01547e57-de64-4860-a521-525509dacf5b	1	Stepfan Taylor	S.Taylor	1991-06-09	69	214	Stanford	RB	30	ACT	0	0	2013-09-14 23:48:09.911467	2013-09-14 23:48:09.91147	ARI
1055	68b5fdb2-e0e1-48aa-96a3-18a85c393a09	1	Ryan Williams	R.Williams	1990-04-09	69	207	Virginia Tech	RB	34	ACT	0	0	2013-09-14 23:48:09.915114	2013-09-14 23:48:09.915117	ARI
1056	471dbe81-54c4-4b52-8bd1-4933c9800e1f	1	Michael Floyd	M.Floyd	1989-11-27	75	225	Notre Dame	WR	15	ACT	0	0	2013-09-14 23:48:09.918723	2013-09-14 23:48:09.918726	ARI
1057	38fe7db8-76b7-44a5-8308-b67d1f383829	1	Jim Dray	J.Dray	1986-12-31	77	255	Stanford	TE	81	ACT	0	0	2013-09-14 23:48:09.922467	2013-09-14 23:48:09.922469	ARI
1058	1ce7bca8-68f0-47ba-9484-5baf57dd75e8	1	Andre Ellington	A.Ellington	1989-02-03	69	199	Clemson	RB	38	ACT	0	0	2013-09-14 23:48:09.925987	2013-09-14 23:48:09.925989	ARI
1059	76b51e0a-be98-4a8a-8ac3-dc5e829e1ae9	1	Rob Housler	R.Housler	1988-03-17	77	250	Florida Atlantic	TE	84	ACT	0	0	2013-09-14 23:48:09.929759	2013-09-14 23:48:09.929761	ARI
1060	979f7f83-00e8-4ec8-9420-9e5a53f0b406	1	Eric Winston	E.Winston	1983-11-17	79	302	Miami (Fla.)	OT	65	ACT	0	0	2013-09-14 23:48:09.933693	2013-09-14 23:48:09.933695	ARI
1061	e4a029cd-4889-490f-abf2-4df97ced40c0	1	Javone Lawson	J.Lawson	1990-02-17	73	183	Louisiana-Lafayette	WR	89	IR	0	0	2013-09-14 23:48:09.937399	2013-09-14 23:48:09.937401	ARI
1062	5b05fd1a-2fc5-43bd-9d61-861270522c1b	1	D.C. Jefferson	D.Jefferson	1989-05-07	78	255	Rutgers	TE	86	ACT	0	0	2013-09-14 23:48:09.941449	2013-09-14 23:48:09.941451	ARI
1063	b6a61b38-5cfa-46eb-b1c5-b0255d7ebaf5	1	Larry Fitzgerald	L.Fitzgerald	1983-08-31	75	218	Pittsburgh	WR	11	ACT	0	0	2013-09-14 23:48:09.94504	2013-09-14 23:48:09.945044	ARI
1064	57ad34b3-f60d-4b2d-9e01-3cb5a9451c37	1	Carson Palmer	C.Palmer	1979-12-27	77	235	USC	QB	3	ACT	0	0	2013-09-14 23:48:09.949687	2013-09-14 23:48:09.949689	ARI
1065	DEF-ARI	1	ARI Defense	ARI		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:09.95329	2013-09-14 23:48:09.953293	ARI
1066	46664226-53c3-4ef9-9aeb-f708e3e8269f	1	Mike Iupati	M.Iupati	1987-05-12	77	331	Idaho	G	77	ACT	0	0	2013-09-14 23:48:10.238153	2013-09-14 23:48:10.238154	SF
1067	16cc9ade-f9ad-4d32-b5b9-d7568ee80f58	1	Garrett Celek	G.Celek	1988-05-29	77	252	Michigan State	TE	88	ACT	0	0	2013-09-14 23:48:10.241777	2013-09-14 23:48:10.241779	SF
1068	fe767946-236d-4c04-9c59-5e3edd51acfe	1	Michael Crabtree	M.Crabtree	1987-09-14	73	214	Texas Tech	WR	15	PUP	0	0	2013-09-14 23:48:10.244803	2013-09-14 23:48:10.244805	SF
1069	d7055ba2-f8b4-4407-b491-60c05dff6162	1	Alex Boone	A.Boone	1987-05-04	80	300	Ohio State	OT	75	ACT	0	0	2013-09-14 23:48:10.247421	2013-09-14 23:48:10.247423	SF
1070	3699dfd9-d437-43f7-b674-adbb31e7e64b	1	Colt McCoy	C.McCoy	1986-09-05	73	220	Texas	QB	2	ACT	0	0	2013-09-14 23:48:10.250065	2013-09-14 23:48:10.250067	SF
1071	02f3eb16-982c-48ff-b731-7456812ab200	1	Anthony Davis	A.Davis	1989-10-11	77	323	Rutgers	OT	76	ACT	0	0	2013-09-14 23:48:10.252408	2013-09-14 23:48:10.252409	SF
1072	da8d175e-d233-4a0b-b5db-91e371971577	1	Adam Snyder	A.Snyder	1982-01-30	78	325	Oregon	G	68	ACT	0	0	2013-09-14 23:48:10.255053	2013-09-14 23:48:10.255055	SF
1073	9be8224a-4a19-4f6a-a2be-ecbd3a24868c	1	Bruce Miller	B.Miller	1987-08-06	74	248	Central Florida	FB	49	ACT	0	0	2013-09-14 23:48:10.257405	2013-09-14 23:48:10.257406	SF
1074	21d172c4-1c74-44b8-9131-aee05a2beb60	1	Mario Manningham	M.Manningham	1986-05-25	72	185	Michigan	WR	82	PUP	0	0	2013-09-14 23:48:10.260026	2013-09-14 23:48:10.260028	SF
1075	173f1122-520e-43ae-95c9-a854bd272b29	1	C.J. Spillman	C.Spillman	1986-05-06	72	199	Marshall	SAF	27	ACT	0	0	2013-09-14 23:48:10.262769	2013-09-14 23:48:10.262771	SF
1076	0a95e792-6455-4927-9539-f95fa7f41fbb	1	Vernon Davis	V.Davis	1984-01-31	75	250	Maryland	TE	85	ACT	0	0	2013-09-14 23:48:10.265271	2013-09-14 23:48:10.265273	SF
1077	d5cd4c8a-d534-4dee-aef1-3d1f7e974b61	1	B.J. Daniels	B.Daniels	1989-10-24	72	217	South Florida	QB	5	ACT	0	0	2013-09-14 23:48:10.267504	2013-09-14 23:48:10.267506	SF
1078	f2b3c3e1-535c-42ca-85a5-3f76b63b23bd	1	Jon Baldwin	J.Baldwin	1989-08-10	76	230	Pittsburgh	WR	84	ACT	0	0	2013-09-14 23:48:10.269977	2013-09-14 23:48:10.269978	SF
1079	7bf077c7-40f9-4015-ac73-93f1b7418a24	1	Kendall Hunter	K.Hunter	1988-09-16	67	199	Oklahoma State	RB	32	ACT	0	0	2013-09-14 23:48:10.272455	2013-09-14 23:48:10.272456	SF
1080	8f24a248-b328-43ec-8677-67600e42a8f7	1	Vance McDonald	V.McDonald	1990-06-13	76	267	Rice	TE	89	ACT	0	0	2013-09-14 23:48:10.274815	2013-09-14 23:48:10.274816	SF
1081	c9c6ff4b-952e-41d5-863a-5d5313afcfa6	1	LaMichael James	L.James	1989-10-22	69	195	Oregon	RB	23	ACT	0	0	2013-09-14 23:48:10.277007	2013-09-14 23:48:10.277008	SF
1082	2bd18508-91d1-463f-ab87-18a41fe7ca32	1	Donte Whitner	D.Whitner	1985-07-24	70	208	Ohio State	SAF	31	ACT	0	0	2013-09-14 23:48:10.279246	2013-09-14 23:48:10.279248	SF
1083	52b93a85-f011-4049-8268-cd4de896b6e2	1	Marlon Moore	M.Moore	1987-09-03	72	190	Fresno State	WR	19	ACT	0	0	2013-09-14 23:48:10.281529	2013-09-14 23:48:10.28153	SF
1084	e5247e5f-c4af-4a9b-8c7c-da75ef7fbf8d	1	Phil Dawson	P.Dawson	1975-01-23	71	200	Texas	K	9	ACT	0	0	2013-09-14 23:48:10.284018	2013-09-14 23:48:10.284019	SF
1085	ce205f70-4bcd-4cc8-b4bf-b2e2a530b9dd	1	Brandon Carswell	B.Carswell	1989-05-22	73	201	USC	WR	84	IR	0	0	2013-09-14 23:48:10.286485	2013-09-14 23:48:10.286486	SF
1086	4d628a09-3631-4166-85f6-45f41a74e992	1	Joe Staley	J.Staley	1984-08-30	77	315	Central Michigan	OT	74	ACT	0	0	2013-09-14 23:48:10.291903	2013-09-14 23:48:10.291904	SF
1087	c6c558e1-e2b2-4fb5-a5a3-ee58526f10d8	1	Chris Harper	C.Harper	1989-09-10	73	229	Kansas State	WR	13	ACT	0	0	2013-09-14 23:48:10.294504	2013-09-14 23:48:10.294506	SF
1088	33629816-c735-4a70-9e7c-eec8445eab7a	1	Quinton Patton	Q.Patton	1990-08-09	72	204	Louisiana Tech	WR	11	ACT	0	0	2013-09-14 23:48:10.297259	2013-09-14 23:48:10.29726	SF
1089	eb1d1304-1900-4587-ae06-75c77efd85a8	1	Anquan Boldin	A.Boldin	1980-10-03	73	223	Florida State	WR	81	ACT	0	0	2013-09-14 23:48:10.299783	2013-09-14 23:48:10.299785	SF
1090	ead15824-3958-47f8-9e2e-09670fca7a67	1	Alex Debniak	A.Debniak		74	240	Stanford	FB	44	IR	0	0	2013-09-14 23:48:10.302049	2013-09-14 23:48:10.30205	SF
1091	c615cf52-bc61-43ed-bb76-39695ca019c0	1	Eric Reid	E.Reid	1991-12-10	73	213	LSU	FS	35	ACT	0	0	2013-09-14 23:48:10.305719	2013-09-14 23:48:10.305722	SF
1092	6a2b129d-a9e5-4131-b491-82269b323f77	1	Frank Gore	F.Gore	1983-05-14	69	217	Miami (FL)	RB	21	ACT	0	0	2013-09-14 23:48:10.309448	2013-09-14 23:48:10.309451	SF
1093	0e581a51-e705-45e2-85d3-bc2c073e626e	1	Joe Looney	J.Looney	1990-08-31	75	309	Wake Forest	G	78	ACT	0	0	2013-09-14 23:48:10.313775	2013-09-14 23:48:10.313779	SF
1094	670e7379-29d7-4b64-b289-b8a6f3e12b6a	1	Marcus Lattimore	M.Lattimore	1991-10-29	71	221	South Carolina	RB	38	NON	0	0	2013-09-14 23:48:10.317429	2013-09-14 23:48:10.317431	SF
1095	423cfbc1-446f-4670-b9dc-4b8d7f67745d	1	Kyle Williams	K.Williams	1988-07-19	70	186	Arizona State	WR	10	ACT	0	0	2013-09-14 23:48:10.321317	2013-09-14 23:48:10.321319	SF
1096	d00b8cd0-86fb-4d44-9816-7011747ad3fd	1	Kassim Osgood	K.Osgood	1980-05-20	77	220	San Diego State	WR	14	ACT	0	0	2013-09-14 23:48:10.324868	2013-09-14 23:48:10.324871	SF
1097	d03aa6ca-ae90-44cb-954f-507213a73b22	1	Daniel Kilgore	D.Kilgore	1987-12-18	75	308	Appalachian State	G	67	ACT	0	0	2013-09-14 23:48:10.328653	2013-09-14 23:48:10.328656	SF
1098	e3dd75f8-7b4c-420d-8f0f-a95b8a90ab66	1	Craig Dahl	C.Dahl	1985-06-17	73	212	North Dakota State	SAF	43	ACT	0	0	2013-09-14 23:48:10.332798	2013-09-14 23:48:10.3328	SF
1099	3fed6499-3bcb-42f4-b583-5579a97b5e30	1	Anthony Dixon	A.Dixon	1987-09-24	73	233	Mississippi State	RB	24	ACT	0	0	2013-09-14 23:48:10.336887	2013-09-14 23:48:10.336889	SF
1100	2a5b21e2-e2f1-435b-b05f-aa6b3169554d	1	Luke Marquardt	L.Marquardt	1990-03-23	80	315	Azusa Pacific	T	64	NON	0	0	2013-09-14 23:48:10.340742	2013-09-14 23:48:10.340745	SF
1101	a893e70f-e3a6-4f2c-98c0-0f83c2be00d6	1	Jonathan Goodwin	J.Goodwin	1978-12-02	75	318	Michigan	C	59	ACT	0	0	2013-09-14 23:48:10.34461	2013-09-14 23:48:10.344613	SF
1102	068b70bc-9558-4e99-b729-754fd28937ed	1	Colin Kaepernick	C.Kaepernick	1987-11-03	76	230	Nevada	QB	7	ACT	0	0	2013-09-14 23:48:10.348326	2013-09-14 23:48:10.348328	SF
1103	d19bff06-99b5-42d9-92fe-f60a419b4392	1	Raymond Ventrone	R.Ventrone	1982-10-21	70	200	Villanova	DB	41	ACT	0	0	2013-09-14 23:48:10.35208	2013-09-14 23:48:10.352082	SF
1104	DEF-SF	1	SF Defense	SF		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:10.355794	2013-09-14 23:48:10.355796	SF
1105	27921351-a775-4649-bd49-7b4c486d1ba2	1	Lance Kendricks	L.Kendricks	1988-01-30	75	247	Wisconsin	TE	88	ACT	0	0	2013-09-14 23:48:10.632843	2013-09-14 23:48:10.632846	STL
1106	d19be33b-5177-4cbc-825f-d3061fff6c6e	1	Cory Harkey	C.Harkey	1990-06-17	76	260	UCLA	TE	46	ACT	0	0	2013-09-14 23:48:10.637348	2013-09-14 23:48:10.637351	STL
1107	4a8190f6-039d-485b-8d51-7f98368b02e1	1	Darian Stewart	D.Stewart	1988-08-04	71	214	South Carolina	SAF	20	ACT	0	0	2013-09-14 23:48:10.641875	2013-09-14 23:48:10.641877	STL
1108	837bce25-3d09-47a7-9840-b9afa3c0074c	1	Daryl Richardson	D.Richardson	1990-04-12	70	196	Abilene Christian	RB	26	ACT	0	0	2013-09-14 23:48:10.646062	2013-09-14 23:48:10.646065	STL
1109	3b7a1409-d154-4e5c-8c94-9d4a0e0993c7	1	Jared Cook	J.Cook	1987-04-07	77	248	South Carolina	TE	89	ACT	0	0	2013-09-14 23:48:10.650302	2013-09-14 23:48:10.650305	STL
1110	fdbb3713-de2e-49e8-a6ff-ca7db66404dd	1	Harvey Dahl	H.Dahl	1981-06-24	77	308	Nevada-Reno	G	62	ACT	0	0	2013-09-14 23:48:10.654329	2013-09-14 23:48:10.654332	STL
1111	e0f05175-f652-4f5e-9931-068a712291e6	1	T.J. McDonald	T.McDonald	1991-01-26	74	219	USC	FS	25	ACT	0	0	2013-09-14 23:48:10.658414	2013-09-14 23:48:10.658417	STL
1112	0f034359-b69c-4c34-a648-de78e394ddab	1	Zac Stacy	Z.Stacy	1991-04-09	68	216	Vanderbilt	RB	30	ACT	0	0	2013-09-14 23:48:10.662084	2013-09-14 23:48:10.662086	STL
1113	855b104f-34f9-49b9-b25a-6fa2dec18dba	1	Shelley Smith	S.Smith	1987-05-21	75	297	Colorado State	G	66	ACT	0	0	2013-09-14 23:48:10.665987	2013-09-14 23:48:10.665989	STL
1114	274e943a-b4bd-469b-8fba-f4d24202931a	1	Matthew Daniels	M.Daniels	1989-09-27	72	211	Duke	DB	37	ACT	0	0	2013-09-14 23:48:10.670002	2013-09-14 23:48:10.670004	STL
1115	d53cd589-73d6-4aad-ae69-e979670a0d14	1	Rodger Saffold	R.Saffold	1988-06-06	77	314	Indiana	OT	76	ACT	0	0	2013-09-14 23:48:10.67383	2013-09-14 23:48:10.673832	STL
1116	502b3a6c-e965-478a-858e-964b4ac2296c	1	Tavon Austin	T.Austin	1991-03-15	68	174	West Virginia	WR	11	ACT	0	0	2013-09-14 23:48:10.677432	2013-09-14 23:48:10.677434	STL
1117	081f217e-4ecb-401d-9ab5-3f55528e5619	1	Chris Givens	C.Givens	1989-12-06	72	198	Wake Forest	WR	13	ACT	0	0	2013-09-14 23:48:10.681058	2013-09-14 23:48:10.68106	STL
1118	f963be41-d1a9-4410-8e8d-c21dcbaae24b	1	Chase Reynolds	C.Reynolds	1987-10-22	72	195	Montana	RB	34	ACT	0	0	2013-09-14 23:48:10.685238	2013-09-14 23:48:10.68524	STL
1119	de9e506f-e683-4d15-9d91-ef9625fa74f3	1	Brandon Washington	B.Washington	1988-08-13	74	320	Miami (FL)	G	70	ACT	0	0	2013-09-14 23:48:10.688694	2013-09-14 23:48:10.688696	STL
1120	cc3640b0-7560-431f-84ab-599e9dc8cac6	1	Sam Bradford	S.Bradford	1987-11-08	76	224	Oklahoma	QB	8	ACT	0	0	2013-09-14 23:48:10.692324	2013-09-14 23:48:10.692326	STL
1121	c9c7dc5a-aecb-4d5b-8ffb-fc82184f7e63	1	Matt Giordano	M.Giordano	1982-10-16	71	210	California	DB	27	ACT	0	0	2013-09-14 23:48:10.696423	2013-09-14 23:48:10.696426	STL
1122	93d11276-45d2-4168-a9b7-df0cbf12dabb	1	Greg Zuerlein	G.Zuerlein	1987-12-27	72	187	Missouri Western State	K	4	ACT	0	0	2013-09-14 23:48:10.700186	2013-09-14 23:48:10.700188	STL
1123	da2d3510-355a-4a0d-a79d-bd96b4cfcecb	1	Kellen Clemens	K.Clemens	1983-06-07	74	220	Oregon	QB	10	ACT	0	0	2013-09-14 23:48:10.704549	2013-09-14 23:48:10.704551	STL
1124	37acea2b-df62-4aa6-a064-cf63f20efc12	1	Isaiah Pead	I.Pead	1989-12-14	71	200	Cincinnati	RB	24	ACT	0	0	2013-09-14 23:48:10.708234	2013-09-14 23:48:10.708236	STL
1125	06787c1d-f02b-4217-9152-c269e826928a	1	Benny Cunningham	B.Cunningham	1990-07-07	70	210	Middle Tennessee State	RB	45	ACT	0	0	2013-09-14 23:48:10.711833	2013-09-14 23:48:10.711836	STL
1126	eb881031-ffac-4e6e-80c3-fdfbc6272642	1	Barrett Jones	B.Jones	1990-05-25	76	306	Alabama	G	67	ACT	0	0	2013-09-14 23:48:10.715728	2013-09-14 23:48:10.715731	STL
1127	858bd473-e345-43c6-8e23-be100f63f145	1	Chris Williams	C.Williams	1985-08-26	78	320	Vanderbilt	T	65	ACT	0	0	2013-09-14 23:48:10.719477	2013-09-14 23:48:10.719479	STL
1128	e0e55096-4f50-42e3-897c-663017220b56	1	Jake Long	J.Long	1985-05-09	79	319	Michigan	OT	77	ACT	0	0	2013-09-14 23:48:10.723036	2013-09-14 23:48:10.723039	STL
1129	0c6420ab-6624-4f44-8ed8-d3d3e72914fa	1	Mike McNeill	M.McNeill	1988-03-07	76	235	Nebraska	TE	89	ACT	0	0	2013-09-14 23:48:10.726298	2013-09-14 23:48:10.7263	STL
1130	a5ae791d-9fbe-4568-80ff-a4b813d8203d	1	Tim Barnes	T.Barnes	1988-05-14	76	300	Missouri	C	61	ACT	0	0	2013-09-14 23:48:10.730211	2013-09-14 23:48:10.730214	STL
1131	f8ca735c-2779-4d0c-914e-e58e11c2356d	1	Brian Quick	B.Quick	1989-06-05	75	220	Appalachian State	WR	83	ACT	0	0	2013-09-14 23:48:10.734051	2013-09-14 23:48:10.734053	STL
1132	d954bad7-541b-43d5-9918-ef1cead10b13	1	Joe Barksdale	J.Barksdale	1988-01-01	76	325	LSU	OT	68	ACT	0	0	2013-09-14 23:48:10.737977	2013-09-14 23:48:10.73798	STL
1133	cea336bd-f79b-4d54-a528-1e03ebd1fcfc	1	C.J. Akins	C.Akins	1991-05-10	73	200	Angelo State	WR	19	IR	0	0	2013-09-14 23:48:10.741931	2013-09-14 23:48:10.741934	STL
1134	4432a990-5b9d-402b-ae64-03990eff8146	1	Scott Wells	S.Wells	1981-01-07	74	300	Tennessee	C	63	ACT	0	0	2013-09-14 23:48:10.746059	2013-09-14 23:48:10.746061	STL
1135	bdf9b438-3ec5-485b-ab9c-bbce34e5e306	1	Stedman Bailey	S.Bailey	1990-11-11	70	193	West Virginia	WR	12	ACT	0	0	2013-09-14 23:48:10.753811	2013-09-14 23:48:10.75383	STL
1136	b87b2286-c3e7-46f1-a3b6-abd89aced3c6	1	Austin Pettis	A.Pettis	1988-05-07	75	207	Boise State	WR	18	ACT	0	0	2013-09-14 23:48:10.75747	2013-09-14 23:48:10.757473	STL
1137	b7253ed5-d2c3-4757-8b54-5176fe9f45df	1	Rodney McLeod	R.McLeod	1990-06-23	71	183	Virginia	SAF	23	ACT	0	0	2013-09-14 23:48:10.761103	2013-09-14 23:48:10.761105	STL
1138	86922605-9c45-40e4-a17d-1a95447e866c	1	Quinton Pointer	Q. Pointer	1988-04-16	69	195	Nevada-Las Vegas	DB	33	ACT	0	0	2013-09-14 23:48:10.764859	2013-09-14 23:48:10.764862	STL
1139	DEF-STL	1	STL Defense	STL		0	0		DEF	0	ACT	0	0	2013-09-14 23:48:10.76859	2013-09-14 23:48:10.768592	STL
\.


--
-- Name: players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('players_id_seq', 1139, true);


--
-- Data for Name: recipients; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY recipients (id, stripe_id, user_id) FROM stdin;
\.


--
-- Name: recipients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('recipients_id_seq', 1, false);


--
-- Data for Name: rosters; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY rosters (id, owner_id, created_at, updated_at, market_id, contest_id, buy_in, remaining_salary, score, contest_rank, amount_paid, paid_at, cancelled_cause, cancelled_at, state, positions, submitted_at, contest_type_id, cancelled) FROM stdin;
\.


--
-- Name: rosters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('rosters_id_seq', 1, false);


--
-- Data for Name: rosters_players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY rosters_players (id, player_id, roster_id, purchase_price, player_stats_id, market_id) FROM stdin;
\.


--
-- Name: rosters_players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('rosters_players_id_seq', 1, false);


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY schema_migrations (version) FROM stdin;
20130729221647
20130729221649
20130729221651
20130729221653
20130729221656
20130729221658
20130729221700
20130730000647
20130804081134
20130805030230
20130806072637
20130807060442
20130807061951
20130808001559
20130809215005
20130809221555
20130809230432
20130812202035
20130812215355
20130812234731
20130813004535
20130813185841
20130814022648
20130815042952
20130815064004
20130816134233
20130816182554
20130817031710
20130819193818
20130819200144
20130819230410
20130820233659
20130821082715
20130821220913
20130822184226
20130823090650
20130824042127
20130827004116
20130828025536
20130902001651
20130903141910
20130904075159
20130905012909
20130906145707
20130907032924
20130908154407
20130911190421
20130912062358
20130912091546
20130912142739
20130914231329
\.


--
-- Data for Name: sports; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY sports (id, name, created_at, updated_at) FROM stdin;
1	NFL	0001-01-01 00:00:00	0001-01-01 00:00:00
\.


--
-- Name: sports_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('sports_id_seq', 1, true);


--
-- Data for Name: stat_events; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY stat_events (id, type, data, point_value, created_at, updated_at, player_stats_id, game_stats_id) FROM stdin;
\.


--
-- Name: stat_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('stat_events_id_seq', 1, false);


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY teams (id, sport_id, abbrev, name, conference, division, market, state, country, lat, long, standings, created_at, updated_at) FROM stdin;
1	1	NYJ	Jets	AFC	AFC East	New York	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.34849	2013-09-14 23:47:57.348492
2	1	NE	Patriots	AFC	AFC East	New England	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.354661	2013-09-14 23:47:57.354664
3	1	BUF	Bills	AFC	AFC East	Buffalo	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.358825	2013-09-14 23:47:57.358827
4	1	MIA	Dolphins	AFC	AFC East	Miami	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.362583	2013-09-14 23:47:57.362585
5	1	CLE	Browns	AFC	AFC North	Cleveland	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.366278	2013-09-14 23:47:57.366281
6	1	CIN	Bengals	AFC	AFC North	Cincinnati	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.369575	2013-09-14 23:47:57.369577
7	1	BAL	Ravens	AFC	AFC North	Baltimore	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.372939	2013-09-14 23:47:57.372941
8	1	PIT	Steelers	AFC	AFC North	Pittsburgh	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.376365	2013-09-14 23:47:57.376367
9	1	HOU	Texans	AFC	AFC South	Houston	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.37971	2013-09-14 23:47:57.379712
10	1	IND	Colts	AFC	AFC South	Indianapolis	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.383148	2013-09-14 23:47:57.38315
11	1	TEN	Titans	AFC	AFC South	Tennessee	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.386568	2013-09-14 23:47:57.38657
12	1	JAC	Jaguars	AFC	AFC South	Jacksonville	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.389722	2013-09-14 23:47:57.389724
13	1	KC	Chiefs	AFC	AFC West	Kansas City	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.392998	2013-09-14 23:47:57.392999
14	1	DEN	Broncos	AFC	AFC West	Denver	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.396116	2013-09-14 23:47:57.396119
15	1	OAK	Raiders	AFC	AFC West	Oakland	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.399289	2013-09-14 23:47:57.399291
16	1	SD	Chargers	AFC	AFC West	San Diego	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.402519	2013-09-14 23:47:57.402521
17	1	WAS	Redskins	NFC	NFC East	Washington	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.405494	2013-09-14 23:47:57.405496
18	1	PHI	Eagles	NFC	NFC East	Philadelphia	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.408882	2013-09-14 23:47:57.408884
19	1	DAL	Cowboys	NFC	NFC East	Dallas	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.412055	2013-09-14 23:47:57.412058
20	1	NYG	Giants	NFC	NFC East	New York	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.415475	2013-09-14 23:47:57.415477
21	1	DET	Lions	NFC	NFC North	Detroit	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.418626	2013-09-14 23:47:57.418628
22	1	CHI	Bears	NFC	NFC North	Chicago	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.421711	2013-09-14 23:47:57.421712
23	1	MIN	Vikings	NFC	NFC North	Minnesota	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.424882	2013-09-14 23:47:57.424884
24	1	GB	Packers	NFC	NFC North	Green Bay	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.428303	2013-09-14 23:47:57.428305
25	1	CAR	Panthers	NFC	NFC South	Carolina	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.431587	2013-09-14 23:47:57.431589
26	1	NO	Saints	NFC	NFC South	New Orleans	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.435115	2013-09-14 23:47:57.435117
27	1	TB	Buccaneers	NFC	NFC South	Tampa Bay	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.438401	2013-09-14 23:47:57.438403
28	1	ATL	Falcons	NFC	NFC South	Atlanta	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.44157	2013-09-14 23:47:57.441573
29	1	SEA	Seahawks	NFC	NFC West	Seattle	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.444854	2013-09-14 23:47:57.444856
30	1	ARI	Cardinals	NFC	NFC West	Arizona	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.448131	2013-09-14 23:47:57.448133
31	1	SF	49ers	NFC	NFC West	San Francisco	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.451325	2013-09-14 23:47:57.451327
32	1	STL	Rams	NFC	NFC West	St. Louis	\N	USA	0.000000	0.000000		2013-09-14 23:47:57.45462	2013-09-14 23:47:57.454622
\.


--
-- Name: teams_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('teams_id_seq', 32, true);


--
-- Data for Name: transaction_records; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY transaction_records (id, event, user_id, roster_id, amount) FROM stdin;
\.


--
-- Name: transaction_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('transaction_records_id_seq', 1, false);


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY users (id, name, created_at, updated_at, email, encrypted_password, reset_password_token, reset_password_sent_at, remember_created_at, sign_in_count, current_sign_in_at, last_sign_in_at, current_sign_in_ip, last_sign_in_ip, provider, uid, confirmation_token, confirmed_at, unconfirmed_email, confirmation_sent_at, admin, image_url) FROM stdin;
\.


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('users_id_seq', 1, false);


--
-- Data for Name: venues; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY venues (id, stats_id, country, state, city, type, name, surface) FROM stdin;
\.


--
-- Name: venues_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('venues_id_seq', 1, false);


--
-- Name: contest_rosters_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY rosters
    ADD CONSTRAINT contest_rosters_pkey PRIMARY KEY (id);


--
-- Name: contest_rosters_players_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY rosters_players
    ADD CONSTRAINT contest_rosters_players_pkey PRIMARY KEY (id);


--
-- Name: contest_types_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY contest_types
    ADD CONSTRAINT contest_types_pkey PRIMARY KEY (id);


--
-- Name: contests_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY contests
    ADD CONSTRAINT contests_pkey PRIMARY KEY (id);


--
-- Name: customer_objects_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY customer_objects
    ADD CONSTRAINT customer_objects_pkey PRIMARY KEY (id);


--
-- Name: game_events_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY game_events
    ADD CONSTRAINT game_events_pkey PRIMARY KEY (id);


--
-- Name: games_markets_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY games_markets
    ADD CONSTRAINT games_markets_pkey PRIMARY KEY (id);


--
-- Name: games_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: market_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY market_orders
    ADD CONSTRAINT market_orders_pkey PRIMARY KEY (id);


--
-- Name: market_players_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY market_players
    ADD CONSTRAINT market_players_pkey PRIMARY KEY (id);


--
-- Name: markets_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY markets
    ADD CONSTRAINT markets_pkey PRIMARY KEY (id);


--
-- Name: players_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY players
    ADD CONSTRAINT players_pkey PRIMARY KEY (id);


--
-- Name: recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY recipients
    ADD CONSTRAINT recipients_pkey PRIMARY KEY (id);


--
-- Name: sports_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY sports
    ADD CONSTRAINT sports_pkey PRIMARY KEY (id);


--
-- Name: stat_events_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY stat_events
    ADD CONSTRAINT stat_events_pkey PRIMARY KEY (id);


--
-- Name: teams_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: transaction_records_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY transaction_records
    ADD CONSTRAINT transaction_records_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: venues_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY venues
    ADD CONSTRAINT venues_pkey PRIMARY KEY (id);


--
-- Name: contest_rosters_players_index; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX contest_rosters_players_index ON rosters_players USING btree (player_id, roster_id);


--
-- Name: index_contest_types_on_market_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_contest_types_on_market_id ON contest_types USING btree (market_id);


--
-- Name: index_contests_on_market_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_contests_on_market_id ON contests USING btree (market_id);


--
-- Name: index_game_events_on_game_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_game_events_on_game_stats_id ON game_events USING btree (game_stats_id);


--
-- Name: index_game_events_on_game_stats_id_and_sequence_number; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_game_events_on_game_stats_id_and_sequence_number ON game_events USING btree (game_stats_id, sequence_number);


--
-- Name: index_game_events_on_sequence_number; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_game_events_on_sequence_number ON game_events USING btree (sequence_number);


--
-- Name: index_games_markets_on_market_id_and_game_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_games_markets_on_market_id_and_game_stats_id ON games_markets USING btree (market_id, game_stats_id);


--
-- Name: index_games_on_game_day; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_games_on_game_day ON games USING btree (game_day);


--
-- Name: index_games_on_game_time; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_games_on_game_time ON games USING btree (game_time);


--
-- Name: index_games_on_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_games_on_stats_id ON games USING btree (stats_id);


--
-- Name: index_market_players_on_player_id_and_market_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_market_players_on_player_id_and_market_id ON market_players USING btree (player_id, market_id);


--
-- Name: index_players_on_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_players_on_stats_id ON players USING btree (stats_id);


--
-- Name: index_players_on_team; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_players_on_team ON players USING btree (team);


--
-- Name: index_rosters_on_contest_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_rosters_on_contest_id ON rosters USING btree (contest_id);


--
-- Name: index_rosters_on_contest_type_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_rosters_on_contest_type_id ON rosters USING btree (contest_type_id);


--
-- Name: index_rosters_on_market_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_rosters_on_market_id ON rosters USING btree (market_id);


--
-- Name: index_rosters_on_submitted_at; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_rosters_on_submitted_at ON rosters USING btree (submitted_at);


--
-- Name: index_rosters_players_on_market_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_rosters_players_on_market_id ON rosters_players USING btree (market_id);


--
-- Name: index_sports_on_name; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_sports_on_name ON sports USING btree (name);


--
-- Name: index_stat_events_on_game_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_stat_events_on_game_stats_id ON stat_events USING btree (game_stats_id);


--
-- Name: index_teams_on_abbrev; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_teams_on_abbrev ON teams USING btree (abbrev);


--
-- Name: index_teams_on_abbrev_and_sport_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_teams_on_abbrev_and_sport_id ON teams USING btree (abbrev, sport_id);


--
-- Name: index_transaction_records_on_roster_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_transaction_records_on_roster_id ON transaction_records USING btree (roster_id);


--
-- Name: index_transaction_records_on_user_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_transaction_records_on_user_id ON transaction_records USING btree (user_id);


--
-- Name: index_users_on_confirmation_token; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_confirmation_token ON users USING btree (confirmation_token);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_email ON users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON users USING btree (reset_password_token);


--
-- Name: index_venues_on_stats_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_venues_on_stats_id ON venues USING btree (stats_id);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

