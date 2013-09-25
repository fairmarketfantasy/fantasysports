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

CREATE FUNCTION buy(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
	_market_player market_players;
	_market markets;
BEGIN
	SELECT * FROM rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	SELECT * FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _market_player;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % is locked or nonexistent', _player_id;
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

	SELECT price(_market_player.bets, _market.total_bets, _roster.buy_in, _market.price_multiplier) INTO _price;

	--if the roster is in progress, we can just add the player to the roster without locking on the market
	INSERT INTO rosters_players(player_id, roster_id, purchase_price, player_stats_id, market_id) 
		VALUES (_player_id, _roster_id, _price, _market_player.player_stats_id, _market.id);

	IF _roster.state = 'submitted' THEN
		--perform the updates.
		UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
		UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
		UPDATE rosters SET remaining_salary = remaining_salary - _price WHERE id = _roster_id;
		INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
			   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price);
	END IF;
END;
$$;


ALTER FUNCTION public.buy(_roster_id integer, _player_id integer, OUT _price numeric) OWNER TO fantasysports;

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
		mp.player_id NOT IN (SELECT rosters_players.player_id 
			FROM rosters_players WHERE roster_id = $1);
$_$;


ALTER FUNCTION public.buy_prices(_roster_id integer) OWNER TO fantasysports;

--
-- Name: cancel_roster(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION cancel_roster(_roster_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
BEGIN
	--make sure the roster is in progress
	SELECT * from rosters where id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	--make sure that the market is available
	PERFORM id from markets WHERE id = _roster.market_id and state in ('published', 'opened') FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is unavailable, roster may not be canceled', _roster.market_id;
	END IF;

	-- decrement bets for all market players in roster by buy_in amount
	UPDATE market_players SET bets = bets - _roster.buy_in 
		WHERE market_id = _roster.market_id AND player_id IN
		(SELECT player_id from rosters_players where roster_id = _roster_id); 

	-- decrement total_bets by buy_in times number of players bought
	update markets set total_bets = total_bets -
		_roster.buy_in * (select count(*) from rosters_players where roster_id  = _roster.id)
		where id = _roster.market_id;

	-- delete rosters_players, market_orders, and finally the roster
	DELETE FROM rosters_players WHERE roster_id = _roster_id;
	DELETE FROM market_orders where roster_id = _roster_id;
	DELETE FROM rosters where id = _roster_id;
END;
$$;


ALTER FUNCTION public.cancel_roster(_roster_id integer) OWNER TO fantasysports;

--
-- Name: lock_players(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION lock_players(_market_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_locked_bets numeric := 0;
	_now timestamp;
BEGIN
	--ensure that the market exists and may be closed
	PERFORM id FROM markets WHERE id = _market_id AND state = 'opened' FOR UPDATE;
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
			WHERE id = _market_id;
	END IF;
	
END;
$$;


ALTER FUNCTION public.lock_players(_market_id integer) OWNER TO fantasysports;

--
-- Name: market_prices(integer, integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION market_prices(_market_id integer, _buy_in integer) RETURNS TABLE(player_id integer, buy_price numeric, sell_price numeric, locked boolean, score integer)
    LANGUAGE sql
    AS $_$
	SELECT 
		mp.player_id, 
		price(mp.bets, m.total_bets, $2, m.price_multiplier), 
		price(mp.bets, m.total_bets,  0, m.price_multiplier), 
		mp.locked, 
		mp.score
	FROM markets m
	JOIN market_players mp on m.id = mp.market_id
	WHERE m.id = $1;
$_$;


ALTER FUNCTION public.market_prices(_market_id integer, _buy_in integer) OWNER TO fantasysports;

--
-- Name: open_market(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION open_market(_market_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_market markets;
	_price numeric;
	_market_player market_players;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state = 'published' 
		AND (shadow_bets = 0 OR opened_at < CURRENT_TIMESTAMP) FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not openable', _market_id;
	END IF;

	RAISE NOTICE 'opening market %', _market_id;

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

	UPDATE markets SET state='opened', opened_at = CURRENT_TIMESTAMP WHERE id = _market_id;

END;
$$;


ALTER FUNCTION public.open_market(_market_id integer) OWNER TO fantasysports;

--
-- Name: price(numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
	SELECT CASE ($2 + $3) WHEN 0 THEN 1000 ELSE 
		ROUND(LEAST(100000, GREATEST(1000, ($1 + $3) * 100000 * $4 / ($2 + $3))))
	END;
$_$;


ALTER FUNCTION public.price(bets numeric, total_bets numeric, buy_in numeric, multiplier numeric) OWNER TO fantasysports;

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

	--update player points and stuff in preparation for shadow bets
	WITH 
		total_points as (select player_stats_id, sum(point_value) as points from stat_events group by player_stats_id),
		total_games as (select player_stats_id, count(distinct(game_stats_id)) as games from stat_events group by player_stats_id)
		UPDATE players SET total_games = total_games.games, total_points = total_points.points
		FROM total_points, total_games
		WHERE 
			players.stats_id = total_points.player_stats_id AND 
			players.stats_id = total_games.player_stats_id;

	--check that shadow_bets is something reasonable
	IF _market.shadow_bets <= 1000 THEN
		RAISE NOTICE 'shadow bets is too small, setting to 100000';
		UPDATE markets set shadow_bets = 100000 where id = _market_id;
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
	WITH game_times as ( 
		SELECT 
			min(g.game_time) - INTERVAL '5m' as min_time,
			max(g.game_time) - INTERVAL '5m' as max_time
		FROM games g 
		JOIN games_markets gm on g.stats_id = gm.game_stats_id 
		WHERE gm.market_id = _market_id
	) UPDATE markets SET opened_at = min_time, closed_at = max_time,
		state = 'published', published_at = CURRENT_TIMESTAMP, price_multiplier = 1
		FROM game_times
		WHERE id = _market_id;

	RAISE NOTICE 'published market %', _market_id;
END;
$$;


ALTER FUNCTION public.publish_market(_market_id integer, OUT _market markets) OWNER TO fantasysports;

--
-- Name: remove_shadow_bets(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION remove_shadow_bets(_market_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	_real_bets numeric;
	_market markets;
	_new_shadow_bets numeric;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state in ('published', 'opened') AND shadow_bets > 0
		FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'cannot remove shadow bets from market %', _market_id;
	END IF;

	--adjust shadow bets:
	--if it's time to open the market, simply remove remaining shadow bets
	--else, ensure that the total number of shadow bets removed from the initial
	--pool of shadow bets is proportial to the number of bets cast, where the coefficient
	--is the shadow_bet_rate
	_real_bets = _market.total_bets - _market.shadow_bets;
	_new_shadow_bets = GREATEST(0, _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate);

	--if no change, then return
	IF _market.shadow_bets - _new_shadow_bets = 0 THEN
		RETURN;
	END IF;

	UPDATE markets SET shadow_bets = _new_shadow_bets, total_bets = _real_bets + _new_shadow_bets 
		WHERE id = _market_id;
	UPDATE market_players SET
		bets = bets - shadow_bets + (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets,
		shadow_bets = (initial_shadow_bets / _market.initial_shadow_bets) * _new_shadow_bets
		WHERE market_id = _market_id;
END;
$$;


ALTER FUNCTION public.remove_shadow_bets(_market_id integer) OWNER TO fantasysports;

--
-- Name: roster_prices(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION roster_prices(_roster_id integer) RETURNS TABLE(purchase_price numeric, player_id integer, buy_price numeric, sell_price numeric, locked boolean, score integer, id integer, stats_id character varying, sport_id integer, name character varying, name_abbr character varying, birthdate character varying, height integer, weight integer, college character varying, "position" character varying, jersey_number integer, status character varying, total_games integer, total_points integer, created_at timestamp without time zone, updated_at timestamp without time zone, team character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
BEGIN
	SELECT * FROM rosters WHERE rosters.id = _roster_id INTO _roster;
	RETURN QUERY SELECT rp.purchase_price, mp.*, p.* from market_prices(_roster.market_id, _roster.buy_in) mp
	join players p on p.id = mp.player_id
	join rosters_players rp on rp.player_id = mp.player_id and rp.roster_id = _roster_id;
END;
$$;


ALTER FUNCTION public.roster_prices(_roster_id integer) OWNER TO fantasysports;

--
-- Name: sell(integer, integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION sell(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_market markets;
BEGIN
	SELECT * from rosters WHERE id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
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

	--if in progress, simply remove from roster and exit stage left
	DELETE FROM rosters_players where roster_id = _roster_id AND player_id = _player_id;

	IF _roster.state = 'submitted' THEN
		--perform the updates.
		UPDATE markets SET total_bets = total_bets - _roster.buy_in WHERE id = _roster.market_id;
		UPDATE market_players SET bets = bets - _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
		UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
		INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price);
	END IF;

END;
$$;


ALTER FUNCTION public.sell(_roster_id integer, _player_id integer, OUT _price numeric) OWNER TO fantasysports;

--
-- Name: sell_prices(integer); Type: FUNCTION; Schema: public; Owner: fantasysports
--

CREATE FUNCTION sell_prices(_roster_id integer) RETURNS TABLE(roster_player_id integer, player_id integer, sell_price numeric, purchase_price numeric, locked boolean, score integer)
    LANGUAGE sql
    AS $_$
	SELECT rp.id, mp.player_id, price(mp.bets, m.total_bets, 0, m.price_multiplier), 
		rp.purchase_price, mp.locked, mp.score
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
			(select player_stats_id from rosters_players where roster_id = rosters.id) AND market_id = $1
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
    private boolean,
    salary_cap integer,
    payout_description character varying(255) DEFAULT ''::character varying NOT NULL
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
-- Name: contest_types_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('contest_types_id_seq', 1, false);


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
    num_rosters integer DEFAULT 0,
    paid_at timestamp without time zone
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
-- Name: contests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('contests_id_seq', 1, false);


--
-- Name: credit_cards; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE credit_cards (
    id integer NOT NULL,
    customer_object_id integer NOT NULL,
    card_number_hash character varying(255) NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    card_id character varying(255) NOT NULL
);


ALTER TABLE public.credit_cards OWNER TO fantasysports;

--
-- Name: credit_cards_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE credit_cards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.credit_cards_id_seq OWNER TO fantasysports;

--
-- Name: credit_cards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE credit_cards_id_seq OWNED BY credit_cards.id;


--
-- Name: credit_cards_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('credit_cards_id_seq', 1, false);


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
-- Name: customer_objects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('customer_objects_id_seq', 1, false);


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
-- Name: game_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('game_events_id_seq', 224, true);


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
-- Name: games_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('games_id_seq', 332, true);


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
-- Name: games_markets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('games_markets_id_seq', 644, true);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE invitations (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    inviter_id integer NOT NULL,
    private_contest_id integer,
    contest_type_id integer,
    code character varying(255) NOT NULL,
    redeemed boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.invitations OWNER TO fantasysports;

--
-- Name: invitations_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE invitations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.invitations_id_seq OWNER TO fantasysports;

--
-- Name: invitations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE invitations_id_seq OWNED BY invitations.id;


--
-- Name: invitations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('invitations_id_seq', 1, false);


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
-- Name: market_orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('market_orders_id_seq', 1, false);


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
-- Name: market_players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('market_players_id_seq', 18876, true);


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
-- Name: markets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('markets_id_seq', 93, true);


--
-- Name: oauth2_access_tokens; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE oauth2_access_tokens (
    id integer NOT NULL,
    user_id integer,
    client_id integer,
    refresh_token_id integer,
    token character varying(255),
    expires_at timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.oauth2_access_tokens OWNER TO fantasysports;

--
-- Name: oauth2_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE oauth2_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_access_tokens_id_seq OWNER TO fantasysports;

--
-- Name: oauth2_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE oauth2_access_tokens_id_seq OWNED BY oauth2_access_tokens.id;


--
-- Name: oauth2_access_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('oauth2_access_tokens_id_seq', 1, false);


--
-- Name: oauth2_authorization_codes; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE oauth2_authorization_codes (
    id integer NOT NULL,
    user_id integer,
    client_id integer,
    token character varying(255),
    expires_at timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.oauth2_authorization_codes OWNER TO fantasysports;

--
-- Name: oauth2_authorization_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE oauth2_authorization_codes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_authorization_codes_id_seq OWNER TO fantasysports;

--
-- Name: oauth2_authorization_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE oauth2_authorization_codes_id_seq OWNED BY oauth2_authorization_codes.id;


--
-- Name: oauth2_authorization_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('oauth2_authorization_codes_id_seq', 1, false);


--
-- Name: oauth2_clients; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE oauth2_clients (
    id integer NOT NULL,
    name character varying(255),
    redirect_uri character varying(255),
    website character varying(255),
    identifier character varying(255),
    secret character varying(255),
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.oauth2_clients OWNER TO fantasysports;

--
-- Name: oauth2_clients_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE oauth2_clients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_clients_id_seq OWNER TO fantasysports;

--
-- Name: oauth2_clients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE oauth2_clients_id_seq OWNED BY oauth2_clients.id;


--
-- Name: oauth2_clients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('oauth2_clients_id_seq', 1, true);


--
-- Name: oauth2_refresh_tokens; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE oauth2_refresh_tokens (
    id integer NOT NULL,
    user_id integer,
    client_id integer,
    token character varying(255),
    expires_at timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


ALTER TABLE public.oauth2_refresh_tokens OWNER TO fantasysports;

--
-- Name: oauth2_refresh_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: fantasysports
--

CREATE SEQUENCE oauth2_refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.oauth2_refresh_tokens_id_seq OWNER TO fantasysports;

--
-- Name: oauth2_refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: fantasysports
--

ALTER SEQUENCE oauth2_refresh_tokens_id_seq OWNED BY oauth2_refresh_tokens.id;


--
-- Name: oauth2_refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('oauth2_refresh_tokens_id_seq', 1, false);


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
-- Name: players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('players_id_seq', 432, true);


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
-- Name: recipients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('recipients_id_seq', 1, false);


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
-- Name: rosters_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('rosters_id_seq', 1, false);


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
-- Name: rosters_players_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('rosters_players_id_seq', 1, false);


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
-- Name: sports_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('sports_id_seq', 3, true);


--
-- Name: stat_events; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE stat_events (
    id integer NOT NULL,
    activity character varying(255) NOT NULL,
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
-- Name: stat_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('stat_events_id_seq', 1, false);


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
-- Name: teams_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('teams_id_seq', 12, true);


--
-- Name: transaction_records; Type: TABLE; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE TABLE transaction_records (
    id integer NOT NULL,
    event character varying(255) NOT NULL,
    user_id integer,
    roster_id integer,
    amount integer,
    contest_id integer
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
-- Name: transaction_records_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('transaction_records_id_seq', 1, false);


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
    image_url character varying(255),
    total_points integer DEFAULT 0 NOT NULL,
    total_wins integer DEFAULT 0 NOT NULL,
    win_percentile numeric DEFAULT 0 NOT NULL
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
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('users_id_seq', 1, true);


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
-- Name: venues_id_seq; Type: SEQUENCE SET; Schema: public; Owner: fantasysports
--

SELECT pg_catalog.setval('venues_id_seq', 1, false);


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

ALTER TABLE ONLY credit_cards ALTER COLUMN id SET DEFAULT nextval('credit_cards_id_seq'::regclass);


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

ALTER TABLE ONLY invitations ALTER COLUMN id SET DEFAULT nextval('invitations_id_seq'::regclass);


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

ALTER TABLE ONLY oauth2_access_tokens ALTER COLUMN id SET DEFAULT nextval('oauth2_access_tokens_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY oauth2_authorization_codes ALTER COLUMN id SET DEFAULT nextval('oauth2_authorization_codes_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY oauth2_clients ALTER COLUMN id SET DEFAULT nextval('oauth2_clients_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: fantasysports
--

ALTER TABLE ONLY oauth2_refresh_tokens ALTER COLUMN id SET DEFAULT nextval('oauth2_refresh_tokens_id_seq'::regclass);


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

COPY contest_types (id, market_id, name, description, max_entries, buy_in, rake, payout_structure, user_id, private, salary_cap, payout_description) FROM stdin;
\.


--
-- Data for Name: contests; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY contests (id, owner_id, buy_in, user_cap, start_time, end_time, created_at, updated_at, market_id, invitation_code, contest_type_id, num_rosters, paid_at) FROM stdin;
\.


--
-- Data for Name: credit_cards; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY credit_cards (id, customer_object_id, card_number_hash, deleted, card_id) FROM stdin;
\.


--
-- Data for Name: customer_objects; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY customer_objects (id, stripe_id, user_id, created_at, updated_at, balance, locked, locked_reason) FROM stdin;
\.


--
-- Data for Name: game_events; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY game_events (id, stats_id, sequence_number, type, summary, clock, data, created_at, updated_at, game_stats_id, acting_team) FROM stdin;
1		1	cointoss	MIN wins coin toss, elects to receive.	15:00		2013-09-25 01:35:10.244127	2013-09-25 01:35:10.244127	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
2	c4dbf896-9d84-4a4b-91fe-1d3effff1ab1	2	kick	8-B.Cundiff kicks 74 yards from CLE 35. 84-C.Patterson to MIN 20 for 29 yards (25-C.Ogbonnaya).	15:00		2013-09-25 01:35:10.248104	2013-09-25 01:35:10.248105	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
3	e2634444-1cc3-42c7-8788-fb8df003ba98	3	rush	28-A.Peterson to MIN 24 for 4 yards (71-A.Rubin).	14:56		2013-09-25 01:35:10.249895	2013-09-25 01:35:10.249896	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
4	90d56eed-7a2b-428f-9223-7eed934ce382	4	pass	7-C.Ponder complete to 82-K.Rudolph. 82-K.Rudolph to MIN 29 for 5 yards (53-C.Robertson).	14:21		2013-09-25 01:35:10.251232	2013-09-25 01:35:10.251234	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
5	da5a7324-7b23-41ff-8952-33141ff3bc6d	5	rush	28-A.Peterson to MIN 33 for 4 yards (92-D.Bryant).	13:44		2013-09-25 01:35:10.252477	2013-09-25 01:35:10.252477	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
6	afbe7629-00f6-4c34-b573-921109aeb16f	6	pass	7-C.Ponder complete to 15-G.Jennings. 15-G.Jennings pushed ob at CLE 40 for 27 yards (39-T.Gipson).	13:08		2013-09-25 01:35:10.253461	2013-09-25 01:35:10.253462	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
7	6486971b-9751-4a61-aab4-901840acdf37	7	rush	28-A.Peterson to CLE 39 for 1 yard (52-D.Jackson).	12:42		2013-09-25 01:35:10.254553	2013-09-25 01:35:10.254554	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
8	39b655bc-c069-4af6-b0b2-5b24629ec062	8	rush	28-A.Peterson to CLE 35 for 4 yards (43-T.Ward,92-D.Bryant).	12:02		2013-09-25 01:35:10.255624	2013-09-25 01:35:10.255624	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
9	42ccca2b-eed6-40dd-bc48-eae3b8724471	9	pass	7-C.Ponder complete to 17-J.Wright. 17-J.Wright to CLE 15 for 20 yards (43-T.Ward).	11:25		2013-09-25 01:35:10.256646	2013-09-25 01:35:10.256647	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
10	9dc31706-310a-4108-bef5-a7a5da68a6f6	10	pass	7-C.Ponder incomplete. Intended for 89-J.Carlson.	10:44		2013-09-25 01:35:10.257965	2013-09-25 01:35:10.257966	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
11	9522c5ce-1025-4acd-bab0-60673fe2e389	11	rush	28-A.Peterson to CLE 6 for 9 yards.	10:38		2013-09-25 01:35:10.259095	2013-09-25 01:35:10.259096	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
12	c6d73175-ebef-4c2f-8184-392157c18b77	12	rush	28-A.Peterson to CLE 2 for 4 yards (51-B.Mingo,43-T.Ward).	09:57		2013-09-25 01:35:10.260314	2013-09-25 01:35:10.260315	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
13	2b68af75-f3d0-45c0-8a83-1d682761363c	13	rush	28-A.Peterson runs 2 yards for a touchdown.	09:19		2013-09-25 01:35:10.261396	2013-09-25 01:35:10.261396	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
14	f9268ef3-b524-4a83-85b7-603d0829b8e5	14	extrapoint	3-B.Walsh extra point is good.	09:13		2013-09-25 01:35:10.262406	2013-09-25 01:35:10.262406	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
15		15	tvtimeout	TV timeout at 09:13.	09:13		2013-09-25 01:35:10.263588	2013-09-25 01:35:10.263588	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
16	a2951f21-a136-4c6f-abb6-684ebdd32c39	16	kick	3-B.Walsh kicks 65 yards from MIN 35 to CLE End Zone. touchback.	09:13		2013-09-25 01:35:10.264564	2013-09-25 01:35:10.264565	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
17		17	tvtimeout	TV timeout at 09:13.	09:13		2013-09-25 01:35:10.265509	2013-09-25 01:35:10.26551	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
18	04fd5398-4718-4559-bff2-e1b7a5030233	18	pass	6-B.Hoyer incomplete. Intended for 15-D.Bess.	09:13		2013-09-25 01:35:10.267346	2013-09-25 01:35:10.267347	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
19	f1a44a42-2fd6-412a-8666-b2e996fe0d54	19	rush	34-B.Rainey to CLE 21 for 1 yard (98-L.Guion,50-E.Henderson).	09:09		2013-09-25 01:35:10.268341	2013-09-25 01:35:10.268342	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
20	4375ce25-e279-416b-a40d-93c58e7f8a5a	20	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	08:32		2013-09-25 01:35:10.269372	2013-09-25 01:35:10.269373	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
21	7699c499-0f77-4ad8-9f8d-30b79451ae77	21	punt	5-S.Lanning punts 56 yards from CLE 21. 35-M.Sherels to MIN 25 for 2 yards (24-J.Bademosi). Penalty on MIN 21-J.Robinson, Illegal block in the back, 10 yards, enforced at MIN 25.	08:28		2013-09-25 01:35:10.270509	2013-09-25 01:35:10.270509	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
22		22	tvtimeout	TV timeout at 08:20.	08:20		2013-09-25 01:35:10.2715	2013-09-25 01:35:10.271501	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
23	9aac6321-c123-46b9-8848-355900dc76d5	23	pass	7-C.Ponder incomplete. Intended for 84-C.Patterson.	08:17		2013-09-25 01:35:10.272484	2013-09-25 01:35:10.272485	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
24	426c42e9-abb0-4beb-81f4-6820b0ca5b05	24	rush	28-A.Peterson to MIN 16 for 1 yard (99-P.Kruger).	08:11		2013-09-25 01:35:10.273492	2013-09-25 01:35:10.273492	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
25	4c8b23ae-3c5c-44e8-820c-3238ef6802a0	25	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson to MIN 23 for 7 yards (39-T.Gipson).	07:32		2013-09-25 01:35:10.274517	2013-09-25 01:35:10.274518	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
26	09529434-3827-4b53-85a0-d784295b1fa6	26	punt	12-J.Locke punts 45 yards from MIN 23 to CLE 32, fair catch by 80-T.Benjamin.	07:03		2013-09-25 01:35:10.275561	2013-09-25 01:35:10.275562	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
27		27	tvtimeout	TV timeout at 06:58.	06:58		2013-09-25 01:35:10.276577	2013-09-25 01:35:10.276578	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
28	6ef3b3d9-5a8f-4776-b67f-6bc137e58f83	28	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess to CLE 41 for 9 yards (52-C.Greenway).	06:55		2013-09-25 01:35:10.277557	2013-09-25 01:35:10.277558	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
29	f009a342-8862-472a-b86e-41dd03357bf1	29	rush	25-C.Ogbonnaya to CLE 42 for 1 yard (97-E.Griffen,52-C.Greenway).	06:21		2013-09-25 01:35:10.27855	2013-09-25 01:35:10.278551	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
30	007bf299-6fbd-4ebd-963c-56257a4d556a	30	rush	26-W.McGahee to CLE 42 for no gain (59-D.Bishop,50-E.Henderson).	05:50		2013-09-25 01:35:10.27954	2013-09-25 01:35:10.27954	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
31	104c6c8c-8ef2-489b-9cc8-4e4726f9087a	31	pass	6-B.Hoyer incomplete. Intended for 25-C.Ogbonnaya.	05:15		2013-09-25 01:35:10.280544	2013-09-25 01:35:10.280545	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
32	3db009df-1c93-4a73-ba6a-f5560df92e5c	32	pass	6-B.Hoyer complete to 84-J.Cameron. 84-J.Cameron pushed ob at MIN 47 for 11 yards (52-C.Greenway).	05:09		2013-09-25 01:35:10.281515	2013-09-25 01:35:10.281516	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
33	f4aa161d-ec38-4132-bf22-0bbf2a7623ad	33	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon runs 47 yards for a touchdown.	04:50		2013-09-25 01:35:10.282716	2013-09-25 01:35:10.282717	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
34	d2cd95ee-8bab-42c0-a355-e5bd59b45355	34	extrapoint	8-B.Cundiff extra point is good.	04:42		2013-09-25 01:35:10.283723	2013-09-25 01:35:10.283724	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
35		35	tvtimeout	TV timeout at 04:42.	04:42		2013-09-25 01:35:10.284682	2013-09-25 01:35:10.284682	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
36	909907a5-ec9c-4602-95d1-56f51da88d26	36	kick	8-B.Cundiff kicks 65 yards from CLE 35 to MIN End Zone. touchback.	04:42		2013-09-25 01:35:10.285679	2013-09-25 01:35:10.285679	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
37	fd1835d4-6659-4715-baf7-154ebafed5b0	37	rush	28-A.Peterson to MIN 20 for no gain (97-J.Sheard).	04:42		2013-09-25 01:35:10.286621	2013-09-25 01:35:10.286622	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
38	b729e35d-0408-4b75-be70-aa34cf534b88	38	pass	7-C.Ponder incomplete. Intended for 82-K.Rudolph.	04:07		2013-09-25 01:35:10.287552	2013-09-25 01:35:10.287553	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
39	c491a4b4-d379-4265-a910-3432da3dba5b	39	pass	7-C.Ponder sacked at MIN 14 for -6 yards (90-B.Winn).	04:01		2013-09-25 01:35:10.288453	2013-09-25 01:35:10.288454	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
40	313b8a96-64c0-4f09-8b5d-44f37f2d5f7a	40	punt	12-J.Locke punts 50 yards from MIN 14. 80-T.Benjamin to CLE 28 for -8 yards (24-A.Jefferson). Penalty on CLE 96-P.Hazel, Holding, 10 yards, enforced at CLE 28.	03:33		2013-09-25 01:35:10.289763	2013-09-25 01:35:10.289763	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
41	0f579888-e559-4ef2-8131-57f60084d7ea	41	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to CLE 48 for 30 yards (50-E.Henderson).	03:21		2013-09-25 01:35:10.290768	2013-09-25 01:35:10.290769	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
42	9a374615-246e-46a5-ae74-2059de0c693d	42	penalty	Penalty on MIN 69-J.Allen, Neutral zone infraction, 5 yards, enforced at CLE 48. No Play.	02:53		2013-09-25 01:35:10.291763	2013-09-25 01:35:10.291764	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
43	41905c4c-8e20-4dfc-abdb-96d774741c56	43	rush	6-B.Hoyer to MIN 49 for -2 yards (96-B.Robison).	02:36		2013-09-25 01:35:10.292757	2013-09-25 01:35:10.292758	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
44	46c1ee3c-b6af-4fe4-b976-28979d16a9bf	44	pass	6-B.Hoyer complete to 25-C.Ogbonnaya. 25-C.Ogbonnaya to MIN 43 for 6 yards (55-M.Mitchell).	02:06		2013-09-25 01:35:10.293771	2013-09-25 01:35:10.293772	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
45	55b7ff1f-3ab7-4228-862a-29ea4da98191	45	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess to MIN 40 for 3 yards (35-M.Sherels).	01:12		2013-09-25 01:35:10.294932	2013-09-25 01:35:10.294932	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
46	f47e0057-a3e9-4ee0-b820-63cd5b62e84e	46	rush	12-J.Gordon pushed ob at MIN 18 for 22 yards (55-M.Mitchell).	:43		2013-09-25 01:35:10.295884	2013-09-25 01:35:10.295885	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
47	524a0f5b-43d5-4f35-a4ce-54b21180f441	47	pass	6-B.Hoyer complete to 18-G.Little. 18-G.Little to MIN 19 for -1 yard (35-M.Sherels).	:01		2013-09-25 01:35:10.296828	2013-09-25 01:35:10.296828	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
48		48	quarterend	End of Quarter	:00		2013-09-25 01:35:10.297751	2013-09-25 01:35:10.297751	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
49	92b03bd0-e959-409c-9ce5-535ecc60229e	49	pass	6-B.Hoyer complete to 84-J.Cameron. 84-J.Cameron runs 19 yards for a touchdown.	15:00		2013-09-25 01:35:10.298663	2013-09-25 01:35:10.298664	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
50	7734e10d-2177-4377-b85f-c402ded3c2a6	50	extrapoint	8-B.Cundiff extra point is good.	14:55		2013-09-25 01:35:10.299582	2013-09-25 01:35:10.299582	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
51	9528d2f1-9e35-423f-b44c-b120c9109538	51	kick	8-B.Cundiff kicks 65 yards from CLE 35 to MIN End Zone. touchback.	14:55		2013-09-25 01:35:10.300559	2013-09-25 01:35:10.30056	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
52	723951c9-eafa-4ec0-aba3-9edc39309682	52	pass	7-C.Ponder complete to 17-J.Wright. 17-J.Wright pushed ob at MIN 31 for 11 yards (21-C.Owens).	14:55		2013-09-25 01:35:10.301501	2013-09-25 01:35:10.301502	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
53	d0bfa892-4260-4057-978d-acad7aefc0dd	53	rush	28-A.Peterson to MIN 37 for 6 yards (99-P.Kruger,23-J.Haden).	14:30		2013-09-25 01:35:10.302433	2013-09-25 01:35:10.302433	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
54	ba0354d2-6faa-4088-a863-0b588f33186d	54	rush	28-A.Peterson to MIN 45 for 8 yards (22-B.Skrine).	13:57		2013-09-25 01:35:10.303383	2013-09-25 01:35:10.303383	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
55	c30a9255-170e-4263-83cd-8e5477ce73c5	55	rush	28-A.Peterson to MIN 44 for -1 yard (67-I.Kitchen,52-D.Jackson).	13:20		2013-09-25 01:35:10.304344	2013-09-25 01:35:10.304344	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
56	afe7a945-2210-486c-ac34-a63e8c82b3b3	56	pass	7-C.Ponder complete to 84-C.Patterson. 84-C.Patterson to CLE 19 for 37 yards (22-B.Skrine).	12:46		2013-09-25 01:35:10.305291	2013-09-25 01:35:10.305292	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
57	62692423-c23e-4742-9a19-fba159d50f4b	57	pass	7-C.Ponder complete to 15-G.Jennings. 15-G.Jennings pushed ob at CLE 10 for 9 yards (39-T.Gipson).	11:59		2013-09-25 01:35:10.306377	2013-09-25 01:35:10.306378	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
58	1cc889a0-c575-41d2-a5fd-3ef74fb8446f	58	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson pushed ob at CLE 7 for 3 yards (43-T.Ward).	11:26		2013-09-25 01:35:10.307344	2013-09-25 01:35:10.307345	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
59	12e76419-a70e-43ec-a76c-d2d82d32e8de	59	rush	28-A.Peterson to CLE 6 for 1 yard (90-B.Winn,99-P.Kruger).	10:54		2013-09-25 01:35:10.308318	2013-09-25 01:35:10.308319	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
60	af91a550-1d89-4cd0-96ec-c26adae0020b	60	rush	7-C.Ponder runs 6 yards for a touchdown.	10:15		2013-09-25 01:35:10.309298	2013-09-25 01:35:10.309298	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
61	a000896a-c1df-4d53-93a1-fad44580fd67	61	extrapoint	3-B.Walsh extra point is good.	10:12		2013-09-25 01:35:10.310334	2013-09-25 01:35:10.310335	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
62		62	tvtimeout	TV timeout at 10:12.	10:12		2013-09-25 01:35:10.311317	2013-09-25 01:35:10.311318	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
63	12a07669-28fe-46c2-bc01-9d3851c019af	63	kick	3-B.Walsh kicks 65 yards from MIN 35 to CLE End Zone. touchback.	10:12		2013-09-25 01:35:10.312267	2013-09-25 01:35:10.312267	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
64		64	tvtimeout	TV timeout at 10:12.	10:12		2013-09-25 01:35:10.3132	2013-09-25 01:35:10.313201	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
65	f32c943b-1f9d-4ac1-b287-c015d1e171da	65	rush	26-W.McGahee to CLE 24 for 4 yards (95-S.Floyd). Penalty on MIN 96-B.Robison, Illegal use of hands, 5 yards, enforced at CLE 24.	10:12		2013-09-25 01:35:10.314154	2013-09-25 01:35:10.314154	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
66	af8ee99b-135d-45eb-84f6-d0870e50defc	66	pass	6-B.Hoyer complete to 25-C.Ogbonnaya. 25-C.Ogbonnaya to CLE 34 for 5 yards (59-D.Bishop).	09:49		2013-09-25 01:35:10.315131	2013-09-25 01:35:10.315131	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
67	6b647545-8ca7-4b12-8e9e-16567110d11b	67	rush	26-W.McGahee to CLE 33 for -1 yard (97-E.Griffen).	09:13		2013-09-25 01:35:10.316064	2013-09-25 01:35:10.316065	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
68	22c0e375-c75f-4031-9c11-9846da4b5a64	68	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to CLE 38 for 5 yards (35-M.Sherels).	08:38		2013-09-25 01:35:10.317819	2013-09-25 01:35:10.317819	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
69	db4979d5-5c93-4e84-8049-c7fb4c490e66	69	rush	37-J.Aubrey to MIN 28 for 34 yards (35-M.Sherels).	08:05		2013-09-25 01:35:10.318819	2013-09-25 01:35:10.31882	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
70	7a929038-7594-4072-8b4d-2716a51418d0	70	rush	26-W.McGahee to MIN 26 for 2 yards (52-C.Greenway).	07:10		2013-09-25 01:35:10.319853	2013-09-25 01:35:10.319854	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
71	219ce340-047d-4e06-af36-5a41c1530241	71	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	06:43		2013-09-25 01:35:10.320855	2013-09-25 01:35:10.320856	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
72	5e4db8c6-c5f2-4255-ae56-62364de28258	72	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess pushed ob at MIN 20 for 6 yards (21-J.Robinson).	06:35		2013-09-25 01:35:10.32182	2013-09-25 01:35:10.32182	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
73	68241ca5-e56d-4a24-9a14-b2a56de09608	73	fieldgoal	8-B.Cundiff 38 yards Field Goal is Good.	06:12		2013-09-25 01:35:10.32278	2013-09-25 01:35:10.322781	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
74		74	tvtimeout	TV timeout at 06:07.	06:07		2013-09-25 01:35:10.323755	2013-09-25 01:35:10.323755	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
75	5d3bee1b-0753-487e-801b-1b7a8a11b5a5	75	kick	8-B.Cundiff kicks 68 yards from CLE 35. 84-C.Patterson to MIN 27 for 30 yards (24-J.Bademosi).	06:07		2013-09-25 01:35:10.324721	2013-09-25 01:35:10.324722	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
76	edf6c45b-1640-4c0b-a80d-1bf57f60cc90	76	rush	28-A.Peterson to MIN 31 for 4 yards (99-P.Kruger,97-J.Sheard).	06:00		2013-09-25 01:35:10.325796	2013-09-25 01:35:10.325796	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
77	8c6ee527-be3a-4ddb-8b7a-441dbbaaea82	77	pass	7-C.Ponder incomplete. Intended for 81-J.Simpson, INTERCEPTED by 43-T.Ward at CLE 49. 43-T.Ward to MIN 38 for 13 yards (81-J.Simpson).	05:23		2013-09-25 01:35:10.326797	2013-09-25 01:35:10.326797	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
78	64c06dab-03ac-44dc-8761-0c00e108faef	78	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	05:12		2013-09-25 01:35:10.327799	2013-09-25 01:35:10.327799	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
79	efea3cf1-4217-4ba4-ae76-ece67bc77bc0	79	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to MIN 17 for 21 yards (21-J.Robinson).	05:09		2013-09-25 01:35:10.328794	2013-09-25 01:35:10.328794	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
80	e4cfd346-f11d-46a1-828c-1f646d2ba52b	80	pass	6-B.Hoyer incomplete. Intended for 84-J.Cameron.	04:34		2013-09-25 01:35:10.329787	2013-09-25 01:35:10.329788	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
81	6fc084f4-6003-49da-8ddb-b5e2c864b73e	81	rush	34-B.Rainey to MIN 11 for 6 yards (22-H.Smith).	04:28		2013-09-25 01:35:10.330732	2013-09-25 01:35:10.330733	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
82		82	teamtimeout	Timeout #1 by CLE at 03:49.	03:49		2013-09-25 01:35:10.331775	2013-09-25 01:35:10.331776	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
83	dfe3a19b-b4f8-4bf9-a2f3-6b5664584805	83	pass	6-B.Hoyer incomplete. Intended for 15-D.Bess.	03:49		2013-09-25 01:35:10.332711	2013-09-25 01:35:10.332711	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
84	efbee644-f267-4f8a-867a-e750c0a17e4a	84	pass	5-S.Lanning complete to 84-J.Cameron. 84-J.Cameron runs 11 yards for a touchdown.	03:45		2013-09-25 01:35:10.333669	2013-09-25 01:35:10.333669	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
85	8f219419-430b-4db1-b67f-aaa81065e186	85	extrapoint	8-B.Cundiff extra point is good.	03:39		2013-09-25 01:35:10.334612	2013-09-25 01:35:10.334612	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
86		86	tvtimeout	TV timeout at 03:39.	03:39		2013-09-25 01:35:10.335634	2013-09-25 01:35:10.335635	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
87	75861178-96af-4eec-b7fe-04bd3862cd3f	87	kick	8-B.Cundiff kicks 65 yards from CLE 35 to MIN End Zone. touchback.	03:39		2013-09-25 01:35:10.336619	2013-09-25 01:35:10.33662	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
88	d2e69f7a-9c99-4e1d-90dc-608bc22053f1	88	pass	7-C.Ponder sacked at MIN 13 for -7 yards (98-P.Taylor).	03:39		2013-09-25 01:35:10.337588	2013-09-25 01:35:10.337589	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
89	2b7d31a3-a72e-430f-bcf1-bd6d458570ea	89	pass	7-C.Ponder complete to 32-T.Gerhart. 32-T.Gerhart to MIN 18 for 5 yards (52-D.Jackson).	03:07		2013-09-25 01:35:10.338576	2013-09-25 01:35:10.338576	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
90		90	teamtimeout	Timeout #2 by CLE at 02:51.	02:51		2013-09-25 01:35:10.339521	2013-09-25 01:35:10.339522	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
91	412b9d25-e979-4d0d-b676-5c12831d48a5	91	pass	7-C.Ponder incomplete. Intended for 81-J.Simpson.	02:51		2013-09-25 01:35:10.34045	2013-09-25 01:35:10.34045	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
92	5630ce7c-a424-4512-b0c9-98666f0dd8de	92	punt	12-J.Locke punts 55 yards from MIN 18 to the CLE 27, 80-T.Benjamin muffs the ball. 51-L.Dean recovers at the CLE 26. 51-L.Dean to CLE 26 for no gain.	02:43		2013-09-25 01:35:10.341363	2013-09-25 01:35:10.341364	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
93	82fb1abe-bee6-40f7-b398-e68d7ed8dd1a	93	penalty	Team penalty on MIN, Unsportsmanlike conduct, 15 yards, enforced at CLE 26. No Play.	02:28		2013-09-25 01:35:10.342375	2013-09-25 01:35:10.342376	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
94	848cb44a-9356-4608-8677-df9940894ab7	94	pass	7-C.Ponder complete to 81-J.Simpson. 81-J.Simpson pushed ob at CLE 36 for 5 yards (23-J.Haden).	02:28		2013-09-25 01:35:10.34334	2013-09-25 01:35:10.34334	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
95	535cce86-11b0-4699-a275-ca3a635f95a1	95	pass	7-C.Ponder complete to 81-J.Simpson. 81-J.Simpson to CLE 27 for 9 yards (23-J.Haden).	02:02		2013-09-25 01:35:10.344323	2013-09-25 01:35:10.344323	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
96		96	twominuteswarning	Two-Minute Warning	02:00		2013-09-25 01:35:10.345262	2013-09-25 01:35:10.345262	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
97	3f439d38-299a-483b-866e-9e6fc2c91600	97	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson to CLE 25 for 2 yards (23-J.Haden).	01:56		2013-09-25 01:35:10.346187	2013-09-25 01:35:10.346187	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
98	a421dccc-6fed-430f-a63f-563e90c38c29	98	fieldgoal	3-B.Walsh 43 yards Field Goal is Good.	01:23		2013-09-25 01:35:10.347102	2013-09-25 01:35:10.347102	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
99		99	teamtimeout	Timeout #1 by MIN at 01:08.	01:08		2013-09-25 01:35:10.348012	2013-09-25 01:35:10.348012	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
100	f0e182ce-c0dd-4687-8e98-53e8acfe52e5	100	kick	3-B.Walsh kicks 65 yards from MIN 35 to CLE End Zone. touchback.	01:08		2013-09-25 01:35:10.348995	2013-09-25 01:35:10.348996	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
101	09130fb5-e9a5-4cd8-aad8-feea4f69b31f	101	pass	6-B.Hoyer complete to 18-G.Little. 18-G.Little pushed ob at CLE 24 for 4 yards (29-X.Rhodes).	01:08		2013-09-25 01:35:10.350049	2013-09-25 01:35:10.35005	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
102	8aad773a-365e-4741-b034-0205f728ba31	102	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	01:02		2013-09-25 01:35:10.351044	2013-09-25 01:35:10.351045	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
103	fcb031ee-d3df-4ab9-8cc8-9dc3386c2116	103	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess runs ob at CLE 33 for 9 yards.	:57		2013-09-25 01:35:10.35214	2013-09-25 01:35:10.352141	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
104	dd38ff0b-5544-4724-b5a2-2b6532ac7458	104	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon, INTERCEPTED by 22-H.Smith at CLE 50. 22-H.Smith to CLE 46 for 4 yards (12-J.Gordon).	:53		2013-09-25 01:35:10.353112	2013-09-25 01:35:10.353112	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
105	cf51fbc0-3836-4375-b411-e4370127d757	105	pass	7-C.Ponder incomplete. Intended for 82-K.Rudolph.	:47		2013-09-25 01:35:10.354088	2013-09-25 01:35:10.354088	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
106	8dd20ca2-1178-4f8a-8d2c-10c74b90d2b8	106	pass	7-C.Ponder complete to 84-C.Patterson. 84-C.Patterson to CLE 34 for 12 yards (52-D.Jackson).	:42		2013-09-25 01:35:10.355094	2013-09-25 01:35:10.355095	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
107		107	teamtimeout	Timeout #2 by MIN at :33.	:33		2013-09-25 01:35:10.356135	2013-09-25 01:35:10.356135	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
108	ce490405-9d2c-4dab-85b5-b5fde4cd1a5f	108	rush	7-C.Ponder scrambles to the to CLE 23 for 11 yards (43-T.Ward).	:33		2013-09-25 01:35:10.357115	2013-09-25 01:35:10.357116	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
109		109	teamtimeout	Timeout #3 by MIN at :25.	:25		2013-09-25 01:35:10.358015	2013-09-25 01:35:10.358016	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
110	e6ee9d98-b9b4-478b-8859-c20542954d95	110	pass	7-C.Ponder complete to 17-J.Wright. 17-J.Wright runs ob at CLE 19 for 4 yards.	:25		2013-09-25 01:35:10.358979	2013-09-25 01:35:10.358979	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
111	f7db6dba-02a9-4416-92cd-f805ef2d6538	111	pass	7-C.Ponder complete to 32-T.Gerhart. 32-T.Gerhart pushed ob at CLE 10 for 9 yards (53-C.Robertson).	:20		2013-09-25 01:35:10.359921	2013-09-25 01:35:10.359921	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
112	d0afd9ac-ad9b-4b3f-bd3f-c233ad3e6d91	112	pass	7-C.Ponder incomplete. Intended for 15-G.Jennings.	:15		2013-09-25 01:35:10.360881	2013-09-25 01:35:10.360881	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
113	438e3321-309e-442a-8ac8-8d185540eb1a	113	pass	7-C.Ponder sacked at CLE 15 for -5 yards, FUMBLES (97-J.Sheard). 53-C.Robertson to CLE 22 for 7 yards (71-P.Loadholt).	:11		2013-09-25 01:35:10.36186	2013-09-25 01:35:10.361861	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
114		114	quarterend	End of 1st Half	:00		2013-09-25 01:35:10.362854	2013-09-25 01:35:10.362855	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
115	fdd6af85-3766-4d46-83a9-14a7f3703108	115	kick	3-B.Walsh kicks 65 yards from MIN 35 to CLE End Zone. touchback.	15:00		2013-09-25 01:35:10.363851	2013-09-25 01:35:10.363852	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
116	d49b6165-22f7-4138-8280-3cc48e310e6e	116	rush	26-W.McGahee to CLE 18 for -2 yards (22-H.Smith).	15:00		2013-09-25 01:35:10.364817	2013-09-25 01:35:10.364817	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
117	ce7e1d11-cf2b-4e62-85ed-2577b2a98276	117	rush	34-B.Rainey to CLE 22 for 4 yards (52-C.Greenway).	14:26		2013-09-25 01:35:10.365751	2013-09-25 01:35:10.365751	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
118		118	teamtimeout	Timeout #1 by CLE at 13:52.	13:52		2013-09-25 01:35:10.366758	2013-09-25 01:35:10.366758	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
119	f2430855-715b-4fc9-a218-f2abb1a48c66	119	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess to CLE 33 for 11 yards (21-J.Robinson).	13:52		2013-09-25 01:35:10.367841	2013-09-25 01:35:10.367841	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
120	ecf174da-70b3-4873-982c-1eb2bc404203	120	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess to CLE 48 for 15 yards (50-E.Henderson).	13:16		2013-09-25 01:35:10.3688	2013-09-25 01:35:10.3688	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
121	3409993c-be0f-46a7-aa43-2584316b0760	121	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to CLE 49 for 1 yard (35-M.Sherels).	12:00		2013-09-25 01:35:10.370827	2013-09-25 01:35:10.370828	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
122	eeca6109-c548-4c9c-9d4b-8ce85b031223	122	pass	6-B.Hoyer complete to 18-G.Little. 18-G.Little to MIN 35 for 16 yards (50-E.Henderson).	11:59		2013-09-25 01:35:10.371829	2013-09-25 01:35:10.37183	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
123	89701e3d-e41a-47ba-8029-e2a1c03904d6	123	pass	6-B.Hoyer incomplete. Intended for 84-J.Cameron, INTERCEPTED by 52-C.Greenway at MIN 26. 52-C.Greenway to MIN 49 for 23 yards (75-O.Cousins).	11:30		2013-09-25 01:35:10.37281	2013-09-25 01:35:10.37281	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
124	db9987b2-7644-47e0-9029-04854bd349d0	124	rush	28-A.Peterson to CLE 47 for 4 yards (39-T.Gipson,52-D.Jackson).	11:24		2013-09-25 01:35:10.373792	2013-09-25 01:35:10.373792	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
125	80fe24d0-7535-4ca4-8f9d-9206d6c583a1	125	rush	28-A.Peterson to CLE 43, FUMBLES (52-D.Jackson). 97-J.Sheard to CLE 37 for no gain (28-A.Peterson).	10:50		2013-09-25 01:35:10.3748	2013-09-25 01:35:10.3748	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
126	7b5d0775-55c9-4be7-9352-be5cea460203	126	rush	26-W.McGahee to CLE 46 for 9 yards (22-H.Smith).	10:44		2013-09-25 01:35:10.375749	2013-09-25 01:35:10.375749	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
127	cf709603-4221-4746-a86e-a997e37b8d52	127	rush	26-W.McGahee to CLE 49 for 3 yards (50-E.Henderson).	10:10		2013-09-25 01:35:10.376677	2013-09-25 01:35:10.376677	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
128	4fdc7ef1-770b-450c-8c93-7542bf429471	128	pass	6-B.Hoyer complete to 34-B.Rainey. 34-B.Rainey to MIN 47 for 4 yards (21-J.Robinson).	09:36		2013-09-25 01:35:10.377724	2013-09-25 01:35:10.377724	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
129	832d9a20-286e-4c9d-8009-d60e9672763c	129	pass	6-B.Hoyer incomplete. Intended for 18-G.Little.	09:00		2013-09-25 01:35:10.378668	2013-09-25 01:35:10.378668	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
130	74e091f2-8d2b-417c-9b76-24302f390a7e	130	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	08:56		2013-09-25 01:35:10.379661	2013-09-25 01:35:10.379662	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
131	8d077319-b585-403c-ab70-ac52f37f58d1	131	punt	5-S.Lanning punts 37 yards from MIN 47 to MIN 10, fair catch by 35-M.Sherels.	08:51		2013-09-25 01:35:10.380641	2013-09-25 01:35:10.380642	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
132	51801aba-0041-4fc1-bcbc-11dc93d74eff	132	pass	7-C.Ponder incomplete. Intended for 84-C.Patterson.	08:45		2013-09-25 01:35:10.381602	2013-09-25 01:35:10.381603	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
133	2217c41d-820a-4ffd-b749-2308fa85c089	133	pass	7-C.Ponder incomplete. Intended for 82-K.Rudolph.	08:42		2013-09-25 01:35:10.382624	2013-09-25 01:35:10.382624	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
134	e0236175-4cab-476d-9471-7c259c206fdf	134	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson to MIN 14 for 4 yards (43-T.Ward).	08:37		2013-09-25 01:35:10.3836	2013-09-25 01:35:10.3836	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
135	1bf73324-8f3e-4774-be3c-72bd02c26493	135	punt	12-J.Locke punts 57 yards from MIN 14. 80-T.Benjamin to MIN 43 for 28 yards (36-R.Blanton).	08:21		2013-09-25 01:35:10.384566	2013-09-25 01:35:10.384567	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
136	529887a4-e265-42ea-a6b4-569e9a3636b4	136	rush	34-B.Rainey to MIN 37 for 6 yards (96-B.Robison).	08:06		2013-09-25 01:35:10.385588	2013-09-25 01:35:10.385589	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
137	196ba6e7-a401-4d3f-b3d6-09472ea157fb	137	pass	6-B.Hoyer incomplete. Intended for 84-J.Cameron.	07:34		2013-09-25 01:35:10.386695	2013-09-25 01:35:10.386695	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
138	d0d06f76-1a2f-4b98-9956-ed5773c43da0	138	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	07:29		2013-09-25 01:35:10.387773	2013-09-25 01:35:10.387774	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
139	5ab70a3f-8061-488d-9042-0c3c5194c960	139	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	07:24		2013-09-25 01:35:10.388765	2013-09-25 01:35:10.388766	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
140	20133a06-bfe4-4c76-adb4-45160da87b60	140	rush	28-A.Peterson pushed ob at MIN 46 for 8 yards (23-J.Haden).	07:21		2013-09-25 01:35:10.389777	2013-09-25 01:35:10.389778	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
141	64a57b15-77e5-40e4-a687-d88d9496a75c	141	pass	7-C.Ponder complete to 89-J.Carlson. 89-J.Carlson to MIN 49 for 3 yards (23-J.Haden).	06:45		2013-09-25 01:35:10.390759	2013-09-25 01:35:10.390759	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
142	ca411795-74e6-491b-858a-6e96868576a5	142	rush	28-A.Peterson to CLE 47 for 4 yards.	06:09		2013-09-25 01:35:10.391758	2013-09-25 01:35:10.391758	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
143	ff7a3ceb-ab24-494f-a196-bf53ddf1036b	143	pass	7-C.Ponder sacked at MIN 47 for -6 yards (93-J.Hughes).	05:32		2013-09-25 01:35:10.392825	2013-09-25 01:35:10.392826	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
144	33234c19-d3ec-479d-9a88-daf8041a6b7a	144	pass	7-C.Ponder sacked at MIN 46 for -1 yard (51-B.Mingo).	05:00		2013-09-25 01:35:10.393802	2013-09-25 01:35:10.393802	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
145	53106186-0e5f-4d69-9b79-4c58de3a9452	145	punt	12-J.Locke punts 38 yards from MIN 46 to CLE 16, fair catch by 15-D.Bess.	04:28		2013-09-25 01:35:10.394764	2013-09-25 01:35:10.394765	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
146		146	tvtimeout	TV timeout at 04:23.	04:23		2013-09-25 01:35:10.395725	2013-09-25 01:35:10.395726	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
147	15fe4e5c-89cd-4bc8-be2b-efc2a8288751	147	rush	26-W.McGahee to CLE 10 for -6 yards (59-D.Bishop).	04:21		2013-09-25 01:35:10.396703	2013-09-25 01:35:10.396704	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
148	12e538ca-f183-4ce8-b141-0da4f4cf3d03	148	penalty	Team penalty on CLE, 12 men in the huddle, 5 yards, enforced at CLE 10. No Play.	03:54		2013-09-25 01:35:10.397834	2013-09-25 01:35:10.397834	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
149	314eda94-9931-4f33-a9f9-82a2ffddd621	149	pass	6-B.Hoyer incomplete. Intended for 18-G.Little, INTERCEPTED by 50-E.Henderson at CLE 18. 50-E.Henderson to CLE 9 for 9 yards (71-A.Rubin).	03:34		2013-09-25 01:35:10.398833	2013-09-25 01:35:10.398833	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
150	0300e889-04c0-40e7-af7e-2261a02c709f	150	pass	7-C.Ponder incomplete. Intended for 14-J.Webb.	03:25		2013-09-25 01:35:10.399862	2013-09-25 01:35:10.399863	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
151	b1469d82-cd93-4af1-b6f5-0ad6cd9ca6b8	151	rush	28-A.Peterson to CLE 8 for 1 yard (93-J.Hughes,51-B.Mingo).	03:21		2013-09-25 01:35:10.40087	2013-09-25 01:35:10.400871	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
152	cb7671c9-6631-4995-b436-66a4fdc43ee0	152	rush	7-C.Ponder scrambles to the runs 8 yards for a touchdown.	02:41		2013-09-25 01:35:10.401833	2013-09-25 01:35:10.401833	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
153	b157a27b-2fde-44d6-a709-7d69fd7c9298	153	extrapoint	3-B.Walsh extra point is good.	02:36		2013-09-25 01:35:10.402844	2013-09-25 01:35:10.402845	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
154	2159a12e-33bb-459c-9d93-26e9da71ce27	154	kick	3-B.Walsh kicks 65 yards from MIN 35. 18-G.Little to CLE 26 for 26 yards (34-A.Sendejo).	02:36		2013-09-25 01:35:10.403863	2013-09-25 01:35:10.403863	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
155	0693ebd1-01a8-4172-a927-ff45aba2261a	155	pass	6-B.Hoyer sacked at CLE 18 for -8 yards (50-E.Henderson).	02:31		2013-09-25 01:35:10.404886	2013-09-25 01:35:10.404886	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
156	0443fb61-44dd-483f-99e6-14e533d05bf4	156	pass	6-B.Hoyer incomplete. Penalty on CLE 6-B.Hoyer, Intentional grounding, 12 yards, enforced at CLE 18.	01:53		2013-09-25 01:35:10.405901	2013-09-25 01:35:10.405902	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
157	91b231e5-896e-4b95-8df5-279e48cdbe42	157	rush	25-C.Ogbonnaya to CLE 28 for 22 yards (34-A.Sendejo).	01:44		2013-09-25 01:35:10.406937	2013-09-25 01:35:10.406938	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
158	2843b45d-4828-4f5d-beac-c59997bf1759	158	punt	5-S.Lanning punts 44 yards from CLE 28. 35-M.Sherels to MIN 28, FUMBLES (35-M.Sherels). 35-M.Sherels recovers at the MIN 28. 35-M.Sherels to MIN 28 for no gain.	01:14		2013-09-25 01:35:10.408023	2013-09-25 01:35:10.408024	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
159	df0ebb4e-0728-4a2e-9217-7f51f0592297	159	pass	7-C.Ponder incomplete. Intended for 17-J.Wright.	01:01		2013-09-25 01:35:10.409002	2013-09-25 01:35:10.409002	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
160	16d62031-1b1f-4ac0-b28a-786cfdb582e1	160	rush	28-A.Peterson to MIN 30 for 2 yards (52-D.Jackson).	:57		2013-09-25 01:35:10.40991	2013-09-25 01:35:10.409911	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
161	17e98550-f8b8-464a-983c-52171084b44a	161	rush	7-C.Ponder scrambles, runs ob at MIN 44 for 14 yards.	:20		2013-09-25 01:35:10.410913	2013-09-25 01:35:10.410914	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
162		162	quarterend	End of Quarter	:00		2013-09-25 01:35:10.411918	2013-09-25 01:35:10.411919	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
163	e1262f7f-d177-4ebb-98ee-66097c505a18	163	pass	7-C.Ponder incomplete. Intended for 81-J.Simpson.	15:00		2013-09-25 01:35:10.41288	2013-09-25 01:35:10.412881	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
164	01cf24ca-2d6e-43b6-81e2-6e8407e33714	164	rush	28-A.Peterson to MIN 48 for 4 yards (71-A.Rubin,98-P.Taylor).	14:55		2013-09-25 01:35:10.413879	2013-09-25 01:35:10.413879	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
165	44cba02c-07a0-43b2-a966-3687672bb023	165	pass	7-C.Ponder complete to 15-G.Jennings. 15-G.Jennings to CLE 45 for 7 yards (53-C.Robertson,52-D.Jackson).	14:13		2013-09-25 01:35:10.414865	2013-09-25 01:35:10.414866	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
166	9aee6d97-2786-4a11-bfec-69abb465feb2	166	pass	7-C.Ponder incomplete. Intended for 81-J.Simpson.	13:32		2013-09-25 01:35:10.415837	2013-09-25 01:35:10.415837	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
167	9b91d03e-ff7c-475a-8f8b-bf35ac882661	167	rush	28-A.Peterson to CLE 42 for 3 yards (51-B.Mingo).	13:25		2013-09-25 01:35:10.416801	2013-09-25 01:35:10.416802	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
168	f5c0237f-6a32-4a8f-b0a1-7a3e83f40dc0	168	rush	7-C.Ponder scrambles, pushed ob at CLE 35 for 7 yards (23-J.Haden).	12:46		2013-09-25 01:35:10.41783	2013-09-25 01:35:10.41783	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
169	dc0ea1d5-7600-445a-bfcc-5fc7dd78b848	169	penalty	Penalty on CLE 53-C.Robertson, Facemasking, 15 yards, enforced at CLE 35. No Play.	12:39		2013-09-25 01:35:10.4188	2013-09-25 01:35:10.418801	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
170	d2e071ab-4f87-4d3a-9bd4-d7ff455903d8	170	rush	28-A.Peterson to CLE 15 for 5 yards (43-T.Ward).	12:20		2013-09-25 01:35:10.419775	2013-09-25 01:35:10.419775	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
171	3b5f529a-b789-4588-a681-1348696be22a	171	pass	7-C.Ponder complete to 82-K.Rudolph. 82-K.Rudolph pushed ob at CLE 12 for 3 yards (43-T.Ward).	11:38		2013-09-25 01:35:10.420743	2013-09-25 01:35:10.420743	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
172	d453a95c-fbc5-4735-bccd-349a94c0221d	172	pass	7-C.Ponder incomplete. Intended for 15-G.Jennings.	10:54		2013-09-25 01:35:10.421672	2013-09-25 01:35:10.421672	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
173	7515990e-b5d4-489c-a030-63da857306a6	173	fieldgoal	3-B.Walsh 30 yards Field Goal is Good.	10:50		2013-09-25 01:35:10.422594	2013-09-25 01:35:10.422595	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
174		174	tvtimeout	TV timeout at 10:50.	10:50		2013-09-25 01:35:10.42355	2013-09-25 01:35:10.423551	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
175	f67dfd2e-90aa-496d-828a-b8cb77cd5c75	175	kick	3-B.Walsh kicks 65 yards from MIN 35 to CLE End Zone. touchback.	10:47		2013-09-25 01:35:10.425393	2013-09-25 01:35:10.425394	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
176		176	teamtimeout	Timeout #1 by MIN at 10:47.	10:47		2013-09-25 01:35:10.426455	2013-09-25 01:35:10.426455	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
177	065cfa66-9eee-4fbc-a02e-b1836993839d	177	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to CLE 28 for 8 yards (52-C.Greenway).	10:47		2013-09-25 01:35:10.427466	2013-09-25 01:35:10.427466	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
178	b033f084-2b34-4b87-ae29-5df030cdb9ad	178	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to CLE 38 for 10 yards (35-M.Sherels).	10:11		2013-09-25 01:35:10.428519	2013-09-25 01:35:10.428519	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
179	a2eced23-e05a-43ad-a159-bba04b100b53	179	pass	6-B.Hoyer incomplete. Intended for 12-J.Gordon.	09:29		2013-09-25 01:35:10.429467	2013-09-25 01:35:10.429468	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
180	1431d07b-b62f-4112-b54a-cc36a9741daf	180	pass	6-B.Hoyer sacked at CLE 29 for -9 yards (96-B.Robison).	09:25		2013-09-25 01:35:10.430382	2013-09-25 01:35:10.430382	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
181	5ed7831c-b5ff-422a-85e8-d2d7bd397e21	181	pass	6-B.Hoyer incomplete. Intended for 84-J.Cameron.	08:52		2013-09-25 01:35:10.431325	2013-09-25 01:35:10.431326	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
182	db2d585d-a5b3-4a5f-becc-d798630f92d7	182	punt	5-S.Lanning punts 50 yards from CLE 29 to MIN 21, fair catch by 35-M.Sherels.	08:46		2013-09-25 01:35:10.432295	2013-09-25 01:35:10.432296	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
183		183	tvtimeout	TV timeout at 08:39.	08:39		2013-09-25 01:35:10.433265	2013-09-25 01:35:10.433266	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
184	ff53a578-68b4-45c6-9655-d0fd93be7519	184	pass	7-C.Ponder incomplete. Intended for 48-Z.Line.	08:39		2013-09-25 01:35:10.434204	2013-09-25 01:35:10.434205	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
185	3397983f-8178-4132-98d5-4ed4e2cd33ec	185	rush	28-A.Peterson to MIN 21 for no gain (93-J.Hughes).	08:34		2013-09-25 01:35:10.435182	2013-09-25 01:35:10.435182	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
186	b07da7c3-223c-44d5-8b09-32055a8bac84	186	pass	7-C.Ponder complete to 82-K.Rudolph. 82-K.Rudolph to MIN 30 for 9 yards (22-B.Skrine).	08:01		2013-09-25 01:35:10.436131	2013-09-25 01:35:10.436132	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
187	50505962-3f91-4cce-9936-ddbb5c6a913c	187	punt	12-J.Locke punts 44 yards from MIN 30 to CLE 26, fair catch by 80-T.Benjamin.	07:18		2013-09-25 01:35:10.437131	2013-09-25 01:35:10.437132	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
188	07950e36-e474-40dd-bfad-c84a9ede25a6	188	pass	6-B.Hoyer complete to 15-D.Bess. 15-D.Bess to CLE 40 for 14 yards (21-J.Robinson).	07:11		2013-09-25 01:35:10.438158	2013-09-25 01:35:10.438158	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
189	16431a65-908a-4d3f-9269-b6f0b0c6f9a3	189	pass	6-B.Hoyer sacked at CLE 31 for -9 yards (50-E.Henderson).	06:33		2013-09-25 01:35:10.439143	2013-09-25 01:35:10.439143	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
190	bec00128-02c9-49d8-a971-1d2f98a131b9	190	pass	6-B.Hoyer complete to 84-J.Cameron. 84-J.Cameron to CLE 36 for 5 yards (22-H.Smith).	06:02		2013-09-25 01:35:10.440094	2013-09-25 01:35:10.440094	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
191	652a62f4-e67e-4af3-85e5-cfba1c393377	191	penalty	Penalty on CLE 73-J.Thomas, False start, 5 yards, enforced at CLE 36. No Play.	05:20		2013-09-25 01:35:10.441017	2013-09-25 01:35:10.441017	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
192	fae85108-fbb9-4647-b66b-86424a252cc3	192	pass	6-B.Hoyer complete to 25-C.Ogbonnaya. 25-C.Ogbonnaya to CLE 39 for 8 yards (35-M.Sherels).	05:03		2013-09-25 01:35:10.441943	2013-09-25 01:35:10.441943	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
193	ae6a9957-fea2-4d22-9510-bb82c6e8081a	193	punt	5-S.Lanning punts 47 yards from CLE 39 to MIN 14, fair catch by 35-M.Sherels.	04:30		2013-09-25 01:35:10.442891	2013-09-25 01:35:10.442891	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
194	f93f370a-6cd4-44a6-a7a3-0898adf48afa	194	rush	84-C.Patterson to MIN 14 for no gain (52-D.Jackson).	04:22		2013-09-25 01:35:10.443947	2013-09-25 01:35:10.443948	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
195	d7fe7993-8202-4aae-9f49-b4548351c43c	195	rush	28-A.Peterson to MIN 20 for 6 yards (23-J.Haden,53-C.Robertson).	03:38		2013-09-25 01:35:10.444838	2013-09-25 01:35:10.444838	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
196		196	teamtimeout	Timeout #2 by CLE at 03:32.	03:32		2013-09-25 01:35:10.445755	2013-09-25 01:35:10.445755	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
197		197	teamtimeout	Timeout #2 by MIN at 03:32.	03:32		2013-09-25 01:35:10.446742	2013-09-25 01:35:10.446742	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
198	c0e35f14-c8bd-4207-bfc8-8d1fb8f8fd11	198	pass	7-C.Ponder incomplete. Intended for 15-G.Jennings.	03:32		2013-09-25 01:35:10.447697	2013-09-25 01:35:10.447698	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
199	10eb79f1-f6cf-4eab-b884-410255aaa97e	199	punt	12-J.Locke punts 35 yards from MIN 20 to CLE 45, fair catch by 80-T.Benjamin.	03:28		2013-09-25 01:35:10.448633	2013-09-25 01:35:10.448634	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
200	96f30f36-d52b-414c-bf6d-79d4e535fd83	200	pass	6-B.Hoyer incomplete. Intended for 15-D.Bess.	03:21		2013-09-25 01:35:10.44954	2013-09-25 01:35:10.44954	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
201	807bbce2-0527-4e2d-8caa-487f4898ef65	201	pass	6-B.Hoyer incomplete. Intended for 18-G.Little.	03:17		2013-09-25 01:35:10.450456	2013-09-25 01:35:10.450457	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
202	2ce4d1e1-2fe6-4ed6-8756-93d55bf1311c	202	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to MIN 44 for 11 yards (29-X.Rhodes).	03:12		2013-09-25 01:35:10.451417	2013-09-25 01:35:10.451418	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
203	6c2b3000-bb74-4c77-83d9-056203c5068b	203	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to MIN 41 for 3 yards (35-M.Sherels).	02:47		2013-09-25 01:35:10.452292	2013-09-25 01:35:10.452293	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
204	4e642316-b950-4886-9888-4c5a7e5b6efc	204	pass	6-B.Hoyer complete to 25-C.Ogbonnaya. 25-C.Ogbonnaya to MIN 30 for 11 yards (21-J.Robinson).	02:06		2013-09-25 01:35:10.453312	2013-09-25 01:35:10.453312	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
205		205	twominuteswarning	Two-Minute Warning	01:59		2013-09-25 01:35:10.454247	2013-09-25 01:35:10.454248	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
206	d080b87d-0049-4997-8b77-56621a723133	206	pass	6-B.Hoyer incomplete. Intended for 18-G.Little.	01:59		2013-09-25 01:35:10.455213	2013-09-25 01:35:10.455213	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
207	c2fa5bcd-0e73-4626-91c7-d79f35fbec34	207	pass	6-B.Hoyer complete to 84-J.Cameron. 84-J.Cameron to MIN 17 for 13 yards (22-H.Smith).	01:54		2013-09-25 01:35:10.45613	2013-09-25 01:35:10.45613	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
208	b12141fe-609a-42ec-9d8d-0ff936810b1a	208	pass	6-B.Hoyer complete to 12-J.Gordon. 12-J.Gordon to MIN 7 for 10 yards (34-A.Sendejo).	01:30		2013-09-25 01:35:10.457093	2013-09-25 01:35:10.457093	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
209	ab34265b-3d4a-4d4c-b7da-eb9a89af1475	209	pass	6-B.Hoyer incomplete. Intended for 18-G.Little.	01:04		2013-09-25 01:35:10.45806	2013-09-25 01:35:10.458061	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
210	73e8a689-eed5-4bec-915a-48898dbf1577	210	pass	6-B.Hoyer incomplete. Intended for 84-J.Cameron.	01:00		2013-09-25 01:35:10.458937	2013-09-25 01:35:10.458938	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
211	809e9781-ae6b-491a-a725-5a055b8710c7	211	pass	6-B.Hoyer complete to 84-J.Cameron. 84-J.Cameron runs 7 yards for a touchdown.	:55		2013-09-25 01:35:10.46007	2013-09-25 01:35:10.46007	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
212	1e7b1ac8-b689-4f00-8199-1ebf3cda26d1	212	extrapoint	5-S.Lanning extra point is good.	:51		2013-09-25 01:35:10.46099	2013-09-25 01:35:10.460991	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
213	87579ee5-231c-488c-a822-79273b0add3a	213	kick	8-B.Cundiff kicks 55 yards from CLE 35. 32-T.Gerhart to MIN 29 for 19 yards (25-C.Ogbonnaya).	:51		2013-09-25 01:35:10.462209	2013-09-25 01:35:10.462209	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
214	433f325f-571f-4806-98e9-4d6adab8df5e	214	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson to MIN 33 for 4 yards (52-D.Jackson).	:47		2013-09-25 01:35:10.463481	2013-09-25 01:35:10.463482	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
215	aacc3f72-12c8-4789-84e1-b969cf5836d8	215	pass	7-C.Ponder complete to 82-K.Rudolph. 82-K.Rudolph runs ob at MIN 37 for 4 yards.	:31		2013-09-25 01:35:10.46445	2013-09-25 01:35:10.46445	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
216	55ee84d2-2d96-4bd6-ae28-b8d233715ebe	216	pass	7-C.Ponder complete to 81-J.Simpson. 81-J.Simpson pushed ob at CLE 48 for 15 yards (21-C.Owens).	:26		2013-09-25 01:35:10.465432	2013-09-25 01:35:10.465433	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
217	bebc8ea0-bb5b-451c-bd5d-cec0c18e9a1e	217	pass	7-C.Ponder complete to 82-K.Rudolph. 82-K.Rudolph to CLE 41 for 7 yards (22-B.Skrine).	:20		2013-09-25 01:35:10.466388	2013-09-25 01:35:10.466389	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
218		218	teamtimeout	Timeout #3 by MIN at :12.	:12		2013-09-25 01:35:10.467349	2013-09-25 01:35:10.467349	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
219	5e478d75-0362-4783-9d8b-4f6458098165	219	pass	7-C.Ponder complete to 28-A.Peterson. 28-A.Peterson runs ob at CLE 34 for 7 yards.	:12		2013-09-25 01:35:10.468309	2013-09-25 01:35:10.46831	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
220	96ac79ce-0479-4fc8-8b10-6526ce391a9a	220	pass	7-C.Ponder incomplete. Intended for 81-J.Simpson.	:10		2013-09-25 01:35:10.469301	2013-09-25 01:35:10.469302	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
221		221	teamtimeout	Timeout #3 by CLE at :04.	:04		2013-09-25 01:35:10.470231	2013-09-25 01:35:10.470232	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
222	2cab4a7e-cdfb-4b41-806b-1996bc8bfd53	222	pass	7-C.Ponder sacked at CLE 42 for -8 yards (92-D.Bryant).	:04		2013-09-25 01:35:10.471212	2013-09-25 01:35:10.471213	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
223		223	quarterend	End of 4th Quarter	:00		2013-09-25 01:35:10.472141	2013-09-25 01:35:10.472142	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
224		224	gameover	End of Game	:00		2013-09-25 01:35:10.473112	2013-09-25 01:35:10.473112	da21bd78-8d94-4b34-8c67-bd03fc4948e5	
\.


--
-- Data for Name: games; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY games (id, stats_id, status, game_day, game_time, created_at, updated_at, home_team, away_team, season_type, season_week, season_year, network) FROM stdin;
1	c8598af4-2a8e-4196-b900-a1a21b1acb16	closed	2012-08-05	2012-08-06 00:00:00	2013-09-25 01:33:59.162509	2013-09-25 01:33:59.16251	NO	ARI	PRE	0	2012	NFL Network
2	433d3222-e82d-4f14-97e2-4115579473f6	closed	2012-08-09	2012-08-09 23:00:00	2013-09-25 01:33:59.166641	2013-09-25 01:33:59.166642	BUF	WAS	PRE	1	2012	Local
3	b63e01f9-600d-42ee-b1f0-b020846b246b	closed	2012-08-09	2012-08-09 23:30:00	2013-09-25 01:33:59.168525	2013-09-25 01:33:59.168526	PHI	PIT	PRE	1	2012	Local
4	e25de70d-9bff-4490-9695-fd66cf45aa6d	closed	2012-08-09	2012-08-09 23:30:00	2013-09-25 01:33:59.169734	2013-09-25 01:33:59.169735	NE	NO	PRE	1	2012	Local
5	c69d0297-6db2-4599-9ecb-2e9d70e6feb1	closed	2012-08-09	2012-08-09 23:30:00	2013-09-25 01:33:59.170978	2013-09-25 01:33:59.170979	ATL	BAL	PRE	1	2012	Local
6	088077a2-e49e-4ec6-b7b8-7318752adf6a	closed	2012-08-09	2012-08-10 00:00:00	2013-09-25 01:33:59.172282	2013-09-25 01:33:59.172282	SD	GB	PRE	1	2012	ESPN
7	12a31b8b-119e-4ea2-9627-5ae7a0829b47	closed	2012-08-09	2012-08-10 00:30:00	2013-09-25 01:33:59.173505	2013-09-25 01:33:59.173506	CHI	DEN	PRE	1	2012	Local
8	e93f780c-dc00-4456-835b-0abc6a64e58d	closed	2012-08-10	2012-08-10 23:30:00	2013-09-25 01:33:59.17469	2013-09-25 01:33:59.174691	JAC	NYG	PRE	1	2012	Local
9	b307bf92-9c69-4443-bc18-cee45fb63fcb	closed	2012-08-10	2012-08-10 23:30:00	2013-09-25 01:33:59.175947	2013-09-25 01:33:59.175947	CIN	NYJ	PRE	1	2012	Local
10	9279dd5b-5429-4680-bee4-26cfaaf51b21	closed	2012-08-10	2012-08-10 23:30:00	2013-09-25 01:33:59.177195	2013-09-25 01:33:59.177196	MIA	TB	PRE	1	2012	Local
11	1a984c80-f0fa-48c8-a88d-a67a82344753	closed	2012-08-10	2012-08-10 23:30:00	2013-09-25 01:33:59.178429	2013-09-25 01:33:59.178429	DET	CLE	PRE	1	2012	Local
12	3af20dde-aa41-46f2-a7e2-929ce5b4a2e6	closed	2012-08-10	2012-08-11 00:00:00	2013-09-25 01:33:59.179707	2013-09-25 01:33:59.179708	KC	ARI	PRE	1	2012	Local
13	92613948-82c8-46c1-b943-1c43c10914fb	closed	2012-08-10	2012-08-11 01:00:00	2013-09-25 01:33:59.180946	2013-09-25 01:33:59.180947	SF	MIN	PRE	1	2012	Local
14	cf2a0638-ee67-4ca5-9666-fc37b37b1145	closed	2012-08-11	2012-08-11 23:00:00	2013-09-25 01:33:59.182118	2013-09-25 01:33:59.182118	CAR	HOU	PRE	1	2012	Local
15	9f3127d9-3f67-4972-b2d9-96bee12e523c	closed	2012-08-11	2012-08-12 02:00:00	2013-09-25 01:33:59.183305	2013-09-25 01:33:59.183306	SEA	TEN	PRE	1	2012	Local
16	4b60bf06-aa62-4ad0-ba70-978998ac96ae	closed	2012-08-12	2012-08-12 17:30:00	2013-09-25 01:33:59.18437	2013-09-25 01:33:59.184371	IND	STL	PRE	1	2012	Local
17	1e65ee9d-bc47-4488-b810-2814d7844ab7	closed	2012-08-13	2012-08-14 00:00:00	2013-09-25 01:33:59.185386	2013-09-25 01:33:59.185386	OAK	DAL	PRE	1	2012	ESPN
18	359d506a-a5f5-48a1-b57d-53d0ccbb5cf8	closed	2012-08-16	2012-08-17 00:00:00	2013-09-25 01:33:59.186391	2013-09-25 01:33:59.186391	GB	CLE	PRE	2	2012	Local
19	2a6243f8-96d6-480d-8fee-cb5e0674bb6c	closed	2012-08-16	2012-08-17 00:00:00	2013-09-25 01:33:59.188227	2013-09-25 01:33:59.188227	ATL	CIN	PRE	2	2012	FOX
20	59ab4796-ce25-43b4-8a88-1042acab089c	closed	2012-08-17	2012-08-17 23:30:00	2013-09-25 01:33:59.189186	2013-09-25 01:33:59.189187	TB	TEN	PRE	2	2012	Local
21	f4c9021f-9ed9-4c96-accf-b963eceb0631	closed	2012-08-17	2012-08-18 00:00:00	2013-09-25 01:33:59.190249	2013-09-25 01:33:59.190249	CAR	MIA	PRE	2	2012	Local
22	a698e65e-acd5-4e6d-ab5c-0dbd46e5e200	closed	2012-08-17	2012-08-18 00:00:00	2013-09-25 01:33:59.191248	2013-09-25 01:33:59.191249	BAL	DET	PRE	2	2012	FOX
23	84553432-a933-4334-ab3d-d6829dcadb79	closed	2012-08-17	2012-08-18 00:00:00	2013-09-25 01:33:59.19226	2013-09-25 01:33:59.192261	MIN	BUF	PRE	2	2012	Local
24	4e2164af-a659-4771-b9a9-28149926f3ab	closed	2012-08-17	2012-08-18 00:00:00	2013-09-25 01:33:59.19319	2013-09-25 01:33:59.193191	NO	JAC	PRE	2	2012	Local
25	d2dafc3d-9f5c-402c-a79a-75f5d6f61c32	closed	2012-08-17	2012-08-18 02:00:00	2013-09-25 01:33:59.194146	2013-09-25 01:33:59.194146	ARI	OAK	PRE	2	2012	Local
26	328c3224-f478-4e2a-a880-320da00e93a1	closed	2012-08-18	2012-08-18 23:00:00	2013-09-25 01:33:59.195055	2013-09-25 01:33:59.195056	NYJ	NYG	PRE	2	2012	Local
27	bb1ce977-6fa3-47b9-a68c-9a4b7eb6c972	closed	2012-08-18	2012-08-19 00:00:00	2013-09-25 01:33:59.196167	2013-09-25 01:33:59.196168	HOU	SF	PRE	2	2012	Local
28	0b9f5671-9303-4b4f-af1f-0f01a4979ab5	closed	2012-08-18	2012-08-19 00:00:00	2013-09-25 01:33:59.19739	2013-09-25 01:33:59.197392	STL	KC	PRE	2	2012	Local
29	4d89b3cb-414b-4580-aa88-3049488fa40e	closed	2012-08-18	2012-08-19 00:00:00	2013-09-25 01:33:59.198863	2013-09-25 01:33:59.198864	CHI	WAS	PRE	2	2012	Local
30	0a58319d-ba1e-4b20-8c5b-9504d62c0240	closed	2012-08-18	2012-08-19 01:00:00	2013-09-25 01:33:59.199959	2013-09-25 01:33:59.19996	SD	DAL	PRE	2	2012	Local
31	7774d41c-4e57-449d-8808-a9d9017e3c4e	closed	2012-08-18	2012-08-19 01:00:00	2013-09-25 01:33:59.20093	2013-09-25 01:33:59.20093	DEN	SEA	PRE	2	2012	Local
32	5c04ec0a-eea2-4c42-a828-3b5c850e1cee	closed	2012-08-19	2012-08-20 00:00:00	2013-09-25 01:33:59.201893	2013-09-25 01:33:59.201893	PIT	IND	PRE	2	2012	NBC
33	3e08aa64-ff08-4220-bed3-11b201bdce32	closed	2012-08-20	2012-08-21 00:00:00	2013-09-25 01:33:59.202792	2013-09-25 01:33:59.202792	NE	PHI	PRE	2	2012	ESPN
34	45cb850d-0145-436e-a87a-74e2479f3fb4	closed	2012-08-23	2012-08-23 23:00:00	2013-09-25 01:33:59.203672	2013-09-25 01:33:59.203672	CIN	GB	PRE	3	2012	Local
35	8bf4397b-35be-4092-ae9e-fe53685b9822	closed	2012-08-23	2012-08-23 23:30:00	2013-09-25 01:33:59.204679	2013-09-25 01:33:59.20468	BAL	JAC	PRE	3	2012	Local
36	f31d9091-f4f3-44bd-a55a-436cd1919c95	closed	2012-08-23	2012-08-24 00:00:00	2013-09-25 01:33:59.20562	2013-09-25 01:33:59.205621	TEN	ARI	PRE	3	2012	ESPN
37	d62c5441-c0d3-46f4-9593-2431fd009964	closed	2012-08-24	2012-08-24 23:30:00	2013-09-25 01:33:59.206802	2013-09-25 01:33:59.206802	CLE	PHI	PRE	3	2012	Local
38	6cdb66c4-507e-43f3-b448-40bfd82465ea	closed	2012-08-24	2012-08-24 23:30:00	2013-09-25 01:33:59.207828	2013-09-25 01:33:59.207829	TB	NE	PRE	3	2012	Local
39	99977009-a44a-43dd-b7df-228c5d6a73ee	closed	2012-08-24	2012-08-24 23:30:00	2013-09-25 01:33:59.208764	2013-09-25 01:33:59.208765	MIA	ATL	PRE	3	2012	Local
40	b88f865f-a481-4172-a8a1-b5fe2b1ee1fa	closed	2012-08-24	2012-08-25 00:00:00	2013-09-25 01:33:59.209711	2013-09-25 01:33:59.209712	NYG	CHI	PRE	3	2012	CBS
41	cdfe8a41-a53f-4167-96f3-2d14d2b72f01	closed	2012-08-24	2012-08-25 00:00:00	2013-09-25 01:33:59.210608	2013-09-25 01:33:59.210609	KC	SEA	PRE	3	2012	Local
42	f19af262-9406-4356-aef6-682982d5dfd9	closed	2012-08-24	2012-08-25 00:00:00	2013-09-25 01:33:59.211532	2013-09-25 01:33:59.211533	MIN	SD	PRE	3	2012	Local
43	53f222a2-0d2d-47c8-9250-525352dc071c	closed	2012-08-25	2012-08-25 20:00:00	2013-09-25 01:33:59.212437	2013-09-25 01:33:59.212437	WAS	IND	PRE	3	2012	Local
44	a13c98ad-c050-4108-8fcc-473d44676b76	closed	2012-08-25	2012-08-25 23:00:00	2013-09-25 01:33:59.213311	2013-09-25 01:33:59.213312	OAK	DET	PRE	3	2012	Local
45	22a5799f-6931-4134-9b68-e98f37ce33ac	closed	2012-08-25	2012-08-25 23:00:00	2013-09-25 01:33:59.214187	2013-09-25 01:33:59.214187	BUF	PIT	PRE	3	2012	Local
46	cd0d9050-31d7-4c9b-9c9a-a64d2e855004	closed	2012-08-25	2012-08-26 00:00:00	2013-09-25 01:33:59.215058	2013-09-25 01:33:59.215059	NO	HOU	PRE	3	2012	CBS
47	8abb4c7e-4ea1-4f34-8c88-93f8d8ce0e4c	closed	2012-08-25	2012-08-26 00:00:00	2013-09-25 01:33:59.215933	2013-09-25 01:33:59.215933	DAL	STL	PRE	3	2012	Local
48	337608ae-eea7-47af-84ce-1d240768d2a5	closed	2012-08-26	2012-08-26 20:00:00	2013-09-25 01:33:59.216807	2013-09-25 01:33:59.216808	DEN	SF	PRE	3	2012	FOX
49	f8360816-6842-45b6-865e-8181fc4c1dea	closed	2012-08-26	2012-08-27 00:00:00	2013-09-25 01:33:59.21772	2013-09-25 01:33:59.217721	NYJ	CAR	PRE	3	2012	NBC
50	f8c07dbb-89b6-49ea-a3bd-c447e93487a5	closed	2012-08-29	2012-08-29 23:00:00	2013-09-25 01:33:59.218604	2013-09-25 01:33:59.218605	WAS	TB	PRE	4	2012	Local
51	d028364e-76db-4df0-956b-dc85b1ed8acd	closed	2012-08-29	2012-08-29 23:00:00	2013-09-25 01:33:59.219661	2013-09-25 01:33:59.219661	NYG	NE	PRE	4	2012	Local
52	88ce4fe4-f7b1-4ca7-af93-0cfe74cf5355	closed	2012-08-29	2012-08-30 00:30:00	2013-09-25 01:33:59.220737	2013-09-25 01:33:59.220738	DAL	MIA	PRE	4	2012	Local
53	29ec4d43-1560-4815-9eb8-c94375f59432	closed	2012-08-30	2012-08-30 22:30:00	2013-09-25 01:33:59.221752	2013-09-25 01:33:59.221753	JAC	ATL	PRE	4	2012	Local
54	5df0e3a6-a162-4f6d-8e8e-50088f17e57e	closed	2012-08-30	2012-08-30 22:35:00	2013-09-25 01:33:59.222767	2013-09-25 01:33:59.222768	PHI	NYJ	PRE	4	2012	Local
55	2fedd747-35a4-4363-a82c-765966d60f74	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.223693	2013-09-25 01:33:59.223694	PIT	CAR	PRE	4	2012	Local
56	40de8012-491c-4910-a726-6af0546ab71a	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.224599	2013-09-25 01:33:59.2246	GB	KC	PRE	4	2012	Local
57	e35d0602-e54e-49f1-af7c-bf17b6dcc88a	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.226079	2013-09-25 01:33:59.226079	IND	CIN	PRE	4	2012	Local
58	9184c32d-cb22-4b3b-86fd-1057b51ff5f5	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.227015	2013-09-25 01:33:59.227015	TEN	NO	PRE	4	2012	Local
59	10114609-8647-465c-8cd6-568bf34e5cfb	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.227982	2013-09-25 01:33:59.227983	HOU	MIN	PRE	4	2012	Local
60	76023528-c252-488f-9bfb-c8e6173c4aa3	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.229784	2013-09-25 01:33:59.229785	STL	BAL	PRE	4	2012	Local
61	51c5d478-78cb-4ec3-b7d8-f54a980cbe38	closed	2012-08-30	2012-08-30 23:00:00	2013-09-25 01:33:59.230824	2013-09-25 01:33:59.230825	DET	BUF	PRE	4	2012	Local
62	dad76dd4-f0c7-491a-8083-e921784313e6	closed	2012-08-30	2012-08-30 23:30:00	2013-09-25 01:33:59.231803	2013-09-25 01:33:59.231804	CLE	CHI	PRE	4	2012	Local
63	8814e472-c782-4db9-bec9-cfc881a69e7c	closed	2012-08-30	2012-08-31 02:00:00	2013-09-25 01:33:59.232794	2013-09-25 01:33:59.232795	SEA	OAK	PRE	4	2012	Local
64	0bd2b7f7-4740-47bc-ab72-0897582bc6b2	closed	2012-08-30	2012-08-31 02:00:00	2013-09-25 01:33:59.233717	2013-09-25 01:33:59.233718	SF	SD	PRE	4	2012	Local
65	89eba5c6-0f15-4ee1-a59c-c02a179e7d11	closed	2012-08-30	2012-08-31 03:00:00	2013-09-25 01:33:59.234663	2013-09-25 01:33:59.234664	ARI	DEN	PRE	4	2012	Local
66	8c0bce5a-7ca2-41e5-9838-d1b8c356ddc3	closed	2012-09-05	2012-09-06 00:30:00	2013-09-25 01:34:00.690362	2013-09-25 01:34:00.690364	NYG	DAL	REG	1	2012	NBC
67	0651e14f-55b0-403f-9ff0-d0f11261490d	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.693125	2013-09-25 01:34:00.693126	KC	ATL	REG	1	2012	FOX
68	bf9a4d33-9ec9-4349-9f8e-95f1d9c4ab19	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.694475	2013-09-25 01:34:00.694476	NO	WAS	REG	1	2012	FOX
69	61064b59-e31b-40c8-a1e9-f06dbe510636	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.695716	2013-09-25 01:34:00.695717	CLE	PHI	REG	1	2012	FOX
70	d5c8a042-7689-4526-bc6f-d902bb283e8d	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.696946	2013-09-25 01:34:00.696947	NYJ	BUF	REG	1	2012	CBS
71	a980f016-419a-40ef-ad48-957a12481e06	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.698156	2013-09-25 01:34:00.698157	HOU	MIA	REG	1	2012	CBS
72	437c79b9-ff27-4fed-9899-07ef79e789da	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.699352	2013-09-25 01:34:00.699352	CHI	IND	REG	1	2012	CBS
73	6ea85017-196f-410d-92db-66799b110c7a	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.700487	2013-09-25 01:34:00.700488	DET	STL	REG	1	2012	FOX
74	ac73c14d-a974-4721-933e-d90d437b12fd	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.701702	2013-09-25 01:34:00.701703	TEN	NE	REG	1	2012	CBS
75	548315c0-cd08-4715-b6a2-cb093b6da797	closed	2012-09-09	2012-09-09 17:00:00	2013-09-25 01:34:00.702924	2013-09-25 01:34:00.702925	MIN	JAC	REG	1	2012	CBS
76	a9d5654c-7ec2-4865-ad4a-01d16186dfe0	closed	2012-09-09	2012-09-09 20:15:00	2013-09-25 01:34:00.704348	2013-09-25 01:34:00.704349	TB	CAR	REG	1	2012	FOX
77	1c5b1b11-4f35-4c35-9952-f7ba1267dd23	closed	2012-09-09	2012-09-09 20:15:00	2013-09-25 01:34:00.705683	2013-09-25 01:34:00.705684	GB	SF	REG	1	2012	FOX
78	9baf8d67-424b-46dd-b47e-d1f975f6d80d	closed	2012-09-09	2012-09-09 20:15:00	2013-09-25 01:34:00.706905	2013-09-25 01:34:00.706906	ARI	SEA	REG	1	2012	FOX
79	2b736f4f-6608-41ed-80e9-a7eabd5b5b9c	closed	2012-09-09	2012-09-10 00:20:00	2013-09-25 01:34:00.707931	2013-09-25 01:34:00.707932	DEN	PIT	REG	1	2012	NBC
80	a24be3cb-3993-46b0-98a5-dedf278ba7f7	closed	2012-09-10	2012-09-10 23:00:00	2013-09-25 01:34:00.708924	2013-09-25 01:34:00.708924	BAL	CIN	REG	1	2012	ESPN
81	fadd283f-66b2-4cfe-89d9-ad1036d864f8	closed	2012-09-10	2012-09-11 02:15:00	2013-09-25 01:34:00.709859	2013-09-25 01:34:00.709859	OAK	SD	REG	1	2012	ESPN
82	624f53e3-c31c-4439-ad2b-6269907c49bd	closed	2012-09-13	2012-09-14 00:20:00	2013-09-25 01:34:00.71107	2013-09-25 01:34:00.711071	GB	CHI	REG	2	2012	NFL
83	05ba0eb5-cc0c-4999-aee8-1ddd197a66a1	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.712194	2013-09-25 01:34:00.712195	NE	ARI	REG	2	2012	FOX
84	b098946b-24cd-4756-b15e-f150709b4a87	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.713369	2013-09-25 01:34:00.71337	NYG	TB	REG	2	2012	FOX
85	a18a77d3-651a-45ec-9c29-2c6f70454ad4	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.714434	2013-09-25 01:34:00.714435	CIN	CLE	REG	2	2012	CBS
86	004d3292-821f-4093-a1ef-4a10927eaec7	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.716511	2013-09-25 01:34:00.716512	PHI	BAL	REG	2	2012	CBS
87	2061b908-2cef-4392-98e7-28be8e581c24	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.717489	2013-09-25 01:34:00.71749	JAC	HOU	REG	2	2012	CBS
88	37796d82-3be5-4084-83c6-4cf4b2361191	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.718457	2013-09-25 01:34:00.718457	CAR	NO	REG	2	2012	FOX
89	eac82e72-f11d-4e2c-97c7-5c243da77687	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.719388	2013-09-25 01:34:00.719389	MIA	OAK	REG	2	2012	CBS
90	925d1052-00d5-4799-bfee-970c3c5f6ea6	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.720342	2013-09-25 01:34:00.720343	IND	MIN	REG	2	2012	FOX
91	c8ed1cc0-e8cd-452d-9921-bde312ec2248	closed	2012-09-16	2012-09-16 17:00:00	2013-09-25 01:34:00.721261	2013-09-25 01:34:00.721261	BUF	KC	REG	2	2012	CBS
92	d35e05ff-b548-4544-8e1a-be2dbc0015fc	closed	2012-09-16	2012-09-16 20:05:00	2013-09-25 01:34:00.722151	2013-09-25 01:34:00.722151	STL	WAS	REG	2	2012	FOX
93	f17a6bd7-35d0-4f21-aca9-bf59261ed818	closed	2012-09-16	2012-09-16 20:05:00	2013-09-25 01:34:00.723051	2013-09-25 01:34:00.723052	SEA	DAL	REG	2	2012	FOX
94	b39f914b-cdbc-44f8-bdf2-725dc5122c55	closed	2012-09-16	2012-09-16 20:15:00	2013-09-25 01:34:00.723929	2013-09-25 01:34:00.72393	PIT	NYJ	REG	2	2012	CBS
95	3cfb5ab2-c319-49f5-8ce5-8b4da14144f6	closed	2012-09-16	2012-09-16 20:15:00	2013-09-25 01:34:00.725349	2013-09-25 01:34:00.725349	SD	TEN	REG	2	2012	CBS
96	69202002-f224-4c87-a499-ada8775aa19e	closed	2012-09-16	2012-09-17 00:20:00	2013-09-25 01:34:00.726737	2013-09-25 01:34:00.726738	SF	DET	REG	2	2012	NBC
97	8e72d0de-954a-423e-a17e-be35d6d147cf	closed	2012-09-17	2012-09-18 00:30:00	2013-09-25 01:34:00.727746	2013-09-25 01:34:00.727746	ATL	DEN	REG	2	2012	ESPN
98	de0470aa-f3fa-47d6-a4d2-62f738527d87	closed	2012-09-20	2012-09-21 00:20:00	2013-09-25 01:34:00.728733	2013-09-25 01:34:00.728734	CAR	NYG	REG	3	2012	NFL
99	34a343ce-97e9-4c65-9560-87681886ec1b	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.72968	2013-09-25 01:34:00.729681	MIN	SF	REG	3	2012	FOX
100	c85fe28f-fe13-4f0e-8458-ff780e8b2489	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.730679	2013-09-25 01:34:00.73068	NO	KC	REG	3	2012	CBS
101	842c8697-299c-46f0-b60f-2a0c81f65fbf	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.731684	2013-09-25 01:34:00.731685	TEN	DET	REG	3	2012	FOX
102	0710508f-241b-4eb1-a39e-91a7dd97e2f6	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.73264	2013-09-25 01:34:00.73264	IND	JAC	REG	3	2012	CBS
103	dc04122b-0031-464b-b396-f91c8b38cffe	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.733572	2013-09-25 01:34:00.733573	WAS	CIN	REG	3	2012	CBS
104	1a33d801-3ed7-4dfe-9627-b79655818716	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.734507	2013-09-25 01:34:00.734508	DAL	TB	REG	3	2012	FOX
105	9a97b81e-7748-48f1-aa90-a311b34ee44b	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.735483	2013-09-25 01:34:00.735484	CHI	STL	REG	3	2012	FOX
106	b6dd5fc1-4d02-4b2a-8a8f-d7ae60c34113	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.736609	2013-09-25 01:34:00.736609	CLE	BUF	REG	3	2012	CBS
107	9e39ac0c-a4b6-4b7c-92eb-6c502842c49d	closed	2012-09-23	2012-09-23 17:00:00	2013-09-25 01:34:00.73753	2013-09-25 01:34:00.737531	MIA	NYJ	REG	3	2012	CBS
108	f242f82a-0cc0-47e6-915f-fb2857072cea	closed	2012-09-23	2012-09-23 20:05:00	2013-09-25 01:34:00.738444	2013-09-25 01:34:00.738445	ARI	PHI	REG	3	2012	FOX
109	55240ff2-7bc0-4a12-a11f-b98f7b455d7d	closed	2012-09-23	2012-09-23 20:05:00	2013-09-25 01:34:00.739383	2013-09-25 01:34:00.739383	SD	ATL	REG	3	2012	FOX
110	ae346165-4704-474c-a74f-3a017704d5e1	closed	2012-09-23	2012-09-23 20:25:00	2013-09-25 01:34:00.740317	2013-09-25 01:34:00.740317	DEN	HOU	REG	3	2012	CBS
111	25b0855d-c3db-4aab-ac8c-3668fc21cc59	closed	2012-09-23	2012-09-23 20:25:00	2013-09-25 01:34:00.741289	2013-09-25 01:34:00.741289	OAK	PIT	REG	3	2012	CBS
112	86f3c1d8-362d-4a78-b904-3d8175642d0e	closed	2012-09-23	2012-09-24 00:20:00	2013-09-25 01:34:00.742187	2013-09-25 01:34:00.742187	BAL	NE	REG	3	2012	NBC
113	4b7a2283-42e4-4ea5-8eb8-58e69b3d8fa0	closed	2012-09-24	2012-09-25 00:30:00	2013-09-25 01:34:00.743087	2013-09-25 01:34:00.743087	SEA	GB	REG	3	2012	ESPN
114	61f1f5bd-8034-4f18-b1ff-a67baadbde43	closed	2012-09-27	2012-09-28 00:20:00	2013-09-25 01:34:00.744051	2013-09-25 01:34:00.744051	BAL	CLE	REG	4	2012	NFL
115	edf56db0-6070-419c-9658-e2447a31e634	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.745051	2013-09-25 01:34:00.745051	KC	SD	REG	4	2012	CBS
116	f6a58cd9-a044-4575-b976-6a2e64e153b0	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.746341	2013-09-25 01:34:00.746342	HOU	TEN	REG	4	2012	CBS
117	f6dc5787-8148-41b7-a457-783ded83b4be	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.747297	2013-09-25 01:34:00.747297	STL	SEA	REG	4	2012	FOX
118	8cd22449-12c5-4b39-a417-c94457b8c031	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.748258	2013-09-25 01:34:00.748259	ATL	CAR	REG	4	2012	FOX
119	a0e65956-1116-4928-a8a6-a1f1b9cd049b	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.749203	2013-09-25 01:34:00.749204	NYJ	SF	REG	4	2012	FOX
120	71621efb-9ee5-4ade-8c8b-16f2a70d8868	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.750132	2013-09-25 01:34:00.750133	BUF	NE	REG	4	2012	CBS
121	66d3a390-c140-4b30-9ec9-ab2bce20c811	closed	2012-09-30	2012-09-30 17:00:00	2013-09-25 01:34:00.751063	2013-09-25 01:34:00.751064	DET	MIN	REG	4	2012	FOX
122	8e488985-b4b1-49eb-9a63-8336de33cac6	closed	2012-09-30	2012-09-30 20:05:00	2013-09-25 01:34:00.75197	2013-09-25 01:34:00.751971	DEN	OAK	REG	4	2012	CBS
123	a17f7a8f-9a01-421a-aa73-fdd8eeb19a95	closed	2012-09-30	2012-09-30 20:05:00	2013-09-25 01:34:00.752836	2013-09-25 01:34:00.752836	JAC	CIN	REG	4	2012	CBS
124	ea8cc558-82c5-4a72-ae79-b0029751aab8	closed	2012-09-30	2012-09-30 20:05:00	2013-09-25 01:34:00.753728	2013-09-25 01:34:00.753729	ARI	MIA	REG	4	2012	CBS
125	53dcb17e-7a6e-4447-80ac-a3705c4e1cce	closed	2012-09-30	2012-09-30 20:25:00	2013-09-25 01:34:00.754718	2013-09-25 01:34:00.754719	GB	NO	REG	4	2012	FOX
126	55fd913d-6c41-4aa3-a93f-436121a2fd50	closed	2012-09-30	2012-09-30 20:25:00	2013-09-25 01:34:00.75566	2013-09-25 01:34:00.755661	TB	WAS	REG	4	2012	FOX
127	c0c56eeb-4b96-497e-9e93-68e3f4c94dac	closed	2012-09-30	2012-10-01 00:20:00	2013-09-25 01:34:00.75656	2013-09-25 01:34:00.756561	PHI	NYG	REG	4	2012	NBC
128	6185b90a-a2d7-42d5-bd21-c1f5700a88f7	closed	2012-10-01	2012-10-02 00:30:00	2013-09-25 01:34:00.757523	2013-09-25 01:34:00.757524	DAL	CHI	REG	4	2012	ESPN
129	0eab80ab-67d6-41a9-8cdb-7567fcd40e6e	closed	2012-10-04	2012-10-05 00:20:00	2013-09-25 01:34:00.75844	2013-09-25 01:34:00.758441	STL	ARI	REG	5	2012	NFL
130	3ec50774-1757-42c7-b579-836e7cae0f5e	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.759352	2013-09-25 01:34:00.759353	WAS	ATL	REG	5	2012	FOX
131	631868a2-53fa-4ec7-afa7-1f516affcded	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.760396	2013-09-25 01:34:00.760396	PIT	PHI	REG	5	2012	FOX
132	745e6643-5191-4244-acef-1f8f968579ca	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.761347	2013-09-25 01:34:00.761347	IND	GB	REG	5	2012	FOX
133	8d625a89-7cc9-45cd-b1d5-ec725ae19f39	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.762281	2013-09-25 01:34:00.762282	KC	BAL	REG	5	2012	CBS
134	a94d5be7-b5b5-471f-ad47-fa9c53976fec	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.763186	2013-09-25 01:34:00.763187	NYG	CLE	REG	5	2012	CBS
135	e39a59f4-e605-4670-9c81-29c65876e737	closed	2012-10-07	2012-10-07 17:00:00	2013-09-25 01:34:00.764095	2013-09-25 01:34:00.764096	CIN	MIA	REG	5	2012	CBS
136	ada0f50f-6256-456d-aaec-408c12a99a02	closed	2012-10-07	2012-10-07 20:05:00	2013-09-25 01:34:00.765023	2013-09-25 01:34:00.765023	JAC	CHI	REG	5	2012	FOX
137	603ec3c7-5298-4e58-82ee-b7091a1a3db3	closed	2012-10-07	2012-10-07 20:05:00	2013-09-25 01:34:00.765921	2013-09-25 01:34:00.765922	CAR	SEA	REG	5	2012	FOX
138	edded3ae-8ed6-417b-8b46-4862e903255d	closed	2012-10-07	2012-10-07 20:25:00	2013-09-25 01:34:00.76681	2013-09-25 01:34:00.766811	MIN	TEN	REG	5	2012	CBS
139	52918071-f70a-43f5-ba6e-b3c88d62db94	closed	2012-10-07	2012-10-07 20:25:00	2013-09-25 01:34:00.768722	2013-09-25 01:34:00.768722	NE	DEN	REG	5	2012	CBS
140	0a01969c-8b35-4a8d-b410-fc557fcfaeb6	closed	2012-10-07	2012-10-07 20:25:00	2013-09-25 01:34:00.769676	2013-09-25 01:34:00.769677	SF	BUF	REG	5	2012	CBS
141	5f86eee3-293e-484a-9da6-d4bcbcecfe73	closed	2012-10-07	2012-10-08 00:20:00	2013-09-25 01:34:00.770638	2013-09-25 01:34:00.770639	NO	SD	REG	5	2012	NBC
142	e5f9ae78-c14c-4752-b08f-c2fc9f1f099c	closed	2012-10-08	2012-10-09 00:30:00	2013-09-25 01:34:00.771599	2013-09-25 01:34:00.7716	NYJ	HOU	REG	5	2012	ESPN
143	d6bb6e75-0041-4fed-ac20-8ee8c80a4000	closed	2012-10-11	2012-10-12 00:20:00	2013-09-25 01:34:00.772544	2013-09-25 01:34:00.772545	TEN	PIT	REG	6	2012	NFL
144	7d3eef90-f40f-44f1-91f3-d4bc0b77e32d	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.773471	2013-09-25 01:34:00.773471	MIA	STL	REG	6	2012	FOX
145	4665b393-f6d7-45be-bad5-1ac29d6de44f	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.774398	2013-09-25 01:34:00.774399	TB	KC	REG	6	2012	CBS
146	4dea8474-b52f-4f39-9a51-3e4078c95771	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.775499	2013-09-25 01:34:00.7755	NYJ	IND	REG	6	2012	CBS
147	8b021915-33b7-4d74-9d08-a35484371aeb	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.776478	2013-09-25 01:34:00.776479	BAL	DAL	REG	6	2012	FOX
148	79235c95-5451-46ad-bf37-17a0136182b9	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.777421	2013-09-25 01:34:00.777421	CLE	CIN	REG	6	2012	CBS
149	476019b6-4227-40a5-a6ee-1e2add4aadb2	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.778381	2013-09-25 01:34:00.778381	PHI	DET	REG	6	2012	FOX
150	cd72fefe-4c33-42ca-9dc3-e44e56bc5a2c	closed	2012-10-14	2012-10-14 17:00:00	2013-09-25 01:34:00.779293	2013-09-25 01:34:00.779293	ATL	OAK	REG	6	2012	CBS
151	6641c92e-0b1c-4b7c-87ff-f4c7127fddbe	closed	2012-10-14	2012-10-14 20:05:00	2013-09-25 01:34:00.780209	2013-09-25 01:34:00.78021	ARI	BUF	REG	6	2012	CBS
152	9b812e6c-4a2f-4b44-a9ae-ad2e99229913	closed	2012-10-14	2012-10-14 20:05:00	2013-09-25 01:34:00.781225	2013-09-25 01:34:00.781226	SEA	NE	REG	6	2012	CBS
153	6f3162e8-f3ce-4670-8895-3c4552e4fb93	closed	2012-10-14	2012-10-14 20:25:00	2013-09-25 01:34:00.782193	2013-09-25 01:34:00.782193	SF	NYG	REG	6	2012	FOX
154	6f15d24f-4135-4e62-814e-0d13269dab08	closed	2012-10-14	2012-10-14 20:25:00	2013-09-25 01:34:00.783113	2013-09-25 01:34:00.783113	WAS	MIN	REG	6	2012	FOX
155	bc40b1b8-1504-48a6-a6b5-08d5d60a383c	closed	2012-10-14	2012-10-15 00:20:00	2013-09-25 01:34:00.784014	2013-09-25 01:34:00.784014	HOU	GB	REG	6	2012	NBC
156	68a14c56-9902-4740-be6d-147f6e90cb1a	closed	2012-10-15	2012-10-16 00:30:00	2013-09-25 01:34:00.784913	2013-09-25 01:34:00.784913	SD	DEN	REG	6	2012	ESPN
157	4ec7505c-cc8e-4729-8ff2-a410d7e0195c	closed	2012-10-18	2012-10-19 00:20:00	2013-09-25 01:34:00.785798	2013-09-25 01:34:00.785798	SF	SEA	REG	7	2012	NFL
158	4f9faa74-3cd4-4e6a-a727-6fae0030cc83	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.786828	2013-09-25 01:34:00.786829	STL	GB	REG	7	2012	FOX
159	2a00184e-2a06-4e3b-b2c7-a8d389511d94	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.787794	2013-09-25 01:34:00.787795	IND	CLE	REG	7	2012	CBS
160	7d1a7ad2-c7ea-4050-8d97-9257e9d96b13	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.78873	2013-09-25 01:34:00.78873	HOU	BAL	REG	7	2012	CBS
161	af793107-1d27-406d-b887-a6d5ccf42ecb	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.790313	2013-09-25 01:34:00.790313	MIN	ARI	REG	7	2012	FOX
162	d1d6d910-5544-43e3-86ff-09e1c6b390cf	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.791333	2013-09-25 01:34:00.791334	CAR	DAL	REG	7	2012	FOX
163	6bf05fc1-8e11-44e0-bbb9-91efe06decf7	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.792279	2013-09-25 01:34:00.79228	TB	NO	REG	7	2012	FOX
164	f02b63c4-d5b5-42de-a8b1-2ce86e3d754a	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.793268	2013-09-25 01:34:00.793269	NYG	WAS	REG	7	2012	FOX
165	9a38d9e9-aa16-4865-bac8-68854f978513	closed	2012-10-21	2012-10-21 17:00:00	2013-09-25 01:34:00.794207	2013-09-25 01:34:00.794208	BUF	TEN	REG	7	2012	CBS
166	bb39815c-2223-4a0a-b278-9cb7bb91e3c4	closed	2012-10-21	2012-10-21 20:25:00	2013-09-25 01:34:00.795169	2013-09-25 01:34:00.795169	OAK	JAC	REG	7	2012	CBS
167	97fffa25-3c4f-45f4-9918-4710fc45b9c9	closed	2012-10-21	2012-10-21 20:25:00	2013-09-25 01:34:00.79614	2013-09-25 01:34:00.796141	NE	NYJ	REG	7	2012	CBS
168	0f221e25-97c3-485b-8566-dc29de153a71	closed	2012-10-21	2012-10-22 00:20:00	2013-09-25 01:34:00.797071	2013-09-25 01:34:00.797071	CIN	PIT	REG	7	2012	NBC
169	5a4a870e-2158-477e-8aa4-821c7a2a2839	closed	2012-10-22	2012-10-23 00:30:00	2013-09-25 01:34:00.798012	2013-09-25 01:34:00.798012	CHI	DET	REG	7	2012	ESPN
170	8640c455-0289-416e-8c77-a0bd9a619433	closed	2012-10-25	2012-10-26 00:20:00	2013-09-25 01:34:00.79895	2013-09-25 01:34:00.798951	MIN	TB	REG	8	2012	NFL
171	04d51f99-798a-469f-bac9-2614ad62b3f5	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.799844	2013-09-25 01:34:00.799845	CLE	SD	REG	8	2012	CBS
172	bdb882b0-c95a-4e46-9854-39141b3feaf7	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.800769	2013-09-25 01:34:00.800769	DET	SEA	REG	8	2012	FOX
173	002fb9d6-a944-48ce-af64-7785e830e5bd	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.801755	2013-09-25 01:34:00.801755	PHI	ATL	REG	8	2012	FOX
174	d3735dd5-91e7-40c8-896b-0d13da37f3cb	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.802708	2013-09-25 01:34:00.802709	GB	JAC	REG	8	2012	CBS
175	17322ee3-7486-463d-b085-312dfd6a3097	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.803715	2013-09-25 01:34:00.803716	STL	NE	REG	8	2012	CBS
176	9d7d7b69-12a7-4fd8-a819-ceb6d4adc075	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.804654	2013-09-25 01:34:00.804655	TEN	IND	REG	8	2012	CBS
177	5cfeacf7-c8b7-420e-bbb8-d911318e97f8	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.805582	2013-09-25 01:34:00.805583	CHI	CAR	REG	8	2012	FOX
178	e8efe3fb-f53a-4d10-90cb-dd1abd76c821	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.806543	2013-09-25 01:34:00.806544	PIT	WAS	REG	8	2012	FOX
179	88d2c482-cdcb-413c-a753-d6e004cca8d0	closed	2012-10-28	2012-10-28 17:00:00	2013-09-25 01:34:00.807462	2013-09-25 01:34:00.807462	NYJ	MIA	REG	8	2012	CBS
180	ffad2389-e576-4cbe-931f-fab6c11e7103	closed	2012-10-28	2012-10-28 20:05:00	2013-09-25 01:34:00.808401	2013-09-25 01:34:00.808402	KC	OAK	REG	8	2012	CBS
181	c0da0c8c-0273-4791-bde0-412a3666f302	closed	2012-10-28	2012-10-28 20:15:00	2013-09-25 01:34:00.80936	2013-09-25 01:34:00.809361	DAL	NYG	REG	8	2012	FOX
182	4cb918e1-2db1-4c0d-bdff-dfd59b68995a	closed	2012-10-28	2012-10-29 00:20:00	2013-09-25 01:34:00.810329	2013-09-25 01:34:00.810329	DEN	NO	REG	8	2012	NBC
183	c87dd434-3827-4795-9e5c-738fa16d6b5e	closed	2012-10-29	2012-10-30 00:30:00	2013-09-25 01:34:00.811288	2013-09-25 01:34:00.811288	ARI	SF	REG	8	2012	ESPN
184	82748625-c24e-437a-b991-cab7f766c249	closed	2012-11-01	2012-11-02 00:20:00	2013-09-25 01:34:00.812214	2013-09-25 01:34:00.812214	SD	KC	REG	9	2012	NFL
185	d26633b8-d3ec-49ab-a8a5-f4bb59a67fcf	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.813142	2013-09-25 01:34:00.813143	CIN	DEN	REG	9	2012	CBS
186	55d0b262-98ff-49fa-95c8-5ab8ec8cbd34	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.814069	2013-09-25 01:34:00.81407	IND	MIA	REG	9	2012	CBS
187	bbd8d64c-eaee-46ee-959c-af327fe9413f	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.81503	2013-09-25 01:34:00.815031	GB	ARI	REG	9	2012	FOX
188	61fc12f3-c65d-4c43-8276-a8cfd1507ce5	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.815966	2013-09-25 01:34:00.815966	WAS	CAR	REG	9	2012	FOX
189	1270df07-34fb-4c42-adcf-4bc23d464eaf	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.816894	2013-09-25 01:34:00.816895	JAC	DET	REG	9	2012	FOX
190	14dbd4e6-ff0d-4e52-ba53-f8bb5e1246e7	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.817815	2013-09-25 01:34:00.817816	CLE	BAL	REG	9	2012	CBS
191	3ff1c6c6-aee8-4aa7-a5b7-ae1a883eeb93	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.818757	2013-09-25 01:34:00.818757	TEN	CHI	REG	9	2012	FOX
192	5ac4bca6-1c9f-4240-a3b7-f1b05e324731	closed	2012-11-04	2012-11-04 18:00:00	2013-09-25 01:34:00.819721	2013-09-25 01:34:00.819722	HOU	BUF	REG	9	2012	CBS
193	7795416d-8aee-48ab-ba48-6bab493c38ea	closed	2012-11-04	2012-11-04 21:05:00	2013-09-25 01:34:00.820681	2013-09-25 01:34:00.820682	SEA	MIN	REG	9	2012	FOX
194	b59666fa-cce9-4118-978e-c6ce3aae8295	closed	2012-11-04	2012-11-04 21:05:00	2013-09-25 01:34:00.8216	2013-09-25 01:34:00.8216	OAK	TB	REG	9	2012	FOX
195	e3144922-b6c6-4587-8879-acbd9a04fab5	closed	2012-11-04	2012-11-04 21:25:00	2013-09-25 01:34:00.822507	2013-09-25 01:34:00.822508	NYG	PIT	REG	9	2012	CBS
196	5fd8e2c9-bf0a-4d34-ad7b-1301ddc2acbd	closed	2012-11-04	2012-11-05 01:20:00	2013-09-25 01:34:00.823474	2013-09-25 01:34:00.823474	ATL	DAL	REG	9	2012	NBC
197	dd451e81-a4bb-46bb-aea2-d4883e684a52	closed	2012-11-05	2012-11-06 01:30:00	2013-09-25 01:34:00.825637	2013-09-25 01:34:00.825637	NO	PHI	REG	9	2012	ESPN
198	868e2fdc-a515-4ed9-8e66-d25170f8a3e3	closed	2012-11-08	2012-11-09 01:20:00	2013-09-25 01:34:00.826609	2013-09-25 01:34:00.82661	JAC	IND	REG	10	2012	NFL
199	48160ea1-18b1-4c0a-8330-2e055572807d	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.827612	2013-09-25 01:34:00.827613	CAR	DEN	REG	10	2012	CBS
200	5736ec21-f0b7-4e7b-a809-ec1a8123fd4f	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.828591	2013-09-25 01:34:00.828592	MIN	DET	REG	10	2012	FOX
201	3be3d922-0f1a-4f86-abc6-231218833764	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.829524	2013-09-25 01:34:00.829525	MIA	TEN	REG	10	2012	CBS
202	b7ed6f52-f4d5-4487-952c-84e582e18bb6	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.830412	2013-09-25 01:34:00.830413	CIN	NYG	REG	10	2012	FOX
203	ce2c97f4-6d01-4f2e-ba8b-1df529a238bd	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.83133	2013-09-25 01:34:00.831331	TB	SD	REG	10	2012	CBS
204	ed4ff082-457a-4cb2-8cb6-054943310885	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.832237	2013-09-25 01:34:00.832237	NO	ATL	REG	10	2012	FOX
205	f14841c7-f684-4e1d-a434-63660db1d656	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.833125	2013-09-25 01:34:00.833126	NE	BUF	REG	10	2012	CBS
206	731b96bf-7580-4cc2-82bc-8fa61bafa549	closed	2012-11-11	2012-11-11 18:00:00	2013-09-25 01:34:00.834076	2013-09-25 01:34:00.834076	BAL	OAK	REG	10	2012	CBS
207	d922e55b-c7d9-4221-ba44-07e0e13aa354	closed	2012-11-11	2012-11-11 21:05:00	2013-09-25 01:34:00.835026	2013-09-25 01:34:00.835027	SEA	NYJ	REG	10	2012	CBS
208	43418344-87e8-4e42-b870-988341541ffd	closed	2012-11-11	2012-11-11 21:25:00	2013-09-25 01:34:00.835971	2013-09-25 01:34:00.835971	PHI	DAL	REG	10	2012	FOX
209	87fe3139-4378-484e-a6d8-c28f94f346f7	closed	2012-11-11	2012-11-11 21:25:00	2013-09-25 01:34:00.836937	2013-09-25 01:34:00.836938	SF	STL	REG	10	2012	FOX
210	413e0815-d6fa-4c87-9cd1-0e95fe0f04d9	closed	2012-11-11	2012-11-12 01:20:00	2013-09-25 01:34:00.837887	2013-09-25 01:34:00.837887	CHI	HOU	REG	10	2012	NBC
211	0b9136b6-346f-48cb-aa65-1b217340c789	closed	2012-11-12	2012-11-13 01:30:00	2013-09-25 01:34:00.838865	2013-09-25 01:34:00.838866	PIT	KC	REG	10	2012	ESPN
212	c40dcdf2-0abe-4e83-9eb4-f10b443e9987	closed	2012-11-15	2012-11-16 01:20:00	2013-09-25 01:34:00.839793	2013-09-25 01:34:00.839793	BUF	MIA	REG	11	2012	NFL
213	76c38c3a-121d-46ba-9ab9-c926133187e1	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.840763	2013-09-25 01:34:00.840764	HOU	JAC	REG	11	2012	CBS
214	97b78c85-0782-4f1b-8665-05879859df21	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.841701	2013-09-25 01:34:00.841702	STL	NYJ	REG	11	2012	CBS
215	705b8290-bb28-4d9c-8d6f-4949b5f11a13	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.842617	2013-09-25 01:34:00.842617	DAL	CLE	REG	11	2012	CBS
216	b1d95871-c502-460c-8e5a-d7265ebfed45	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.843535	2013-09-25 01:34:00.843536	KC	CIN	REG	11	2012	CBS
217	9d287068-1bdf-441a-b16d-37436ce68b65	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.844464	2013-09-25 01:34:00.844465	CAR	TB	REG	11	2012	FOX
218	e2f7e169-ce18-40ce-a7fc-938a7e03e221	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.845447	2013-09-25 01:34:00.845448	WAS	PHI	REG	11	2012	FOX
219	cfcaece1-32d7-475c-84e6-1ee5920dbfee	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.846357	2013-09-25 01:34:00.846357	DET	GB	REG	11	2012	FOX
220	a078fd59-409c-4403-9bf6-887fc3b4cd4a	closed	2012-11-18	2012-11-18 18:00:00	2013-09-25 01:34:00.847277	2013-09-25 01:34:00.847277	ATL	ARI	REG	11	2012	FOX
221	8d7975bd-7e20-4951-861d-f8f22f75d306	closed	2012-11-18	2012-11-18 21:05:00	2013-09-25 01:34:00.848193	2013-09-25 01:34:00.848194	OAK	NO	REG	11	2012	FOX
222	cb1dc503-de5d-479e-8538-4d5b845e2a9e	closed	2012-11-18	2012-11-18 21:25:00	2013-09-25 01:34:00.849094	2013-09-25 01:34:00.849094	DEN	SD	REG	11	2012	CBS
223	5c1c76ce-a612-4244-87e7-91af73f9b0d9	closed	2012-11-18	2012-11-18 21:25:00	2013-09-25 01:34:00.849976	2013-09-25 01:34:00.849977	NE	IND	REG	11	2012	CBS
224	b0aefc0c-dd2c-43ed-9df3-b433420a217f	closed	2012-11-18	2012-11-19 01:20:00	2013-09-25 01:34:00.850875	2013-09-25 01:34:00.850875	PIT	BAL	REG	11	2012	NBC
225	f9cf9e59-51d7-4e01-977c-82081c976703	closed	2012-11-19	2012-11-20 01:30:00	2013-09-25 01:34:00.851761	2013-09-25 01:34:00.851761	SF	CHI	REG	11	2012	ESPN
226	be31f41a-69e1-4cf9-9278-a14716825ff6	closed	2012-11-22	2012-11-22 17:30:00	2013-09-25 01:34:00.852661	2013-09-25 01:34:00.852662	DET	HOU	REG	12	2012	CBS
227	7f8d78e0-0d6f-4a6f-917f-6983e1fd8d5e	closed	2012-11-22	2012-11-22 21:15:00	2013-09-25 01:34:00.85356	2013-09-25 01:34:00.853561	DAL	WAS	REG	12	2012	FOX
228	5a1dea8c-a3d7-4b80-a348-84728332f6f6	closed	2012-11-22	2012-11-23 01:20:00	2013-09-25 01:34:00.854477	2013-09-25 01:34:00.854478	NYJ	NE	REG	12	2012	NBC
229	c035cfde-f3b8-4038-8810-32624cf5f445	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.855434	2013-09-25 01:34:00.855435	CHI	MIN	REG	12	2012	FOX
230	ee1f9484-eaf0-429f-a57c-a7c085c2ec1a	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.856419	2013-09-25 01:34:00.856419	IND	BUF	REG	12	2012	CBS
231	17243217-181d-47c7-8104-4f2c9e4f56b7	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.857358	2013-09-25 01:34:00.857359	KC	DEN	REG	12	2012	CBS
232	cbbd12e0-801c-4786-9706-e8f9d3055298	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.858294	2013-09-25 01:34:00.858295	CIN	OAK	REG	12	2012	CBS
233	760c7e7e-d20c-4dd1-a416-4ddd49cb5119	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.859249	2013-09-25 01:34:00.85925	TB	ATL	REG	12	2012	FOX
234	1fb5ee2f-e462-426e-871f-1c1cd66b6d26	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.860203	2013-09-25 01:34:00.860204	CLE	PIT	REG	12	2012	CBS
235	8955d925-41a1-43c3-b642-39a3ba1e3000	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.861144	2013-09-25 01:34:00.861145	JAC	TEN	REG	12	2012	CBS
236	56bb0617-5acf-4f91-a42d-2d9d45434426	closed	2012-11-25	2012-11-25 18:00:00	2013-09-25 01:34:00.862057	2013-09-25 01:34:00.862057	MIA	SEA	REG	12	2012	FOX
237	c49c7899-420b-4625-a0fc-61a1049d5922	closed	2012-11-25	2012-11-25 21:05:00	2013-09-25 01:34:00.862963	2013-09-25 01:34:00.862963	SD	BAL	REG	12	2012	CBS
238	a57d29bd-8f26-47c7-b24d-5b5ceba1a853	closed	2012-11-25	2012-11-25 21:25:00	2013-09-25 01:34:00.863816	2013-09-25 01:34:00.863816	ARI	STL	REG	12	2012	FOX
239	9ff6957e-cd97-4e03-a5d0-794dca1543b2	closed	2012-11-25	2012-11-25 21:25:00	2013-09-25 01:34:00.864765	2013-09-25 01:34:00.864765	NO	SF	REG	12	2012	FOX
240	db3d08dc-c2e9-4e83-bfef-1a442b36a889	closed	2012-11-25	2012-11-26 01:20:00	2013-09-25 01:34:00.865683	2013-09-25 01:34:00.865684	NYG	GB	REG	12	2012	NBC
241	b9fe77e6-2890-4ffc-8af1-12a8e22500e8	closed	2012-11-26	2012-11-27 01:30:00	2013-09-25 01:34:00.866625	2013-09-25 01:34:00.866626	PHI	CAR	REG	12	2012	ESPN
242	a2e1d22b-af19-4b01-9603-a0619945d86e	closed	2012-11-29	2012-11-30 01:20:00	2013-09-25 01:34:00.867527	2013-09-25 01:34:00.867527	ATL	NO	REG	13	2012	NFL
243	6a7e4ea1-886b-4b7f-93b4-13f4be468a5b	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.868459	2013-09-25 01:34:00.86846	MIA	NE	REG	13	2012	CBS
244	bf3d482a-b379-47e0-98f8-8cc454c79d2f	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.869385	2013-09-25 01:34:00.869386	CHI	SEA	REG	13	2012	FOX
245	7c61d74e-0e99-4224-a004-4eeecceb81b3	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.870274	2013-09-25 01:34:00.870274	GB	MIN	REG	13	2012	FOX
246	c292a1f8-b13f-4b3b-868c-f44b4227aba0	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.871157	2013-09-25 01:34:00.871158	STL	SF	REG	13	2012	FOX
247	183cef2e-5871-4052-811f-abdf0a182a2a	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.872046	2013-09-25 01:34:00.872046	TEN	HOU	REG	13	2012	CBS
248	438931f2-bcde-476b-b00a-8d9e4474c8b1	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.872934	2013-09-25 01:34:00.872935	NYJ	ARI	REG	13	2012	FOX
249	c1759708-0f16-4c7c-bff8-a700bbff9237	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.873823	2013-09-25 01:34:00.873823	KC	CAR	REG	13	2012	FOX
250	4e264c9a-353e-42cb-ac09-6186f74cbe2e	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.874706	2013-09-25 01:34:00.874707	DET	IND	REG	13	2012	CBS
251	2cd35039-ba77-47e5-b957-9edef9fcf5a5	closed	2012-12-02	2012-12-02 18:00:00	2013-09-25 01:34:00.875597	2013-09-25 01:34:00.875598	BUF	JAC	REG	13	2012	CBS
252	c292b014-4449-4038-97a5-054a5a3414f9	closed	2012-12-02	2012-12-02 21:05:00	2013-09-25 01:34:00.876474	2013-09-25 01:34:00.876474	DEN	TB	REG	13	2012	FOX
253	85c8a7ab-dd06-4d0e-af57-1bab3052b90f	closed	2012-12-02	2012-12-02 21:25:00	2013-09-25 01:34:00.877314	2013-09-25 01:34:00.877314	BAL	PIT	REG	13	2012	CBS
254	afb21bff-f0a7-42e9-ba83-628d9b7b58f1	closed	2012-12-02	2012-12-02 21:25:00	2013-09-25 01:34:00.879501	2013-09-25 01:34:00.879501	SD	CIN	REG	13	2012	CBS
255	7e04e3d6-2185-47da-890e-9f6dbddc50c5	closed	2012-12-02	2012-12-02 21:25:00	2013-09-25 01:34:00.880441	2013-09-25 01:34:00.880441	OAK	CLE	REG	13	2012	CBS
256	f90789da-db58-42c9-b678-b8c9880226f6	closed	2012-12-02	2012-12-03 01:20:00	2013-09-25 01:34:00.881632	2013-09-25 01:34:00.881633	DAL	PHI	REG	13	2012	NBC
257	081ce725-8b29-434f-a328-eff8f1831584	closed	2012-12-03	2012-12-04 01:30:00	2013-09-25 01:34:00.882577	2013-09-25 01:34:00.882577	WAS	NYG	REG	13	2012	ESPN
258	6f19c3f0-2ae8-46d6-a06e-a2daffd4c7b9	closed	2012-12-06	2012-12-07 01:20:00	2013-09-25 01:34:00.883483	2013-09-25 01:34:00.883483	OAK	DEN	REG	14	2012	NFL
259	3c41f6d2-f4ed-4cd0-9902-cefae66a7f38	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.884372	2013-09-25 01:34:00.884372	MIN	CHI	REG	14	2012	FOX
260	de119a69-a16e-47d8-9a64-f769a09564e1	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.88526	2013-09-25 01:34:00.885261	CIN	DAL	REG	14	2012	FOX
261	72e6a09f-708d-463e-9d8f-c3fca1bed7b2	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.886152	2013-09-25 01:34:00.886152	JAC	NYJ	REG	14	2012	CBS
262	947c3359-fb46-4c50-8207-33a43a35c155	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.887043	2013-09-25 01:34:00.887043	TB	PHI	REG	14	2012	FOX
263	5178e12e-5597-449d-9b39-126a7c8fed33	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.887922	2013-09-25 01:34:00.887923	IND	TEN	REG	14	2012	CBS
264	4c2f059d-3c1f-4420-8a0f-a3917431ab67	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.888857	2013-09-25 01:34:00.888858	CAR	ATL	REG	14	2012	FOX
265	303a0070-3bf7-495a-89a5-314fd63f1e09	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.88975	2013-09-25 01:34:00.889751	CLE	KC	REG	14	2012	CBS
266	5aa70166-f140-4669-9345-fa429d2e9ea4	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.890793	2013-09-25 01:34:00.890793	PIT	SD	REG	14	2012	CBS
267	4c5f684d-113e-451c-9284-f1b22727d740	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.891739	2013-09-25 01:34:00.89174	BUF	STL	REG	14	2012	FOX
268	5bd42766-5b91-4763-a8fe-0df3b25e016f	closed	2012-12-09	2012-12-09 18:00:00	2013-09-25 01:34:00.892724	2013-09-25 01:34:00.892725	WAS	BAL	REG	14	2012	CBS
269	3519d8b2-c742-4f89-9437-6a8f1917c925	closed	2012-12-09	2012-12-09 21:05:00	2013-09-25 01:34:00.893702	2013-09-25 01:34:00.893702	SF	MIA	REG	14	2012	CBS
270	4c56a20f-46d6-47af-a86e-daefb14fbe8a	closed	2012-12-09	2012-12-09 21:25:00	2013-09-25 01:34:00.894652	2013-09-25 01:34:00.894653	NYG	NO	REG	14	2012	FOX
271	47d76252-33bb-45aa-b0ef-724a702d2d28	closed	2012-12-09	2012-12-09 21:25:00	2013-09-25 01:34:00.89561	2013-09-25 01:34:00.89561	SEA	ARI	REG	14	2012	FOX
272	a713208c-0330-401e-8a8d-b40417e33bf9	closed	2012-12-09	2012-12-10 01:20:00	2013-09-25 01:34:00.896575	2013-09-25 01:34:00.896576	GB	DET	REG	14	2012	NBC
273	bfbe0676-cdde-48bf-9c68-51df8e467789	closed	2012-12-10	2012-12-11 01:30:00	2013-09-25 01:34:00.897529	2013-09-25 01:34:00.897529	NE	HOU	REG	14	2012	ESPN
274	afdc4098-450e-4f77-9cea-845e04fd0f07	closed	2012-12-13	2012-12-14 01:20:00	2013-09-25 01:34:00.898421	2013-09-25 01:34:00.898422	PHI	CIN	REG	15	2012	NFL
275	6d3e96ef-95f8-43ab-a75c-86f034ce9d1a	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.89932	2013-09-25 01:34:00.89932	CHI	GB	REG	15	2012	FOX
276	80a84713-7b41-4958-a562-55810e2859df	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.900207	2013-09-25 01:34:00.900207	ATL	NYG	REG	15	2012	FOX
277	e41e41f0-e80d-42af-898e-d13919de97dd	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.9011	2013-09-25 01:34:00.9011	BAL	DEN	REG	15	2012	CBS
278	19314aea-7cd2-444a-b3ab-a7c784e28542	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.902025	2013-09-25 01:34:00.902026	STL	MIN	REG	15	2012	FOX
279	016b3fd8-f683-42f5-a06f-0dee018bd327	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.902963	2013-09-25 01:34:00.902963	NO	TB	REG	15	2012	FOX
280	a2647c98-2967-496c-9bd4-82850a11c877	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.903883	2013-09-25 01:34:00.903883	HOU	IND	REG	15	2012	CBS
281	1e92fc1e-917f-44ec-807c-fc04a679210e	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.904779	2013-09-25 01:34:00.904779	MIA	JAC	REG	15	2012	CBS
282	3bc1dcd6-db3f-4ec3-ad0c-3ba599adddcb	closed	2012-12-16	2012-12-16 18:00:00	2013-09-25 01:34:00.905684	2013-09-25 01:34:00.905685	CLE	WAS	REG	15	2012	FOX
283	70ee2f0e-d3fb-4af6-905e-15998cefba32	closed	2012-12-16	2012-12-16 21:05:00	2013-09-25 01:34:00.906563	2013-09-25 01:34:00.906563	SD	CAR	REG	15	2012	FOX
284	7d65d1c1-1886-4f5b-a5e5-e84ec1a1ce90	closed	2012-12-16	2012-12-16 21:05:00	2013-09-25 01:34:00.907449	2013-09-25 01:34:00.90745	ARI	DET	REG	15	2012	FOX
285	68a9b9ef-0848-4f6e-8581-340f8f20220f	closed	2012-12-16	2012-12-16 21:05:00	2013-09-25 01:34:00.90837	2013-09-25 01:34:00.908371	BUF	SEA	REG	15	2012	FOX
286	77fdba01-9715-4450-a791-8a9986be4095	closed	2012-12-16	2012-12-16 21:25:00	2013-09-25 01:34:00.909251	2013-09-25 01:34:00.909251	DAL	PIT	REG	15	2012	CBS
287	0e2e8472-598e-458f-8f95-82aa81783ddf	closed	2012-12-16	2012-12-16 21:25:00	2013-09-25 01:34:00.910133	2013-09-25 01:34:00.910133	OAK	KC	REG	15	2012	CBS
288	3e8ddf7f-ff00-4f67-b6da-45b1635cf44b	closed	2012-12-16	2012-12-17 01:20:00	2013-09-25 01:34:00.91111	2013-09-25 01:34:00.911111	NE	SF	REG	15	2012	NBC
289	3176de98-615e-4d49-952f-654eb2ed26c3	closed	2012-12-17	2012-12-18 01:30:00	2013-09-25 01:34:00.91204	2013-09-25 01:34:00.91204	TEN	NYJ	REG	15	2012	ESPN
290	b3d40adc-aaa8-4786-9e81-c886db35576a	closed	2012-12-22	2012-12-23 01:30:00	2013-09-25 01:34:00.913002	2013-09-25 01:34:00.913002	DET	ATL	REG	16	2012	ESPN
291	aa3082c8-4e92-45a8-8d0d-d7e4c47d644f	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.91394	2013-09-25 01:34:00.91394	JAC	NE	REG	16	2012	CBS
292	b90e3cc5-56d9-4796-94b7-a55d47395878	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.914881	2013-09-25 01:34:00.914881	GB	TEN	REG	16	2012	CBS
293	202c04b4-2d2d-4cba-a8ae-87a4523a806c	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.915826	2013-09-25 01:34:00.915827	CAR	OAK	REG	16	2012	CBS
294	20c0fbf5-65ce-4aad-92ba-9c7a9f2cb11a	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.916769	2013-09-25 01:34:00.91677	PHI	WAS	REG	16	2012	FOX
295	9231e06a-5d43-4a0d-9dbb-3757864384a1	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.91773	2013-09-25 01:34:00.91773	MIA	BUF	REG	16	2012	CBS
296	41543c2c-7099-4d11-af7b-f5fe1a90e7c8	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.918692	2013-09-25 01:34:00.918693	TB	STL	REG	16	2012	FOX
297	f9e7d2ca-0292-4de3-824a-5e8539dc2486	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.919625	2013-09-25 01:34:00.919625	HOU	MIN	REG	16	2012	FOX
298	944fe36f-4bac-452e-a0ba-206463838d2f	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.920589	2013-09-25 01:34:00.920589	KC	IND	REG	16	2012	CBS
299	70bf1444-43bb-4593-a250-e39f7f319652	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.921503	2013-09-25 01:34:00.921503	NYJ	SD	REG	16	2012	CBS
300	8de8f1a8-4832-4bac-99cf-ef355156ce1a	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.922437	2013-09-25 01:34:00.922438	PIT	CIN	REG	16	2012	CBS
301	c469f647-53ac-48ef-91e0-d297de795b9c	closed	2012-12-23	2012-12-23 18:00:00	2013-09-25 01:34:00.923339	2013-09-25 01:34:00.923339	DAL	NO	REG	16	2012	FOX
302	a46c5f0d-9d2b-4407-bc9b-d8e7a3640ca4	closed	2012-12-23	2012-12-23 21:05:00	2013-09-25 01:34:00.924232	2013-09-25 01:34:00.924232	DEN	CLE	REG	16	2012	CBS
303	4c95b787-b88e-4276-b195-a79f23120599	closed	2012-12-23	2012-12-23 21:25:00	2013-09-25 01:34:00.925167	2013-09-25 01:34:00.925168	BAL	NYG	REG	16	2012	FOX
304	58043c3d-2b89-40b4-99c6-1622e2ea926d	closed	2012-12-23	2012-12-23 21:25:00	2013-09-25 01:34:00.926142	2013-09-25 01:34:00.926142	ARI	CHI	REG	16	2012	FOX
305	98fa3efa-7ca7-438e-b250-cf4a31c67d89	closed	2012-12-23	2012-12-24 01:20:00	2013-09-25 01:34:00.927098	2013-09-25 01:34:00.927099	SEA	SF	REG	16	2012	NBC
306	374ba2fb-9e27-47a4-a07f-d1bd93705431	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.92804	2013-09-25 01:34:00.928041	TEN	JAC	REG	17	2012	CBS
307	24cda793-fb5a-481c-84f4-6ebeb463815d	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.929039	2013-09-25 01:34:00.92904	DET	CHI	REG	17	2012	FOX
308	105113aa-9639-4c35-8072-6019a6b3ccdf	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.929965	2013-09-25 01:34:00.929966	ATL	TB	REG	17	2012	FOX
309	9a44993b-24a1-47f6-bf5b-dd51f19c7349	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.930911	2013-09-25 01:34:00.930912	BUF	NYJ	REG	17	2012	CBS
310	49a56fa8-60d9-4568-8d90-0a8d0c48dce8	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.931817	2013-09-25 01:34:00.931818	NO	CAR	REG	17	2012	FOX
311	dcfb0c36-f456-48a7-9aa9-4fd0e08441dd	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.932708	2013-09-25 01:34:00.932708	IND	HOU	REG	17	2012	CBS
312	188dd35e-20a9-4624-a481-3150618c42d0	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.934924	2013-09-25 01:34:00.934925	CIN	BAL	REG	17	2012	CBS
313	22209519-f6e1-4dad-958d-27c835301514	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.935957	2013-09-25 01:34:00.935957	NYG	PHI	REG	17	2012	FOX
314	ca51fd90-a36f-4949-bf4c-67ae742c9c44	closed	2012-12-30	2012-12-30 18:00:00	2013-09-25 01:34:00.936918	2013-09-25 01:34:00.936918	PIT	CLE	REG	17	2012	CBS
315	0fac861c-8913-4449-a1bc-9f62fa10c230	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.937945	2013-09-25 01:34:00.937946	DEN	KC	REG	17	2012	CBS
316	cfd6200d-594b-4506-92ce-a6d57337cf66	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.938923	2013-09-25 01:34:00.938924	SF	ARI	REG	17	2012	FOX
317	265cc0df-20d9-4aaa-9e48-ece01e4990cb	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.939847	2013-09-25 01:34:00.939848	SEA	STL	REG	17	2012	FOX
318	adbd3f90-72dc-4266-82fb-4a69323ede89	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.940781	2013-09-25 01:34:00.940781	NE	MIA	REG	17	2012	CBS
319	5c1a5ea1-76d7-4917-b949-f59ec4a1487f	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.941704	2013-09-25 01:34:00.941704	SD	OAK	REG	17	2012	CBS
320	9bed8e6c-05d2-43d8-a530-38803ea856cf	closed	2012-12-30	2012-12-30 21:25:00	2013-09-25 01:34:00.942639	2013-09-25 01:34:00.94264	MIN	GB	REG	17	2012	FOX
321	aa45faa8-738c-4948-9213-6ab70aa1e91e	closed	2012-12-30	2012-12-31 01:20:00	2013-09-25 01:34:00.943644	2013-09-25 01:34:00.943645	WAS	DAL	REG	17	2012	NBC
322	a64d599e-ca12-44a8-84cb-4d6dda4c27ed	closed	2013-01-05	2013-01-05 21:30:00	2013-09-25 01:34:01.217248	2013-09-25 01:34:01.217249	HOU	CIN	PST	1	2012	NBC
323	d4de7da3-4b7d-4876-b3eb-366108087ae6	closed	2013-01-05	2013-01-06 01:00:00	2013-09-25 01:34:01.220424	2013-09-25 01:34:01.220425	GB	MIN	PST	1	2012	NBC
324	54798965-47da-4351-9d45-a3e77a74b0c1	closed	2013-01-06	2013-01-06 18:00:00	2013-09-25 01:34:01.222198	2013-09-25 01:34:01.222198	BAL	IND	PST	1	2012	CBS
325	0c77c9e6-526e-42c6-be52-e484371eff78	closed	2013-01-06	2013-01-06 21:30:00	2013-09-25 01:34:01.223508	2013-09-25 01:34:01.223509	WAS	SEA	PST	1	2012	FOX
326	a4783c19-523d-42d5-874b-51b348116b34	closed	2013-01-12	2013-01-12 21:30:00	2013-09-25 01:34:01.224746	2013-09-25 01:34:01.224746	DEN	BAL	PST	2	2012	CBS
327	7d6b7fc9-2472-4232-a0d9-db4265e8ed41	closed	2013-01-12	2013-01-13 01:00:00	2013-09-25 01:34:01.22591	2013-09-25 01:34:01.22591	SF	GB	PST	2	2012	FOX
328	b3c72176-2b61-4ac8-b06e-c2f04948f6c1	closed	2013-01-13	2013-01-13 18:00:00	2013-09-25 01:34:01.227058	2013-09-25 01:34:01.227059	ATL	SEA	PST	2	2012	FOX
329	8739f187-98cf-483a-89b0-c1058ef9ab31	closed	2013-01-13	2013-01-13 21:30:00	2013-09-25 01:34:01.228282	2013-09-25 01:34:01.228283	NE	HOU	PST	2	2012	CBS
330	6d7d8252-f0b3-42e3-ac51-fead5f18e49f	closed	2013-01-20	2013-01-20 20:00:00	2013-09-25 01:34:01.229497	2013-09-25 01:34:01.229497	ATL	SF	PST	3	2012	FOX
331	a13766b3-ee0b-4ba8-9b78-8787e7da6bc5	closed	2013-01-20	2013-01-20 23:30:00	2013-09-25 01:34:01.230634	2013-09-25 01:34:01.230635	NE	BAL	PST	3	2012	CBS
332	14ff1d51-9784-4677-850b-36c8c19f7884	closed	2013-02-03	2013-02-03 23:30:00	2013-09-25 01:34:01.231783	2013-09-25 01:34:01.231784	SF	BAL	PST	4	2012	CBS
\.


--
-- Data for Name: games_markets; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY games_markets (id, game_stats_id, market_id) FROM stdin;
1	e93f780c-dc00-4456-835b-0abc6a64e58d	1
2	b307bf92-9c69-4443-bc18-cee45fb63fcb	1
3	9279dd5b-5429-4680-bee4-26cfaaf51b21	1
4	1a984c80-f0fa-48c8-a88d-a67a82344753	1
5	3af20dde-aa41-46f2-a7e2-929ce5b4a2e6	1
6	92613948-82c8-46c1-b943-1c43c10914fb	1
7	5c04ec0a-eea2-4c42-a828-3b5c850e1cee	2
8	0eab80ab-67d6-41a9-8cdb-7567fcd40e6e	3
9	34a343ce-97e9-4c65-9560-87681886ec1b	4
10	c85fe28f-fe13-4f0e-8458-ff780e8b2489	4
11	842c8697-299c-46f0-b60f-2a0c81f65fbf	4
12	0710508f-241b-4eb1-a39e-91a7dd97e2f6	4
13	dc04122b-0031-464b-b396-f91c8b38cffe	4
14	1a33d801-3ed7-4dfe-9627-b79655818716	4
15	9a97b81e-7748-48f1-aa90-a311b34ee44b	4
16	b6dd5fc1-4d02-4b2a-8a8f-d7ae60c34113	4
17	9e39ac0c-a4b6-4b7c-92eb-6c502842c49d	4
18	f242f82a-0cc0-47e6-915f-fb2857072cea	4
19	55240ff2-7bc0-4a12-a11f-b98f7b455d7d	4
20	ae346165-4704-474c-a74f-3a017704d5e1	4
21	25b0855d-c3db-4aab-ac8c-3668fc21cc59	4
22	86f3c1d8-362d-4a78-b904-3d8175642d0e	4
23	68a14c56-9902-4740-be6d-147f6e90cb1a	5
24	4f9faa74-3cd4-4e6a-a727-6fae0030cc83	6
25	2a00184e-2a06-4e3b-b2c7-a8d389511d94	6
26	7d1a7ad2-c7ea-4050-8d97-9257e9d96b13	6
27	af793107-1d27-406d-b887-a6d5ccf42ecb	6
28	d1d6d910-5544-43e3-86ff-09e1c6b390cf	6
29	6bf05fc1-8e11-44e0-bbb9-91efe06decf7	6
30	f02b63c4-d5b5-42de-a8b1-2ce86e3d754a	6
31	9a38d9e9-aa16-4865-bac8-68854f978513	6
32	bb39815c-2223-4a0a-b278-9cb7bb91e3c4	6
33	97fffa25-3c4f-45f4-9918-4710fc45b9c9	6
34	0f221e25-97c3-485b-8566-dc29de153a71	6
35	081ce725-8b29-434f-a328-eff8f1831584	7
36	de0470aa-f3fa-47d6-a4d2-62f738527d87	8
37	4b7a2283-42e4-4ea5-8eb8-58e69b3d8fa0	9
38	edf56db0-6070-419c-9658-e2447a31e634	10
39	f6a58cd9-a044-4575-b976-6a2e64e153b0	10
40	f6dc5787-8148-41b7-a457-783ded83b4be	10
41	8cd22449-12c5-4b39-a417-c94457b8c031	10
42	a0e65956-1116-4928-a8a6-a1f1b9cd049b	10
43	71621efb-9ee5-4ade-8c8b-16f2a70d8868	10
44	66d3a390-c140-4b30-9ec9-ab2bce20c811	10
45	8e488985-b4b1-49eb-9a63-8336de33cac6	10
46	a17f7a8f-9a01-421a-aa73-fdd8eeb19a95	10
47	ea8cc558-82c5-4a72-ae79-b0029751aab8	10
48	53dcb17e-7a6e-4447-80ac-a3705c4e1cce	10
49	55fd913d-6c41-4aa3-a93f-436121a2fd50	10
50	c0c56eeb-4b96-497e-9e93-68e3f4c94dac	10
51	e5f9ae78-c14c-4752-b08f-c2fc9f1f099c	11
52	04d51f99-798a-469f-bac9-2614ad62b3f5	12
53	bdb882b0-c95a-4e46-9854-39141b3feaf7	12
54	002fb9d6-a944-48ce-af64-7785e830e5bd	12
55	d3735dd5-91e7-40c8-896b-0d13da37f3cb	12
56	17322ee3-7486-463d-b085-312dfd6a3097	12
57	9d7d7b69-12a7-4fd8-a819-ceb6d4adc075	12
58	5cfeacf7-c8b7-420e-bbb8-d911318e97f8	12
59	e8efe3fb-f53a-4d10-90cb-dd1abd76c821	12
60	88d2c482-cdcb-413c-a753-d6e004cca8d0	12
61	ffad2389-e576-4cbe-931f-fab6c11e7103	12
62	c0da0c8c-0273-4791-bde0-412a3666f302	12
63	4cb918e1-2db1-4c0d-bdff-dfd59b68995a	12
64	8e72d0de-954a-423e-a17e-be35d6d147cf	13
65	82748625-c24e-437a-b991-cab7f766c249	14
66	a64d599e-ca12-44a8-84cb-4d6dda4c27ed	15
67	d4de7da3-4b7d-4876-b3eb-366108087ae6	15
68	a4783c19-523d-42d5-874b-51b348116b34	16
69	7d6b7fc9-2472-4232-a0d9-db4265e8ed41	16
70	c87dd434-3827-4795-9e5c-738fa16d6b5e	17
71	48160ea1-18b1-4c0a-8330-2e055572807d	18
72	5736ec21-f0b7-4e7b-a809-ec1a8123fd4f	18
73	3be3d922-0f1a-4f86-abc6-231218833764	18
74	b7ed6f52-f4d5-4487-952c-84e582e18bb6	18
75	ce2c97f4-6d01-4f2e-ba8b-1df529a238bd	18
76	ed4ff082-457a-4cb2-8cb6-054943310885	18
77	f14841c7-f684-4e1d-a434-63660db1d656	18
78	731b96bf-7580-4cc2-82bc-8fa61bafa549	18
79	d922e55b-c7d9-4221-ba44-07e0e13aa354	18
80	43418344-87e8-4e42-b870-988341541ffd	18
81	87fe3139-4378-484e-a6d8-c28f94f346f7	18
82	413e0815-d6fa-4c87-9cd1-0e95fe0f04d9	18
83	aa3082c8-4e92-45a8-8d0d-d7e4c47d644f	19
84	b90e3cc5-56d9-4796-94b7-a55d47395878	19
85	202c04b4-2d2d-4cba-a8ae-87a4523a806c	19
86	20c0fbf5-65ce-4aad-92ba-9c7a9f2cb11a	19
87	9231e06a-5d43-4a0d-9dbb-3757864384a1	19
88	41543c2c-7099-4d11-af7b-f5fe1a90e7c8	19
89	f9e7d2ca-0292-4de3-824a-5e8539dc2486	19
90	944fe36f-4bac-452e-a0ba-206463838d2f	19
91	70bf1444-43bb-4593-a250-e39f7f319652	19
92	8de8f1a8-4832-4bac-99cf-ef355156ce1a	19
93	c469f647-53ac-48ef-91e0-d297de795b9c	19
94	a46c5f0d-9d2b-4407-bc9b-d8e7a3640ca4	19
95	4c95b787-b88e-4276-b195-a79f23120599	19
96	58043c3d-2b89-40b4-99c6-1622e2ea926d	19
97	98fa3efa-7ca7-438e-b250-cf4a31c67d89	19
98	1e65ee9d-bc47-4488-b810-2814d7844ab7	20
99	a24be3cb-3993-46b0-98a5-dedf278ba7f7	21
100	fadd283f-66b2-4cfe-89d9-ad1036d864f8	21
101	0b9136b6-346f-48cb-aa65-1b217340c789	22
102	6f19c3f0-2ae8-46d6-a06e-a2daffd4c7b9	23
104	24cda793-fb5a-481c-84f4-6ebeb463815d	24
105	105113aa-9639-4c35-8072-6019a6b3ccdf	24
106	9a44993b-24a1-47f6-bf5b-dd51f19c7349	24
107	49a56fa8-60d9-4568-8d90-0a8d0c48dce8	24
120	76c38c3a-121d-46ba-9ab9-c926133187e1	26
121	97b78c85-0782-4f1b-8665-05879859df21	26
122	705b8290-bb28-4d9c-8d6f-4949b5f11a13	26
123	b1d95871-c502-460c-8e5a-d7265ebfed45	26
124	9d287068-1bdf-441a-b16d-37436ce68b65	26
125	e2f7e169-ce18-40ce-a7fc-938a7e03e221	26
126	cfcaece1-32d7-475c-84e6-1ee5920dbfee	26
127	a078fd59-409c-4403-9bf6-887fc3b4cd4a	26
128	8d7975bd-7e20-4951-861d-f8f22f75d306	26
129	cb1dc503-de5d-479e-8538-4d5b845e2a9e	26
130	5c1c76ce-a612-4244-87e7-91af73f9b0d9	26
131	b0aefc0c-dd2c-43ed-9df3-b433420a217f	26
132	bfbe0676-cdde-48bf-9c68-51df8e467789	27
134	3e08aa64-ff08-4220-bed3-11b201bdce32	29
135	a2e1d22b-af19-4b01-9603-a0619945d86e	30
136	b3d40adc-aaa8-4786-9e81-c886db35576a	31
137	29ec4d43-1560-4815-9eb8-c94375f59432	32
138	5df0e3a6-a162-4f6d-8e8e-50088f17e57e	32
139	40de8012-491c-4910-a726-6af0546ab71a	32
140	e35d0602-e54e-49f1-af7c-bf17b6dcc88a	32
141	9184c32d-cb22-4b3b-86fd-1057b51ff5f5	32
142	76023528-c252-488f-9bfb-c8e6173c4aa3	32
143	51c5d478-78cb-4ec3-b7d8-f54a980cbe38	32
144	10114609-8647-465c-8cd6-568bf34e5cfb	32
145	2fedd747-35a4-4363-a82c-765966d60f74	32
146	dad76dd4-f0c7-491a-8083-e921784313e6	32
147	8814e472-c782-4db9-bec9-cfc881a69e7c	32
148	0bd2b7f7-4740-47bc-ab72-0897582bc6b2	32
149	89eba5c6-0f15-4ee1-a59c-c02a179e7d11	32
150	624f53e3-c31c-4439-ad2b-6269907c49bd	33
151	5a4a870e-2158-477e-8aa4-821c7a2a2839	34
152	868e2fdc-a515-4ed9-8e66-d25170f8a3e3	35
153	d62c5441-c0d3-46f4-9593-2431fd009964	36
154	6cdb66c4-507e-43f3-b448-40bfd82465ea	36
155	99977009-a44a-43dd-b7df-228c5d6a73ee	36
156	b88f865f-a481-4172-a8a1-b5fe2b1ee1fa	36
157	cdfe8a41-a53f-4167-96f3-2d14d2b72f01	36
158	f19af262-9406-4356-aef6-682982d5dfd9	36
159	7d3eef90-f40f-44f1-91f3-d4bc0b77e32d	37
160	4665b393-f6d7-45be-bad5-1ac29d6de44f	37
161	4dea8474-b52f-4f39-9a51-3e4078c95771	37
162	8b021915-33b7-4d74-9d08-a35484371aeb	37
163	79235c95-5451-46ad-bf37-17a0136182b9	37
164	476019b6-4227-40a5-a6ee-1e2add4aadb2	37
165	cd72fefe-4c33-42ca-9dc3-e44e56bc5a2c	37
166	6641c92e-0b1c-4b7c-87ff-f4c7127fddbe	37
167	9b812e6c-4a2f-4b44-a9ae-ad2e99229913	37
168	6f3162e8-f3ce-4670-8895-3c4552e4fb93	37
169	6f15d24f-4135-4e62-814e-0d13269dab08	37
170	bc40b1b8-1504-48a6-a6b5-08d5d60a383c	37
171	f9cf9e59-51d7-4e01-977c-82081c976703	38
172	53f222a2-0d2d-47c8-9250-525352dc071c	39
173	a13c98ad-c050-4108-8fcc-473d44676b76	39
174	22a5799f-6931-4134-9b68-e98f37ce33ac	39
175	cd0d9050-31d7-4c9b-9c9a-a64d2e855004	39
176	8abb4c7e-4ea1-4f34-8c88-93f8d8ce0e4c	39
177	45cb850d-0145-436e-a87a-74e2479f3fb4	40
178	8bf4397b-35be-4092-ae9e-fe53685b9822	40
179	f31d9091-f4f3-44bd-a55a-436cd1919c95	40
180	d6bb6e75-0041-4fed-ac20-8ee8c80a4000	41
181	54798965-47da-4351-9d45-a3e77a74b0c1	42
182	0c77c9e6-526e-42c6-be52-e484371eff78	42
183	433d3222-e82d-4f14-97e2-4115579473f6	43
184	b63e01f9-600d-42ee-b1f0-b020846b246b	43
185	e25de70d-9bff-4490-9695-fd66cf45aa6d	43
186	c69d0297-6db2-4599-9ecb-2e9d70e6feb1	43
187	088077a2-e49e-4ec6-b7b8-7318752adf6a	43
188	12a31b8b-119e-4ea2-9627-5ae7a0829b47	43
189	cf2a0638-ee67-4ca5-9666-fc37b37b1145	44
190	9f3127d9-3f67-4972-b2d9-96bee12e523c	44
191	4b60bf06-aa62-4ad0-ba70-978998ac96ae	45
192	f8c07dbb-89b6-49ea-a3bd-c447e93487a5	46
193	d028364e-76db-4df0-956b-dc85b1ed8acd	46
194	88ce4fe4-f7b1-4ca7-af93-0cfe74cf5355	46
195	0651e14f-55b0-403f-9ff0-d0f11261490d	47
196	bf9a4d33-9ec9-4349-9f8e-95f1d9c4ab19	47
197	61064b59-e31b-40c8-a1e9-f06dbe510636	47
198	d5c8a042-7689-4526-bc6f-d902bb283e8d	47
199	a980f016-419a-40ef-ad48-957a12481e06	47
200	437c79b9-ff27-4fed-9899-07ef79e789da	47
201	6ea85017-196f-410d-92db-66799b110c7a	47
202	ac73c14d-a974-4721-933e-d90d437b12fd	47
203	548315c0-cd08-4715-b6a2-cb093b6da797	47
204	a9d5654c-7ec2-4865-ad4a-01d16186dfe0	47
205	1c5b1b11-4f35-4c35-9952-f7ba1267dd23	47
206	9baf8d67-424b-46dd-b47e-d1f975f6d80d	47
207	2b736f4f-6608-41ed-80e9-a7eabd5b5b9c	47
208	4ec7505c-cc8e-4729-8ff2-a410d7e0195c	48
209	8c0bce5a-7ca2-41e5-9838-d1b8c356ddc3	49
210	8640c455-0289-416e-8c77-a0bd9a619433	50
211	c40dcdf2-0abe-4e83-9eb4-f10b443e9987	51
212	b9fe77e6-2890-4ffc-8af1-12a8e22500e8	52
213	359d506a-a5f5-48a1-b57d-53d0ccbb5cf8	53
214	2a6243f8-96d6-480d-8fee-cb5e0674bb6c	53
108	dcfb0c36-f456-48a7-9aa9-4fd0e08441dd	24
109	188dd35e-20a9-4624-a481-3150618c42d0	24
110	22209519-f6e1-4dad-958d-27c835301514	24
111	ca51fd90-a36f-4949-bf4c-67ae742c9c44	24
112	0fac861c-8913-4449-a1bc-9f62fa10c230	24
113	cfd6200d-594b-4506-92ce-a6d57337cf66	24
114	265cc0df-20d9-4aaa-9e48-ece01e4990cb	24
115	adbd3f90-72dc-4266-82fb-4a69323ede89	24
116	5c1a5ea1-76d7-4917-b949-f59ec4a1487f	24
118	aa45faa8-738c-4948-9213-6ab70aa1e91e	24
133	14ff1d51-9784-4677-850b-36c8c19f7884	28
215	328c3224-f478-4e2a-a880-320da00e93a1	54
216	bb1ce977-6fa3-47b9-a68c-9a4b7eb6c972	54
217	0b9f5671-9303-4b4f-af1f-0f01a4979ab5	54
218	4d89b3cb-414b-4580-aa88-3049488fa40e	54
219	0a58319d-ba1e-4b20-8c5b-9504d62c0240	54
220	7774d41c-4e57-449d-8808-a9d9017e3c4e	54
221	337608ae-eea7-47af-84ce-1d240768d2a5	55
222	f8360816-6842-45b6-865e-8181fc4c1dea	55
223	05ba0eb5-cc0c-4999-aee8-1ddd197a66a1	56
224	b098946b-24cd-4756-b15e-f150709b4a87	56
225	a18a77d3-651a-45ec-9c29-2c6f70454ad4	56
226	004d3292-821f-4093-a1ef-4a10927eaec7	56
227	2061b908-2cef-4392-98e7-28be8e581c24	56
228	37796d82-3be5-4084-83c6-4cf4b2361191	56
229	eac82e72-f11d-4e2c-97c7-5c243da77687	56
230	925d1052-00d5-4799-bfee-970c3c5f6ea6	56
231	c8ed1cc0-e8cd-452d-9921-bde312ec2248	56
232	d35e05ff-b548-4544-8e1a-be2dbc0015fc	56
233	f17a6bd7-35d0-4f21-aca9-bf59261ed818	56
234	b39f914b-cdbc-44f8-bdf2-725dc5122c55	56
235	3cfb5ab2-c319-49f5-8ce5-8b4da14144f6	56
236	69202002-f224-4c87-a499-ada8775aa19e	56
237	61f1f5bd-8034-4f18-b1ff-a67baadbde43	57
238	6185b90a-a2d7-42d5-bd21-c1f5700a88f7	58
239	3ec50774-1757-42c7-b579-836e7cae0f5e	59
240	631868a2-53fa-4ec7-afa7-1f516affcded	59
241	745e6643-5191-4244-acef-1f8f968579ca	59
242	8d625a89-7cc9-45cd-b1d5-ec725ae19f39	59
243	a94d5be7-b5b5-471f-ad47-fa9c53976fec	59
244	e39a59f4-e605-4670-9c81-29c65876e737	59
245	ada0f50f-6256-456d-aaec-408c12a99a02	59
246	603ec3c7-5298-4e58-82ee-b7091a1a3db3	59
247	edded3ae-8ed6-417b-8b46-4862e903255d	59
248	52918071-f70a-43f5-ba6e-b3c88d62db94	59
249	0a01969c-8b35-4a8d-b410-fc557fcfaeb6	59
250	5f86eee3-293e-484a-9da6-d4bcbcecfe73	59
251	dd451e81-a4bb-46bb-aea2-d4883e684a52	60
252	be31f41a-69e1-4cf9-9278-a14716825ff6	61
253	7f8d78e0-0d6f-4a6f-917f-6983e1fd8d5e	61
254	5a1dea8c-a3d7-4b80-a348-84728332f6f6	61
255	c035cfde-f3b8-4038-8810-32624cf5f445	62
256	ee1f9484-eaf0-429f-a57c-a7c085c2ec1a	62
257	17243217-181d-47c7-8104-4f2c9e4f56b7	62
258	cbbd12e0-801c-4786-9706-e8f9d3055298	62
259	760c7e7e-d20c-4dd1-a416-4ddd49cb5119	62
260	1fb5ee2f-e462-426e-871f-1c1cd66b6d26	62
261	8955d925-41a1-43c3-b642-39a3ba1e3000	62
262	56bb0617-5acf-4f91-a42d-2d9d45434426	62
263	c49c7899-420b-4625-a0fc-61a1049d5922	62
264	a57d29bd-8f26-47c7-b24d-5b5ceba1a853	62
265	9ff6957e-cd97-4e03-a5d0-794dca1543b2	62
266	db3d08dc-c2e9-4e83-bfef-1a442b36a889	62
267	3c41f6d2-f4ed-4cd0-9902-cefae66a7f38	63
268	de119a69-a16e-47d8-9a64-f769a09564e1	63
269	72e6a09f-708d-463e-9d8f-c3fca1bed7b2	63
270	947c3359-fb46-4c50-8207-33a43a35c155	63
271	5178e12e-5597-449d-9b39-126a7c8fed33	63
272	4c2f059d-3c1f-4420-8a0f-a3917431ab67	63
273	303a0070-3bf7-495a-89a5-314fd63f1e09	63
274	5aa70166-f140-4669-9345-fa429d2e9ea4	63
275	4c5f684d-113e-451c-9284-f1b22727d740	63
276	5bd42766-5b91-4763-a8fe-0df3b25e016f	63
277	3519d8b2-c742-4f89-9437-6a8f1917c925	63
278	4c56a20f-46d6-47af-a86e-daefb14fbe8a	63
279	47d76252-33bb-45aa-b0ef-724a702d2d28	63
280	a713208c-0330-401e-8a8d-b40417e33bf9	63
281	afdc4098-450e-4f77-9cea-845e04fd0f07	64
282	b3c72176-2b61-4ac8-b06e-c2f04948f6c1	65
283	8739f187-98cf-483a-89b0-c1058ef9ab31	65
284	59ab4796-ce25-43b4-8a88-1042acab089c	66
285	f4c9021f-9ed9-4c96-accf-b963eceb0631	66
286	a698e65e-acd5-4e6d-ab5c-0dbd46e5e200	66
287	84553432-a933-4334-ab3d-d6829dcadb79	66
288	4e2164af-a659-4771-b9a9-28149926f3ab	66
289	d2dafc3d-9f5c-402c-a79a-75f5d6f61c32	66
290	d26633b8-d3ec-49ab-a8a5-f4bb59a67fcf	67
291	55d0b262-98ff-49fa-95c8-5ab8ec8cbd34	67
292	bbd8d64c-eaee-46ee-959c-af327fe9413f	67
293	61fc12f3-c65d-4c43-8276-a8cfd1507ce5	67
294	1270df07-34fb-4c42-adcf-4bc23d464eaf	67
295	14dbd4e6-ff0d-4e52-ba53-f8bb5e1246e7	67
296	3ff1c6c6-aee8-4aa7-a5b7-ae1a883eeb93	67
297	5ac4bca6-1c9f-4240-a3b7-f1b05e324731	67
298	7795416d-8aee-48ab-ba48-6bab493c38ea	67
299	b59666fa-cce9-4118-978e-c6ce3aae8295	67
300	e3144922-b6c6-4587-8879-acbd9a04fab5	67
301	5fd8e2c9-bf0a-4d34-ad7b-1301ddc2acbd	67
302	6a7e4ea1-886b-4b7f-93b4-13f4be468a5b	68
303	bf3d482a-b379-47e0-98f8-8cc454c79d2f	68
304	7c61d74e-0e99-4224-a004-4eeecceb81b3	68
305	c292a1f8-b13f-4b3b-868c-f44b4227aba0	68
306	183cef2e-5871-4052-811f-abdf0a182a2a	68
307	438931f2-bcde-476b-b00a-8d9e4474c8b1	68
308	c1759708-0f16-4c7c-bff8-a700bbff9237	68
309	4e264c9a-353e-42cb-ac09-6186f74cbe2e	68
310	2cd35039-ba77-47e5-b957-9edef9fcf5a5	68
311	c292b014-4449-4038-97a5-054a5a3414f9	68
312	85c8a7ab-dd06-4d0e-af57-1bab3052b90f	68
313	afb21bff-f0a7-42e9-ba83-628d9b7b58f1	68
314	7e04e3d6-2185-47da-890e-9f6dbddc50c5	68
315	f90789da-db58-42c9-b678-b8c9880226f6	68
316	6d3e96ef-95f8-43ab-a75c-86f034ce9d1a	69
317	80a84713-7b41-4958-a562-55810e2859df	69
318	e41e41f0-e80d-42af-898e-d13919de97dd	69
319	19314aea-7cd2-444a-b3ab-a7c784e28542	69
320	016b3fd8-f683-42f5-a06f-0dee018bd327	69
321	a2647c98-2967-496c-9bd4-82850a11c877	69
322	1e92fc1e-917f-44ec-807c-fc04a679210e	69
323	3bc1dcd6-db3f-4ec3-ad0c-3ba599adddcb	69
324	70ee2f0e-d3fb-4af6-905e-15998cefba32	69
325	7d65d1c1-1886-4f5b-a5e5-e84ec1a1ce90	69
326	68a9b9ef-0848-4f6e-8581-340f8f20220f	69
327	77fdba01-9715-4450-a791-8a9986be4095	69
328	0e2e8472-598e-458f-8f95-82aa81783ddf	69
329	3e8ddf7f-ff00-4f67-b6da-45b1635cf44b	69
330	3176de98-615e-4d49-952f-654eb2ed26c3	70
333	433d3222-e82d-4f14-97e2-4115579473f6	72
334	b63e01f9-600d-42ee-b1f0-b020846b246b	72
335	e25de70d-9bff-4490-9695-fd66cf45aa6d	72
336	c69d0297-6db2-4599-9ecb-2e9d70e6feb1	72
337	088077a2-e49e-4ec6-b7b8-7318752adf6a	72
338	12a31b8b-119e-4ea2-9627-5ae7a0829b47	72
339	9279dd5b-5429-4680-bee4-26cfaaf51b21	72
340	e93f780c-dc00-4456-835b-0abc6a64e58d	72
341	b307bf92-9c69-4443-bc18-cee45fb63fcb	72
342	1a984c80-f0fa-48c8-a88d-a67a82344753	72
343	3af20dde-aa41-46f2-a7e2-929ce5b4a2e6	72
344	92613948-82c8-46c1-b943-1c43c10914fb	72
345	cf2a0638-ee67-4ca5-9666-fc37b37b1145	72
346	9f3127d9-3f67-4972-b2d9-96bee12e523c	72
347	4b60bf06-aa62-4ad0-ba70-978998ac96ae	72
348	1e65ee9d-bc47-4488-b810-2814d7844ab7	72
349	45cb850d-0145-436e-a87a-74e2479f3fb4	73
350	8bf4397b-35be-4092-ae9e-fe53685b9822	73
351	f31d9091-f4f3-44bd-a55a-436cd1919c95	73
352	d62c5441-c0d3-46f4-9593-2431fd009964	73
353	6cdb66c4-507e-43f3-b448-40bfd82465ea	73
354	99977009-a44a-43dd-b7df-228c5d6a73ee	73
355	f19af262-9406-4356-aef6-682982d5dfd9	73
356	b88f865f-a481-4172-a8a1-b5fe2b1ee1fa	73
357	cdfe8a41-a53f-4167-96f3-2d14d2b72f01	73
358	53f222a2-0d2d-47c8-9250-525352dc071c	73
359	a13c98ad-c050-4108-8fcc-473d44676b76	73
360	22a5799f-6931-4134-9b68-e98f37ce33ac	73
361	cd0d9050-31d7-4c9b-9c9a-a64d2e855004	73
362	8abb4c7e-4ea1-4f34-8c88-93f8d8ce0e4c	73
363	337608ae-eea7-47af-84ce-1d240768d2a5	73
364	f8360816-6842-45b6-865e-8181fc4c1dea	73
365	624f53e3-c31c-4439-ad2b-6269907c49bd	74
366	05ba0eb5-cc0c-4999-aee8-1ddd197a66a1	74
367	b098946b-24cd-4756-b15e-f150709b4a87	74
368	a18a77d3-651a-45ec-9c29-2c6f70454ad4	74
369	004d3292-821f-4093-a1ef-4a10927eaec7	74
370	2061b908-2cef-4392-98e7-28be8e581c24	74
371	37796d82-3be5-4084-83c6-4cf4b2361191	74
372	eac82e72-f11d-4e2c-97c7-5c243da77687	74
373	c8ed1cc0-e8cd-452d-9921-bde312ec2248	74
374	925d1052-00d5-4799-bfee-970c3c5f6ea6	74
375	d35e05ff-b548-4544-8e1a-be2dbc0015fc	74
376	f17a6bd7-35d0-4f21-aca9-bf59261ed818	74
377	b39f914b-cdbc-44f8-bdf2-725dc5122c55	74
378	3cfb5ab2-c319-49f5-8ce5-8b4da14144f6	74
379	69202002-f224-4c87-a499-ada8775aa19e	74
380	8e72d0de-954a-423e-a17e-be35d6d147cf	74
381	de0470aa-f3fa-47d6-a4d2-62f738527d87	75
382	34a343ce-97e9-4c65-9560-87681886ec1b	75
383	c85fe28f-fe13-4f0e-8458-ff780e8b2489	75
384	842c8697-299c-46f0-b60f-2a0c81f65fbf	75
385	0710508f-241b-4eb1-a39e-91a7dd97e2f6	75
386	dc04122b-0031-464b-b396-f91c8b38cffe	75
387	1a33d801-3ed7-4dfe-9627-b79655818716	75
388	9a97b81e-7748-48f1-aa90-a311b34ee44b	75
389	9e39ac0c-a4b6-4b7c-92eb-6c502842c49d	75
390	b6dd5fc1-4d02-4b2a-8a8f-d7ae60c34113	75
391	f242f82a-0cc0-47e6-915f-fb2857072cea	75
392	55240ff2-7bc0-4a12-a11f-b98f7b455d7d	75
393	ae346165-4704-474c-a74f-3a017704d5e1	75
394	25b0855d-c3db-4aab-ac8c-3668fc21cc59	75
395	86f3c1d8-362d-4a78-b904-3d8175642d0e	75
396	4b7a2283-42e4-4ea5-8eb8-58e69b3d8fa0	75
397	d6bb6e75-0041-4fed-ac20-8ee8c80a4000	76
398	7d3eef90-f40f-44f1-91f3-d4bc0b77e32d	76
399	4665b393-f6d7-45be-bad5-1ac29d6de44f	76
400	4dea8474-b52f-4f39-9a51-3e4078c95771	76
401	8b021915-33b7-4d74-9d08-a35484371aeb	76
402	79235c95-5451-46ad-bf37-17a0136182b9	76
403	476019b6-4227-40a5-a6ee-1e2add4aadb2	76
404	cd72fefe-4c33-42ca-9dc3-e44e56bc5a2c	76
405	6641c92e-0b1c-4b7c-87ff-f4c7127fddbe	76
406	9b812e6c-4a2f-4b44-a9ae-ad2e99229913	76
407	6f3162e8-f3ce-4670-8895-3c4552e4fb93	76
408	6f15d24f-4135-4e62-814e-0d13269dab08	76
409	bc40b1b8-1504-48a6-a6b5-08d5d60a383c	76
410	68a14c56-9902-4740-be6d-147f6e90cb1a	76
411	868e2fdc-a515-4ed9-8e66-d25170f8a3e3	77
412	48160ea1-18b1-4c0a-8330-2e055572807d	77
413	5736ec21-f0b7-4e7b-a809-ec1a8123fd4f	77
414	3be3d922-0f1a-4f86-abc6-231218833764	77
415	b7ed6f52-f4d5-4487-952c-84e582e18bb6	77
416	ce2c97f4-6d01-4f2e-ba8b-1df529a238bd	77
417	ed4ff082-457a-4cb2-8cb6-054943310885	77
418	731b96bf-7580-4cc2-82bc-8fa61bafa549	77
419	f14841c7-f684-4e1d-a434-63660db1d656	77
420	d922e55b-c7d9-4221-ba44-07e0e13aa354	77
421	43418344-87e8-4e42-b870-988341541ffd	77
422	87fe3139-4378-484e-a6d8-c28f94f346f7	77
423	413e0815-d6fa-4c87-9cd1-0e95fe0f04d9	77
424	0b9136b6-346f-48cb-aa65-1b217340c789	77
425	a64d599e-ca12-44a8-84cb-4d6dda4c27ed	78
426	d4de7da3-4b7d-4876-b3eb-366108087ae6	78
427	54798965-47da-4351-9d45-a3e77a74b0c1	78
428	0c77c9e6-526e-42c6-be52-e484371eff78	78
332	a13766b3-ee0b-4ba8-9b78-8787e7da6bc5	71
429	a4783c19-523d-42d5-874b-51b348116b34	79
430	7d6b7fc9-2472-4232-a0d9-db4265e8ed41	79
431	b3c72176-2b61-4ac8-b06e-c2f04948f6c1	79
432	8739f187-98cf-483a-89b0-c1058ef9ab31	79
119	c8598af4-2a8e-4196-b900-a1a21b1acb16	25
433	359d506a-a5f5-48a1-b57d-53d0ccbb5cf8	80
434	2a6243f8-96d6-480d-8fee-cb5e0674bb6c	80
435	59ab4796-ce25-43b4-8a88-1042acab089c	80
436	4e2164af-a659-4771-b9a9-28149926f3ab	80
437	a698e65e-acd5-4e6d-ab5c-0dbd46e5e200	80
438	f4c9021f-9ed9-4c96-accf-b963eceb0631	80
439	84553432-a933-4334-ab3d-d6829dcadb79	80
440	d2dafc3d-9f5c-402c-a79a-75f5d6f61c32	80
441	328c3224-f478-4e2a-a880-320da00e93a1	80
442	bb1ce977-6fa3-47b9-a68c-9a4b7eb6c972	80
443	0b9f5671-9303-4b4f-af1f-0f01a4979ab5	80
444	4d89b3cb-414b-4580-aa88-3049488fa40e	80
445	0a58319d-ba1e-4b20-8c5b-9504d62c0240	80
446	7774d41c-4e57-449d-8808-a9d9017e3c4e	80
447	5c04ec0a-eea2-4c42-a828-3b5c850e1cee	80
448	3e08aa64-ff08-4220-bed3-11b201bdce32	80
449	f8c07dbb-89b6-49ea-a3bd-c447e93487a5	81
450	d028364e-76db-4df0-956b-dc85b1ed8acd	81
451	88ce4fe4-f7b1-4ca7-af93-0cfe74cf5355	81
452	29ec4d43-1560-4815-9eb8-c94375f59432	81
453	5df0e3a6-a162-4f6d-8e8e-50088f17e57e	81
454	76023528-c252-488f-9bfb-c8e6173c4aa3	81
455	51c5d478-78cb-4ec3-b7d8-f54a980cbe38	81
456	9184c32d-cb22-4b3b-86fd-1057b51ff5f5	81
457	2fedd747-35a4-4363-a82c-765966d60f74	81
458	40de8012-491c-4910-a726-6af0546ab71a	81
459	e35d0602-e54e-49f1-af7c-bf17b6dcc88a	81
460	10114609-8647-465c-8cd6-568bf34e5cfb	81
461	dad76dd4-f0c7-491a-8083-e921784313e6	81
462	8814e472-c782-4db9-bec9-cfc881a69e7c	81
463	0bd2b7f7-4740-47bc-ab72-0897582bc6b2	81
464	89eba5c6-0f15-4ee1-a59c-c02a179e7d11	81
465	4ec7505c-cc8e-4729-8ff2-a410d7e0195c	82
466	4f9faa74-3cd4-4e6a-a727-6fae0030cc83	82
467	2a00184e-2a06-4e3b-b2c7-a8d389511d94	82
468	7d1a7ad2-c7ea-4050-8d97-9257e9d96b13	82
469	af793107-1d27-406d-b887-a6d5ccf42ecb	82
470	d1d6d910-5544-43e3-86ff-09e1c6b390cf	82
471	f02b63c4-d5b5-42de-a8b1-2ce86e3d754a	82
472	9a38d9e9-aa16-4865-bac8-68854f978513	82
473	6bf05fc1-8e11-44e0-bbb9-91efe06decf7	82
474	bb39815c-2223-4a0a-b278-9cb7bb91e3c4	82
475	97fffa25-3c4f-45f4-9918-4710fc45b9c9	82
476	0f221e25-97c3-485b-8566-dc29de153a71	82
477	5a4a870e-2158-477e-8aa4-821c7a2a2839	82
478	a2e1d22b-af19-4b01-9603-a0619945d86e	83
479	6a7e4ea1-886b-4b7f-93b4-13f4be468a5b	83
480	bf3d482a-b379-47e0-98f8-8cc454c79d2f	83
481	7c61d74e-0e99-4224-a004-4eeecceb81b3	83
482	c292a1f8-b13f-4b3b-868c-f44b4227aba0	83
483	183cef2e-5871-4052-811f-abdf0a182a2a	83
484	438931f2-bcde-476b-b00a-8d9e4474c8b1	83
485	c1759708-0f16-4c7c-bff8-a700bbff9237	83
486	2cd35039-ba77-47e5-b957-9edef9fcf5a5	83
487	4e264c9a-353e-42cb-ac09-6186f74cbe2e	83
488	c292b014-4449-4038-97a5-054a5a3414f9	83
489	85c8a7ab-dd06-4d0e-af57-1bab3052b90f	83
490	afb21bff-f0a7-42e9-ba83-628d9b7b58f1	83
491	7e04e3d6-2185-47da-890e-9f6dbddc50c5	83
492	f90789da-db58-42c9-b678-b8c9880226f6	83
493	081ce725-8b29-434f-a328-eff8f1831584	83
494	afdc4098-450e-4f77-9cea-845e04fd0f07	84
495	6d3e96ef-95f8-43ab-a75c-86f034ce9d1a	84
496	80a84713-7b41-4958-a562-55810e2859df	84
497	e41e41f0-e80d-42af-898e-d13919de97dd	84
498	19314aea-7cd2-444a-b3ab-a7c784e28542	84
499	016b3fd8-f683-42f5-a06f-0dee018bd327	84
500	a2647c98-2967-496c-9bd4-82850a11c877	84
501	1e92fc1e-917f-44ec-807c-fc04a679210e	84
502	3bc1dcd6-db3f-4ec3-ad0c-3ba599adddcb	84
503	70ee2f0e-d3fb-4af6-905e-15998cefba32	84
504	7d65d1c1-1886-4f5b-a5e5-e84ec1a1ce90	84
505	68a9b9ef-0848-4f6e-8581-340f8f20220f	84
506	77fdba01-9715-4450-a791-8a9986be4095	84
507	0e2e8472-598e-458f-8f95-82aa81783ddf	84
508	3e8ddf7f-ff00-4f67-b6da-45b1635cf44b	84
509	3176de98-615e-4d49-952f-654eb2ed26c3	84
510	b3d40adc-aaa8-4786-9e81-c886db35576a	85
511	aa3082c8-4e92-45a8-8d0d-d7e4c47d644f	85
512	b90e3cc5-56d9-4796-94b7-a55d47395878	85
513	202c04b4-2d2d-4cba-a8ae-87a4523a806c	85
514	20c0fbf5-65ce-4aad-92ba-9c7a9f2cb11a	85
515	9231e06a-5d43-4a0d-9dbb-3757864384a1	85
516	41543c2c-7099-4d11-af7b-f5fe1a90e7c8	85
517	f9e7d2ca-0292-4de3-824a-5e8539dc2486	85
518	70bf1444-43bb-4593-a250-e39f7f319652	85
519	8de8f1a8-4832-4bac-99cf-ef355156ce1a	85
520	c469f647-53ac-48ef-91e0-d297de795b9c	85
521	944fe36f-4bac-452e-a0ba-206463838d2f	85
522	a46c5f0d-9d2b-4407-bc9b-d8e7a3640ca4	85
523	4c95b787-b88e-4276-b195-a79f23120599	85
524	58043c3d-2b89-40b4-99c6-1622e2ea926d	85
525	98fa3efa-7ca7-438e-b250-cf4a31c67d89	85
103	374ba2fb-9e27-47a4-a07f-d1bd93705431	24
117	9bed8e6c-05d2-43d8-a530-38803ea856cf	24
526	61f1f5bd-8034-4f18-b1ff-a67baadbde43	86
527	edf56db0-6070-419c-9658-e2447a31e634	86
528	f6a58cd9-a044-4575-b976-6a2e64e153b0	86
529	f6dc5787-8148-41b7-a457-783ded83b4be	86
530	8cd22449-12c5-4b39-a417-c94457b8c031	86
531	a0e65956-1116-4928-a8a6-a1f1b9cd049b	86
532	71621efb-9ee5-4ade-8c8b-16f2a70d8868	86
533	66d3a390-c140-4b30-9ec9-ab2bce20c811	86
534	8e488985-b4b1-49eb-9a63-8336de33cac6	86
535	a17f7a8f-9a01-421a-aa73-fdd8eeb19a95	86
536	ea8cc558-82c5-4a72-ae79-b0029751aab8	86
537	53dcb17e-7a6e-4447-80ac-a3705c4e1cce	86
538	55fd913d-6c41-4aa3-a93f-436121a2fd50	86
539	c0c56eeb-4b96-497e-9e93-68e3f4c94dac	86
540	6185b90a-a2d7-42d5-bd21-c1f5700a88f7	86
541	c40dcdf2-0abe-4e83-9eb4-f10b443e9987	87
542	76c38c3a-121d-46ba-9ab9-c926133187e1	87
543	97b78c85-0782-4f1b-8665-05879859df21	87
544	705b8290-bb28-4d9c-8d6f-4949b5f11a13	87
545	b1d95871-c502-460c-8e5a-d7265ebfed45	87
546	9d287068-1bdf-441a-b16d-37436ce68b65	87
547	e2f7e169-ce18-40ce-a7fc-938a7e03e221	87
548	a078fd59-409c-4403-9bf6-887fc3b4cd4a	87
549	cfcaece1-32d7-475c-84e6-1ee5920dbfee	87
550	8d7975bd-7e20-4951-861d-f8f22f75d306	87
551	cb1dc503-de5d-479e-8538-4d5b845e2a9e	87
552	5c1c76ce-a612-4244-87e7-91af73f9b0d9	87
553	b0aefc0c-dd2c-43ed-9df3-b433420a217f	87
554	f9cf9e59-51d7-4e01-977c-82081c976703	87
555	6f19c3f0-2ae8-46d6-a06e-a2daffd4c7b9	88
556	3c41f6d2-f4ed-4cd0-9902-cefae66a7f38	88
557	de119a69-a16e-47d8-9a64-f769a09564e1	88
558	72e6a09f-708d-463e-9d8f-c3fca1bed7b2	88
559	947c3359-fb46-4c50-8207-33a43a35c155	88
560	5178e12e-5597-449d-9b39-126a7c8fed33	88
561	4c2f059d-3c1f-4420-8a0f-a3917431ab67	88
562	303a0070-3bf7-495a-89a5-314fd63f1e09	88
563	4c5f684d-113e-451c-9284-f1b22727d740	88
564	5bd42766-5b91-4763-a8fe-0df3b25e016f	88
565	5aa70166-f140-4669-9345-fa429d2e9ea4	88
566	3519d8b2-c742-4f89-9437-6a8f1917c925	88
567	4c56a20f-46d6-47af-a86e-daefb14fbe8a	88
568	47d76252-33bb-45aa-b0ef-724a702d2d28	88
569	a713208c-0330-401e-8a8d-b40417e33bf9	88
570	bfbe0676-cdde-48bf-9c68-51df8e467789	88
331	6d7d8252-f0b3-42e3-ac51-fead5f18e49f	71
571	8c0bce5a-7ca2-41e5-9838-d1b8c356ddc3	89
572	0651e14f-55b0-403f-9ff0-d0f11261490d	89
573	bf9a4d33-9ec9-4349-9f8e-95f1d9c4ab19	89
574	61064b59-e31b-40c8-a1e9-f06dbe510636	89
575	d5c8a042-7689-4526-bc6f-d902bb283e8d	89
576	a980f016-419a-40ef-ad48-957a12481e06	89
577	437c79b9-ff27-4fed-9899-07ef79e789da	89
578	6ea85017-196f-410d-92db-66799b110c7a	89
579	548315c0-cd08-4715-b6a2-cb093b6da797	89
580	ac73c14d-a974-4721-933e-d90d437b12fd	89
581	a9d5654c-7ec2-4865-ad4a-01d16186dfe0	89
582	1c5b1b11-4f35-4c35-9952-f7ba1267dd23	89
583	9baf8d67-424b-46dd-b47e-d1f975f6d80d	89
584	2b736f4f-6608-41ed-80e9-a7eabd5b5b9c	89
585	a24be3cb-3993-46b0-98a5-dedf278ba7f7	89
586	fadd283f-66b2-4cfe-89d9-ad1036d864f8	89
587	0eab80ab-67d6-41a9-8cdb-7567fcd40e6e	90
588	3ec50774-1757-42c7-b579-836e7cae0f5e	90
589	631868a2-53fa-4ec7-afa7-1f516affcded	90
590	745e6643-5191-4244-acef-1f8f968579ca	90
591	8d625a89-7cc9-45cd-b1d5-ec725ae19f39	90
592	a94d5be7-b5b5-471f-ad47-fa9c53976fec	90
593	e39a59f4-e605-4670-9c81-29c65876e737	90
594	ada0f50f-6256-456d-aaec-408c12a99a02	90
595	603ec3c7-5298-4e58-82ee-b7091a1a3db3	90
596	edded3ae-8ed6-417b-8b46-4862e903255d	90
597	52918071-f70a-43f5-ba6e-b3c88d62db94	90
598	0a01969c-8b35-4a8d-b410-fc557fcfaeb6	90
599	5f86eee3-293e-484a-9da6-d4bcbcecfe73	90
600	e5f9ae78-c14c-4752-b08f-c2fc9f1f099c	90
601	8640c455-0289-416e-8c77-a0bd9a619433	91
602	04d51f99-798a-469f-bac9-2614ad62b3f5	91
603	bdb882b0-c95a-4e46-9854-39141b3feaf7	91
604	002fb9d6-a944-48ce-af64-7785e830e5bd	91
605	d3735dd5-91e7-40c8-896b-0d13da37f3cb	91
606	17322ee3-7486-463d-b085-312dfd6a3097	91
607	9d7d7b69-12a7-4fd8-a819-ceb6d4adc075	91
608	e8efe3fb-f53a-4d10-90cb-dd1abd76c821	91
609	88d2c482-cdcb-413c-a753-d6e004cca8d0	91
610	5cfeacf7-c8b7-420e-bbb8-d911318e97f8	91
611	ffad2389-e576-4cbe-931f-fab6c11e7103	91
612	c0da0c8c-0273-4791-bde0-412a3666f302	91
613	4cb918e1-2db1-4c0d-bdff-dfd59b68995a	91
614	c87dd434-3827-4795-9e5c-738fa16d6b5e	91
615	82748625-c24e-437a-b991-cab7f766c249	92
616	d26633b8-d3ec-49ab-a8a5-f4bb59a67fcf	92
617	55d0b262-98ff-49fa-95c8-5ab8ec8cbd34	92
618	bbd8d64c-eaee-46ee-959c-af327fe9413f	92
619	61fc12f3-c65d-4c43-8276-a8cfd1507ce5	92
620	1270df07-34fb-4c42-adcf-4bc23d464eaf	92
621	14dbd4e6-ff0d-4e52-ba53-f8bb5e1246e7	92
622	5ac4bca6-1c9f-4240-a3b7-f1b05e324731	92
623	3ff1c6c6-aee8-4aa7-a5b7-ae1a883eeb93	92
624	7795416d-8aee-48ab-ba48-6bab493c38ea	92
625	b59666fa-cce9-4118-978e-c6ce3aae8295	92
626	e3144922-b6c6-4587-8879-acbd9a04fab5	92
627	5fd8e2c9-bf0a-4d34-ad7b-1301ddc2acbd	92
628	dd451e81-a4bb-46bb-aea2-d4883e684a52	92
629	be31f41a-69e1-4cf9-9278-a14716825ff6	93
630	7f8d78e0-0d6f-4a6f-917f-6983e1fd8d5e	93
631	5a1dea8c-a3d7-4b80-a348-84728332f6f6	93
632	17243217-181d-47c7-8104-4f2c9e4f56b7	93
633	cbbd12e0-801c-4786-9706-e8f9d3055298	93
634	760c7e7e-d20c-4dd1-a416-4ddd49cb5119	93
635	8955d925-41a1-43c3-b642-39a3ba1e3000	93
636	56bb0617-5acf-4f91-a42d-2d9d45434426	93
637	1fb5ee2f-e462-426e-871f-1c1cd66b6d26	93
638	c035cfde-f3b8-4038-8810-32624cf5f445	93
639	ee1f9484-eaf0-429f-a57c-a7c085c2ec1a	93
640	c49c7899-420b-4625-a0fc-61a1049d5922	93
641	a57d29bd-8f26-47c7-b24d-5b5ceba1a853	93
642	9ff6957e-cd97-4e03-a5d0-794dca1543b2	93
643	db3d08dc-c2e9-4e83-bfef-1a442b36a889	93
644	b9fe77e6-2890-4ffc-8af1-12a8e22500e8	93
\.


--
-- Data for Name: invitations; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY invitations (id, email, inviter_id, private_contest_id, contest_type_id, code, redeemed, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: market_orders; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY market_orders (id, market_id, roster_id, action, player_id, price, rejected, rejected_reason, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: market_players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY market_players (id, market_id, player_id, shadow_bets, bets, locked_at, initial_shadow_bets, locked, score, player_stats_id) FROM stdin;
1	1	109	\N	0	\N	\N	f	0	\N
2	1	108	\N	0	\N	\N	f	0	\N
3	1	107	\N	0	\N	\N	f	0	\N
4	1	106	\N	0	\N	\N	f	0	\N
5	1	105	\N	0	\N	\N	f	0	\N
6	1	104	\N	0	\N	\N	f	0	\N
7	1	103	\N	0	\N	\N	f	0	\N
8	1	102	\N	0	\N	\N	f	0	\N
9	1	101	\N	0	\N	\N	f	0	\N
10	1	100	\N	0	\N	\N	f	0	\N
11	1	99	\N	0	\N	\N	f	0	\N
12	1	98	\N	0	\N	\N	f	0	\N
13	1	97	\N	0	\N	\N	f	0	\N
14	1	96	\N	0	\N	\N	f	0	\N
15	1	95	\N	0	\N	\N	f	0	\N
16	1	94	\N	0	\N	\N	f	0	\N
17	1	93	\N	0	\N	\N	f	0	\N
18	1	92	\N	0	\N	\N	f	0	\N
19	1	91	\N	0	\N	\N	f	0	\N
20	1	90	\N	0	\N	\N	f	0	\N
21	1	89	\N	0	\N	\N	f	0	\N
22	1	88	\N	0	\N	\N	f	0	\N
23	1	87	\N	0	\N	\N	f	0	\N
24	1	86	\N	0	\N	\N	f	0	\N
25	1	85	\N	0	\N	\N	f	0	\N
26	1	84	\N	0	\N	\N	f	0	\N
27	1	83	\N	0	\N	\N	f	0	\N
28	1	82	\N	0	\N	\N	f	0	\N
29	1	81	\N	0	\N	\N	f	0	\N
30	1	80	\N	0	\N	\N	f	0	\N
31	1	79	\N	0	\N	\N	f	0	\N
32	1	78	\N	0	\N	\N	f	0	\N
33	1	77	\N	0	\N	\N	f	0	\N
34	1	76	\N	0	\N	\N	f	0	\N
35	1	75	\N	0	\N	\N	f	0	\N
36	1	401	\N	0	\N	\N	f	0	\N
37	1	400	\N	0	\N	\N	f	0	\N
38	1	399	\N	0	\N	\N	f	0	\N
39	1	398	\N	0	\N	\N	f	0	\N
40	1	397	\N	0	\N	\N	f	0	\N
41	1	396	\N	0	\N	\N	f	0	\N
42	1	395	\N	0	\N	\N	f	0	\N
43	1	394	\N	0	\N	\N	f	0	\N
44	1	393	\N	0	\N	\N	f	0	\N
45	1	392	\N	0	\N	\N	f	0	\N
46	1	391	\N	0	\N	\N	f	0	\N
47	1	390	\N	0	\N	\N	f	0	\N
48	1	389	\N	0	\N	\N	f	0	\N
49	1	388	\N	0	\N	\N	f	0	\N
50	1	387	\N	0	\N	\N	f	0	\N
51	1	386	\N	0	\N	\N	f	0	\N
52	1	385	\N	0	\N	\N	f	0	\N
53	1	384	\N	0	\N	\N	f	0	\N
54	1	383	\N	0	\N	\N	f	0	\N
55	1	382	\N	0	\N	\N	f	0	\N
56	1	381	\N	0	\N	\N	f	0	\N
57	1	380	\N	0	\N	\N	f	0	\N
58	1	379	\N	0	\N	\N	f	0	\N
59	1	378	\N	0	\N	\N	f	0	\N
60	1	377	\N	0	\N	\N	f	0	\N
61	1	376	\N	0	\N	\N	f	0	\N
62	1	375	\N	0	\N	\N	f	0	\N
63	1	374	\N	0	\N	\N	f	0	\N
64	1	373	\N	0	\N	\N	f	0	\N
65	1	372	\N	0	\N	\N	f	0	\N
66	1	371	\N	0	\N	\N	f	0	\N
67	1	370	\N	0	\N	\N	f	0	\N
68	1	369	\N	0	\N	\N	f	0	\N
69	1	368	\N	0	\N	\N	f	0	\N
70	1	367	\N	0	\N	\N	f	0	\N
71	1	366	\N	0	\N	\N	f	0	\N
72	1	365	\N	0	\N	\N	f	0	\N
73	1	364	\N	0	\N	\N	f	0	\N
74	1	363	\N	0	\N	\N	f	0	\N
75	1	362	\N	0	\N	\N	f	0	\N
76	1	361	\N	0	\N	\N	f	0	\N
77	1	323	\N	0	\N	\N	f	0	\N
78	1	322	\N	0	\N	\N	f	0	\N
79	1	321	\N	0	\N	\N	f	0	\N
80	1	320	\N	0	\N	\N	f	0	\N
81	1	319	\N	0	\N	\N	f	0	\N
82	1	318	\N	0	\N	\N	f	0	\N
83	1	317	\N	0	\N	\N	f	0	\N
84	1	316	\N	0	\N	\N	f	0	\N
85	1	315	\N	0	\N	\N	f	0	\N
86	1	314	\N	0	\N	\N	f	0	\N
87	1	313	\N	0	\N	\N	f	0	\N
88	1	312	\N	0	\N	\N	f	0	\N
89	1	311	\N	0	\N	\N	f	0	\N
90	1	310	\N	0	\N	\N	f	0	\N
91	1	309	\N	0	\N	\N	f	0	\N
92	1	308	\N	0	\N	\N	f	0	\N
93	1	307	\N	0	\N	\N	f	0	\N
94	1	306	\N	0	\N	\N	f	0	\N
95	1	305	\N	0	\N	\N	f	0	\N
96	1	304	\N	0	\N	\N	f	0	\N
97	1	303	\N	0	\N	\N	f	0	\N
98	1	302	\N	0	\N	\N	f	0	\N
99	1	301	\N	0	\N	\N	f	0	\N
100	1	300	\N	0	\N	\N	f	0	\N
101	1	299	\N	0	\N	\N	f	0	\N
102	1	298	\N	0	\N	\N	f	0	\N
103	1	297	\N	0	\N	\N	f	0	\N
104	1	296	\N	0	\N	\N	f	0	\N
105	1	295	\N	0	\N	\N	f	0	\N
106	1	294	\N	0	\N	\N	f	0	\N
107	1	293	\N	0	\N	\N	f	0	\N
108	1	292	\N	0	\N	\N	f	0	\N
109	1	291	\N	0	\N	\N	f	0	\N
110	2	180	\N	0	\N	\N	f	0	\N
111	2	179	\N	0	\N	\N	f	0	\N
112	2	178	\N	0	\N	\N	f	0	\N
113	2	177	\N	0	\N	\N	f	0	\N
114	2	176	\N	0	\N	\N	f	0	\N
115	2	175	\N	0	\N	\N	f	0	\N
116	2	174	\N	0	\N	\N	f	0	\N
117	2	173	\N	0	\N	\N	f	0	\N
118	2	172	\N	0	\N	\N	f	0	\N
119	2	171	\N	0	\N	\N	f	0	\N
120	2	170	\N	0	\N	\N	f	0	\N
121	2	169	\N	0	\N	\N	f	0	\N
122	2	168	\N	0	\N	\N	f	0	\N
123	2	167	\N	0	\N	\N	f	0	\N
124	2	166	\N	0	\N	\N	f	0	\N
125	2	165	\N	0	\N	\N	f	0	\N
126	2	164	\N	0	\N	\N	f	0	\N
127	2	163	\N	0	\N	\N	f	0	\N
128	2	162	\N	0	\N	\N	f	0	\N
129	2	161	\N	0	\N	\N	f	0	\N
130	2	160	\N	0	\N	\N	f	0	\N
131	2	159	\N	0	\N	\N	f	0	\N
132	2	158	\N	0	\N	\N	f	0	\N
133	2	157	\N	0	\N	\N	f	0	\N
134	2	156	\N	0	\N	\N	f	0	\N
135	2	155	\N	0	\N	\N	f	0	\N
136	2	154	\N	0	\N	\N	f	0	\N
137	2	153	\N	0	\N	\N	f	0	\N
138	2	152	\N	0	\N	\N	f	0	\N
139	2	151	\N	0	\N	\N	f	0	\N
140	2	150	\N	0	\N	\N	f	0	\N
141	2	149	\N	0	\N	\N	f	0	\N
142	2	148	\N	0	\N	\N	f	0	\N
143	2	147	\N	0	\N	\N	f	0	\N
144	2	146	\N	0	\N	\N	f	0	\N
145	4	323	\N	0	\N	\N	f	0	\N
146	4	322	\N	0	\N	\N	f	0	\N
147	4	321	\N	0	\N	\N	f	0	\N
148	4	320	\N	0	\N	\N	f	0	\N
149	4	319	\N	0	\N	\N	f	0	\N
150	4	318	\N	0	\N	\N	f	0	\N
151	4	317	\N	0	\N	\N	f	0	\N
152	4	316	\N	0	\N	\N	f	0	\N
153	4	315	\N	0	\N	\N	f	0	\N
154	4	314	\N	0	\N	\N	f	0	\N
155	4	313	\N	0	\N	\N	f	0	\N
156	4	312	\N	0	\N	\N	f	0	\N
157	4	311	\N	0	\N	\N	f	0	\N
158	4	310	\N	0	\N	\N	f	0	\N
159	4	309	\N	0	\N	\N	f	0	\N
160	4	308	\N	0	\N	\N	f	0	\N
161	4	307	\N	0	\N	\N	f	0	\N
162	4	306	\N	0	\N	\N	f	0	\N
163	4	305	\N	0	\N	\N	f	0	\N
164	4	304	\N	0	\N	\N	f	0	\N
165	4	303	\N	0	\N	\N	f	0	\N
166	4	302	\N	0	\N	\N	f	0	\N
167	4	301	\N	0	\N	\N	f	0	\N
168	4	300	\N	0	\N	\N	f	0	\N
169	4	299	\N	0	\N	\N	f	0	\N
170	4	298	\N	0	\N	\N	f	0	\N
171	4	297	\N	0	\N	\N	f	0	\N
172	4	296	\N	0	\N	\N	f	0	\N
173	4	295	\N	0	\N	\N	f	0	\N
174	4	294	\N	0	\N	\N	f	0	\N
175	4	293	\N	0	\N	\N	f	0	\N
176	4	292	\N	0	\N	\N	f	0	\N
177	4	291	\N	0	\N	\N	f	0	\N
178	4	401	\N	0	\N	\N	f	0	\N
179	4	400	\N	0	\N	\N	f	0	\N
180	4	399	\N	0	\N	\N	f	0	\N
181	4	398	\N	0	\N	\N	f	0	\N
182	4	397	\N	0	\N	\N	f	0	\N
183	4	396	\N	0	\N	\N	f	0	\N
184	4	395	\N	0	\N	\N	f	0	\N
185	4	394	\N	0	\N	\N	f	0	\N
186	4	393	\N	0	\N	\N	f	0	\N
187	4	392	\N	0	\N	\N	f	0	\N
188	4	391	\N	0	\N	\N	f	0	\N
189	4	390	\N	0	\N	\N	f	0	\N
190	4	389	\N	0	\N	\N	f	0	\N
191	4	388	\N	0	\N	\N	f	0	\N
192	4	387	\N	0	\N	\N	f	0	\N
193	4	386	\N	0	\N	\N	f	0	\N
194	4	385	\N	0	\N	\N	f	0	\N
195	4	384	\N	0	\N	\N	f	0	\N
196	4	383	\N	0	\N	\N	f	0	\N
197	4	382	\N	0	\N	\N	f	0	\N
198	4	381	\N	0	\N	\N	f	0	\N
199	4	380	\N	0	\N	\N	f	0	\N
200	4	379	\N	0	\N	\N	f	0	\N
201	4	378	\N	0	\N	\N	f	0	\N
202	4	377	\N	0	\N	\N	f	0	\N
203	4	376	\N	0	\N	\N	f	0	\N
204	4	375	\N	0	\N	\N	f	0	\N
205	4	374	\N	0	\N	\N	f	0	\N
206	4	373	\N	0	\N	\N	f	0	\N
207	4	372	\N	0	\N	\N	f	0	\N
208	4	371	\N	0	\N	\N	f	0	\N
209	4	370	\N	0	\N	\N	f	0	\N
210	4	369	\N	0	\N	\N	f	0	\N
211	4	368	\N	0	\N	\N	f	0	\N
212	4	367	\N	0	\N	\N	f	0	\N
213	4	366	\N	0	\N	\N	f	0	\N
214	4	365	\N	0	\N	\N	f	0	\N
215	4	364	\N	0	\N	\N	f	0	\N
216	4	363	\N	0	\N	\N	f	0	\N
217	4	362	\N	0	\N	\N	f	0	\N
218	4	361	\N	0	\N	\N	f	0	\N
219	4	180	\N	0	\N	\N	f	0	\N
220	4	179	\N	0	\N	\N	f	0	\N
221	4	178	\N	0	\N	\N	f	0	\N
222	4	177	\N	0	\N	\N	f	0	\N
223	4	176	\N	0	\N	\N	f	0	\N
224	4	175	\N	0	\N	\N	f	0	\N
225	4	174	\N	0	\N	\N	f	0	\N
226	4	173	\N	0	\N	\N	f	0	\N
227	4	172	\N	0	\N	\N	f	0	\N
228	4	171	\N	0	\N	\N	f	0	\N
229	4	170	\N	0	\N	\N	f	0	\N
230	4	169	\N	0	\N	\N	f	0	\N
231	4	168	\N	0	\N	\N	f	0	\N
232	4	167	\N	0	\N	\N	f	0	\N
233	4	166	\N	0	\N	\N	f	0	\N
234	4	165	\N	0	\N	\N	f	0	\N
235	4	164	\N	0	\N	\N	f	0	\N
236	4	163	\N	0	\N	\N	f	0	\N
237	4	162	\N	0	\N	\N	f	0	\N
238	4	161	\N	0	\N	\N	f	0	\N
239	4	160	\N	0	\N	\N	f	0	\N
240	4	159	\N	0	\N	\N	f	0	\N
241	4	158	\N	0	\N	\N	f	0	\N
242	4	157	\N	0	\N	\N	f	0	\N
243	4	156	\N	0	\N	\N	f	0	\N
244	4	155	\N	0	\N	\N	f	0	\N
245	4	154	\N	0	\N	\N	f	0	\N
246	4	153	\N	0	\N	\N	f	0	\N
247	4	152	\N	0	\N	\N	f	0	\N
248	4	151	\N	0	\N	\N	f	0	\N
249	4	150	\N	0	\N	\N	f	0	\N
250	4	149	\N	0	\N	\N	f	0	\N
251	4	148	\N	0	\N	\N	f	0	\N
252	4	147	\N	0	\N	\N	f	0	\N
253	4	146	\N	0	\N	\N	f	0	\N
254	4	254	\N	0	\N	\N	f	0	\N
255	4	253	\N	0	\N	\N	f	0	\N
256	4	252	\N	0	\N	\N	f	0	\N
257	4	251	\N	0	\N	\N	f	0	\N
258	4	250	\N	0	\N	\N	f	0	\N
259	4	249	\N	0	\N	\N	f	0	\N
260	4	248	\N	0	\N	\N	f	0	\N
261	4	247	\N	0	\N	\N	f	0	\N
262	4	246	\N	0	\N	\N	f	0	\N
263	4	245	\N	0	\N	\N	f	0	\N
264	4	244	\N	0	\N	\N	f	0	\N
265	4	243	\N	0	\N	\N	f	0	\N
266	4	242	\N	0	\N	\N	f	0	\N
267	4	241	\N	0	\N	\N	f	0	\N
268	4	240	\N	0	\N	\N	f	0	\N
269	4	239	\N	0	\N	\N	f	0	\N
270	4	238	\N	0	\N	\N	f	0	\N
271	4	237	\N	0	\N	\N	f	0	\N
272	4	236	\N	0	\N	\N	f	0	\N
273	4	235	\N	0	\N	\N	f	0	\N
274	4	234	\N	0	\N	\N	f	0	\N
275	4	233	\N	0	\N	\N	f	0	\N
276	4	232	\N	0	\N	\N	f	0	\N
277	4	231	\N	0	\N	\N	f	0	\N
278	4	230	\N	0	\N	\N	f	0	\N
279	4	229	\N	0	\N	\N	f	0	\N
280	4	228	\N	0	\N	\N	f	0	\N
281	4	227	\N	0	\N	\N	f	0	\N
282	4	226	\N	0	\N	\N	f	0	\N
283	4	225	\N	0	\N	\N	f	0	\N
284	4	224	\N	0	\N	\N	f	0	\N
285	4	223	\N	0	\N	\N	f	0	\N
286	4	222	\N	0	\N	\N	f	0	\N
287	4	221	\N	0	\N	\N	f	0	\N
288	4	220	\N	0	\N	\N	f	0	\N
289	4	219	\N	0	\N	\N	f	0	\N
290	4	109	\N	0	\N	\N	f	0	\N
291	4	108	\N	0	\N	\N	f	0	\N
292	4	107	\N	0	\N	\N	f	0	\N
293	4	106	\N	0	\N	\N	f	0	\N
294	4	105	\N	0	\N	\N	f	0	\N
295	4	104	\N	0	\N	\N	f	0	\N
296	4	103	\N	0	\N	\N	f	0	\N
297	4	102	\N	0	\N	\N	f	0	\N
298	4	101	\N	0	\N	\N	f	0	\N
299	4	100	\N	0	\N	\N	f	0	\N
300	4	99	\N	0	\N	\N	f	0	\N
301	4	98	\N	0	\N	\N	f	0	\N
302	4	97	\N	0	\N	\N	f	0	\N
303	4	96	\N	0	\N	\N	f	0	\N
304	4	95	\N	0	\N	\N	f	0	\N
305	4	94	\N	0	\N	\N	f	0	\N
306	4	93	\N	0	\N	\N	f	0	\N
307	4	92	\N	0	\N	\N	f	0	\N
308	4	91	\N	0	\N	\N	f	0	\N
309	4	90	\N	0	\N	\N	f	0	\N
310	4	89	\N	0	\N	\N	f	0	\N
311	4	88	\N	0	\N	\N	f	0	\N
312	4	87	\N	0	\N	\N	f	0	\N
313	4	86	\N	0	\N	\N	f	0	\N
314	4	85	\N	0	\N	\N	f	0	\N
315	4	84	\N	0	\N	\N	f	0	\N
316	4	83	\N	0	\N	\N	f	0	\N
317	4	82	\N	0	\N	\N	f	0	\N
318	4	81	\N	0	\N	\N	f	0	\N
319	4	80	\N	0	\N	\N	f	0	\N
320	4	79	\N	0	\N	\N	f	0	\N
321	4	78	\N	0	\N	\N	f	0	\N
322	4	77	\N	0	\N	\N	f	0	\N
323	4	76	\N	0	\N	\N	f	0	\N
324	4	75	\N	0	\N	\N	f	0	\N
325	4	360	\N	0	\N	\N	f	0	\N
326	4	359	\N	0	\N	\N	f	0	\N
327	4	358	\N	0	\N	\N	f	0	\N
328	4	357	\N	0	\N	\N	f	0	\N
329	4	356	\N	0	\N	\N	f	0	\N
330	4	355	\N	0	\N	\N	f	0	\N
331	4	354	\N	0	\N	\N	f	0	\N
332	4	353	\N	0	\N	\N	f	0	\N
333	4	352	\N	0	\N	\N	f	0	\N
334	4	351	\N	0	\N	\N	f	0	\N
335	4	350	\N	0	\N	\N	f	0	\N
336	4	349	\N	0	\N	\N	f	0	\N
337	4	348	\N	0	\N	\N	f	0	\N
338	4	347	\N	0	\N	\N	f	0	\N
339	4	346	\N	0	\N	\N	f	0	\N
340	4	345	\N	0	\N	\N	f	0	\N
341	4	344	\N	0	\N	\N	f	0	\N
342	4	343	\N	0	\N	\N	f	0	\N
343	4	342	\N	0	\N	\N	f	0	\N
344	4	341	\N	0	\N	\N	f	0	\N
345	4	340	\N	0	\N	\N	f	0	\N
346	4	339	\N	0	\N	\N	f	0	\N
347	4	338	\N	0	\N	\N	f	0	\N
348	4	337	\N	0	\N	\N	f	0	\N
349	4	336	\N	0	\N	\N	f	0	\N
350	4	335	\N	0	\N	\N	f	0	\N
351	4	334	\N	0	\N	\N	f	0	\N
352	4	333	\N	0	\N	\N	f	0	\N
353	4	332	\N	0	\N	\N	f	0	\N
354	4	331	\N	0	\N	\N	f	0	\N
355	4	330	\N	0	\N	\N	f	0	\N
356	4	329	\N	0	\N	\N	f	0	\N
357	4	328	\N	0	\N	\N	f	0	\N
358	4	327	\N	0	\N	\N	f	0	\N
359	4	326	\N	0	\N	\N	f	0	\N
360	4	325	\N	0	\N	\N	f	0	\N
361	4	324	\N	0	\N	\N	f	0	\N
362	4	218	\N	0	\N	\N	f	0	\N
363	4	217	\N	0	\N	\N	f	0	\N
364	4	216	\N	0	\N	\N	f	0	\N
365	4	215	\N	0	\N	\N	f	0	\N
366	4	214	\N	0	\N	\N	f	0	\N
367	4	213	\N	0	\N	\N	f	0	\N
368	4	212	\N	0	\N	\N	f	0	\N
369	4	211	\N	0	\N	\N	f	0	\N
370	4	210	\N	0	\N	\N	f	0	\N
371	4	209	\N	0	\N	\N	f	0	\N
372	4	208	\N	0	\N	\N	f	0	\N
373	4	207	\N	0	\N	\N	f	0	\N
374	4	206	\N	0	\N	\N	f	0	\N
375	4	205	\N	0	\N	\N	f	0	\N
376	4	204	\N	0	\N	\N	f	0	\N
377	4	203	\N	0	\N	\N	f	0	\N
378	4	202	\N	0	\N	\N	f	0	\N
379	4	201	\N	0	\N	\N	f	0	\N
380	4	200	\N	0	\N	\N	f	0	\N
381	4	199	\N	0	\N	\N	f	0	\N
382	4	198	\N	0	\N	\N	f	0	\N
383	4	197	\N	0	\N	\N	f	0	\N
384	4	196	\N	0	\N	\N	f	0	\N
385	4	195	\N	0	\N	\N	f	0	\N
386	4	194	\N	0	\N	\N	f	0	\N
387	4	193	\N	0	\N	\N	f	0	\N
388	4	192	\N	0	\N	\N	f	0	\N
389	4	191	\N	0	\N	\N	f	0	\N
390	4	190	\N	0	\N	\N	f	0	\N
391	4	189	\N	0	\N	\N	f	0	\N
392	4	188	\N	0	\N	\N	f	0	\N
393	4	187	\N	0	\N	\N	f	0	\N
394	4	186	\N	0	\N	\N	f	0	\N
395	4	185	\N	0	\N	\N	f	0	\N
396	4	184	\N	0	\N	\N	f	0	\N
397	4	183	\N	0	\N	\N	f	0	\N
398	4	182	\N	0	\N	\N	f	0	\N
399	4	181	\N	0	\N	\N	f	0	\N
400	4	145	\N	0	\N	\N	f	0	\N
401	4	144	\N	0	\N	\N	f	0	\N
402	4	143	\N	0	\N	\N	f	0	\N
403	4	142	\N	0	\N	\N	f	0	\N
404	4	141	\N	0	\N	\N	f	0	\N
405	4	140	\N	0	\N	\N	f	0	\N
406	4	139	\N	0	\N	\N	f	0	\N
407	4	138	\N	0	\N	\N	f	0	\N
408	4	137	\N	0	\N	\N	f	0	\N
409	4	136	\N	0	\N	\N	f	0	\N
410	4	135	\N	0	\N	\N	f	0	\N
411	4	134	\N	0	\N	\N	f	0	\N
412	4	133	\N	0	\N	\N	f	0	\N
413	4	132	\N	0	\N	\N	f	0	\N
414	4	131	\N	0	\N	\N	f	0	\N
415	4	130	\N	0	\N	\N	f	0	\N
416	4	129	\N	0	\N	\N	f	0	\N
417	4	128	\N	0	\N	\N	f	0	\N
418	4	127	\N	0	\N	\N	f	0	\N
419	4	126	\N	0	\N	\N	f	0	\N
420	4	125	\N	0	\N	\N	f	0	\N
421	4	124	\N	0	\N	\N	f	0	\N
422	4	123	\N	0	\N	\N	f	0	\N
423	4	122	\N	0	\N	\N	f	0	\N
424	4	121	\N	0	\N	\N	f	0	\N
425	4	120	\N	0	\N	\N	f	0	\N
426	4	119	\N	0	\N	\N	f	0	\N
427	4	118	\N	0	\N	\N	f	0	\N
428	4	117	\N	0	\N	\N	f	0	\N
429	4	116	\N	0	\N	\N	f	0	\N
430	4	115	\N	0	\N	\N	f	0	\N
431	4	114	\N	0	\N	\N	f	0	\N
432	4	113	\N	0	\N	\N	f	0	\N
433	4	112	\N	0	\N	\N	f	0	\N
434	4	111	\N	0	\N	\N	f	0	\N
435	4	110	\N	0	\N	\N	f	0	\N
436	4	74	\N	0	\N	\N	f	0	\N
437	4	73	\N	0	\N	\N	f	0	\N
438	4	72	\N	0	\N	\N	f	0	\N
439	4	71	\N	0	\N	\N	f	0	\N
440	4	70	\N	0	\N	\N	f	0	\N
441	4	69	\N	0	\N	\N	f	0	\N
442	4	68	\N	0	\N	\N	f	0	\N
443	4	67	\N	0	\N	\N	f	0	\N
444	4	66	\N	0	\N	\N	f	0	\N
445	4	65	\N	0	\N	\N	f	0	\N
446	4	64	\N	0	\N	\N	f	0	\N
447	4	63	\N	0	\N	\N	f	0	\N
448	4	62	\N	0	\N	\N	f	0	\N
449	4	61	\N	0	\N	\N	f	0	\N
450	4	60	\N	0	\N	\N	f	0	\N
451	4	59	\N	0	\N	\N	f	0	\N
452	4	58	\N	0	\N	\N	f	0	\N
453	4	57	\N	0	\N	\N	f	0	\N
454	4	56	\N	0	\N	\N	f	0	\N
455	4	55	\N	0	\N	\N	f	0	\N
456	4	54	\N	0	\N	\N	f	0	\N
457	4	53	\N	0	\N	\N	f	0	\N
458	4	52	\N	0	\N	\N	f	0	\N
459	4	51	\N	0	\N	\N	f	0	\N
460	4	50	\N	0	\N	\N	f	0	\N
461	4	49	\N	0	\N	\N	f	0	\N
462	4	48	\N	0	\N	\N	f	0	\N
463	4	47	\N	0	\N	\N	f	0	\N
464	4	46	\N	0	\N	\N	f	0	\N
465	4	45	\N	0	\N	\N	f	0	\N
466	4	44	\N	0	\N	\N	f	0	\N
467	4	43	\N	0	\N	\N	f	0	\N
468	4	42	\N	0	\N	\N	f	0	\N
469	4	41	\N	0	\N	\N	f	0	\N
470	4	40	\N	0	\N	\N	f	0	\N
471	4	39	\N	0	\N	\N	f	0	\N
472	4	38	\N	0	\N	\N	f	0	\N
473	4	37	\N	0	\N	\N	f	0	\N
474	4	36	\N	0	\N	\N	f	0	\N
475	4	35	\N	0	\N	\N	f	0	\N
476	4	34	\N	0	\N	\N	f	0	\N
477	4	33	\N	0	\N	\N	f	0	\N
478	4	32	\N	0	\N	\N	f	0	\N
479	4	31	\N	0	\N	\N	f	0	\N
480	4	30	\N	0	\N	\N	f	0	\N
481	4	29	\N	0	\N	\N	f	0	\N
482	4	28	\N	0	\N	\N	f	0	\N
483	4	27	\N	0	\N	\N	f	0	\N
484	4	26	\N	0	\N	\N	f	0	\N
485	4	25	\N	0	\N	\N	f	0	\N
486	4	24	\N	0	\N	\N	f	0	\N
487	4	23	\N	0	\N	\N	f	0	\N
488	4	22	\N	0	\N	\N	f	0	\N
489	4	21	\N	0	\N	\N	f	0	\N
490	4	20	\N	0	\N	\N	f	0	\N
491	4	19	\N	0	\N	\N	f	0	\N
492	4	18	\N	0	\N	\N	f	0	\N
493	4	17	\N	0	\N	\N	f	0	\N
494	4	16	\N	0	\N	\N	f	0	\N
495	4	15	\N	0	\N	\N	f	0	\N
496	4	14	\N	0	\N	\N	f	0	\N
497	4	13	\N	0	\N	\N	f	0	\N
498	4	12	\N	0	\N	\N	f	0	\N
499	4	11	\N	0	\N	\N	f	0	\N
500	4	10	\N	0	\N	\N	f	0	\N
501	4	9	\N	0	\N	\N	f	0	\N
502	4	8	\N	0	\N	\N	f	0	\N
503	4	7	\N	0	\N	\N	f	0	\N
504	4	6	\N	0	\N	\N	f	0	\N
505	4	5	\N	0	\N	\N	f	0	\N
506	4	4	\N	0	\N	\N	f	0	\N
507	4	3	\N	0	\N	\N	f	0	\N
508	4	2	\N	0	\N	\N	f	0	\N
509	4	1	\N	0	\N	\N	f	0	\N
510	5	218	\N	0	\N	\N	f	0	\N
511	5	217	\N	0	\N	\N	f	0	\N
512	5	216	\N	0	\N	\N	f	0	\N
513	5	215	\N	0	\N	\N	f	0	\N
514	5	214	\N	0	\N	\N	f	0	\N
515	5	213	\N	0	\N	\N	f	0	\N
516	5	212	\N	0	\N	\N	f	0	\N
517	5	211	\N	0	\N	\N	f	0	\N
518	5	210	\N	0	\N	\N	f	0	\N
519	5	209	\N	0	\N	\N	f	0	\N
520	5	208	\N	0	\N	\N	f	0	\N
521	5	207	\N	0	\N	\N	f	0	\N
522	5	206	\N	0	\N	\N	f	0	\N
523	5	205	\N	0	\N	\N	f	0	\N
524	5	204	\N	0	\N	\N	f	0	\N
525	5	203	\N	0	\N	\N	f	0	\N
526	5	202	\N	0	\N	\N	f	0	\N
527	5	201	\N	0	\N	\N	f	0	\N
528	5	200	\N	0	\N	\N	f	0	\N
529	5	199	\N	0	\N	\N	f	0	\N
530	5	198	\N	0	\N	\N	f	0	\N
531	5	197	\N	0	\N	\N	f	0	\N
532	5	196	\N	0	\N	\N	f	0	\N
533	5	195	\N	0	\N	\N	f	0	\N
534	5	194	\N	0	\N	\N	f	0	\N
535	5	193	\N	0	\N	\N	f	0	\N
536	5	192	\N	0	\N	\N	f	0	\N
537	5	191	\N	0	\N	\N	f	0	\N
538	5	190	\N	0	\N	\N	f	0	\N
539	5	189	\N	0	\N	\N	f	0	\N
540	5	188	\N	0	\N	\N	f	0	\N
541	5	187	\N	0	\N	\N	f	0	\N
542	5	186	\N	0	\N	\N	f	0	\N
543	5	185	\N	0	\N	\N	f	0	\N
544	5	184	\N	0	\N	\N	f	0	\N
545	5	183	\N	0	\N	\N	f	0	\N
546	5	182	\N	0	\N	\N	f	0	\N
547	5	181	\N	0	\N	\N	f	0	\N
548	6	290	\N	0	\N	\N	f	0	\N
549	6	289	\N	0	\N	\N	f	0	\N
550	6	288	\N	0	\N	\N	f	0	\N
551	6	287	\N	0	\N	\N	f	0	\N
552	6	286	\N	0	\N	\N	f	0	\N
553	6	285	\N	0	\N	\N	f	0	\N
554	6	284	\N	0	\N	\N	f	0	\N
555	6	283	\N	0	\N	\N	f	0	\N
556	6	282	\N	0	\N	\N	f	0	\N
557	6	281	\N	0	\N	\N	f	0	\N
558	6	280	\N	0	\N	\N	f	0	\N
559	6	279	\N	0	\N	\N	f	0	\N
560	6	278	\N	0	\N	\N	f	0	\N
561	6	277	\N	0	\N	\N	f	0	\N
562	6	276	\N	0	\N	\N	f	0	\N
563	6	275	\N	0	\N	\N	f	0	\N
564	6	274	\N	0	\N	\N	f	0	\N
565	6	273	\N	0	\N	\N	f	0	\N
566	6	272	\N	0	\N	\N	f	0	\N
567	6	271	\N	0	\N	\N	f	0	\N
568	6	270	\N	0	\N	\N	f	0	\N
569	6	269	\N	0	\N	\N	f	0	\N
570	6	268	\N	0	\N	\N	f	0	\N
571	6	267	\N	0	\N	\N	f	0	\N
572	6	266	\N	0	\N	\N	f	0	\N
573	6	265	\N	0	\N	\N	f	0	\N
574	6	264	\N	0	\N	\N	f	0	\N
575	6	263	\N	0	\N	\N	f	0	\N
576	6	262	\N	0	\N	\N	f	0	\N
577	6	261	\N	0	\N	\N	f	0	\N
578	6	260	\N	0	\N	\N	f	0	\N
579	6	259	\N	0	\N	\N	f	0	\N
580	6	258	\N	0	\N	\N	f	0	\N
581	6	257	\N	0	\N	\N	f	0	\N
582	6	256	\N	0	\N	\N	f	0	\N
583	6	255	\N	0	\N	\N	f	0	\N
584	6	180	\N	0	\N	\N	f	0	\N
585	6	179	\N	0	\N	\N	f	0	\N
586	6	178	\N	0	\N	\N	f	0	\N
587	6	177	\N	0	\N	\N	f	0	\N
588	6	176	\N	0	\N	\N	f	0	\N
589	6	175	\N	0	\N	\N	f	0	\N
590	6	174	\N	0	\N	\N	f	0	\N
591	6	173	\N	0	\N	\N	f	0	\N
592	6	172	\N	0	\N	\N	f	0	\N
593	6	171	\N	0	\N	\N	f	0	\N
594	6	170	\N	0	\N	\N	f	0	\N
595	6	169	\N	0	\N	\N	f	0	\N
596	6	168	\N	0	\N	\N	f	0	\N
597	6	167	\N	0	\N	\N	f	0	\N
598	6	166	\N	0	\N	\N	f	0	\N
599	6	165	\N	0	\N	\N	f	0	\N
600	6	164	\N	0	\N	\N	f	0	\N
601	6	163	\N	0	\N	\N	f	0	\N
602	6	162	\N	0	\N	\N	f	0	\N
603	6	161	\N	0	\N	\N	f	0	\N
604	6	160	\N	0	\N	\N	f	0	\N
605	6	159	\N	0	\N	\N	f	0	\N
606	6	158	\N	0	\N	\N	f	0	\N
607	6	157	\N	0	\N	\N	f	0	\N
608	6	156	\N	0	\N	\N	f	0	\N
609	6	155	\N	0	\N	\N	f	0	\N
610	6	154	\N	0	\N	\N	f	0	\N
611	6	153	\N	0	\N	\N	f	0	\N
612	6	152	\N	0	\N	\N	f	0	\N
613	6	151	\N	0	\N	\N	f	0	\N
614	6	150	\N	0	\N	\N	f	0	\N
615	6	149	\N	0	\N	\N	f	0	\N
616	6	148	\N	0	\N	\N	f	0	\N
617	6	147	\N	0	\N	\N	f	0	\N
618	6	146	\N	0	\N	\N	f	0	\N
619	6	145	\N	0	\N	\N	f	0	\N
620	6	144	\N	0	\N	\N	f	0	\N
621	6	143	\N	0	\N	\N	f	0	\N
622	6	142	\N	0	\N	\N	f	0	\N
623	6	141	\N	0	\N	\N	f	0	\N
624	6	140	\N	0	\N	\N	f	0	\N
625	6	139	\N	0	\N	\N	f	0	\N
626	6	138	\N	0	\N	\N	f	0	\N
627	6	137	\N	0	\N	\N	f	0	\N
628	6	136	\N	0	\N	\N	f	0	\N
629	6	135	\N	0	\N	\N	f	0	\N
630	6	134	\N	0	\N	\N	f	0	\N
631	6	133	\N	0	\N	\N	f	0	\N
632	6	132	\N	0	\N	\N	f	0	\N
633	6	131	\N	0	\N	\N	f	0	\N
634	6	130	\N	0	\N	\N	f	0	\N
635	6	129	\N	0	\N	\N	f	0	\N
636	6	128	\N	0	\N	\N	f	0	\N
637	6	127	\N	0	\N	\N	f	0	\N
638	6	126	\N	0	\N	\N	f	0	\N
639	6	125	\N	0	\N	\N	f	0	\N
640	6	124	\N	0	\N	\N	f	0	\N
641	6	123	\N	0	\N	\N	f	0	\N
642	6	122	\N	0	\N	\N	f	0	\N
643	6	121	\N	0	\N	\N	f	0	\N
644	6	120	\N	0	\N	\N	f	0	\N
645	6	119	\N	0	\N	\N	f	0	\N
646	6	118	\N	0	\N	\N	f	0	\N
647	6	117	\N	0	\N	\N	f	0	\N
648	6	116	\N	0	\N	\N	f	0	\N
649	6	115	\N	0	\N	\N	f	0	\N
650	6	114	\N	0	\N	\N	f	0	\N
651	6	113	\N	0	\N	\N	f	0	\N
652	6	112	\N	0	\N	\N	f	0	\N
653	6	111	\N	0	\N	\N	f	0	\N
654	6	110	\N	0	\N	\N	f	0	\N
655	6	74	\N	0	\N	\N	f	0	\N
656	6	73	\N	0	\N	\N	f	0	\N
657	6	72	\N	0	\N	\N	f	0	\N
658	6	71	\N	0	\N	\N	f	0	\N
659	6	70	\N	0	\N	\N	f	0	\N
660	6	69	\N	0	\N	\N	f	0	\N
661	6	68	\N	0	\N	\N	f	0	\N
662	6	67	\N	0	\N	\N	f	0	\N
663	6	66	\N	0	\N	\N	f	0	\N
664	6	65	\N	0	\N	\N	f	0	\N
665	6	64	\N	0	\N	\N	f	0	\N
666	6	63	\N	0	\N	\N	f	0	\N
667	6	62	\N	0	\N	\N	f	0	\N
668	6	61	\N	0	\N	\N	f	0	\N
669	6	60	\N	0	\N	\N	f	0	\N
670	6	59	\N	0	\N	\N	f	0	\N
671	6	58	\N	0	\N	\N	f	0	\N
672	6	57	\N	0	\N	\N	f	0	\N
673	6	56	\N	0	\N	\N	f	0	\N
674	6	55	\N	0	\N	\N	f	0	\N
675	6	54	\N	0	\N	\N	f	0	\N
676	6	53	\N	0	\N	\N	f	0	\N
677	6	52	\N	0	\N	\N	f	0	\N
678	6	51	\N	0	\N	\N	f	0	\N
679	6	50	\N	0	\N	\N	f	0	\N
680	6	49	\N	0	\N	\N	f	0	\N
681	6	48	\N	0	\N	\N	f	0	\N
682	6	47	\N	0	\N	\N	f	0	\N
683	6	46	\N	0	\N	\N	f	0	\N
684	6	45	\N	0	\N	\N	f	0	\N
685	6	44	\N	0	\N	\N	f	0	\N
686	6	43	\N	0	\N	\N	f	0	\N
687	6	42	\N	0	\N	\N	f	0	\N
688	6	41	\N	0	\N	\N	f	0	\N
689	6	40	\N	0	\N	\N	f	0	\N
690	6	323	\N	0	\N	\N	f	0	\N
691	6	322	\N	0	\N	\N	f	0	\N
692	6	321	\N	0	\N	\N	f	0	\N
693	6	320	\N	0	\N	\N	f	0	\N
694	6	319	\N	0	\N	\N	f	0	\N
695	6	318	\N	0	\N	\N	f	0	\N
696	6	317	\N	0	\N	\N	f	0	\N
697	6	316	\N	0	\N	\N	f	0	\N
698	6	315	\N	0	\N	\N	f	0	\N
699	6	314	\N	0	\N	\N	f	0	\N
700	6	313	\N	0	\N	\N	f	0	\N
701	6	312	\N	0	\N	\N	f	0	\N
702	6	311	\N	0	\N	\N	f	0	\N
703	6	310	\N	0	\N	\N	f	0	\N
704	6	309	\N	0	\N	\N	f	0	\N
705	6	308	\N	0	\N	\N	f	0	\N
706	6	307	\N	0	\N	\N	f	0	\N
707	6	306	\N	0	\N	\N	f	0	\N
708	6	305	\N	0	\N	\N	f	0	\N
709	6	304	\N	0	\N	\N	f	0	\N
710	6	303	\N	0	\N	\N	f	0	\N
711	6	302	\N	0	\N	\N	f	0	\N
712	6	301	\N	0	\N	\N	f	0	\N
713	6	300	\N	0	\N	\N	f	0	\N
714	6	299	\N	0	\N	\N	f	0	\N
715	6	298	\N	0	\N	\N	f	0	\N
716	6	297	\N	0	\N	\N	f	0	\N
717	6	296	\N	0	\N	\N	f	0	\N
718	6	295	\N	0	\N	\N	f	0	\N
719	6	294	\N	0	\N	\N	f	0	\N
720	6	293	\N	0	\N	\N	f	0	\N
721	6	292	\N	0	\N	\N	f	0	\N
722	6	291	\N	0	\N	\N	f	0	\N
723	6	254	\N	0	\N	\N	f	0	\N
724	6	253	\N	0	\N	\N	f	0	\N
725	6	252	\N	0	\N	\N	f	0	\N
726	6	251	\N	0	\N	\N	f	0	\N
727	6	250	\N	0	\N	\N	f	0	\N
728	6	249	\N	0	\N	\N	f	0	\N
729	6	248	\N	0	\N	\N	f	0	\N
730	6	247	\N	0	\N	\N	f	0	\N
731	6	246	\N	0	\N	\N	f	0	\N
732	6	245	\N	0	\N	\N	f	0	\N
733	6	244	\N	0	\N	\N	f	0	\N
734	6	243	\N	0	\N	\N	f	0	\N
735	6	242	\N	0	\N	\N	f	0	\N
736	6	241	\N	0	\N	\N	f	0	\N
737	6	240	\N	0	\N	\N	f	0	\N
738	6	239	\N	0	\N	\N	f	0	\N
739	6	238	\N	0	\N	\N	f	0	\N
740	6	237	\N	0	\N	\N	f	0	\N
741	6	236	\N	0	\N	\N	f	0	\N
742	6	235	\N	0	\N	\N	f	0	\N
743	6	234	\N	0	\N	\N	f	0	\N
744	6	233	\N	0	\N	\N	f	0	\N
745	6	232	\N	0	\N	\N	f	0	\N
746	6	231	\N	0	\N	\N	f	0	\N
747	6	230	\N	0	\N	\N	f	0	\N
748	6	229	\N	0	\N	\N	f	0	\N
749	6	228	\N	0	\N	\N	f	0	\N
750	6	227	\N	0	\N	\N	f	0	\N
751	6	226	\N	0	\N	\N	f	0	\N
752	6	225	\N	0	\N	\N	f	0	\N
753	6	224	\N	0	\N	\N	f	0	\N
754	6	223	\N	0	\N	\N	f	0	\N
755	6	222	\N	0	\N	\N	f	0	\N
756	6	221	\N	0	\N	\N	f	0	\N
757	6	220	\N	0	\N	\N	f	0	\N
758	6	219	\N	0	\N	\N	f	0	\N
759	6	39	\N	0	\N	\N	f	0	\N
760	6	38	\N	0	\N	\N	f	0	\N
761	6	37	\N	0	\N	\N	f	0	\N
762	6	36	\N	0	\N	\N	f	0	\N
763	6	35	\N	0	\N	\N	f	0	\N
764	6	34	\N	0	\N	\N	f	0	\N
765	6	33	\N	0	\N	\N	f	0	\N
766	6	32	\N	0	\N	\N	f	0	\N
767	6	31	\N	0	\N	\N	f	0	\N
768	6	30	\N	0	\N	\N	f	0	\N
769	6	29	\N	0	\N	\N	f	0	\N
770	6	28	\N	0	\N	\N	f	0	\N
771	6	27	\N	0	\N	\N	f	0	\N
772	6	26	\N	0	\N	\N	f	0	\N
773	6	25	\N	0	\N	\N	f	0	\N
774	6	24	\N	0	\N	\N	f	0	\N
775	6	23	\N	0	\N	\N	f	0	\N
776	6	22	\N	0	\N	\N	f	0	\N
777	6	21	\N	0	\N	\N	f	0	\N
778	6	20	\N	0	\N	\N	f	0	\N
779	6	19	\N	0	\N	\N	f	0	\N
780	6	18	\N	0	\N	\N	f	0	\N
781	6	17	\N	0	\N	\N	f	0	\N
782	6	16	\N	0	\N	\N	f	0	\N
783	6	15	\N	0	\N	\N	f	0	\N
784	6	14	\N	0	\N	\N	f	0	\N
785	6	13	\N	0	\N	\N	f	0	\N
786	6	12	\N	0	\N	\N	f	0	\N
787	6	11	\N	0	\N	\N	f	0	\N
788	6	10	\N	0	\N	\N	f	0	\N
789	6	9	\N	0	\N	\N	f	0	\N
790	6	8	\N	0	\N	\N	f	0	\N
791	6	7	\N	0	\N	\N	f	0	\N
792	6	6	\N	0	\N	\N	f	0	\N
793	6	5	\N	0	\N	\N	f	0	\N
794	6	4	\N	0	\N	\N	f	0	\N
795	6	3	\N	0	\N	\N	f	0	\N
796	6	2	\N	0	\N	\N	f	0	\N
797	6	1	\N	0	\N	\N	f	0	\N
798	6	109	\N	0	\N	\N	f	0	\N
799	6	108	\N	0	\N	\N	f	0	\N
800	6	107	\N	0	\N	\N	f	0	\N
801	6	106	\N	0	\N	\N	f	0	\N
802	6	105	\N	0	\N	\N	f	0	\N
803	6	104	\N	0	\N	\N	f	0	\N
804	6	103	\N	0	\N	\N	f	0	\N
805	6	102	\N	0	\N	\N	f	0	\N
806	6	101	\N	0	\N	\N	f	0	\N
807	6	100	\N	0	\N	\N	f	0	\N
808	6	99	\N	0	\N	\N	f	0	\N
809	6	98	\N	0	\N	\N	f	0	\N
810	6	97	\N	0	\N	\N	f	0	\N
811	6	96	\N	0	\N	\N	f	0	\N
812	6	95	\N	0	\N	\N	f	0	\N
813	6	94	\N	0	\N	\N	f	0	\N
814	6	93	\N	0	\N	\N	f	0	\N
815	6	92	\N	0	\N	\N	f	0	\N
816	6	91	\N	0	\N	\N	f	0	\N
817	6	90	\N	0	\N	\N	f	0	\N
818	6	89	\N	0	\N	\N	f	0	\N
819	6	88	\N	0	\N	\N	f	0	\N
820	6	87	\N	0	\N	\N	f	0	\N
821	6	86	\N	0	\N	\N	f	0	\N
822	6	85	\N	0	\N	\N	f	0	\N
823	6	84	\N	0	\N	\N	f	0	\N
824	6	83	\N	0	\N	\N	f	0	\N
825	6	82	\N	0	\N	\N	f	0	\N
826	6	81	\N	0	\N	\N	f	0	\N
827	6	80	\N	0	\N	\N	f	0	\N
828	6	79	\N	0	\N	\N	f	0	\N
829	6	78	\N	0	\N	\N	f	0	\N
830	6	77	\N	0	\N	\N	f	0	\N
831	6	76	\N	0	\N	\N	f	0	\N
832	6	75	\N	0	\N	\N	f	0	\N
833	7	254	\N	0	\N	\N	f	0	\N
834	7	253	\N	0	\N	\N	f	0	\N
835	7	252	\N	0	\N	\N	f	0	\N
836	7	251	\N	0	\N	\N	f	0	\N
837	7	250	\N	0	\N	\N	f	0	\N
838	7	249	\N	0	\N	\N	f	0	\N
839	7	248	\N	0	\N	\N	f	0	\N
840	7	247	\N	0	\N	\N	f	0	\N
841	7	246	\N	0	\N	\N	f	0	\N
842	7	245	\N	0	\N	\N	f	0	\N
843	7	244	\N	0	\N	\N	f	0	\N
844	7	243	\N	0	\N	\N	f	0	\N
845	7	242	\N	0	\N	\N	f	0	\N
846	7	241	\N	0	\N	\N	f	0	\N
847	7	240	\N	0	\N	\N	f	0	\N
848	7	239	\N	0	\N	\N	f	0	\N
849	7	238	\N	0	\N	\N	f	0	\N
850	7	237	\N	0	\N	\N	f	0	\N
851	7	236	\N	0	\N	\N	f	0	\N
852	7	235	\N	0	\N	\N	f	0	\N
853	7	234	\N	0	\N	\N	f	0	\N
854	7	233	\N	0	\N	\N	f	0	\N
855	7	232	\N	0	\N	\N	f	0	\N
856	7	231	\N	0	\N	\N	f	0	\N
857	7	230	\N	0	\N	\N	f	0	\N
858	7	229	\N	0	\N	\N	f	0	\N
859	7	228	\N	0	\N	\N	f	0	\N
860	7	227	\N	0	\N	\N	f	0	\N
861	7	226	\N	0	\N	\N	f	0	\N
862	7	225	\N	0	\N	\N	f	0	\N
863	7	224	\N	0	\N	\N	f	0	\N
864	7	223	\N	0	\N	\N	f	0	\N
865	7	222	\N	0	\N	\N	f	0	\N
866	7	221	\N	0	\N	\N	f	0	\N
867	7	220	\N	0	\N	\N	f	0	\N
868	7	219	\N	0	\N	\N	f	0	\N
869	9	432	\N	0	\N	\N	f	0	\N
870	9	431	\N	0	\N	\N	f	0	\N
871	9	430	\N	0	\N	\N	f	0	\N
872	9	429	\N	0	\N	\N	f	0	\N
873	9	428	\N	0	\N	\N	f	0	\N
874	9	427	\N	0	\N	\N	f	0	\N
875	9	426	\N	0	\N	\N	f	0	\N
876	9	425	\N	0	\N	\N	f	0	\N
877	9	424	\N	0	\N	\N	f	0	\N
878	9	423	\N	0	\N	\N	f	0	\N
879	9	422	\N	0	\N	\N	f	0	\N
880	9	421	\N	0	\N	\N	f	0	\N
881	9	420	\N	0	\N	\N	f	0	\N
882	9	419	\N	0	\N	\N	f	0	\N
883	9	418	\N	0	\N	\N	f	0	\N
884	9	417	\N	0	\N	\N	f	0	\N
885	9	416	\N	0	\N	\N	f	0	\N
886	9	415	\N	0	\N	\N	f	0	\N
887	9	414	\N	0	\N	\N	f	0	\N
888	9	413	\N	0	\N	\N	f	0	\N
889	9	412	\N	0	\N	\N	f	0	\N
890	9	411	\N	0	\N	\N	f	0	\N
891	9	410	\N	0	\N	\N	f	0	\N
892	9	409	\N	0	\N	\N	f	0	\N
893	9	408	\N	0	\N	\N	f	0	\N
894	9	407	\N	0	\N	\N	f	0	\N
895	9	406	\N	0	\N	\N	f	0	\N
896	9	405	\N	0	\N	\N	f	0	\N
897	9	404	\N	0	\N	\N	f	0	\N
898	9	403	\N	0	\N	\N	f	0	\N
899	9	402	\N	0	\N	\N	f	0	\N
900	9	290	\N	0	\N	\N	f	0	\N
901	9	289	\N	0	\N	\N	f	0	\N
902	9	288	\N	0	\N	\N	f	0	\N
903	9	287	\N	0	\N	\N	f	0	\N
904	9	286	\N	0	\N	\N	f	0	\N
905	9	285	\N	0	\N	\N	f	0	\N
906	9	284	\N	0	\N	\N	f	0	\N
907	9	283	\N	0	\N	\N	f	0	\N
908	9	282	\N	0	\N	\N	f	0	\N
909	9	281	\N	0	\N	\N	f	0	\N
910	9	280	\N	0	\N	\N	f	0	\N
911	9	279	\N	0	\N	\N	f	0	\N
912	9	278	\N	0	\N	\N	f	0	\N
913	9	277	\N	0	\N	\N	f	0	\N
914	9	276	\N	0	\N	\N	f	0	\N
915	9	275	\N	0	\N	\N	f	0	\N
916	9	274	\N	0	\N	\N	f	0	\N
917	9	273	\N	0	\N	\N	f	0	\N
918	9	272	\N	0	\N	\N	f	0	\N
919	9	271	\N	0	\N	\N	f	0	\N
920	9	270	\N	0	\N	\N	f	0	\N
921	9	269	\N	0	\N	\N	f	0	\N
922	9	268	\N	0	\N	\N	f	0	\N
923	9	267	\N	0	\N	\N	f	0	\N
924	9	266	\N	0	\N	\N	f	0	\N
925	9	265	\N	0	\N	\N	f	0	\N
926	9	264	\N	0	\N	\N	f	0	\N
927	9	263	\N	0	\N	\N	f	0	\N
928	9	262	\N	0	\N	\N	f	0	\N
929	9	261	\N	0	\N	\N	f	0	\N
930	9	260	\N	0	\N	\N	f	0	\N
931	9	259	\N	0	\N	\N	f	0	\N
932	9	258	\N	0	\N	\N	f	0	\N
933	9	257	\N	0	\N	\N	f	0	\N
934	9	256	\N	0	\N	\N	f	0	\N
935	9	255	\N	0	\N	\N	f	0	\N
936	10	145	\N	0	\N	\N	f	0	\N
937	10	144	\N	0	\N	\N	f	0	\N
938	10	143	\N	0	\N	\N	f	0	\N
939	10	142	\N	0	\N	\N	f	0	\N
940	10	141	\N	0	\N	\N	f	0	\N
941	10	140	\N	0	\N	\N	f	0	\N
942	10	139	\N	0	\N	\N	f	0	\N
943	10	138	\N	0	\N	\N	f	0	\N
944	10	137	\N	0	\N	\N	f	0	\N
945	10	136	\N	0	\N	\N	f	0	\N
946	10	135	\N	0	\N	\N	f	0	\N
947	10	134	\N	0	\N	\N	f	0	\N
948	10	133	\N	0	\N	\N	f	0	\N
949	10	132	\N	0	\N	\N	f	0	\N
950	10	131	\N	0	\N	\N	f	0	\N
951	10	130	\N	0	\N	\N	f	0	\N
952	10	129	\N	0	\N	\N	f	0	\N
953	10	128	\N	0	\N	\N	f	0	\N
954	10	127	\N	0	\N	\N	f	0	\N
955	10	126	\N	0	\N	\N	f	0	\N
956	10	125	\N	0	\N	\N	f	0	\N
957	10	124	\N	0	\N	\N	f	0	\N
958	10	123	\N	0	\N	\N	f	0	\N
959	10	122	\N	0	\N	\N	f	0	\N
960	10	121	\N	0	\N	\N	f	0	\N
961	10	120	\N	0	\N	\N	f	0	\N
962	10	119	\N	0	\N	\N	f	0	\N
963	10	118	\N	0	\N	\N	f	0	\N
964	10	117	\N	0	\N	\N	f	0	\N
965	10	116	\N	0	\N	\N	f	0	\N
966	10	115	\N	0	\N	\N	f	0	\N
967	10	114	\N	0	\N	\N	f	0	\N
968	10	113	\N	0	\N	\N	f	0	\N
969	10	112	\N	0	\N	\N	f	0	\N
970	10	111	\N	0	\N	\N	f	0	\N
971	10	110	\N	0	\N	\N	f	0	\N
972	10	432	\N	0	\N	\N	f	0	\N
973	10	431	\N	0	\N	\N	f	0	\N
974	10	430	\N	0	\N	\N	f	0	\N
975	10	429	\N	0	\N	\N	f	0	\N
976	10	428	\N	0	\N	\N	f	0	\N
977	10	427	\N	0	\N	\N	f	0	\N
978	10	426	\N	0	\N	\N	f	0	\N
979	10	425	\N	0	\N	\N	f	0	\N
980	10	424	\N	0	\N	\N	f	0	\N
981	10	423	\N	0	\N	\N	f	0	\N
982	10	422	\N	0	\N	\N	f	0	\N
983	10	421	\N	0	\N	\N	f	0	\N
984	10	420	\N	0	\N	\N	f	0	\N
985	10	419	\N	0	\N	\N	f	0	\N
986	10	418	\N	0	\N	\N	f	0	\N
987	10	417	\N	0	\N	\N	f	0	\N
988	10	416	\N	0	\N	\N	f	0	\N
989	10	415	\N	0	\N	\N	f	0	\N
990	10	414	\N	0	\N	\N	f	0	\N
991	10	413	\N	0	\N	\N	f	0	\N
992	10	412	\N	0	\N	\N	f	0	\N
993	10	411	\N	0	\N	\N	f	0	\N
994	10	410	\N	0	\N	\N	f	0	\N
995	10	409	\N	0	\N	\N	f	0	\N
996	10	408	\N	0	\N	\N	f	0	\N
997	10	407	\N	0	\N	\N	f	0	\N
998	10	406	\N	0	\N	\N	f	0	\N
999	10	405	\N	0	\N	\N	f	0	\N
1000	10	404	\N	0	\N	\N	f	0	\N
1001	10	403	\N	0	\N	\N	f	0	\N
1002	10	402	\N	0	\N	\N	f	0	\N
1003	10	360	\N	0	\N	\N	f	0	\N
1004	10	359	\N	0	\N	\N	f	0	\N
1005	10	358	\N	0	\N	\N	f	0	\N
1006	10	357	\N	0	\N	\N	f	0	\N
1007	10	356	\N	0	\N	\N	f	0	\N
1008	10	355	\N	0	\N	\N	f	0	\N
1009	10	354	\N	0	\N	\N	f	0	\N
1010	10	353	\N	0	\N	\N	f	0	\N
1011	10	352	\N	0	\N	\N	f	0	\N
1012	10	351	\N	0	\N	\N	f	0	\N
1013	10	350	\N	0	\N	\N	f	0	\N
1014	10	349	\N	0	\N	\N	f	0	\N
1015	10	348	\N	0	\N	\N	f	0	\N
1016	10	347	\N	0	\N	\N	f	0	\N
1017	10	346	\N	0	\N	\N	f	0	\N
1018	10	345	\N	0	\N	\N	f	0	\N
1019	10	344	\N	0	\N	\N	f	0	\N
1020	10	343	\N	0	\N	\N	f	0	\N
1021	10	342	\N	0	\N	\N	f	0	\N
1022	10	341	\N	0	\N	\N	f	0	\N
1023	10	340	\N	0	\N	\N	f	0	\N
1024	10	339	\N	0	\N	\N	f	0	\N
1025	10	338	\N	0	\N	\N	f	0	\N
1026	10	337	\N	0	\N	\N	f	0	\N
1027	10	336	\N	0	\N	\N	f	0	\N
1028	10	335	\N	0	\N	\N	f	0	\N
1029	10	334	\N	0	\N	\N	f	0	\N
1030	10	333	\N	0	\N	\N	f	0	\N
1031	10	332	\N	0	\N	\N	f	0	\N
1032	10	331	\N	0	\N	\N	f	0	\N
1033	10	330	\N	0	\N	\N	f	0	\N
1034	10	329	\N	0	\N	\N	f	0	\N
1035	10	328	\N	0	\N	\N	f	0	\N
1036	10	327	\N	0	\N	\N	f	0	\N
1037	10	326	\N	0	\N	\N	f	0	\N
1038	10	325	\N	0	\N	\N	f	0	\N
1039	10	324	\N	0	\N	\N	f	0	\N
1040	10	401	\N	0	\N	\N	f	0	\N
1041	10	400	\N	0	\N	\N	f	0	\N
1042	10	399	\N	0	\N	\N	f	0	\N
1043	10	398	\N	0	\N	\N	f	0	\N
1044	10	397	\N	0	\N	\N	f	0	\N
1045	10	396	\N	0	\N	\N	f	0	\N
1046	10	395	\N	0	\N	\N	f	0	\N
1047	10	394	\N	0	\N	\N	f	0	\N
1048	10	393	\N	0	\N	\N	f	0	\N
1049	10	392	\N	0	\N	\N	f	0	\N
1050	10	391	\N	0	\N	\N	f	0	\N
1051	10	390	\N	0	\N	\N	f	0	\N
1052	10	389	\N	0	\N	\N	f	0	\N
1053	10	388	\N	0	\N	\N	f	0	\N
1054	10	387	\N	0	\N	\N	f	0	\N
1055	10	386	\N	0	\N	\N	f	0	\N
1056	10	385	\N	0	\N	\N	f	0	\N
1057	10	384	\N	0	\N	\N	f	0	\N
1058	10	383	\N	0	\N	\N	f	0	\N
1059	10	382	\N	0	\N	\N	f	0	\N
1060	10	381	\N	0	\N	\N	f	0	\N
1061	10	380	\N	0	\N	\N	f	0	\N
1062	10	379	\N	0	\N	\N	f	0	\N
1063	10	378	\N	0	\N	\N	f	0	\N
1064	10	377	\N	0	\N	\N	f	0	\N
1065	10	376	\N	0	\N	\N	f	0	\N
1066	10	375	\N	0	\N	\N	f	0	\N
1067	10	374	\N	0	\N	\N	f	0	\N
1068	10	373	\N	0	\N	\N	f	0	\N
1069	10	372	\N	0	\N	\N	f	0	\N
1070	10	371	\N	0	\N	\N	f	0	\N
1071	10	370	\N	0	\N	\N	f	0	\N
1072	10	369	\N	0	\N	\N	f	0	\N
1073	10	368	\N	0	\N	\N	f	0	\N
1074	10	367	\N	0	\N	\N	f	0	\N
1075	10	366	\N	0	\N	\N	f	0	\N
1076	10	365	\N	0	\N	\N	f	0	\N
1077	10	364	\N	0	\N	\N	f	0	\N
1078	10	363	\N	0	\N	\N	f	0	\N
1079	10	362	\N	0	\N	\N	f	0	\N
1080	10	361	\N	0	\N	\N	f	0	\N
1081	10	39	\N	0	\N	\N	f	0	\N
1082	10	38	\N	0	\N	\N	f	0	\N
1083	10	37	\N	0	\N	\N	f	0	\N
1084	10	36	\N	0	\N	\N	f	0	\N
1085	10	35	\N	0	\N	\N	f	0	\N
1086	10	34	\N	0	\N	\N	f	0	\N
1087	10	33	\N	0	\N	\N	f	0	\N
1088	10	32	\N	0	\N	\N	f	0	\N
1089	10	31	\N	0	\N	\N	f	0	\N
1090	10	30	\N	0	\N	\N	f	0	\N
1091	10	29	\N	0	\N	\N	f	0	\N
1092	10	28	\N	0	\N	\N	f	0	\N
1093	10	27	\N	0	\N	\N	f	0	\N
1094	10	26	\N	0	\N	\N	f	0	\N
1095	10	25	\N	0	\N	\N	f	0	\N
1096	10	24	\N	0	\N	\N	f	0	\N
1097	10	23	\N	0	\N	\N	f	0	\N
1098	10	22	\N	0	\N	\N	f	0	\N
1099	10	21	\N	0	\N	\N	f	0	\N
1100	10	20	\N	0	\N	\N	f	0	\N
1101	10	19	\N	0	\N	\N	f	0	\N
1102	10	18	\N	0	\N	\N	f	0	\N
1103	10	17	\N	0	\N	\N	f	0	\N
1104	10	16	\N	0	\N	\N	f	0	\N
1105	10	15	\N	0	\N	\N	f	0	\N
1106	10	14	\N	0	\N	\N	f	0	\N
1107	10	13	\N	0	\N	\N	f	0	\N
1108	10	12	\N	0	\N	\N	f	0	\N
1109	10	11	\N	0	\N	\N	f	0	\N
1110	10	10	\N	0	\N	\N	f	0	\N
1111	10	9	\N	0	\N	\N	f	0	\N
1112	10	8	\N	0	\N	\N	f	0	\N
1113	10	7	\N	0	\N	\N	f	0	\N
1114	10	6	\N	0	\N	\N	f	0	\N
1115	10	5	\N	0	\N	\N	f	0	\N
1116	10	4	\N	0	\N	\N	f	0	\N
1117	10	3	\N	0	\N	\N	f	0	\N
1118	10	2	\N	0	\N	\N	f	0	\N
1119	10	1	\N	0	\N	\N	f	0	\N
1120	10	323	\N	0	\N	\N	f	0	\N
1121	10	322	\N	0	\N	\N	f	0	\N
1122	10	321	\N	0	\N	\N	f	0	\N
1123	10	320	\N	0	\N	\N	f	0	\N
1124	10	319	\N	0	\N	\N	f	0	\N
1125	10	318	\N	0	\N	\N	f	0	\N
1126	10	317	\N	0	\N	\N	f	0	\N
1127	10	316	\N	0	\N	\N	f	0	\N
1128	10	315	\N	0	\N	\N	f	0	\N
1129	10	314	\N	0	\N	\N	f	0	\N
1130	10	313	\N	0	\N	\N	f	0	\N
1131	10	312	\N	0	\N	\N	f	0	\N
1132	10	311	\N	0	\N	\N	f	0	\N
1133	10	310	\N	0	\N	\N	f	0	\N
1134	10	309	\N	0	\N	\N	f	0	\N
1135	10	308	\N	0	\N	\N	f	0	\N
1136	10	307	\N	0	\N	\N	f	0	\N
1137	10	306	\N	0	\N	\N	f	0	\N
1138	10	305	\N	0	\N	\N	f	0	\N
1139	10	304	\N	0	\N	\N	f	0	\N
1140	10	303	\N	0	\N	\N	f	0	\N
1141	10	302	\N	0	\N	\N	f	0	\N
1142	10	301	\N	0	\N	\N	f	0	\N
1143	10	300	\N	0	\N	\N	f	0	\N
1144	10	299	\N	0	\N	\N	f	0	\N
1145	10	298	\N	0	\N	\N	f	0	\N
1146	10	297	\N	0	\N	\N	f	0	\N
1147	10	296	\N	0	\N	\N	f	0	\N
1148	10	295	\N	0	\N	\N	f	0	\N
1149	10	294	\N	0	\N	\N	f	0	\N
1150	10	293	\N	0	\N	\N	f	0	\N
1151	10	292	\N	0	\N	\N	f	0	\N
1152	10	291	\N	0	\N	\N	f	0	\N
1153	10	218	\N	0	\N	\N	f	0	\N
1154	10	217	\N	0	\N	\N	f	0	\N
1155	10	216	\N	0	\N	\N	f	0	\N
1156	10	215	\N	0	\N	\N	f	0	\N
1157	10	214	\N	0	\N	\N	f	0	\N
1158	10	213	\N	0	\N	\N	f	0	\N
1159	10	212	\N	0	\N	\N	f	0	\N
1160	10	211	\N	0	\N	\N	f	0	\N
1161	10	210	\N	0	\N	\N	f	0	\N
1162	10	209	\N	0	\N	\N	f	0	\N
1163	10	208	\N	0	\N	\N	f	0	\N
1164	10	207	\N	0	\N	\N	f	0	\N
1165	10	206	\N	0	\N	\N	f	0	\N
1166	10	205	\N	0	\N	\N	f	0	\N
1167	10	204	\N	0	\N	\N	f	0	\N
1168	10	203	\N	0	\N	\N	f	0	\N
1169	10	202	\N	0	\N	\N	f	0	\N
1170	10	201	\N	0	\N	\N	f	0	\N
1171	10	200	\N	0	\N	\N	f	0	\N
1172	10	199	\N	0	\N	\N	f	0	\N
1173	10	198	\N	0	\N	\N	f	0	\N
1174	10	197	\N	0	\N	\N	f	0	\N
1175	10	196	\N	0	\N	\N	f	0	\N
1176	10	195	\N	0	\N	\N	f	0	\N
1177	10	194	\N	0	\N	\N	f	0	\N
1178	10	193	\N	0	\N	\N	f	0	\N
1179	10	192	\N	0	\N	\N	f	0	\N
1180	10	191	\N	0	\N	\N	f	0	\N
1181	10	190	\N	0	\N	\N	f	0	\N
1182	10	189	\N	0	\N	\N	f	0	\N
1183	10	188	\N	0	\N	\N	f	0	\N
1184	10	187	\N	0	\N	\N	f	0	\N
1185	10	186	\N	0	\N	\N	f	0	\N
1186	10	185	\N	0	\N	\N	f	0	\N
1187	10	184	\N	0	\N	\N	f	0	\N
1188	10	183	\N	0	\N	\N	f	0	\N
1189	10	182	\N	0	\N	\N	f	0	\N
1190	10	181	\N	0	\N	\N	f	0	\N
1191	10	109	\N	0	\N	\N	f	0	\N
1192	10	108	\N	0	\N	\N	f	0	\N
1193	10	107	\N	0	\N	\N	f	0	\N
1194	10	106	\N	0	\N	\N	f	0	\N
1195	10	105	\N	0	\N	\N	f	0	\N
1196	10	104	\N	0	\N	\N	f	0	\N
1197	10	103	\N	0	\N	\N	f	0	\N
1198	10	102	\N	0	\N	\N	f	0	\N
1199	10	101	\N	0	\N	\N	f	0	\N
1200	10	100	\N	0	\N	\N	f	0	\N
1201	10	99	\N	0	\N	\N	f	0	\N
1202	10	98	\N	0	\N	\N	f	0	\N
1203	10	97	\N	0	\N	\N	f	0	\N
1204	10	96	\N	0	\N	\N	f	0	\N
1205	10	95	\N	0	\N	\N	f	0	\N
1206	10	94	\N	0	\N	\N	f	0	\N
1207	10	93	\N	0	\N	\N	f	0	\N
1208	10	92	\N	0	\N	\N	f	0	\N
1209	10	91	\N	0	\N	\N	f	0	\N
1210	10	90	\N	0	\N	\N	f	0	\N
1211	10	89	\N	0	\N	\N	f	0	\N
1212	10	88	\N	0	\N	\N	f	0	\N
1213	10	87	\N	0	\N	\N	f	0	\N
1214	10	86	\N	0	\N	\N	f	0	\N
1215	10	85	\N	0	\N	\N	f	0	\N
1216	10	84	\N	0	\N	\N	f	0	\N
1217	10	83	\N	0	\N	\N	f	0	\N
1218	10	82	\N	0	\N	\N	f	0	\N
1219	10	81	\N	0	\N	\N	f	0	\N
1220	10	80	\N	0	\N	\N	f	0	\N
1221	10	79	\N	0	\N	\N	f	0	\N
1222	10	78	\N	0	\N	\N	f	0	\N
1223	10	77	\N	0	\N	\N	f	0	\N
1224	10	76	\N	0	\N	\N	f	0	\N
1225	10	75	\N	0	\N	\N	f	0	\N
1226	10	290	\N	0	\N	\N	f	0	\N
1227	10	289	\N	0	\N	\N	f	0	\N
1228	10	288	\N	0	\N	\N	f	0	\N
1229	10	287	\N	0	\N	\N	f	0	\N
1230	10	286	\N	0	\N	\N	f	0	\N
1231	10	285	\N	0	\N	\N	f	0	\N
1232	10	284	\N	0	\N	\N	f	0	\N
1233	10	283	\N	0	\N	\N	f	0	\N
1234	10	282	\N	0	\N	\N	f	0	\N
1235	10	281	\N	0	\N	\N	f	0	\N
1236	10	280	\N	0	\N	\N	f	0	\N
1237	10	279	\N	0	\N	\N	f	0	\N
1238	10	278	\N	0	\N	\N	f	0	\N
1239	10	277	\N	0	\N	\N	f	0	\N
1240	10	276	\N	0	\N	\N	f	0	\N
1241	10	275	\N	0	\N	\N	f	0	\N
1242	10	274	\N	0	\N	\N	f	0	\N
1243	10	273	\N	0	\N	\N	f	0	\N
1244	10	272	\N	0	\N	\N	f	0	\N
1245	10	271	\N	0	\N	\N	f	0	\N
1246	10	270	\N	0	\N	\N	f	0	\N
1247	10	269	\N	0	\N	\N	f	0	\N
1248	10	268	\N	0	\N	\N	f	0	\N
1249	10	267	\N	0	\N	\N	f	0	\N
1250	10	266	\N	0	\N	\N	f	0	\N
1251	10	265	\N	0	\N	\N	f	0	\N
1252	10	264	\N	0	\N	\N	f	0	\N
1253	10	263	\N	0	\N	\N	f	0	\N
1254	10	262	\N	0	\N	\N	f	0	\N
1255	10	261	\N	0	\N	\N	f	0	\N
1256	10	260	\N	0	\N	\N	f	0	\N
1257	10	259	\N	0	\N	\N	f	0	\N
1258	10	258	\N	0	\N	\N	f	0	\N
1259	10	257	\N	0	\N	\N	f	0	\N
1260	10	256	\N	0	\N	\N	f	0	\N
1261	10	255	\N	0	\N	\N	f	0	\N
1262	10	254	\N	0	\N	\N	f	0	\N
1263	10	253	\N	0	\N	\N	f	0	\N
1264	10	252	\N	0	\N	\N	f	0	\N
1265	10	251	\N	0	\N	\N	f	0	\N
1266	10	250	\N	0	\N	\N	f	0	\N
1267	10	249	\N	0	\N	\N	f	0	\N
1268	10	248	\N	0	\N	\N	f	0	\N
1269	10	247	\N	0	\N	\N	f	0	\N
1270	10	246	\N	0	\N	\N	f	0	\N
1271	10	245	\N	0	\N	\N	f	0	\N
1272	10	244	\N	0	\N	\N	f	0	\N
1273	10	243	\N	0	\N	\N	f	0	\N
1274	10	242	\N	0	\N	\N	f	0	\N
1275	10	241	\N	0	\N	\N	f	0	\N
1276	10	240	\N	0	\N	\N	f	0	\N
1277	10	239	\N	0	\N	\N	f	0	\N
1278	10	238	\N	0	\N	\N	f	0	\N
1279	10	237	\N	0	\N	\N	f	0	\N
1280	10	236	\N	0	\N	\N	f	0	\N
1281	10	235	\N	0	\N	\N	f	0	\N
1282	10	234	\N	0	\N	\N	f	0	\N
1283	10	233	\N	0	\N	\N	f	0	\N
1284	10	232	\N	0	\N	\N	f	0	\N
1285	10	231	\N	0	\N	\N	f	0	\N
1286	10	230	\N	0	\N	\N	f	0	\N
1287	10	229	\N	0	\N	\N	f	0	\N
1288	10	228	\N	0	\N	\N	f	0	\N
1289	10	227	\N	0	\N	\N	f	0	\N
1290	10	226	\N	0	\N	\N	f	0	\N
1291	10	225	\N	0	\N	\N	f	0	\N
1292	10	224	\N	0	\N	\N	f	0	\N
1293	10	223	\N	0	\N	\N	f	0	\N
1294	10	222	\N	0	\N	\N	f	0	\N
1295	10	221	\N	0	\N	\N	f	0	\N
1296	10	220	\N	0	\N	\N	f	0	\N
1297	10	219	\N	0	\N	\N	f	0	\N
1298	11	145	\N	0	\N	\N	f	0	\N
1299	11	144	\N	0	\N	\N	f	0	\N
1300	11	143	\N	0	\N	\N	f	0	\N
1301	11	142	\N	0	\N	\N	f	0	\N
1302	11	141	\N	0	\N	\N	f	0	\N
1303	11	140	\N	0	\N	\N	f	0	\N
1304	11	139	\N	0	\N	\N	f	0	\N
1305	11	138	\N	0	\N	\N	f	0	\N
1306	11	137	\N	0	\N	\N	f	0	\N
1307	11	136	\N	0	\N	\N	f	0	\N
1308	11	135	\N	0	\N	\N	f	0	\N
1309	11	134	\N	0	\N	\N	f	0	\N
1310	11	133	\N	0	\N	\N	f	0	\N
1311	11	132	\N	0	\N	\N	f	0	\N
1312	11	131	\N	0	\N	\N	f	0	\N
1313	11	130	\N	0	\N	\N	f	0	\N
1314	11	129	\N	0	\N	\N	f	0	\N
1315	11	128	\N	0	\N	\N	f	0	\N
1316	11	127	\N	0	\N	\N	f	0	\N
1317	11	126	\N	0	\N	\N	f	0	\N
1318	11	125	\N	0	\N	\N	f	0	\N
1319	11	124	\N	0	\N	\N	f	0	\N
1320	11	123	\N	0	\N	\N	f	0	\N
1321	11	122	\N	0	\N	\N	f	0	\N
1322	11	121	\N	0	\N	\N	f	0	\N
1323	11	120	\N	0	\N	\N	f	0	\N
1324	11	119	\N	0	\N	\N	f	0	\N
1325	11	118	\N	0	\N	\N	f	0	\N
1326	11	117	\N	0	\N	\N	f	0	\N
1327	11	116	\N	0	\N	\N	f	0	\N
1328	11	115	\N	0	\N	\N	f	0	\N
1329	11	114	\N	0	\N	\N	f	0	\N
1330	11	113	\N	0	\N	\N	f	0	\N
1331	11	112	\N	0	\N	\N	f	0	\N
1332	11	111	\N	0	\N	\N	f	0	\N
1333	11	110	\N	0	\N	\N	f	0	\N
1334	12	432	\N	0	\N	\N	f	0	\N
1335	12	431	\N	0	\N	\N	f	0	\N
1336	12	430	\N	0	\N	\N	f	0	\N
1337	12	429	\N	0	\N	\N	f	0	\N
1338	12	428	\N	0	\N	\N	f	0	\N
1339	12	427	\N	0	\N	\N	f	0	\N
1340	12	426	\N	0	\N	\N	f	0	\N
1341	12	425	\N	0	\N	\N	f	0	\N
1342	12	424	\N	0	\N	\N	f	0	\N
1343	12	423	\N	0	\N	\N	f	0	\N
1344	12	422	\N	0	\N	\N	f	0	\N
1345	12	421	\N	0	\N	\N	f	0	\N
1346	12	420	\N	0	\N	\N	f	0	\N
1347	12	419	\N	0	\N	\N	f	0	\N
1348	12	418	\N	0	\N	\N	f	0	\N
1349	12	417	\N	0	\N	\N	f	0	\N
1350	12	416	\N	0	\N	\N	f	0	\N
1351	12	415	\N	0	\N	\N	f	0	\N
1352	12	414	\N	0	\N	\N	f	0	\N
1353	12	413	\N	0	\N	\N	f	0	\N
1354	12	412	\N	0	\N	\N	f	0	\N
1355	12	411	\N	0	\N	\N	f	0	\N
1356	12	410	\N	0	\N	\N	f	0	\N
1357	12	409	\N	0	\N	\N	f	0	\N
1358	12	408	\N	0	\N	\N	f	0	\N
1359	12	407	\N	0	\N	\N	f	0	\N
1360	12	406	\N	0	\N	\N	f	0	\N
1361	12	405	\N	0	\N	\N	f	0	\N
1362	12	404	\N	0	\N	\N	f	0	\N
1363	12	403	\N	0	\N	\N	f	0	\N
1364	12	402	\N	0	\N	\N	f	0	\N
1365	12	360	\N	0	\N	\N	f	0	\N
1366	12	359	\N	0	\N	\N	f	0	\N
1367	12	358	\N	0	\N	\N	f	0	\N
1368	12	357	\N	0	\N	\N	f	0	\N
1369	12	356	\N	0	\N	\N	f	0	\N
1370	12	355	\N	0	\N	\N	f	0	\N
1371	12	354	\N	0	\N	\N	f	0	\N
1372	12	353	\N	0	\N	\N	f	0	\N
1373	12	352	\N	0	\N	\N	f	0	\N
1374	12	351	\N	0	\N	\N	f	0	\N
1375	12	350	\N	0	\N	\N	f	0	\N
1376	12	349	\N	0	\N	\N	f	0	\N
1377	12	348	\N	0	\N	\N	f	0	\N
1378	12	347	\N	0	\N	\N	f	0	\N
1379	12	346	\N	0	\N	\N	f	0	\N
1380	12	345	\N	0	\N	\N	f	0	\N
1381	12	344	\N	0	\N	\N	f	0	\N
1382	12	343	\N	0	\N	\N	f	0	\N
1383	12	342	\N	0	\N	\N	f	0	\N
1384	12	341	\N	0	\N	\N	f	0	\N
1385	12	340	\N	0	\N	\N	f	0	\N
1386	12	339	\N	0	\N	\N	f	0	\N
1387	12	338	\N	0	\N	\N	f	0	\N
1388	12	337	\N	0	\N	\N	f	0	\N
1389	12	336	\N	0	\N	\N	f	0	\N
1390	12	335	\N	0	\N	\N	f	0	\N
1391	12	334	\N	0	\N	\N	f	0	\N
1392	12	333	\N	0	\N	\N	f	0	\N
1393	12	332	\N	0	\N	\N	f	0	\N
1394	12	331	\N	0	\N	\N	f	0	\N
1395	12	330	\N	0	\N	\N	f	0	\N
1396	12	329	\N	0	\N	\N	f	0	\N
1397	12	328	\N	0	\N	\N	f	0	\N
1398	12	327	\N	0	\N	\N	f	0	\N
1399	12	326	\N	0	\N	\N	f	0	\N
1400	12	325	\N	0	\N	\N	f	0	\N
1401	12	324	\N	0	\N	\N	f	0	\N
1402	12	290	\N	0	\N	\N	f	0	\N
1403	12	289	\N	0	\N	\N	f	0	\N
1404	12	288	\N	0	\N	\N	f	0	\N
1405	12	287	\N	0	\N	\N	f	0	\N
1406	12	286	\N	0	\N	\N	f	0	\N
1407	12	285	\N	0	\N	\N	f	0	\N
1408	12	284	\N	0	\N	\N	f	0	\N
1409	12	283	\N	0	\N	\N	f	0	\N
1410	12	282	\N	0	\N	\N	f	0	\N
1411	12	281	\N	0	\N	\N	f	0	\N
1412	12	280	\N	0	\N	\N	f	0	\N
1413	12	279	\N	0	\N	\N	f	0	\N
1414	12	278	\N	0	\N	\N	f	0	\N
1415	12	277	\N	0	\N	\N	f	0	\N
1416	12	276	\N	0	\N	\N	f	0	\N
1417	12	275	\N	0	\N	\N	f	0	\N
1418	12	274	\N	0	\N	\N	f	0	\N
1419	12	273	\N	0	\N	\N	f	0	\N
1420	12	272	\N	0	\N	\N	f	0	\N
1421	12	271	\N	0	\N	\N	f	0	\N
1422	12	270	\N	0	\N	\N	f	0	\N
1423	12	269	\N	0	\N	\N	f	0	\N
1424	12	268	\N	0	\N	\N	f	0	\N
1425	12	267	\N	0	\N	\N	f	0	\N
1426	12	266	\N	0	\N	\N	f	0	\N
1427	12	265	\N	0	\N	\N	f	0	\N
1428	12	264	\N	0	\N	\N	f	0	\N
1429	12	263	\N	0	\N	\N	f	0	\N
1430	12	262	\N	0	\N	\N	f	0	\N
1431	12	261	\N	0	\N	\N	f	0	\N
1432	12	260	\N	0	\N	\N	f	0	\N
1433	12	259	\N	0	\N	\N	f	0	\N
1434	12	258	\N	0	\N	\N	f	0	\N
1435	12	257	\N	0	\N	\N	f	0	\N
1436	12	256	\N	0	\N	\N	f	0	\N
1437	12	255	\N	0	\N	\N	f	0	\N
1438	12	39	\N	0	\N	\N	f	0	\N
1439	12	38	\N	0	\N	\N	f	0	\N
1440	12	37	\N	0	\N	\N	f	0	\N
1441	12	36	\N	0	\N	\N	f	0	\N
1442	12	35	\N	0	\N	\N	f	0	\N
1443	12	34	\N	0	\N	\N	f	0	\N
1444	12	33	\N	0	\N	\N	f	0	\N
1445	12	32	\N	0	\N	\N	f	0	\N
1446	12	31	\N	0	\N	\N	f	0	\N
1447	12	30	\N	0	\N	\N	f	0	\N
1448	12	29	\N	0	\N	\N	f	0	\N
1449	12	28	\N	0	\N	\N	f	0	\N
1450	12	27	\N	0	\N	\N	f	0	\N
1451	12	26	\N	0	\N	\N	f	0	\N
1452	12	25	\N	0	\N	\N	f	0	\N
1453	12	24	\N	0	\N	\N	f	0	\N
1454	12	23	\N	0	\N	\N	f	0	\N
1455	12	22	\N	0	\N	\N	f	0	\N
1456	12	21	\N	0	\N	\N	f	0	\N
1457	12	20	\N	0	\N	\N	f	0	\N
1458	12	19	\N	0	\N	\N	f	0	\N
1459	12	18	\N	0	\N	\N	f	0	\N
1460	12	17	\N	0	\N	\N	f	0	\N
1461	12	16	\N	0	\N	\N	f	0	\N
1462	12	15	\N	0	\N	\N	f	0	\N
1463	12	14	\N	0	\N	\N	f	0	\N
1464	12	13	\N	0	\N	\N	f	0	\N
1465	12	12	\N	0	\N	\N	f	0	\N
1466	12	11	\N	0	\N	\N	f	0	\N
1467	12	10	\N	0	\N	\N	f	0	\N
1468	12	9	\N	0	\N	\N	f	0	\N
1469	12	8	\N	0	\N	\N	f	0	\N
1470	12	7	\N	0	\N	\N	f	0	\N
1471	12	6	\N	0	\N	\N	f	0	\N
1472	12	5	\N	0	\N	\N	f	0	\N
1473	12	4	\N	0	\N	\N	f	0	\N
1474	12	3	\N	0	\N	\N	f	0	\N
1475	12	2	\N	0	\N	\N	f	0	\N
1476	12	1	\N	0	\N	\N	f	0	\N
1477	12	180	\N	0	\N	\N	f	0	\N
1478	12	179	\N	0	\N	\N	f	0	\N
1479	12	178	\N	0	\N	\N	f	0	\N
1480	12	177	\N	0	\N	\N	f	0	\N
1481	12	176	\N	0	\N	\N	f	0	\N
1482	12	175	\N	0	\N	\N	f	0	\N
1483	12	174	\N	0	\N	\N	f	0	\N
1484	12	173	\N	0	\N	\N	f	0	\N
1485	12	172	\N	0	\N	\N	f	0	\N
1486	12	171	\N	0	\N	\N	f	0	\N
1487	12	170	\N	0	\N	\N	f	0	\N
1488	12	169	\N	0	\N	\N	f	0	\N
1489	12	168	\N	0	\N	\N	f	0	\N
1490	12	167	\N	0	\N	\N	f	0	\N
1491	12	166	\N	0	\N	\N	f	0	\N
1492	12	165	\N	0	\N	\N	f	0	\N
1493	12	164	\N	0	\N	\N	f	0	\N
1494	12	163	\N	0	\N	\N	f	0	\N
1495	12	162	\N	0	\N	\N	f	0	\N
1496	12	161	\N	0	\N	\N	f	0	\N
1497	12	160	\N	0	\N	\N	f	0	\N
1498	12	159	\N	0	\N	\N	f	0	\N
1499	12	158	\N	0	\N	\N	f	0	\N
1500	12	157	\N	0	\N	\N	f	0	\N
1501	12	156	\N	0	\N	\N	f	0	\N
1502	12	155	\N	0	\N	\N	f	0	\N
1503	12	154	\N	0	\N	\N	f	0	\N
1504	12	153	\N	0	\N	\N	f	0	\N
1505	12	152	\N	0	\N	\N	f	0	\N
1506	12	151	\N	0	\N	\N	f	0	\N
1507	12	150	\N	0	\N	\N	f	0	\N
1508	12	149	\N	0	\N	\N	f	0	\N
1509	12	148	\N	0	\N	\N	f	0	\N
1510	12	147	\N	0	\N	\N	f	0	\N
1511	12	146	\N	0	\N	\N	f	0	\N
1512	12	254	\N	0	\N	\N	f	0	\N
1513	12	253	\N	0	\N	\N	f	0	\N
1514	12	252	\N	0	\N	\N	f	0	\N
1515	12	251	\N	0	\N	\N	f	0	\N
1516	12	250	\N	0	\N	\N	f	0	\N
1517	12	249	\N	0	\N	\N	f	0	\N
1518	12	248	\N	0	\N	\N	f	0	\N
1519	12	247	\N	0	\N	\N	f	0	\N
1520	12	246	\N	0	\N	\N	f	0	\N
1521	12	245	\N	0	\N	\N	f	0	\N
1522	12	244	\N	0	\N	\N	f	0	\N
1523	12	243	\N	0	\N	\N	f	0	\N
1524	12	242	\N	0	\N	\N	f	0	\N
1525	12	241	\N	0	\N	\N	f	0	\N
1526	12	240	\N	0	\N	\N	f	0	\N
1527	12	239	\N	0	\N	\N	f	0	\N
1528	12	238	\N	0	\N	\N	f	0	\N
1529	12	237	\N	0	\N	\N	f	0	\N
1530	12	236	\N	0	\N	\N	f	0	\N
1531	12	235	\N	0	\N	\N	f	0	\N
1532	12	234	\N	0	\N	\N	f	0	\N
1533	12	233	\N	0	\N	\N	f	0	\N
1534	12	232	\N	0	\N	\N	f	0	\N
1535	12	231	\N	0	\N	\N	f	0	\N
1536	12	230	\N	0	\N	\N	f	0	\N
1537	12	229	\N	0	\N	\N	f	0	\N
1538	12	228	\N	0	\N	\N	f	0	\N
1539	12	227	\N	0	\N	\N	f	0	\N
1540	12	226	\N	0	\N	\N	f	0	\N
1541	12	225	\N	0	\N	\N	f	0	\N
1542	12	224	\N	0	\N	\N	f	0	\N
1543	12	223	\N	0	\N	\N	f	0	\N
1544	12	222	\N	0	\N	\N	f	0	\N
1545	12	221	\N	0	\N	\N	f	0	\N
1546	12	220	\N	0	\N	\N	f	0	\N
1547	12	219	\N	0	\N	\N	f	0	\N
1548	12	218	\N	0	\N	\N	f	0	\N
1549	12	217	\N	0	\N	\N	f	0	\N
1550	12	216	\N	0	\N	\N	f	0	\N
1551	12	215	\N	0	\N	\N	f	0	\N
1552	12	214	\N	0	\N	\N	f	0	\N
1553	12	213	\N	0	\N	\N	f	0	\N
1554	12	212	\N	0	\N	\N	f	0	\N
1555	12	211	\N	0	\N	\N	f	0	\N
1556	12	210	\N	0	\N	\N	f	0	\N
1557	12	209	\N	0	\N	\N	f	0	\N
1558	12	208	\N	0	\N	\N	f	0	\N
1559	12	207	\N	0	\N	\N	f	0	\N
1560	12	206	\N	0	\N	\N	f	0	\N
1561	12	205	\N	0	\N	\N	f	0	\N
1562	12	204	\N	0	\N	\N	f	0	\N
1563	12	203	\N	0	\N	\N	f	0	\N
1564	12	202	\N	0	\N	\N	f	0	\N
1565	12	201	\N	0	\N	\N	f	0	\N
1566	12	200	\N	0	\N	\N	f	0	\N
1567	12	199	\N	0	\N	\N	f	0	\N
1568	12	198	\N	0	\N	\N	f	0	\N
1569	12	197	\N	0	\N	\N	f	0	\N
1570	12	196	\N	0	\N	\N	f	0	\N
1571	12	195	\N	0	\N	\N	f	0	\N
1572	12	194	\N	0	\N	\N	f	0	\N
1573	12	193	\N	0	\N	\N	f	0	\N
1574	12	192	\N	0	\N	\N	f	0	\N
1575	12	191	\N	0	\N	\N	f	0	\N
1576	12	190	\N	0	\N	\N	f	0	\N
1577	12	189	\N	0	\N	\N	f	0	\N
1578	12	188	\N	0	\N	\N	f	0	\N
1579	12	187	\N	0	\N	\N	f	0	\N
1580	12	186	\N	0	\N	\N	f	0	\N
1581	12	185	\N	0	\N	\N	f	0	\N
1582	12	184	\N	0	\N	\N	f	0	\N
1583	12	183	\N	0	\N	\N	f	0	\N
1584	12	182	\N	0	\N	\N	f	0	\N
1585	12	181	\N	0	\N	\N	f	0	\N
1586	13	360	\N	0	\N	\N	f	0	\N
1587	13	359	\N	0	\N	\N	f	0	\N
1588	13	358	\N	0	\N	\N	f	0	\N
1589	13	357	\N	0	\N	\N	f	0	\N
1590	13	356	\N	0	\N	\N	f	0	\N
1591	13	355	\N	0	\N	\N	f	0	\N
1592	13	354	\N	0	\N	\N	f	0	\N
1593	13	353	\N	0	\N	\N	f	0	\N
1594	13	352	\N	0	\N	\N	f	0	\N
1595	13	351	\N	0	\N	\N	f	0	\N
1596	13	350	\N	0	\N	\N	f	0	\N
1597	13	349	\N	0	\N	\N	f	0	\N
1598	13	348	\N	0	\N	\N	f	0	\N
1599	13	347	\N	0	\N	\N	f	0	\N
1600	13	346	\N	0	\N	\N	f	0	\N
1601	13	345	\N	0	\N	\N	f	0	\N
1602	13	344	\N	0	\N	\N	f	0	\N
1603	13	343	\N	0	\N	\N	f	0	\N
1604	13	342	\N	0	\N	\N	f	0	\N
1605	13	341	\N	0	\N	\N	f	0	\N
1606	13	340	\N	0	\N	\N	f	0	\N
1607	13	339	\N	0	\N	\N	f	0	\N
1608	13	338	\N	0	\N	\N	f	0	\N
1609	13	337	\N	0	\N	\N	f	0	\N
1610	13	336	\N	0	\N	\N	f	0	\N
1611	13	335	\N	0	\N	\N	f	0	\N
1612	13	334	\N	0	\N	\N	f	0	\N
1613	13	333	\N	0	\N	\N	f	0	\N
1614	13	332	\N	0	\N	\N	f	0	\N
1615	13	331	\N	0	\N	\N	f	0	\N
1616	13	330	\N	0	\N	\N	f	0	\N
1617	13	329	\N	0	\N	\N	f	0	\N
1618	13	328	\N	0	\N	\N	f	0	\N
1619	13	327	\N	0	\N	\N	f	0	\N
1620	13	326	\N	0	\N	\N	f	0	\N
1621	13	325	\N	0	\N	\N	f	0	\N
1622	13	324	\N	0	\N	\N	f	0	\N
1623	13	218	\N	0	\N	\N	f	0	\N
1624	13	217	\N	0	\N	\N	f	0	\N
1625	13	216	\N	0	\N	\N	f	0	\N
1626	13	215	\N	0	\N	\N	f	0	\N
1627	13	214	\N	0	\N	\N	f	0	\N
1628	13	213	\N	0	\N	\N	f	0	\N
1629	13	212	\N	0	\N	\N	f	0	\N
1630	13	211	\N	0	\N	\N	f	0	\N
1631	13	210	\N	0	\N	\N	f	0	\N
1632	13	209	\N	0	\N	\N	f	0	\N
1633	13	208	\N	0	\N	\N	f	0	\N
1634	13	207	\N	0	\N	\N	f	0	\N
1635	13	206	\N	0	\N	\N	f	0	\N
1636	13	205	\N	0	\N	\N	f	0	\N
1637	13	204	\N	0	\N	\N	f	0	\N
1638	13	203	\N	0	\N	\N	f	0	\N
1639	13	202	\N	0	\N	\N	f	0	\N
1640	13	201	\N	0	\N	\N	f	0	\N
1641	13	200	\N	0	\N	\N	f	0	\N
1642	13	199	\N	0	\N	\N	f	0	\N
1643	13	198	\N	0	\N	\N	f	0	\N
1644	13	197	\N	0	\N	\N	f	0	\N
1645	13	196	\N	0	\N	\N	f	0	\N
1646	13	195	\N	0	\N	\N	f	0	\N
1647	13	194	\N	0	\N	\N	f	0	\N
1648	13	193	\N	0	\N	\N	f	0	\N
1649	13	192	\N	0	\N	\N	f	0	\N
1650	13	191	\N	0	\N	\N	f	0	\N
1651	13	190	\N	0	\N	\N	f	0	\N
1652	13	189	\N	0	\N	\N	f	0	\N
1653	13	188	\N	0	\N	\N	f	0	\N
1654	13	187	\N	0	\N	\N	f	0	\N
1655	13	186	\N	0	\N	\N	f	0	\N
1656	13	185	\N	0	\N	\N	f	0	\N
1657	13	184	\N	0	\N	\N	f	0	\N
1658	13	183	\N	0	\N	\N	f	0	\N
1659	13	182	\N	0	\N	\N	f	0	\N
1660	13	181	\N	0	\N	\N	f	0	\N
1661	15	145	\N	0	\N	\N	f	0	\N
1662	15	144	\N	0	\N	\N	f	0	\N
1663	15	143	\N	0	\N	\N	f	0	\N
1664	15	142	\N	0	\N	\N	f	0	\N
1665	15	141	\N	0	\N	\N	f	0	\N
1666	15	140	\N	0	\N	\N	f	0	\N
1667	15	139	\N	0	\N	\N	f	0	\N
1668	15	138	\N	0	\N	\N	f	0	\N
1669	15	137	\N	0	\N	\N	f	0	\N
1670	15	136	\N	0	\N	\N	f	0	\N
1671	15	135	\N	0	\N	\N	f	0	\N
1672	15	134	\N	0	\N	\N	f	0	\N
1673	15	133	\N	0	\N	\N	f	0	\N
1674	15	132	\N	0	\N	\N	f	0	\N
1675	15	131	\N	0	\N	\N	f	0	\N
1676	15	130	\N	0	\N	\N	f	0	\N
1677	15	129	\N	0	\N	\N	f	0	\N
1678	15	128	\N	0	\N	\N	f	0	\N
1679	15	127	\N	0	\N	\N	f	0	\N
1680	15	126	\N	0	\N	\N	f	0	\N
1681	15	125	\N	0	\N	\N	f	0	\N
1682	15	124	\N	0	\N	\N	f	0	\N
1683	15	123	\N	0	\N	\N	f	0	\N
1684	15	122	\N	0	\N	\N	f	0	\N
1685	15	121	\N	0	\N	\N	f	0	\N
1686	15	120	\N	0	\N	\N	f	0	\N
1687	15	119	\N	0	\N	\N	f	0	\N
1688	15	118	\N	0	\N	\N	f	0	\N
1689	15	117	\N	0	\N	\N	f	0	\N
1690	15	116	\N	0	\N	\N	f	0	\N
1691	15	115	\N	0	\N	\N	f	0	\N
1692	15	114	\N	0	\N	\N	f	0	\N
1693	15	113	\N	0	\N	\N	f	0	\N
1694	15	112	\N	0	\N	\N	f	0	\N
1695	15	111	\N	0	\N	\N	f	0	\N
1696	15	110	\N	0	\N	\N	f	0	\N
1697	15	109	\N	0	\N	\N	f	0	\N
1698	15	108	\N	0	\N	\N	f	0	\N
1699	15	107	\N	0	\N	\N	f	0	\N
1700	15	106	\N	0	\N	\N	f	0	\N
1701	15	105	\N	0	\N	\N	f	0	\N
1702	15	104	\N	0	\N	\N	f	0	\N
1703	15	103	\N	0	\N	\N	f	0	\N
1704	15	102	\N	0	\N	\N	f	0	\N
1705	15	101	\N	0	\N	\N	f	0	\N
1706	15	100	\N	0	\N	\N	f	0	\N
1707	15	99	\N	0	\N	\N	f	0	\N
1708	15	98	\N	0	\N	\N	f	0	\N
1709	15	97	\N	0	\N	\N	f	0	\N
1710	15	96	\N	0	\N	\N	f	0	\N
1711	15	95	\N	0	\N	\N	f	0	\N
1712	15	94	\N	0	\N	\N	f	0	\N
1713	15	93	\N	0	\N	\N	f	0	\N
1714	15	92	\N	0	\N	\N	f	0	\N
1715	15	91	\N	0	\N	\N	f	0	\N
1716	15	90	\N	0	\N	\N	f	0	\N
1717	15	89	\N	0	\N	\N	f	0	\N
1718	15	88	\N	0	\N	\N	f	0	\N
1719	15	87	\N	0	\N	\N	f	0	\N
1720	15	86	\N	0	\N	\N	f	0	\N
1721	15	85	\N	0	\N	\N	f	0	\N
1722	15	84	\N	0	\N	\N	f	0	\N
1723	15	83	\N	0	\N	\N	f	0	\N
1724	15	82	\N	0	\N	\N	f	0	\N
1725	15	81	\N	0	\N	\N	f	0	\N
1726	15	80	\N	0	\N	\N	f	0	\N
1727	15	79	\N	0	\N	\N	f	0	\N
1728	15	78	\N	0	\N	\N	f	0	\N
1729	15	77	\N	0	\N	\N	f	0	\N
1730	15	76	\N	0	\N	\N	f	0	\N
1731	15	75	\N	0	\N	\N	f	0	\N
1732	15	290	\N	0	\N	\N	f	0	\N
1733	15	289	\N	0	\N	\N	f	0	\N
1734	15	288	\N	0	\N	\N	f	0	\N
1735	15	287	\N	0	\N	\N	f	0	\N
1736	15	286	\N	0	\N	\N	f	0	\N
1737	15	285	\N	0	\N	\N	f	0	\N
1738	15	284	\N	0	\N	\N	f	0	\N
1739	15	283	\N	0	\N	\N	f	0	\N
1740	15	282	\N	0	\N	\N	f	0	\N
1741	15	281	\N	0	\N	\N	f	0	\N
1742	15	280	\N	0	\N	\N	f	0	\N
1743	15	279	\N	0	\N	\N	f	0	\N
1744	15	278	\N	0	\N	\N	f	0	\N
1745	15	277	\N	0	\N	\N	f	0	\N
1746	15	276	\N	0	\N	\N	f	0	\N
1747	15	275	\N	0	\N	\N	f	0	\N
1748	15	274	\N	0	\N	\N	f	0	\N
1749	15	273	\N	0	\N	\N	f	0	\N
1750	15	272	\N	0	\N	\N	f	0	\N
1751	15	271	\N	0	\N	\N	f	0	\N
1752	15	270	\N	0	\N	\N	f	0	\N
1753	15	269	\N	0	\N	\N	f	0	\N
1754	15	268	\N	0	\N	\N	f	0	\N
1755	15	267	\N	0	\N	\N	f	0	\N
1756	15	266	\N	0	\N	\N	f	0	\N
1757	15	265	\N	0	\N	\N	f	0	\N
1758	15	264	\N	0	\N	\N	f	0	\N
1759	15	263	\N	0	\N	\N	f	0	\N
1760	15	262	\N	0	\N	\N	f	0	\N
1761	15	261	\N	0	\N	\N	f	0	\N
1762	15	260	\N	0	\N	\N	f	0	\N
1763	15	259	\N	0	\N	\N	f	0	\N
1764	15	258	\N	0	\N	\N	f	0	\N
1765	15	257	\N	0	\N	\N	f	0	\N
1766	15	256	\N	0	\N	\N	f	0	\N
1767	15	255	\N	0	\N	\N	f	0	\N
1768	15	323	\N	0	\N	\N	f	0	\N
1769	15	322	\N	0	\N	\N	f	0	\N
1770	15	321	\N	0	\N	\N	f	0	\N
1771	15	320	\N	0	\N	\N	f	0	\N
1772	15	319	\N	0	\N	\N	f	0	\N
1773	15	318	\N	0	\N	\N	f	0	\N
1774	15	317	\N	0	\N	\N	f	0	\N
1775	15	316	\N	0	\N	\N	f	0	\N
1776	15	315	\N	0	\N	\N	f	0	\N
1777	15	314	\N	0	\N	\N	f	0	\N
1778	15	313	\N	0	\N	\N	f	0	\N
1779	15	312	\N	0	\N	\N	f	0	\N
1780	15	311	\N	0	\N	\N	f	0	\N
1781	15	310	\N	0	\N	\N	f	0	\N
1782	15	309	\N	0	\N	\N	f	0	\N
1783	15	308	\N	0	\N	\N	f	0	\N
1784	15	307	\N	0	\N	\N	f	0	\N
1785	15	306	\N	0	\N	\N	f	0	\N
1786	15	305	\N	0	\N	\N	f	0	\N
1787	15	304	\N	0	\N	\N	f	0	\N
1788	15	303	\N	0	\N	\N	f	0	\N
1789	15	302	\N	0	\N	\N	f	0	\N
1790	15	301	\N	0	\N	\N	f	0	\N
1791	15	300	\N	0	\N	\N	f	0	\N
1792	15	299	\N	0	\N	\N	f	0	\N
1793	15	298	\N	0	\N	\N	f	0	\N
1794	15	297	\N	0	\N	\N	f	0	\N
1795	15	296	\N	0	\N	\N	f	0	\N
1796	15	295	\N	0	\N	\N	f	0	\N
1797	15	294	\N	0	\N	\N	f	0	\N
1798	15	293	\N	0	\N	\N	f	0	\N
1799	15	292	\N	0	\N	\N	f	0	\N
1800	15	291	\N	0	\N	\N	f	0	\N
1801	16	218	\N	0	\N	\N	f	0	\N
1802	16	217	\N	0	\N	\N	f	0	\N
1803	16	216	\N	0	\N	\N	f	0	\N
1804	16	215	\N	0	\N	\N	f	0	\N
1805	16	214	\N	0	\N	\N	f	0	\N
1806	16	213	\N	0	\N	\N	f	0	\N
1807	16	212	\N	0	\N	\N	f	0	\N
1808	16	211	\N	0	\N	\N	f	0	\N
1809	16	210	\N	0	\N	\N	f	0	\N
1810	16	209	\N	0	\N	\N	f	0	\N
1811	16	208	\N	0	\N	\N	f	0	\N
1812	16	207	\N	0	\N	\N	f	0	\N
1813	16	206	\N	0	\N	\N	f	0	\N
1814	16	205	\N	0	\N	\N	f	0	\N
1815	16	204	\N	0	\N	\N	f	0	\N
1816	16	203	\N	0	\N	\N	f	0	\N
1817	16	202	\N	0	\N	\N	f	0	\N
1818	16	201	\N	0	\N	\N	f	0	\N
1819	16	200	\N	0	\N	\N	f	0	\N
1820	16	199	\N	0	\N	\N	f	0	\N
1821	16	198	\N	0	\N	\N	f	0	\N
1822	16	197	\N	0	\N	\N	f	0	\N
1823	16	196	\N	0	\N	\N	f	0	\N
1824	16	195	\N	0	\N	\N	f	0	\N
1825	16	194	\N	0	\N	\N	f	0	\N
1826	16	193	\N	0	\N	\N	f	0	\N
1827	16	192	\N	0	\N	\N	f	0	\N
1828	16	191	\N	0	\N	\N	f	0	\N
1829	16	190	\N	0	\N	\N	f	0	\N
1830	16	189	\N	0	\N	\N	f	0	\N
1831	16	188	\N	0	\N	\N	f	0	\N
1832	16	187	\N	0	\N	\N	f	0	\N
1833	16	186	\N	0	\N	\N	f	0	\N
1834	16	185	\N	0	\N	\N	f	0	\N
1835	16	184	\N	0	\N	\N	f	0	\N
1836	16	183	\N	0	\N	\N	f	0	\N
1837	16	182	\N	0	\N	\N	f	0	\N
1838	16	181	\N	0	\N	\N	f	0	\N
1839	16	74	\N	0	\N	\N	f	0	\N
1840	16	73	\N	0	\N	\N	f	0	\N
1841	16	72	\N	0	\N	\N	f	0	\N
1842	16	71	\N	0	\N	\N	f	0	\N
1843	16	70	\N	0	\N	\N	f	0	\N
1844	16	69	\N	0	\N	\N	f	0	\N
1845	16	68	\N	0	\N	\N	f	0	\N
1846	16	67	\N	0	\N	\N	f	0	\N
1847	16	66	\N	0	\N	\N	f	0	\N
1848	16	65	\N	0	\N	\N	f	0	\N
1849	16	64	\N	0	\N	\N	f	0	\N
1850	16	63	\N	0	\N	\N	f	0	\N
1851	16	62	\N	0	\N	\N	f	0	\N
1852	16	61	\N	0	\N	\N	f	0	\N
1853	16	60	\N	0	\N	\N	f	0	\N
1854	16	59	\N	0	\N	\N	f	0	\N
1855	16	58	\N	0	\N	\N	f	0	\N
1856	16	57	\N	0	\N	\N	f	0	\N
1857	16	56	\N	0	\N	\N	f	0	\N
1858	16	55	\N	0	\N	\N	f	0	\N
1859	16	54	\N	0	\N	\N	f	0	\N
1860	16	53	\N	0	\N	\N	f	0	\N
1861	16	52	\N	0	\N	\N	f	0	\N
1862	16	51	\N	0	\N	\N	f	0	\N
1863	16	50	\N	0	\N	\N	f	0	\N
1864	16	49	\N	0	\N	\N	f	0	\N
1865	16	48	\N	0	\N	\N	f	0	\N
1866	16	47	\N	0	\N	\N	f	0	\N
1867	16	46	\N	0	\N	\N	f	0	\N
1868	16	45	\N	0	\N	\N	f	0	\N
1869	16	44	\N	0	\N	\N	f	0	\N
1870	16	43	\N	0	\N	\N	f	0	\N
1871	16	42	\N	0	\N	\N	f	0	\N
1872	16	41	\N	0	\N	\N	f	0	\N
1873	16	40	\N	0	\N	\N	f	0	\N
1874	16	401	\N	0	\N	\N	f	0	\N
1875	16	400	\N	0	\N	\N	f	0	\N
1876	16	399	\N	0	\N	\N	f	0	\N
1877	16	398	\N	0	\N	\N	f	0	\N
1878	16	397	\N	0	\N	\N	f	0	\N
1879	16	396	\N	0	\N	\N	f	0	\N
1880	16	395	\N	0	\N	\N	f	0	\N
1881	16	394	\N	0	\N	\N	f	0	\N
1882	16	393	\N	0	\N	\N	f	0	\N
1883	16	392	\N	0	\N	\N	f	0	\N
1884	16	391	\N	0	\N	\N	f	0	\N
1885	16	390	\N	0	\N	\N	f	0	\N
1886	16	389	\N	0	\N	\N	f	0	\N
1887	16	388	\N	0	\N	\N	f	0	\N
1888	16	387	\N	0	\N	\N	f	0	\N
1889	16	386	\N	0	\N	\N	f	0	\N
1890	16	385	\N	0	\N	\N	f	0	\N
1891	16	384	\N	0	\N	\N	f	0	\N
1892	16	383	\N	0	\N	\N	f	0	\N
1893	16	382	\N	0	\N	\N	f	0	\N
1894	16	381	\N	0	\N	\N	f	0	\N
1895	16	380	\N	0	\N	\N	f	0	\N
1896	16	379	\N	0	\N	\N	f	0	\N
1897	16	378	\N	0	\N	\N	f	0	\N
1898	16	377	\N	0	\N	\N	f	0	\N
1899	16	376	\N	0	\N	\N	f	0	\N
1900	16	375	\N	0	\N	\N	f	0	\N
1901	16	374	\N	0	\N	\N	f	0	\N
1902	16	373	\N	0	\N	\N	f	0	\N
1903	16	372	\N	0	\N	\N	f	0	\N
1904	16	371	\N	0	\N	\N	f	0	\N
1905	16	370	\N	0	\N	\N	f	0	\N
1906	16	369	\N	0	\N	\N	f	0	\N
1907	16	368	\N	0	\N	\N	f	0	\N
1908	16	367	\N	0	\N	\N	f	0	\N
1909	16	366	\N	0	\N	\N	f	0	\N
1910	16	365	\N	0	\N	\N	f	0	\N
1911	16	364	\N	0	\N	\N	f	0	\N
1912	16	363	\N	0	\N	\N	f	0	\N
1913	16	362	\N	0	\N	\N	f	0	\N
1914	16	361	\N	0	\N	\N	f	0	\N
1915	16	290	\N	0	\N	\N	f	0	\N
1916	16	289	\N	0	\N	\N	f	0	\N
1917	16	288	\N	0	\N	\N	f	0	\N
1918	16	287	\N	0	\N	\N	f	0	\N
1919	16	286	\N	0	\N	\N	f	0	\N
1920	16	285	\N	0	\N	\N	f	0	\N
1921	16	284	\N	0	\N	\N	f	0	\N
1922	16	283	\N	0	\N	\N	f	0	\N
1923	16	282	\N	0	\N	\N	f	0	\N
1924	16	281	\N	0	\N	\N	f	0	\N
1925	16	280	\N	0	\N	\N	f	0	\N
1926	16	279	\N	0	\N	\N	f	0	\N
1927	16	278	\N	0	\N	\N	f	0	\N
1928	16	277	\N	0	\N	\N	f	0	\N
1929	16	276	\N	0	\N	\N	f	0	\N
1930	16	275	\N	0	\N	\N	f	0	\N
1931	16	274	\N	0	\N	\N	f	0	\N
1932	16	273	\N	0	\N	\N	f	0	\N
1933	16	272	\N	0	\N	\N	f	0	\N
1934	16	271	\N	0	\N	\N	f	0	\N
1935	16	270	\N	0	\N	\N	f	0	\N
1936	16	269	\N	0	\N	\N	f	0	\N
1937	16	268	\N	0	\N	\N	f	0	\N
1938	16	267	\N	0	\N	\N	f	0	\N
1939	16	266	\N	0	\N	\N	f	0	\N
1940	16	265	\N	0	\N	\N	f	0	\N
1941	16	264	\N	0	\N	\N	f	0	\N
1942	16	263	\N	0	\N	\N	f	0	\N
1943	16	262	\N	0	\N	\N	f	0	\N
1944	16	261	\N	0	\N	\N	f	0	\N
1945	16	260	\N	0	\N	\N	f	0	\N
1946	16	259	\N	0	\N	\N	f	0	\N
1947	16	258	\N	0	\N	\N	f	0	\N
1948	16	257	\N	0	\N	\N	f	0	\N
1949	16	256	\N	0	\N	\N	f	0	\N
1950	16	255	\N	0	\N	\N	f	0	\N
1951	17	401	\N	0	\N	\N	f	0	\N
1952	17	400	\N	0	\N	\N	f	0	\N
1953	17	399	\N	0	\N	\N	f	0	\N
1954	17	398	\N	0	\N	\N	f	0	\N
1955	17	397	\N	0	\N	\N	f	0	\N
1956	17	396	\N	0	\N	\N	f	0	\N
1957	17	395	\N	0	\N	\N	f	0	\N
1958	17	394	\N	0	\N	\N	f	0	\N
1959	17	393	\N	0	\N	\N	f	0	\N
1960	17	392	\N	0	\N	\N	f	0	\N
1961	17	391	\N	0	\N	\N	f	0	\N
1962	17	390	\N	0	\N	\N	f	0	\N
1963	17	389	\N	0	\N	\N	f	0	\N
1964	17	388	\N	0	\N	\N	f	0	\N
1965	17	387	\N	0	\N	\N	f	0	\N
1966	17	386	\N	0	\N	\N	f	0	\N
1967	17	385	\N	0	\N	\N	f	0	\N
1968	17	384	\N	0	\N	\N	f	0	\N
1969	17	383	\N	0	\N	\N	f	0	\N
1970	17	382	\N	0	\N	\N	f	0	\N
1971	17	381	\N	0	\N	\N	f	0	\N
1972	17	380	\N	0	\N	\N	f	0	\N
1973	17	379	\N	0	\N	\N	f	0	\N
1974	17	378	\N	0	\N	\N	f	0	\N
1975	17	377	\N	0	\N	\N	f	0	\N
1976	17	376	\N	0	\N	\N	f	0	\N
1977	17	375	\N	0	\N	\N	f	0	\N
1978	17	374	\N	0	\N	\N	f	0	\N
1979	17	373	\N	0	\N	\N	f	0	\N
1980	17	372	\N	0	\N	\N	f	0	\N
1981	17	371	\N	0	\N	\N	f	0	\N
1982	17	370	\N	0	\N	\N	f	0	\N
1983	17	369	\N	0	\N	\N	f	0	\N
1984	17	368	\N	0	\N	\N	f	0	\N
1985	17	367	\N	0	\N	\N	f	0	\N
1986	17	366	\N	0	\N	\N	f	0	\N
1987	17	365	\N	0	\N	\N	f	0	\N
1988	17	364	\N	0	\N	\N	f	0	\N
1989	17	363	\N	0	\N	\N	f	0	\N
1990	17	362	\N	0	\N	\N	f	0	\N
1991	17	361	\N	0	\N	\N	f	0	\N
1992	18	218	\N	0	\N	\N	f	0	\N
1993	18	217	\N	0	\N	\N	f	0	\N
1994	18	216	\N	0	\N	\N	f	0	\N
1995	18	215	\N	0	\N	\N	f	0	\N
1996	18	214	\N	0	\N	\N	f	0	\N
1997	18	213	\N	0	\N	\N	f	0	\N
1998	18	212	\N	0	\N	\N	f	0	\N
1999	18	211	\N	0	\N	\N	f	0	\N
2000	18	210	\N	0	\N	\N	f	0	\N
2001	18	209	\N	0	\N	\N	f	0	\N
2002	18	208	\N	0	\N	\N	f	0	\N
2003	18	207	\N	0	\N	\N	f	0	\N
2004	18	206	\N	0	\N	\N	f	0	\N
2005	18	205	\N	0	\N	\N	f	0	\N
2006	18	204	\N	0	\N	\N	f	0	\N
2007	18	203	\N	0	\N	\N	f	0	\N
2008	18	202	\N	0	\N	\N	f	0	\N
2009	18	201	\N	0	\N	\N	f	0	\N
2010	18	200	\N	0	\N	\N	f	0	\N
2011	18	199	\N	0	\N	\N	f	0	\N
2012	18	198	\N	0	\N	\N	f	0	\N
2013	18	197	\N	0	\N	\N	f	0	\N
2014	18	196	\N	0	\N	\N	f	0	\N
2015	18	195	\N	0	\N	\N	f	0	\N
2016	18	194	\N	0	\N	\N	f	0	\N
2017	18	193	\N	0	\N	\N	f	0	\N
2018	18	192	\N	0	\N	\N	f	0	\N
2019	18	191	\N	0	\N	\N	f	0	\N
2020	18	190	\N	0	\N	\N	f	0	\N
2021	18	189	\N	0	\N	\N	f	0	\N
2022	18	188	\N	0	\N	\N	f	0	\N
2023	18	187	\N	0	\N	\N	f	0	\N
2024	18	186	\N	0	\N	\N	f	0	\N
2025	18	185	\N	0	\N	\N	f	0	\N
2026	18	184	\N	0	\N	\N	f	0	\N
2027	18	183	\N	0	\N	\N	f	0	\N
2028	18	182	\N	0	\N	\N	f	0	\N
2029	18	181	\N	0	\N	\N	f	0	\N
2030	18	323	\N	0	\N	\N	f	0	\N
2031	18	322	\N	0	\N	\N	f	0	\N
2032	18	321	\N	0	\N	\N	f	0	\N
2033	18	320	\N	0	\N	\N	f	0	\N
2034	18	319	\N	0	\N	\N	f	0	\N
2035	18	318	\N	0	\N	\N	f	0	\N
2036	18	317	\N	0	\N	\N	f	0	\N
2037	18	316	\N	0	\N	\N	f	0	\N
2038	18	315	\N	0	\N	\N	f	0	\N
2039	18	314	\N	0	\N	\N	f	0	\N
2040	18	313	\N	0	\N	\N	f	0	\N
2041	18	312	\N	0	\N	\N	f	0	\N
2042	18	311	\N	0	\N	\N	f	0	\N
2043	18	310	\N	0	\N	\N	f	0	\N
2044	18	309	\N	0	\N	\N	f	0	\N
2045	18	308	\N	0	\N	\N	f	0	\N
2046	18	307	\N	0	\N	\N	f	0	\N
2047	18	306	\N	0	\N	\N	f	0	\N
2048	18	305	\N	0	\N	\N	f	0	\N
2049	18	304	\N	0	\N	\N	f	0	\N
2050	18	303	\N	0	\N	\N	f	0	\N
2051	18	302	\N	0	\N	\N	f	0	\N
2052	18	301	\N	0	\N	\N	f	0	\N
2053	18	300	\N	0	\N	\N	f	0	\N
2054	18	299	\N	0	\N	\N	f	0	\N
2055	18	298	\N	0	\N	\N	f	0	\N
2056	18	297	\N	0	\N	\N	f	0	\N
2057	18	296	\N	0	\N	\N	f	0	\N
2058	18	295	\N	0	\N	\N	f	0	\N
2059	18	294	\N	0	\N	\N	f	0	\N
2060	18	293	\N	0	\N	\N	f	0	\N
2061	18	292	\N	0	\N	\N	f	0	\N
2062	18	291	\N	0	\N	\N	f	0	\N
2063	18	109	\N	0	\N	\N	f	0	\N
2064	18	108	\N	0	\N	\N	f	0	\N
2065	18	107	\N	0	\N	\N	f	0	\N
2066	18	106	\N	0	\N	\N	f	0	\N
2067	18	105	\N	0	\N	\N	f	0	\N
2068	18	104	\N	0	\N	\N	f	0	\N
2069	18	103	\N	0	\N	\N	f	0	\N
2070	18	102	\N	0	\N	\N	f	0	\N
2071	18	101	\N	0	\N	\N	f	0	\N
2072	18	100	\N	0	\N	\N	f	0	\N
2073	18	99	\N	0	\N	\N	f	0	\N
2074	18	98	\N	0	\N	\N	f	0	\N
2075	18	97	\N	0	\N	\N	f	0	\N
2076	18	96	\N	0	\N	\N	f	0	\N
2077	18	95	\N	0	\N	\N	f	0	\N
2078	18	94	\N	0	\N	\N	f	0	\N
2079	18	93	\N	0	\N	\N	f	0	\N
2080	18	92	\N	0	\N	\N	f	0	\N
2081	18	91	\N	0	\N	\N	f	0	\N
2082	18	90	\N	0	\N	\N	f	0	\N
2083	18	89	\N	0	\N	\N	f	0	\N
2084	18	88	\N	0	\N	\N	f	0	\N
2085	18	87	\N	0	\N	\N	f	0	\N
2086	18	86	\N	0	\N	\N	f	0	\N
2087	18	85	\N	0	\N	\N	f	0	\N
2088	18	84	\N	0	\N	\N	f	0	\N
2089	18	83	\N	0	\N	\N	f	0	\N
2090	18	82	\N	0	\N	\N	f	0	\N
2091	18	81	\N	0	\N	\N	f	0	\N
2092	18	80	\N	0	\N	\N	f	0	\N
2093	18	79	\N	0	\N	\N	f	0	\N
2094	18	78	\N	0	\N	\N	f	0	\N
2095	18	77	\N	0	\N	\N	f	0	\N
2096	18	76	\N	0	\N	\N	f	0	\N
2097	18	75	\N	0	\N	\N	f	0	\N
2098	18	360	\N	0	\N	\N	f	0	\N
2099	18	359	\N	0	\N	\N	f	0	\N
2100	18	358	\N	0	\N	\N	f	0	\N
2101	18	357	\N	0	\N	\N	f	0	\N
2102	18	356	\N	0	\N	\N	f	0	\N
2103	18	355	\N	0	\N	\N	f	0	\N
2104	18	354	\N	0	\N	\N	f	0	\N
2105	18	353	\N	0	\N	\N	f	0	\N
2106	18	352	\N	0	\N	\N	f	0	\N
2107	18	351	\N	0	\N	\N	f	0	\N
2108	18	350	\N	0	\N	\N	f	0	\N
2109	18	349	\N	0	\N	\N	f	0	\N
2110	18	348	\N	0	\N	\N	f	0	\N
2111	18	347	\N	0	\N	\N	f	0	\N
2112	18	346	\N	0	\N	\N	f	0	\N
2113	18	345	\N	0	\N	\N	f	0	\N
2114	18	344	\N	0	\N	\N	f	0	\N
2115	18	343	\N	0	\N	\N	f	0	\N
2116	18	342	\N	0	\N	\N	f	0	\N
2117	18	341	\N	0	\N	\N	f	0	\N
2118	18	340	\N	0	\N	\N	f	0	\N
2119	18	339	\N	0	\N	\N	f	0	\N
2120	18	338	\N	0	\N	\N	f	0	\N
2121	18	337	\N	0	\N	\N	f	0	\N
2122	18	336	\N	0	\N	\N	f	0	\N
2123	18	335	\N	0	\N	\N	f	0	\N
2124	18	334	\N	0	\N	\N	f	0	\N
2125	18	333	\N	0	\N	\N	f	0	\N
2126	18	332	\N	0	\N	\N	f	0	\N
2127	18	331	\N	0	\N	\N	f	0	\N
2128	18	330	\N	0	\N	\N	f	0	\N
2129	18	329	\N	0	\N	\N	f	0	\N
2130	18	328	\N	0	\N	\N	f	0	\N
2131	18	327	\N	0	\N	\N	f	0	\N
2132	18	326	\N	0	\N	\N	f	0	\N
2133	18	325	\N	0	\N	\N	f	0	\N
2134	18	324	\N	0	\N	\N	f	0	\N
2135	18	39	\N	0	\N	\N	f	0	\N
2136	18	38	\N	0	\N	\N	f	0	\N
2137	18	37	\N	0	\N	\N	f	0	\N
2138	18	36	\N	0	\N	\N	f	0	\N
2139	18	35	\N	0	\N	\N	f	0	\N
2140	18	34	\N	0	\N	\N	f	0	\N
2141	18	33	\N	0	\N	\N	f	0	\N
2142	18	32	\N	0	\N	\N	f	0	\N
2143	18	31	\N	0	\N	\N	f	0	\N
2144	18	30	\N	0	\N	\N	f	0	\N
2145	18	29	\N	0	\N	\N	f	0	\N
2146	18	28	\N	0	\N	\N	f	0	\N
2147	18	27	\N	0	\N	\N	f	0	\N
2148	18	26	\N	0	\N	\N	f	0	\N
2149	18	25	\N	0	\N	\N	f	0	\N
2150	18	24	\N	0	\N	\N	f	0	\N
2151	18	23	\N	0	\N	\N	f	0	\N
2152	18	22	\N	0	\N	\N	f	0	\N
2153	18	21	\N	0	\N	\N	f	0	\N
2154	18	20	\N	0	\N	\N	f	0	\N
2155	18	19	\N	0	\N	\N	f	0	\N
2156	18	18	\N	0	\N	\N	f	0	\N
2157	18	17	\N	0	\N	\N	f	0	\N
2158	18	16	\N	0	\N	\N	f	0	\N
2159	18	15	\N	0	\N	\N	f	0	\N
2160	18	14	\N	0	\N	\N	f	0	\N
2161	18	13	\N	0	\N	\N	f	0	\N
2162	18	12	\N	0	\N	\N	f	0	\N
2163	18	11	\N	0	\N	\N	f	0	\N
2164	18	10	\N	0	\N	\N	f	0	\N
2165	18	9	\N	0	\N	\N	f	0	\N
2166	18	8	\N	0	\N	\N	f	0	\N
2167	18	7	\N	0	\N	\N	f	0	\N
2168	18	6	\N	0	\N	\N	f	0	\N
2169	18	5	\N	0	\N	\N	f	0	\N
2170	18	4	\N	0	\N	\N	f	0	\N
2171	18	3	\N	0	\N	\N	f	0	\N
2172	18	2	\N	0	\N	\N	f	0	\N
2173	18	1	\N	0	\N	\N	f	0	\N
2174	18	74	\N	0	\N	\N	f	0	\N
2175	18	73	\N	0	\N	\N	f	0	\N
2176	18	72	\N	0	\N	\N	f	0	\N
2177	18	71	\N	0	\N	\N	f	0	\N
2178	18	70	\N	0	\N	\N	f	0	\N
2179	18	69	\N	0	\N	\N	f	0	\N
2180	18	68	\N	0	\N	\N	f	0	\N
2181	18	67	\N	0	\N	\N	f	0	\N
2182	18	66	\N	0	\N	\N	f	0	\N
2183	18	65	\N	0	\N	\N	f	0	\N
2184	18	64	\N	0	\N	\N	f	0	\N
2185	18	63	\N	0	\N	\N	f	0	\N
2186	18	62	\N	0	\N	\N	f	0	\N
2187	18	61	\N	0	\N	\N	f	0	\N
2188	18	60	\N	0	\N	\N	f	0	\N
2189	18	59	\N	0	\N	\N	f	0	\N
2190	18	58	\N	0	\N	\N	f	0	\N
2191	18	57	\N	0	\N	\N	f	0	\N
2192	18	56	\N	0	\N	\N	f	0	\N
2193	18	55	\N	0	\N	\N	f	0	\N
2194	18	54	\N	0	\N	\N	f	0	\N
2195	18	53	\N	0	\N	\N	f	0	\N
2196	18	52	\N	0	\N	\N	f	0	\N
2197	18	51	\N	0	\N	\N	f	0	\N
2198	18	50	\N	0	\N	\N	f	0	\N
2199	18	49	\N	0	\N	\N	f	0	\N
2200	18	48	\N	0	\N	\N	f	0	\N
2201	18	47	\N	0	\N	\N	f	0	\N
2202	18	46	\N	0	\N	\N	f	0	\N
2203	18	45	\N	0	\N	\N	f	0	\N
2204	18	44	\N	0	\N	\N	f	0	\N
2205	18	43	\N	0	\N	\N	f	0	\N
2206	18	42	\N	0	\N	\N	f	0	\N
2207	18	41	\N	0	\N	\N	f	0	\N
2208	18	40	\N	0	\N	\N	f	0	\N
2209	18	432	\N	0	\N	\N	f	0	\N
2210	18	431	\N	0	\N	\N	f	0	\N
2211	18	430	\N	0	\N	\N	f	0	\N
2212	18	429	\N	0	\N	\N	f	0	\N
2213	18	428	\N	0	\N	\N	f	0	\N
2214	18	427	\N	0	\N	\N	f	0	\N
2215	18	426	\N	0	\N	\N	f	0	\N
2216	18	425	\N	0	\N	\N	f	0	\N
2217	18	424	\N	0	\N	\N	f	0	\N
2218	18	423	\N	0	\N	\N	f	0	\N
2219	18	422	\N	0	\N	\N	f	0	\N
2220	18	421	\N	0	\N	\N	f	0	\N
2221	18	420	\N	0	\N	\N	f	0	\N
2222	18	419	\N	0	\N	\N	f	0	\N
2223	18	418	\N	0	\N	\N	f	0	\N
2224	18	417	\N	0	\N	\N	f	0	\N
2225	18	416	\N	0	\N	\N	f	0	\N
2226	18	415	\N	0	\N	\N	f	0	\N
2227	18	414	\N	0	\N	\N	f	0	\N
2228	18	413	\N	0	\N	\N	f	0	\N
2229	18	412	\N	0	\N	\N	f	0	\N
2230	18	411	\N	0	\N	\N	f	0	\N
2231	18	410	\N	0	\N	\N	f	0	\N
2232	18	409	\N	0	\N	\N	f	0	\N
2233	18	408	\N	0	\N	\N	f	0	\N
2234	18	407	\N	0	\N	\N	f	0	\N
2235	18	406	\N	0	\N	\N	f	0	\N
2236	18	405	\N	0	\N	\N	f	0	\N
2237	18	404	\N	0	\N	\N	f	0	\N
2238	18	403	\N	0	\N	\N	f	0	\N
2239	18	402	\N	0	\N	\N	f	0	\N
2240	18	401	\N	0	\N	\N	f	0	\N
2241	18	400	\N	0	\N	\N	f	0	\N
2242	18	399	\N	0	\N	\N	f	0	\N
2243	18	398	\N	0	\N	\N	f	0	\N
2244	18	397	\N	0	\N	\N	f	0	\N
2245	18	396	\N	0	\N	\N	f	0	\N
2246	18	395	\N	0	\N	\N	f	0	\N
2247	18	394	\N	0	\N	\N	f	0	\N
2248	18	393	\N	0	\N	\N	f	0	\N
2249	18	392	\N	0	\N	\N	f	0	\N
2250	18	391	\N	0	\N	\N	f	0	\N
2251	18	390	\N	0	\N	\N	f	0	\N
2252	18	389	\N	0	\N	\N	f	0	\N
2253	18	388	\N	0	\N	\N	f	0	\N
2254	18	387	\N	0	\N	\N	f	0	\N
2255	18	386	\N	0	\N	\N	f	0	\N
2256	18	385	\N	0	\N	\N	f	0	\N
2257	18	384	\N	0	\N	\N	f	0	\N
2258	18	383	\N	0	\N	\N	f	0	\N
2259	18	382	\N	0	\N	\N	f	0	\N
2260	18	381	\N	0	\N	\N	f	0	\N
2261	18	380	\N	0	\N	\N	f	0	\N
2262	18	379	\N	0	\N	\N	f	0	\N
2263	18	378	\N	0	\N	\N	f	0	\N
2264	18	377	\N	0	\N	\N	f	0	\N
2265	18	376	\N	0	\N	\N	f	0	\N
2266	18	375	\N	0	\N	\N	f	0	\N
2267	18	374	\N	0	\N	\N	f	0	\N
2268	18	373	\N	0	\N	\N	f	0	\N
2269	18	372	\N	0	\N	\N	f	0	\N
2270	18	371	\N	0	\N	\N	f	0	\N
2271	18	370	\N	0	\N	\N	f	0	\N
2272	18	369	\N	0	\N	\N	f	0	\N
2273	18	368	\N	0	\N	\N	f	0	\N
2274	18	367	\N	0	\N	\N	f	0	\N
2275	18	366	\N	0	\N	\N	f	0	\N
2276	18	365	\N	0	\N	\N	f	0	\N
2277	18	364	\N	0	\N	\N	f	0	\N
2278	18	363	\N	0	\N	\N	f	0	\N
2279	18	362	\N	0	\N	\N	f	0	\N
2280	18	361	\N	0	\N	\N	f	0	\N
2281	18	145	\N	0	\N	\N	f	0	\N
2282	18	144	\N	0	\N	\N	f	0	\N
2283	18	143	\N	0	\N	\N	f	0	\N
2284	18	142	\N	0	\N	\N	f	0	\N
2285	18	141	\N	0	\N	\N	f	0	\N
2286	18	140	\N	0	\N	\N	f	0	\N
2287	18	139	\N	0	\N	\N	f	0	\N
2288	18	138	\N	0	\N	\N	f	0	\N
2289	18	137	\N	0	\N	\N	f	0	\N
2290	18	136	\N	0	\N	\N	f	0	\N
2291	18	135	\N	0	\N	\N	f	0	\N
2292	18	134	\N	0	\N	\N	f	0	\N
2293	18	133	\N	0	\N	\N	f	0	\N
2294	18	132	\N	0	\N	\N	f	0	\N
2295	18	131	\N	0	\N	\N	f	0	\N
2296	18	130	\N	0	\N	\N	f	0	\N
2297	18	129	\N	0	\N	\N	f	0	\N
2298	18	128	\N	0	\N	\N	f	0	\N
2299	18	127	\N	0	\N	\N	f	0	\N
2300	18	126	\N	0	\N	\N	f	0	\N
2301	18	125	\N	0	\N	\N	f	0	\N
2302	18	124	\N	0	\N	\N	f	0	\N
2303	18	123	\N	0	\N	\N	f	0	\N
2304	18	122	\N	0	\N	\N	f	0	\N
2305	18	121	\N	0	\N	\N	f	0	\N
2306	18	120	\N	0	\N	\N	f	0	\N
2307	18	119	\N	0	\N	\N	f	0	\N
2308	18	118	\N	0	\N	\N	f	0	\N
2309	18	117	\N	0	\N	\N	f	0	\N
2310	18	116	\N	0	\N	\N	f	0	\N
2311	18	115	\N	0	\N	\N	f	0	\N
2312	18	114	\N	0	\N	\N	f	0	\N
2313	18	113	\N	0	\N	\N	f	0	\N
2314	18	112	\N	0	\N	\N	f	0	\N
2315	18	111	\N	0	\N	\N	f	0	\N
2316	18	110	\N	0	\N	\N	f	0	\N
2317	19	39	\N	0	\N	\N	f	0	\N
2318	19	38	\N	0	\N	\N	f	0	\N
2319	19	37	\N	0	\N	\N	f	0	\N
2320	19	36	\N	0	\N	\N	f	0	\N
2321	19	35	\N	0	\N	\N	f	0	\N
2322	19	34	\N	0	\N	\N	f	0	\N
2323	19	33	\N	0	\N	\N	f	0	\N
2324	19	32	\N	0	\N	\N	f	0	\N
2325	19	31	\N	0	\N	\N	f	0	\N
2326	19	30	\N	0	\N	\N	f	0	\N
2327	19	29	\N	0	\N	\N	f	0	\N
2328	19	28	\N	0	\N	\N	f	0	\N
2329	19	27	\N	0	\N	\N	f	0	\N
2330	19	26	\N	0	\N	\N	f	0	\N
2331	19	25	\N	0	\N	\N	f	0	\N
2332	19	24	\N	0	\N	\N	f	0	\N
2333	19	23	\N	0	\N	\N	f	0	\N
2334	19	22	\N	0	\N	\N	f	0	\N
2335	19	21	\N	0	\N	\N	f	0	\N
2336	19	20	\N	0	\N	\N	f	0	\N
2337	19	19	\N	0	\N	\N	f	0	\N
2338	19	18	\N	0	\N	\N	f	0	\N
2339	19	17	\N	0	\N	\N	f	0	\N
2340	19	16	\N	0	\N	\N	f	0	\N
2341	19	15	\N	0	\N	\N	f	0	\N
2342	19	14	\N	0	\N	\N	f	0	\N
2343	19	13	\N	0	\N	\N	f	0	\N
2344	19	12	\N	0	\N	\N	f	0	\N
2345	19	11	\N	0	\N	\N	f	0	\N
2346	19	10	\N	0	\N	\N	f	0	\N
2347	19	9	\N	0	\N	\N	f	0	\N
2348	19	8	\N	0	\N	\N	f	0	\N
2349	19	7	\N	0	\N	\N	f	0	\N
2350	19	6	\N	0	\N	\N	f	0	\N
2351	19	5	\N	0	\N	\N	f	0	\N
2352	19	4	\N	0	\N	\N	f	0	\N
2353	19	3	\N	0	\N	\N	f	0	\N
2354	19	2	\N	0	\N	\N	f	0	\N
2355	19	1	\N	0	\N	\N	f	0	\N
2356	19	290	\N	0	\N	\N	f	0	\N
2357	19	289	\N	0	\N	\N	f	0	\N
2358	19	288	\N	0	\N	\N	f	0	\N
2359	19	287	\N	0	\N	\N	f	0	\N
2360	19	286	\N	0	\N	\N	f	0	\N
2361	19	285	\N	0	\N	\N	f	0	\N
2362	19	284	\N	0	\N	\N	f	0	\N
2363	19	283	\N	0	\N	\N	f	0	\N
2364	19	282	\N	0	\N	\N	f	0	\N
2365	19	281	\N	0	\N	\N	f	0	\N
2366	19	280	\N	0	\N	\N	f	0	\N
2367	19	279	\N	0	\N	\N	f	0	\N
2368	19	278	\N	0	\N	\N	f	0	\N
2369	19	277	\N	0	\N	\N	f	0	\N
2370	19	276	\N	0	\N	\N	f	0	\N
2371	19	275	\N	0	\N	\N	f	0	\N
2372	19	274	\N	0	\N	\N	f	0	\N
2373	19	273	\N	0	\N	\N	f	0	\N
2374	19	272	\N	0	\N	\N	f	0	\N
2375	19	271	\N	0	\N	\N	f	0	\N
2376	19	270	\N	0	\N	\N	f	0	\N
2377	19	269	\N	0	\N	\N	f	0	\N
2378	19	268	\N	0	\N	\N	f	0	\N
2379	19	267	\N	0	\N	\N	f	0	\N
2380	19	266	\N	0	\N	\N	f	0	\N
2381	19	265	\N	0	\N	\N	f	0	\N
2382	19	264	\N	0	\N	\N	f	0	\N
2383	19	263	\N	0	\N	\N	f	0	\N
2384	19	262	\N	0	\N	\N	f	0	\N
2385	19	261	\N	0	\N	\N	f	0	\N
2386	19	260	\N	0	\N	\N	f	0	\N
2387	19	259	\N	0	\N	\N	f	0	\N
2388	19	258	\N	0	\N	\N	f	0	\N
2389	19	257	\N	0	\N	\N	f	0	\N
2390	19	256	\N	0	\N	\N	f	0	\N
2391	19	255	\N	0	\N	\N	f	0	\N
2392	19	254	\N	0	\N	\N	f	0	\N
2393	19	253	\N	0	\N	\N	f	0	\N
2394	19	252	\N	0	\N	\N	f	0	\N
2395	19	251	\N	0	\N	\N	f	0	\N
2396	19	250	\N	0	\N	\N	f	0	\N
2397	19	249	\N	0	\N	\N	f	0	\N
2398	19	248	\N	0	\N	\N	f	0	\N
2399	19	247	\N	0	\N	\N	f	0	\N
2400	19	246	\N	0	\N	\N	f	0	\N
2401	19	245	\N	0	\N	\N	f	0	\N
2402	19	244	\N	0	\N	\N	f	0	\N
2403	19	243	\N	0	\N	\N	f	0	\N
2404	19	242	\N	0	\N	\N	f	0	\N
2405	19	241	\N	0	\N	\N	f	0	\N
2406	19	240	\N	0	\N	\N	f	0	\N
2407	19	239	\N	0	\N	\N	f	0	\N
2408	19	238	\N	0	\N	\N	f	0	\N
2409	19	237	\N	0	\N	\N	f	0	\N
2410	19	236	\N	0	\N	\N	f	0	\N
2411	19	235	\N	0	\N	\N	f	0	\N
2412	19	234	\N	0	\N	\N	f	0	\N
2413	19	233	\N	0	\N	\N	f	0	\N
2414	19	232	\N	0	\N	\N	f	0	\N
2415	19	231	\N	0	\N	\N	f	0	\N
2416	19	230	\N	0	\N	\N	f	0	\N
2417	19	229	\N	0	\N	\N	f	0	\N
2418	19	228	\N	0	\N	\N	f	0	\N
2419	19	227	\N	0	\N	\N	f	0	\N
2420	19	226	\N	0	\N	\N	f	0	\N
2421	19	225	\N	0	\N	\N	f	0	\N
2422	19	224	\N	0	\N	\N	f	0	\N
2423	19	223	\N	0	\N	\N	f	0	\N
2424	19	222	\N	0	\N	\N	f	0	\N
2425	19	221	\N	0	\N	\N	f	0	\N
2426	19	220	\N	0	\N	\N	f	0	\N
2427	19	219	\N	0	\N	\N	f	0	\N
2428	19	145	\N	0	\N	\N	f	0	\N
2429	19	144	\N	0	\N	\N	f	0	\N
2430	19	143	\N	0	\N	\N	f	0	\N
2431	19	142	\N	0	\N	\N	f	0	\N
2432	19	141	\N	0	\N	\N	f	0	\N
2433	19	140	\N	0	\N	\N	f	0	\N
2434	19	139	\N	0	\N	\N	f	0	\N
2435	19	138	\N	0	\N	\N	f	0	\N
2436	19	137	\N	0	\N	\N	f	0	\N
2437	19	136	\N	0	\N	\N	f	0	\N
2438	19	135	\N	0	\N	\N	f	0	\N
2439	19	134	\N	0	\N	\N	f	0	\N
2440	19	133	\N	0	\N	\N	f	0	\N
2441	19	132	\N	0	\N	\N	f	0	\N
2442	19	131	\N	0	\N	\N	f	0	\N
2443	19	130	\N	0	\N	\N	f	0	\N
2444	19	129	\N	0	\N	\N	f	0	\N
2445	19	128	\N	0	\N	\N	f	0	\N
2446	19	127	\N	0	\N	\N	f	0	\N
2447	19	126	\N	0	\N	\N	f	0	\N
2448	19	125	\N	0	\N	\N	f	0	\N
2449	19	124	\N	0	\N	\N	f	0	\N
2450	19	123	\N	0	\N	\N	f	0	\N
2451	19	122	\N	0	\N	\N	f	0	\N
2452	19	121	\N	0	\N	\N	f	0	\N
2453	19	120	\N	0	\N	\N	f	0	\N
2454	19	119	\N	0	\N	\N	f	0	\N
2455	19	118	\N	0	\N	\N	f	0	\N
2456	19	117	\N	0	\N	\N	f	0	\N
2457	19	116	\N	0	\N	\N	f	0	\N
2458	19	115	\N	0	\N	\N	f	0	\N
2459	19	114	\N	0	\N	\N	f	0	\N
2460	19	113	\N	0	\N	\N	f	0	\N
2461	19	112	\N	0	\N	\N	f	0	\N
2462	19	111	\N	0	\N	\N	f	0	\N
2463	19	110	\N	0	\N	\N	f	0	\N
2464	19	323	\N	0	\N	\N	f	0	\N
2465	19	322	\N	0	\N	\N	f	0	\N
2466	19	321	\N	0	\N	\N	f	0	\N
2467	19	320	\N	0	\N	\N	f	0	\N
2468	19	319	\N	0	\N	\N	f	0	\N
2469	19	318	\N	0	\N	\N	f	0	\N
2470	19	317	\N	0	\N	\N	f	0	\N
2471	19	316	\N	0	\N	\N	f	0	\N
2472	19	315	\N	0	\N	\N	f	0	\N
2473	19	314	\N	0	\N	\N	f	0	\N
2474	19	313	\N	0	\N	\N	f	0	\N
2475	19	312	\N	0	\N	\N	f	0	\N
2476	19	311	\N	0	\N	\N	f	0	\N
2477	19	310	\N	0	\N	\N	f	0	\N
2478	19	309	\N	0	\N	\N	f	0	\N
2479	19	308	\N	0	\N	\N	f	0	\N
2480	19	307	\N	0	\N	\N	f	0	\N
2481	19	306	\N	0	\N	\N	f	0	\N
2482	19	305	\N	0	\N	\N	f	0	\N
2483	19	304	\N	0	\N	\N	f	0	\N
2484	19	303	\N	0	\N	\N	f	0	\N
2485	19	302	\N	0	\N	\N	f	0	\N
2486	19	301	\N	0	\N	\N	f	0	\N
2487	19	300	\N	0	\N	\N	f	0	\N
2488	19	299	\N	0	\N	\N	f	0	\N
2489	19	298	\N	0	\N	\N	f	0	\N
2490	19	297	\N	0	\N	\N	f	0	\N
2491	19	296	\N	0	\N	\N	f	0	\N
2492	19	295	\N	0	\N	\N	f	0	\N
2493	19	294	\N	0	\N	\N	f	0	\N
2494	19	293	\N	0	\N	\N	f	0	\N
2495	19	292	\N	0	\N	\N	f	0	\N
2496	19	291	\N	0	\N	\N	f	0	\N
2497	19	180	\N	0	\N	\N	f	0	\N
2498	19	179	\N	0	\N	\N	f	0	\N
2499	19	178	\N	0	\N	\N	f	0	\N
2500	19	177	\N	0	\N	\N	f	0	\N
2501	19	176	\N	0	\N	\N	f	0	\N
2502	19	175	\N	0	\N	\N	f	0	\N
2503	19	174	\N	0	\N	\N	f	0	\N
2504	19	173	\N	0	\N	\N	f	0	\N
2505	19	172	\N	0	\N	\N	f	0	\N
2506	19	171	\N	0	\N	\N	f	0	\N
2507	19	170	\N	0	\N	\N	f	0	\N
2508	19	169	\N	0	\N	\N	f	0	\N
2509	19	168	\N	0	\N	\N	f	0	\N
2510	19	167	\N	0	\N	\N	f	0	\N
2511	19	166	\N	0	\N	\N	f	0	\N
2512	19	165	\N	0	\N	\N	f	0	\N
2513	19	164	\N	0	\N	\N	f	0	\N
2514	19	163	\N	0	\N	\N	f	0	\N
2515	19	162	\N	0	\N	\N	f	0	\N
2516	19	161	\N	0	\N	\N	f	0	\N
2517	19	160	\N	0	\N	\N	f	0	\N
2518	19	159	\N	0	\N	\N	f	0	\N
2519	19	158	\N	0	\N	\N	f	0	\N
2520	19	157	\N	0	\N	\N	f	0	\N
2521	19	156	\N	0	\N	\N	f	0	\N
2522	19	155	\N	0	\N	\N	f	0	\N
2523	19	154	\N	0	\N	\N	f	0	\N
2524	19	153	\N	0	\N	\N	f	0	\N
2525	19	152	\N	0	\N	\N	f	0	\N
2526	19	151	\N	0	\N	\N	f	0	\N
2527	19	150	\N	0	\N	\N	f	0	\N
2528	19	149	\N	0	\N	\N	f	0	\N
2529	19	148	\N	0	\N	\N	f	0	\N
2530	19	147	\N	0	\N	\N	f	0	\N
2531	19	146	\N	0	\N	\N	f	0	\N
2532	19	109	\N	0	\N	\N	f	0	\N
2533	19	108	\N	0	\N	\N	f	0	\N
2534	19	107	\N	0	\N	\N	f	0	\N
2535	19	106	\N	0	\N	\N	f	0	\N
2536	19	105	\N	0	\N	\N	f	0	\N
2537	19	104	\N	0	\N	\N	f	0	\N
2538	19	103	\N	0	\N	\N	f	0	\N
2539	19	102	\N	0	\N	\N	f	0	\N
2540	19	101	\N	0	\N	\N	f	0	\N
2541	19	100	\N	0	\N	\N	f	0	\N
2542	19	99	\N	0	\N	\N	f	0	\N
2543	19	98	\N	0	\N	\N	f	0	\N
2544	19	97	\N	0	\N	\N	f	0	\N
2545	19	96	\N	0	\N	\N	f	0	\N
2546	19	95	\N	0	\N	\N	f	0	\N
2547	19	94	\N	0	\N	\N	f	0	\N
2548	19	93	\N	0	\N	\N	f	0	\N
2549	19	92	\N	0	\N	\N	f	0	\N
2550	19	91	\N	0	\N	\N	f	0	\N
2551	19	90	\N	0	\N	\N	f	0	\N
2552	19	89	\N	0	\N	\N	f	0	\N
2553	19	88	\N	0	\N	\N	f	0	\N
2554	19	87	\N	0	\N	\N	f	0	\N
2555	19	86	\N	0	\N	\N	f	0	\N
2556	19	85	\N	0	\N	\N	f	0	\N
2557	19	84	\N	0	\N	\N	f	0	\N
2558	19	83	\N	0	\N	\N	f	0	\N
2559	19	82	\N	0	\N	\N	f	0	\N
2560	19	81	\N	0	\N	\N	f	0	\N
2561	19	80	\N	0	\N	\N	f	0	\N
2562	19	79	\N	0	\N	\N	f	0	\N
2563	19	78	\N	0	\N	\N	f	0	\N
2564	19	77	\N	0	\N	\N	f	0	\N
2565	19	76	\N	0	\N	\N	f	0	\N
2566	19	75	\N	0	\N	\N	f	0	\N
2567	19	218	\N	0	\N	\N	f	0	\N
2568	19	217	\N	0	\N	\N	f	0	\N
2569	19	216	\N	0	\N	\N	f	0	\N
2570	19	215	\N	0	\N	\N	f	0	\N
2571	19	214	\N	0	\N	\N	f	0	\N
2572	19	213	\N	0	\N	\N	f	0	\N
2573	19	212	\N	0	\N	\N	f	0	\N
2574	19	211	\N	0	\N	\N	f	0	\N
2575	19	210	\N	0	\N	\N	f	0	\N
2576	19	209	\N	0	\N	\N	f	0	\N
2577	19	208	\N	0	\N	\N	f	0	\N
2578	19	207	\N	0	\N	\N	f	0	\N
2579	19	206	\N	0	\N	\N	f	0	\N
2580	19	205	\N	0	\N	\N	f	0	\N
2581	19	204	\N	0	\N	\N	f	0	\N
2582	19	203	\N	0	\N	\N	f	0	\N
2583	19	202	\N	0	\N	\N	f	0	\N
2584	19	201	\N	0	\N	\N	f	0	\N
2585	19	200	\N	0	\N	\N	f	0	\N
2586	19	199	\N	0	\N	\N	f	0	\N
2587	19	198	\N	0	\N	\N	f	0	\N
2588	19	197	\N	0	\N	\N	f	0	\N
2589	19	196	\N	0	\N	\N	f	0	\N
2590	19	195	\N	0	\N	\N	f	0	\N
2591	19	194	\N	0	\N	\N	f	0	\N
2592	19	193	\N	0	\N	\N	f	0	\N
2593	19	192	\N	0	\N	\N	f	0	\N
2594	19	191	\N	0	\N	\N	f	0	\N
2595	19	190	\N	0	\N	\N	f	0	\N
2596	19	189	\N	0	\N	\N	f	0	\N
2597	19	188	\N	0	\N	\N	f	0	\N
2598	19	187	\N	0	\N	\N	f	0	\N
2599	19	186	\N	0	\N	\N	f	0	\N
2600	19	185	\N	0	\N	\N	f	0	\N
2601	19	184	\N	0	\N	\N	f	0	\N
2602	19	183	\N	0	\N	\N	f	0	\N
2603	19	182	\N	0	\N	\N	f	0	\N
2604	19	181	\N	0	\N	\N	f	0	\N
2605	19	74	\N	0	\N	\N	f	0	\N
2606	19	73	\N	0	\N	\N	f	0	\N
2607	19	72	\N	0	\N	\N	f	0	\N
2608	19	71	\N	0	\N	\N	f	0	\N
2609	19	70	\N	0	\N	\N	f	0	\N
2610	19	69	\N	0	\N	\N	f	0	\N
2611	19	68	\N	0	\N	\N	f	0	\N
2612	19	67	\N	0	\N	\N	f	0	\N
2613	19	66	\N	0	\N	\N	f	0	\N
2614	19	65	\N	0	\N	\N	f	0	\N
2615	19	64	\N	0	\N	\N	f	0	\N
2616	19	63	\N	0	\N	\N	f	0	\N
2617	19	62	\N	0	\N	\N	f	0	\N
2618	19	61	\N	0	\N	\N	f	0	\N
2619	19	60	\N	0	\N	\N	f	0	\N
2620	19	59	\N	0	\N	\N	f	0	\N
2621	19	58	\N	0	\N	\N	f	0	\N
2622	19	57	\N	0	\N	\N	f	0	\N
2623	19	56	\N	0	\N	\N	f	0	\N
2624	19	55	\N	0	\N	\N	f	0	\N
2625	19	54	\N	0	\N	\N	f	0	\N
2626	19	53	\N	0	\N	\N	f	0	\N
2627	19	52	\N	0	\N	\N	f	0	\N
2628	19	51	\N	0	\N	\N	f	0	\N
2629	19	50	\N	0	\N	\N	f	0	\N
2630	19	49	\N	0	\N	\N	f	0	\N
2631	19	48	\N	0	\N	\N	f	0	\N
2632	19	47	\N	0	\N	\N	f	0	\N
2633	19	46	\N	0	\N	\N	f	0	\N
2634	19	45	\N	0	\N	\N	f	0	\N
2635	19	44	\N	0	\N	\N	f	0	\N
2636	19	43	\N	0	\N	\N	f	0	\N
2637	19	42	\N	0	\N	\N	f	0	\N
2638	19	41	\N	0	\N	\N	f	0	\N
2639	19	40	\N	0	\N	\N	f	0	\N
2640	19	432	\N	0	\N	\N	f	0	\N
2641	19	431	\N	0	\N	\N	f	0	\N
2642	19	430	\N	0	\N	\N	f	0	\N
2643	19	429	\N	0	\N	\N	f	0	\N
2644	19	428	\N	0	\N	\N	f	0	\N
2645	19	427	\N	0	\N	\N	f	0	\N
2646	19	426	\N	0	\N	\N	f	0	\N
2647	19	425	\N	0	\N	\N	f	0	\N
2648	19	424	\N	0	\N	\N	f	0	\N
2649	19	423	\N	0	\N	\N	f	0	\N
2650	19	422	\N	0	\N	\N	f	0	\N
2651	19	421	\N	0	\N	\N	f	0	\N
2652	19	420	\N	0	\N	\N	f	0	\N
2653	19	419	\N	0	\N	\N	f	0	\N
2654	19	418	\N	0	\N	\N	f	0	\N
2655	19	417	\N	0	\N	\N	f	0	\N
2656	19	416	\N	0	\N	\N	f	0	\N
2657	19	415	\N	0	\N	\N	f	0	\N
2658	19	414	\N	0	\N	\N	f	0	\N
2659	19	413	\N	0	\N	\N	f	0	\N
2660	19	412	\N	0	\N	\N	f	0	\N
2661	19	411	\N	0	\N	\N	f	0	\N
2662	19	410	\N	0	\N	\N	f	0	\N
2663	19	409	\N	0	\N	\N	f	0	\N
2664	19	408	\N	0	\N	\N	f	0	\N
2665	19	407	\N	0	\N	\N	f	0	\N
2666	19	406	\N	0	\N	\N	f	0	\N
2667	19	405	\N	0	\N	\N	f	0	\N
2668	19	404	\N	0	\N	\N	f	0	\N
2669	19	403	\N	0	\N	\N	f	0	\N
2670	19	402	\N	0	\N	\N	f	0	\N
2671	19	401	\N	0	\N	\N	f	0	\N
2672	19	400	\N	0	\N	\N	f	0	\N
2673	19	399	\N	0	\N	\N	f	0	\N
2674	19	398	\N	0	\N	\N	f	0	\N
2675	19	397	\N	0	\N	\N	f	0	\N
2676	19	396	\N	0	\N	\N	f	0	\N
2677	19	395	\N	0	\N	\N	f	0	\N
2678	19	394	\N	0	\N	\N	f	0	\N
2679	19	393	\N	0	\N	\N	f	0	\N
2680	19	392	\N	0	\N	\N	f	0	\N
2681	19	391	\N	0	\N	\N	f	0	\N
2682	19	390	\N	0	\N	\N	f	0	\N
2683	19	389	\N	0	\N	\N	f	0	\N
2684	19	388	\N	0	\N	\N	f	0	\N
2685	19	387	\N	0	\N	\N	f	0	\N
2686	19	386	\N	0	\N	\N	f	0	\N
2687	19	385	\N	0	\N	\N	f	0	\N
2688	19	384	\N	0	\N	\N	f	0	\N
2689	19	383	\N	0	\N	\N	f	0	\N
2690	19	382	\N	0	\N	\N	f	0	\N
2691	19	381	\N	0	\N	\N	f	0	\N
2692	19	380	\N	0	\N	\N	f	0	\N
2693	19	379	\N	0	\N	\N	f	0	\N
2694	19	378	\N	0	\N	\N	f	0	\N
2695	19	377	\N	0	\N	\N	f	0	\N
2696	19	376	\N	0	\N	\N	f	0	\N
2697	19	375	\N	0	\N	\N	f	0	\N
2698	19	374	\N	0	\N	\N	f	0	\N
2699	19	373	\N	0	\N	\N	f	0	\N
2700	19	372	\N	0	\N	\N	f	0	\N
2701	19	371	\N	0	\N	\N	f	0	\N
2702	19	370	\N	0	\N	\N	f	0	\N
2703	19	369	\N	0	\N	\N	f	0	\N
2704	19	368	\N	0	\N	\N	f	0	\N
2705	19	367	\N	0	\N	\N	f	0	\N
2706	19	366	\N	0	\N	\N	f	0	\N
2707	19	365	\N	0	\N	\N	f	0	\N
2708	19	364	\N	0	\N	\N	f	0	\N
2709	19	363	\N	0	\N	\N	f	0	\N
2710	19	362	\N	0	\N	\N	f	0	\N
2711	19	361	\N	0	\N	\N	f	0	\N
2712	21	74	\N	0	\N	\N	f	0	\N
2713	21	73	\N	0	\N	\N	f	0	\N
2714	21	72	\N	0	\N	\N	f	0	\N
2715	21	71	\N	0	\N	\N	f	0	\N
2716	21	70	\N	0	\N	\N	f	0	\N
2717	21	69	\N	0	\N	\N	f	0	\N
2718	21	68	\N	0	\N	\N	f	0	\N
2719	21	67	\N	0	\N	\N	f	0	\N
2720	21	66	\N	0	\N	\N	f	0	\N
2721	21	65	\N	0	\N	\N	f	0	\N
2722	21	64	\N	0	\N	\N	f	0	\N
2723	21	63	\N	0	\N	\N	f	0	\N
2724	21	62	\N	0	\N	\N	f	0	\N
2725	21	61	\N	0	\N	\N	f	0	\N
2726	21	60	\N	0	\N	\N	f	0	\N
2727	21	59	\N	0	\N	\N	f	0	\N
2728	21	58	\N	0	\N	\N	f	0	\N
2729	21	57	\N	0	\N	\N	f	0	\N
2730	21	56	\N	0	\N	\N	f	0	\N
2731	21	55	\N	0	\N	\N	f	0	\N
2732	21	54	\N	0	\N	\N	f	0	\N
2733	21	53	\N	0	\N	\N	f	0	\N
2734	21	52	\N	0	\N	\N	f	0	\N
2735	21	51	\N	0	\N	\N	f	0	\N
2736	21	50	\N	0	\N	\N	f	0	\N
2737	21	49	\N	0	\N	\N	f	0	\N
2738	21	48	\N	0	\N	\N	f	0	\N
2739	21	47	\N	0	\N	\N	f	0	\N
2740	21	46	\N	0	\N	\N	f	0	\N
2741	21	45	\N	0	\N	\N	f	0	\N
2742	21	44	\N	0	\N	\N	f	0	\N
2743	21	43	\N	0	\N	\N	f	0	\N
2744	21	42	\N	0	\N	\N	f	0	\N
2745	21	41	\N	0	\N	\N	f	0	\N
2746	21	40	\N	0	\N	\N	f	0	\N
2747	21	109	\N	0	\N	\N	f	0	\N
2748	21	108	\N	0	\N	\N	f	0	\N
2749	21	107	\N	0	\N	\N	f	0	\N
2750	21	106	\N	0	\N	\N	f	0	\N
2751	21	105	\N	0	\N	\N	f	0	\N
2752	21	104	\N	0	\N	\N	f	0	\N
2753	21	103	\N	0	\N	\N	f	0	\N
2754	21	102	\N	0	\N	\N	f	0	\N
2755	21	101	\N	0	\N	\N	f	0	\N
2756	21	100	\N	0	\N	\N	f	0	\N
2757	21	99	\N	0	\N	\N	f	0	\N
2758	21	98	\N	0	\N	\N	f	0	\N
2759	21	97	\N	0	\N	\N	f	0	\N
2760	21	96	\N	0	\N	\N	f	0	\N
2761	21	95	\N	0	\N	\N	f	0	\N
2762	21	94	\N	0	\N	\N	f	0	\N
2763	21	93	\N	0	\N	\N	f	0	\N
2764	21	92	\N	0	\N	\N	f	0	\N
2765	21	91	\N	0	\N	\N	f	0	\N
2766	21	90	\N	0	\N	\N	f	0	\N
2767	21	89	\N	0	\N	\N	f	0	\N
2768	21	88	\N	0	\N	\N	f	0	\N
2769	21	87	\N	0	\N	\N	f	0	\N
2770	21	86	\N	0	\N	\N	f	0	\N
2771	21	85	\N	0	\N	\N	f	0	\N
2772	21	84	\N	0	\N	\N	f	0	\N
2773	21	83	\N	0	\N	\N	f	0	\N
2774	21	82	\N	0	\N	\N	f	0	\N
2775	21	81	\N	0	\N	\N	f	0	\N
2776	21	80	\N	0	\N	\N	f	0	\N
2777	21	79	\N	0	\N	\N	f	0	\N
2778	21	78	\N	0	\N	\N	f	0	\N
2779	21	77	\N	0	\N	\N	f	0	\N
2780	21	76	\N	0	\N	\N	f	0	\N
2781	21	75	\N	0	\N	\N	f	0	\N
2782	23	218	\N	0	\N	\N	f	0	\N
2783	23	217	\N	0	\N	\N	f	0	\N
2784	23	216	\N	0	\N	\N	f	0	\N
2785	23	215	\N	0	\N	\N	f	0	\N
2786	23	214	\N	0	\N	\N	f	0	\N
2787	23	213	\N	0	\N	\N	f	0	\N
2788	23	212	\N	0	\N	\N	f	0	\N
2789	23	211	\N	0	\N	\N	f	0	\N
2790	23	210	\N	0	\N	\N	f	0	\N
2791	23	209	\N	0	\N	\N	f	0	\N
2792	23	208	\N	0	\N	\N	f	0	\N
2793	23	207	\N	0	\N	\N	f	0	\N
2794	23	206	\N	0	\N	\N	f	0	\N
2795	23	205	\N	0	\N	\N	f	0	\N
2796	23	204	\N	0	\N	\N	f	0	\N
2797	23	203	\N	0	\N	\N	f	0	\N
2798	23	202	\N	0	\N	\N	f	0	\N
2799	23	201	\N	0	\N	\N	f	0	\N
2800	23	200	\N	0	\N	\N	f	0	\N
2801	23	199	\N	0	\N	\N	f	0	\N
2802	23	198	\N	0	\N	\N	f	0	\N
2803	23	197	\N	0	\N	\N	f	0	\N
2804	23	196	\N	0	\N	\N	f	0	\N
2805	23	195	\N	0	\N	\N	f	0	\N
2806	23	194	\N	0	\N	\N	f	0	\N
2807	23	193	\N	0	\N	\N	f	0	\N
2808	23	192	\N	0	\N	\N	f	0	\N
2809	23	191	\N	0	\N	\N	f	0	\N
2810	23	190	\N	0	\N	\N	f	0	\N
2811	23	189	\N	0	\N	\N	f	0	\N
2812	23	188	\N	0	\N	\N	f	0	\N
2813	23	187	\N	0	\N	\N	f	0	\N
2814	23	186	\N	0	\N	\N	f	0	\N
2815	23	185	\N	0	\N	\N	f	0	\N
2816	23	184	\N	0	\N	\N	f	0	\N
2817	23	183	\N	0	\N	\N	f	0	\N
2818	23	182	\N	0	\N	\N	f	0	\N
2819	23	181	\N	0	\N	\N	f	0	\N
2820	24	360	\N	0	\N	\N	f	0	\N
2821	24	359	\N	0	\N	\N	f	0	\N
2822	24	358	\N	0	\N	\N	f	0	\N
2823	24	357	\N	0	\N	\N	f	0	\N
2824	24	356	\N	0	\N	\N	f	0	\N
2825	24	355	\N	0	\N	\N	f	0	\N
2826	24	354	\N	0	\N	\N	f	0	\N
2827	24	353	\N	0	\N	\N	f	0	\N
2828	24	352	\N	0	\N	\N	f	0	\N
2829	24	351	\N	0	\N	\N	f	0	\N
2830	24	350	\N	0	\N	\N	f	0	\N
2831	24	349	\N	0	\N	\N	f	0	\N
2832	24	348	\N	0	\N	\N	f	0	\N
2833	24	347	\N	0	\N	\N	f	0	\N
2834	24	346	\N	0	\N	\N	f	0	\N
2835	24	345	\N	0	\N	\N	f	0	\N
2836	24	344	\N	0	\N	\N	f	0	\N
2837	24	343	\N	0	\N	\N	f	0	\N
2838	24	342	\N	0	\N	\N	f	0	\N
2839	24	341	\N	0	\N	\N	f	0	\N
2840	24	340	\N	0	\N	\N	f	0	\N
2841	24	339	\N	0	\N	\N	f	0	\N
2842	24	338	\N	0	\N	\N	f	0	\N
2843	24	337	\N	0	\N	\N	f	0	\N
2844	24	336	\N	0	\N	\N	f	0	\N
2845	24	335	\N	0	\N	\N	f	0	\N
2846	24	334	\N	0	\N	\N	f	0	\N
2847	24	333	\N	0	\N	\N	f	0	\N
2848	24	332	\N	0	\N	\N	f	0	\N
2849	24	331	\N	0	\N	\N	f	0	\N
2850	24	330	\N	0	\N	\N	f	0	\N
2851	24	329	\N	0	\N	\N	f	0	\N
2852	24	328	\N	0	\N	\N	f	0	\N
2853	24	327	\N	0	\N	\N	f	0	\N
2854	24	326	\N	0	\N	\N	f	0	\N
2855	24	325	\N	0	\N	\N	f	0	\N
2856	24	324	\N	0	\N	\N	f	0	\N
2857	24	180	\N	0	\N	\N	f	0	\N
2858	24	179	\N	0	\N	\N	f	0	\N
2859	24	178	\N	0	\N	\N	f	0	\N
2860	24	177	\N	0	\N	\N	f	0	\N
2861	24	176	\N	0	\N	\N	f	0	\N
2862	24	175	\N	0	\N	\N	f	0	\N
2863	24	174	\N	0	\N	\N	f	0	\N
2864	24	173	\N	0	\N	\N	f	0	\N
2865	24	172	\N	0	\N	\N	f	0	\N
2866	24	171	\N	0	\N	\N	f	0	\N
2867	24	170	\N	0	\N	\N	f	0	\N
2868	24	169	\N	0	\N	\N	f	0	\N
2869	24	168	\N	0	\N	\N	f	0	\N
2870	24	167	\N	0	\N	\N	f	0	\N
2871	24	166	\N	0	\N	\N	f	0	\N
2872	24	165	\N	0	\N	\N	f	0	\N
2873	24	164	\N	0	\N	\N	f	0	\N
2874	24	163	\N	0	\N	\N	f	0	\N
2875	24	162	\N	0	\N	\N	f	0	\N
2876	24	161	\N	0	\N	\N	f	0	\N
2877	24	160	\N	0	\N	\N	f	0	\N
2878	24	159	\N	0	\N	\N	f	0	\N
2879	24	158	\N	0	\N	\N	f	0	\N
2880	24	157	\N	0	\N	\N	f	0	\N
2881	24	156	\N	0	\N	\N	f	0	\N
2882	24	155	\N	0	\N	\N	f	0	\N
2883	24	154	\N	0	\N	\N	f	0	\N
2884	24	153	\N	0	\N	\N	f	0	\N
2885	24	152	\N	0	\N	\N	f	0	\N
2886	24	151	\N	0	\N	\N	f	0	\N
2887	24	150	\N	0	\N	\N	f	0	\N
2888	24	149	\N	0	\N	\N	f	0	\N
2889	24	148	\N	0	\N	\N	f	0	\N
2890	24	147	\N	0	\N	\N	f	0	\N
2891	24	146	\N	0	\N	\N	f	0	\N
2892	24	145	\N	0	\N	\N	f	0	\N
2893	24	144	\N	0	\N	\N	f	0	\N
2894	24	143	\N	0	\N	\N	f	0	\N
2895	24	142	\N	0	\N	\N	f	0	\N
2896	24	141	\N	0	\N	\N	f	0	\N
2897	24	140	\N	0	\N	\N	f	0	\N
2898	24	139	\N	0	\N	\N	f	0	\N
2899	24	138	\N	0	\N	\N	f	0	\N
2900	24	137	\N	0	\N	\N	f	0	\N
2901	24	136	\N	0	\N	\N	f	0	\N
2902	24	135	\N	0	\N	\N	f	0	\N
2903	24	134	\N	0	\N	\N	f	0	\N
2904	24	133	\N	0	\N	\N	f	0	\N
2905	24	132	\N	0	\N	\N	f	0	\N
2906	24	131	\N	0	\N	\N	f	0	\N
2907	24	130	\N	0	\N	\N	f	0	\N
2908	24	129	\N	0	\N	\N	f	0	\N
2909	24	128	\N	0	\N	\N	f	0	\N
2910	24	127	\N	0	\N	\N	f	0	\N
2911	24	126	\N	0	\N	\N	f	0	\N
2912	24	125	\N	0	\N	\N	f	0	\N
2913	24	124	\N	0	\N	\N	f	0	\N
2914	24	123	\N	0	\N	\N	f	0	\N
2915	24	122	\N	0	\N	\N	f	0	\N
2916	24	121	\N	0	\N	\N	f	0	\N
2917	24	120	\N	0	\N	\N	f	0	\N
2918	24	119	\N	0	\N	\N	f	0	\N
2919	24	118	\N	0	\N	\N	f	0	\N
2920	24	117	\N	0	\N	\N	f	0	\N
2921	24	116	\N	0	\N	\N	f	0	\N
2922	24	115	\N	0	\N	\N	f	0	\N
2923	24	114	\N	0	\N	\N	f	0	\N
2924	24	113	\N	0	\N	\N	f	0	\N
2925	24	112	\N	0	\N	\N	f	0	\N
2926	24	111	\N	0	\N	\N	f	0	\N
2927	24	110	\N	0	\N	\N	f	0	\N
2928	24	109	\N	0	\N	\N	f	0	\N
2929	24	108	\N	0	\N	\N	f	0	\N
2930	24	107	\N	0	\N	\N	f	0	\N
2931	24	106	\N	0	\N	\N	f	0	\N
2932	24	105	\N	0	\N	\N	f	0	\N
2933	24	104	\N	0	\N	\N	f	0	\N
2934	24	103	\N	0	\N	\N	f	0	\N
2935	24	102	\N	0	\N	\N	f	0	\N
2936	24	101	\N	0	\N	\N	f	0	\N
2937	24	100	\N	0	\N	\N	f	0	\N
2938	24	99	\N	0	\N	\N	f	0	\N
2939	24	98	\N	0	\N	\N	f	0	\N
2940	24	97	\N	0	\N	\N	f	0	\N
2941	24	96	\N	0	\N	\N	f	0	\N
2942	24	95	\N	0	\N	\N	f	0	\N
2943	24	94	\N	0	\N	\N	f	0	\N
2944	24	93	\N	0	\N	\N	f	0	\N
2945	24	92	\N	0	\N	\N	f	0	\N
2946	24	91	\N	0	\N	\N	f	0	\N
2947	24	90	\N	0	\N	\N	f	0	\N
2948	24	89	\N	0	\N	\N	f	0	\N
2949	24	88	\N	0	\N	\N	f	0	\N
2950	24	87	\N	0	\N	\N	f	0	\N
2951	24	86	\N	0	\N	\N	f	0	\N
2952	24	85	\N	0	\N	\N	f	0	\N
2953	24	84	\N	0	\N	\N	f	0	\N
2954	24	83	\N	0	\N	\N	f	0	\N
2955	24	82	\N	0	\N	\N	f	0	\N
2956	24	81	\N	0	\N	\N	f	0	\N
2957	24	80	\N	0	\N	\N	f	0	\N
2958	24	79	\N	0	\N	\N	f	0	\N
2959	24	78	\N	0	\N	\N	f	0	\N
2960	24	77	\N	0	\N	\N	f	0	\N
2961	24	76	\N	0	\N	\N	f	0	\N
2962	24	75	\N	0	\N	\N	f	0	\N
2963	24	74	\N	0	\N	\N	f	0	\N
2964	24	73	\N	0	\N	\N	f	0	\N
2965	24	72	\N	0	\N	\N	f	0	\N
2966	24	71	\N	0	\N	\N	f	0	\N
2967	24	70	\N	0	\N	\N	f	0	\N
2968	24	69	\N	0	\N	\N	f	0	\N
2969	24	68	\N	0	\N	\N	f	0	\N
2970	24	67	\N	0	\N	\N	f	0	\N
2971	24	66	\N	0	\N	\N	f	0	\N
2972	24	65	\N	0	\N	\N	f	0	\N
2973	24	64	\N	0	\N	\N	f	0	\N
2974	24	63	\N	0	\N	\N	f	0	\N
2975	24	62	\N	0	\N	\N	f	0	\N
2976	24	61	\N	0	\N	\N	f	0	\N
2977	24	60	\N	0	\N	\N	f	0	\N
2978	24	59	\N	0	\N	\N	f	0	\N
2979	24	58	\N	0	\N	\N	f	0	\N
2980	24	57	\N	0	\N	\N	f	0	\N
2981	24	56	\N	0	\N	\N	f	0	\N
2982	24	55	\N	0	\N	\N	f	0	\N
2983	24	54	\N	0	\N	\N	f	0	\N
2984	24	53	\N	0	\N	\N	f	0	\N
2985	24	52	\N	0	\N	\N	f	0	\N
2986	24	51	\N	0	\N	\N	f	0	\N
2987	24	50	\N	0	\N	\N	f	0	\N
2988	24	49	\N	0	\N	\N	f	0	\N
2989	24	48	\N	0	\N	\N	f	0	\N
2990	24	47	\N	0	\N	\N	f	0	\N
2991	24	46	\N	0	\N	\N	f	0	\N
2992	24	45	\N	0	\N	\N	f	0	\N
2993	24	44	\N	0	\N	\N	f	0	\N
2994	24	43	\N	0	\N	\N	f	0	\N
2995	24	42	\N	0	\N	\N	f	0	\N
2996	24	41	\N	0	\N	\N	f	0	\N
2997	24	40	\N	0	\N	\N	f	0	\N
2998	24	218	\N	0	\N	\N	f	0	\N
2999	24	217	\N	0	\N	\N	f	0	\N
3000	24	216	\N	0	\N	\N	f	0	\N
3001	24	215	\N	0	\N	\N	f	0	\N
3002	24	214	\N	0	\N	\N	f	0	\N
3003	24	213	\N	0	\N	\N	f	0	\N
3004	24	212	\N	0	\N	\N	f	0	\N
3005	24	211	\N	0	\N	\N	f	0	\N
3006	24	210	\N	0	\N	\N	f	0	\N
3007	24	209	\N	0	\N	\N	f	0	\N
3008	24	208	\N	0	\N	\N	f	0	\N
3009	24	207	\N	0	\N	\N	f	0	\N
3010	24	206	\N	0	\N	\N	f	0	\N
3011	24	205	\N	0	\N	\N	f	0	\N
3012	24	204	\N	0	\N	\N	f	0	\N
3013	24	203	\N	0	\N	\N	f	0	\N
3014	24	202	\N	0	\N	\N	f	0	\N
3015	24	201	\N	0	\N	\N	f	0	\N
3016	24	200	\N	0	\N	\N	f	0	\N
3017	24	199	\N	0	\N	\N	f	0	\N
3018	24	198	\N	0	\N	\N	f	0	\N
3019	24	197	\N	0	\N	\N	f	0	\N
3020	24	196	\N	0	\N	\N	f	0	\N
3021	24	195	\N	0	\N	\N	f	0	\N
3022	24	194	\N	0	\N	\N	f	0	\N
3023	24	193	\N	0	\N	\N	f	0	\N
3024	24	192	\N	0	\N	\N	f	0	\N
3025	24	191	\N	0	\N	\N	f	0	\N
3026	24	190	\N	0	\N	\N	f	0	\N
3027	24	189	\N	0	\N	\N	f	0	\N
3028	24	188	\N	0	\N	\N	f	0	\N
3029	24	187	\N	0	\N	\N	f	0	\N
3030	24	186	\N	0	\N	\N	f	0	\N
3031	24	185	\N	0	\N	\N	f	0	\N
3032	24	184	\N	0	\N	\N	f	0	\N
3033	24	183	\N	0	\N	\N	f	0	\N
3034	24	182	\N	0	\N	\N	f	0	\N
3035	24	181	\N	0	\N	\N	f	0	\N
3036	24	401	\N	0	\N	\N	f	0	\N
3037	24	400	\N	0	\N	\N	f	0	\N
3038	24	399	\N	0	\N	\N	f	0	\N
3039	24	398	\N	0	\N	\N	f	0	\N
3040	24	397	\N	0	\N	\N	f	0	\N
3041	24	396	\N	0	\N	\N	f	0	\N
3042	24	395	\N	0	\N	\N	f	0	\N
3043	24	394	\N	0	\N	\N	f	0	\N
3044	24	393	\N	0	\N	\N	f	0	\N
3045	24	392	\N	0	\N	\N	f	0	\N
3046	24	391	\N	0	\N	\N	f	0	\N
3047	24	390	\N	0	\N	\N	f	0	\N
3048	24	389	\N	0	\N	\N	f	0	\N
3049	24	388	\N	0	\N	\N	f	0	\N
3050	24	387	\N	0	\N	\N	f	0	\N
3051	24	386	\N	0	\N	\N	f	0	\N
3052	24	385	\N	0	\N	\N	f	0	\N
3053	24	384	\N	0	\N	\N	f	0	\N
3054	24	383	\N	0	\N	\N	f	0	\N
3055	24	382	\N	0	\N	\N	f	0	\N
3056	24	381	\N	0	\N	\N	f	0	\N
3057	24	380	\N	0	\N	\N	f	0	\N
3058	24	379	\N	0	\N	\N	f	0	\N
3059	24	378	\N	0	\N	\N	f	0	\N
3060	24	377	\N	0	\N	\N	f	0	\N
3061	24	376	\N	0	\N	\N	f	0	\N
3062	24	375	\N	0	\N	\N	f	0	\N
3063	24	374	\N	0	\N	\N	f	0	\N
3064	24	373	\N	0	\N	\N	f	0	\N
3065	24	372	\N	0	\N	\N	f	0	\N
3066	24	371	\N	0	\N	\N	f	0	\N
3067	24	370	\N	0	\N	\N	f	0	\N
3068	24	369	\N	0	\N	\N	f	0	\N
3069	24	368	\N	0	\N	\N	f	0	\N
3070	24	367	\N	0	\N	\N	f	0	\N
3071	24	366	\N	0	\N	\N	f	0	\N
3072	24	365	\N	0	\N	\N	f	0	\N
3073	24	364	\N	0	\N	\N	f	0	\N
3074	24	363	\N	0	\N	\N	f	0	\N
3075	24	362	\N	0	\N	\N	f	0	\N
3076	24	361	\N	0	\N	\N	f	0	\N
3077	24	432	\N	0	\N	\N	f	0	\N
3078	24	431	\N	0	\N	\N	f	0	\N
3079	24	430	\N	0	\N	\N	f	0	\N
3080	24	429	\N	0	\N	\N	f	0	\N
3081	24	428	\N	0	\N	\N	f	0	\N
3082	24	427	\N	0	\N	\N	f	0	\N
3083	24	426	\N	0	\N	\N	f	0	\N
3084	24	425	\N	0	\N	\N	f	0	\N
3085	24	424	\N	0	\N	\N	f	0	\N
3086	24	423	\N	0	\N	\N	f	0	\N
3087	24	422	\N	0	\N	\N	f	0	\N
3088	24	421	\N	0	\N	\N	f	0	\N
3089	24	420	\N	0	\N	\N	f	0	\N
3090	24	419	\N	0	\N	\N	f	0	\N
3091	24	418	\N	0	\N	\N	f	0	\N
3092	24	417	\N	0	\N	\N	f	0	\N
3093	24	416	\N	0	\N	\N	f	0	\N
3094	24	415	\N	0	\N	\N	f	0	\N
3095	24	414	\N	0	\N	\N	f	0	\N
3096	24	413	\N	0	\N	\N	f	0	\N
3097	24	412	\N	0	\N	\N	f	0	\N
3098	24	411	\N	0	\N	\N	f	0	\N
3099	24	410	\N	0	\N	\N	f	0	\N
3100	24	409	\N	0	\N	\N	f	0	\N
3101	24	408	\N	0	\N	\N	f	0	\N
3102	24	407	\N	0	\N	\N	f	0	\N
3103	24	406	\N	0	\N	\N	f	0	\N
3104	24	405	\N	0	\N	\N	f	0	\N
3105	24	404	\N	0	\N	\N	f	0	\N
3106	24	403	\N	0	\N	\N	f	0	\N
3107	24	402	\N	0	\N	\N	f	0	\N
3108	24	39	\N	0	\N	\N	f	0	\N
3109	24	38	\N	0	\N	\N	f	0	\N
3110	24	37	\N	0	\N	\N	f	0	\N
3111	24	36	\N	0	\N	\N	f	0	\N
3112	24	35	\N	0	\N	\N	f	0	\N
3113	24	34	\N	0	\N	\N	f	0	\N
3114	24	33	\N	0	\N	\N	f	0	\N
3115	24	32	\N	0	\N	\N	f	0	\N
3116	24	31	\N	0	\N	\N	f	0	\N
3117	24	30	\N	0	\N	\N	f	0	\N
3118	24	29	\N	0	\N	\N	f	0	\N
3119	24	28	\N	0	\N	\N	f	0	\N
3120	24	27	\N	0	\N	\N	f	0	\N
3121	24	26	\N	0	\N	\N	f	0	\N
3122	24	25	\N	0	\N	\N	f	0	\N
3123	24	24	\N	0	\N	\N	f	0	\N
3124	24	23	\N	0	\N	\N	f	0	\N
3125	24	22	\N	0	\N	\N	f	0	\N
3126	24	21	\N	0	\N	\N	f	0	\N
3127	24	20	\N	0	\N	\N	f	0	\N
3128	24	19	\N	0	\N	\N	f	0	\N
3129	24	18	\N	0	\N	\N	f	0	\N
3130	24	17	\N	0	\N	\N	f	0	\N
3131	24	16	\N	0	\N	\N	f	0	\N
3132	24	15	\N	0	\N	\N	f	0	\N
3133	24	14	\N	0	\N	\N	f	0	\N
3134	24	13	\N	0	\N	\N	f	0	\N
3135	24	12	\N	0	\N	\N	f	0	\N
3136	24	11	\N	0	\N	\N	f	0	\N
3137	24	10	\N	0	\N	\N	f	0	\N
3138	24	9	\N	0	\N	\N	f	0	\N
3139	24	8	\N	0	\N	\N	f	0	\N
3140	24	7	\N	0	\N	\N	f	0	\N
3141	24	6	\N	0	\N	\N	f	0	\N
3142	24	5	\N	0	\N	\N	f	0	\N
3143	24	4	\N	0	\N	\N	f	0	\N
3144	24	3	\N	0	\N	\N	f	0	\N
3145	24	2	\N	0	\N	\N	f	0	\N
3146	24	1	\N	0	\N	\N	f	0	\N
3147	24	323	\N	0	\N	\N	f	0	\N
3148	24	322	\N	0	\N	\N	f	0	\N
3149	24	321	\N	0	\N	\N	f	0	\N
3150	24	320	\N	0	\N	\N	f	0	\N
3151	24	319	\N	0	\N	\N	f	0	\N
3152	24	318	\N	0	\N	\N	f	0	\N
3153	24	317	\N	0	\N	\N	f	0	\N
3154	24	316	\N	0	\N	\N	f	0	\N
3155	24	315	\N	0	\N	\N	f	0	\N
3156	24	314	\N	0	\N	\N	f	0	\N
3157	24	313	\N	0	\N	\N	f	0	\N
3158	24	312	\N	0	\N	\N	f	0	\N
3159	24	311	\N	0	\N	\N	f	0	\N
3160	24	310	\N	0	\N	\N	f	0	\N
3161	24	309	\N	0	\N	\N	f	0	\N
3162	24	308	\N	0	\N	\N	f	0	\N
3163	24	307	\N	0	\N	\N	f	0	\N
3164	24	306	\N	0	\N	\N	f	0	\N
3165	24	305	\N	0	\N	\N	f	0	\N
3166	24	304	\N	0	\N	\N	f	0	\N
3167	24	303	\N	0	\N	\N	f	0	\N
3168	24	302	\N	0	\N	\N	f	0	\N
3169	24	301	\N	0	\N	\N	f	0	\N
3170	24	300	\N	0	\N	\N	f	0	\N
3171	24	299	\N	0	\N	\N	f	0	\N
3172	24	298	\N	0	\N	\N	f	0	\N
3173	24	297	\N	0	\N	\N	f	0	\N
3174	24	296	\N	0	\N	\N	f	0	\N
3175	24	295	\N	0	\N	\N	f	0	\N
3176	24	294	\N	0	\N	\N	f	0	\N
3177	24	293	\N	0	\N	\N	f	0	\N
3178	24	292	\N	0	\N	\N	f	0	\N
3179	24	291	\N	0	\N	\N	f	0	\N
3180	24	290	\N	0	\N	\N	f	0	\N
3181	24	289	\N	0	\N	\N	f	0	\N
3182	24	288	\N	0	\N	\N	f	0	\N
3183	24	287	\N	0	\N	\N	f	0	\N
3184	24	286	\N	0	\N	\N	f	0	\N
3185	24	285	\N	0	\N	\N	f	0	\N
3186	24	284	\N	0	\N	\N	f	0	\N
3187	24	283	\N	0	\N	\N	f	0	\N
3188	24	282	\N	0	\N	\N	f	0	\N
3189	24	281	\N	0	\N	\N	f	0	\N
3190	24	280	\N	0	\N	\N	f	0	\N
3191	24	279	\N	0	\N	\N	f	0	\N
3192	24	278	\N	0	\N	\N	f	0	\N
3193	24	277	\N	0	\N	\N	f	0	\N
3194	24	276	\N	0	\N	\N	f	0	\N
3195	24	275	\N	0	\N	\N	f	0	\N
3196	24	274	\N	0	\N	\N	f	0	\N
3197	24	273	\N	0	\N	\N	f	0	\N
3198	24	272	\N	0	\N	\N	f	0	\N
3199	24	271	\N	0	\N	\N	f	0	\N
3200	24	270	\N	0	\N	\N	f	0	\N
3201	24	269	\N	0	\N	\N	f	0	\N
3202	24	268	\N	0	\N	\N	f	0	\N
3203	24	267	\N	0	\N	\N	f	0	\N
3204	24	266	\N	0	\N	\N	f	0	\N
3205	24	265	\N	0	\N	\N	f	0	\N
3206	24	264	\N	0	\N	\N	f	0	\N
3207	24	263	\N	0	\N	\N	f	0	\N
3208	24	262	\N	0	\N	\N	f	0	\N
3209	24	261	\N	0	\N	\N	f	0	\N
3210	24	260	\N	0	\N	\N	f	0	\N
3211	24	259	\N	0	\N	\N	f	0	\N
3212	24	258	\N	0	\N	\N	f	0	\N
3213	24	257	\N	0	\N	\N	f	0	\N
3214	24	256	\N	0	\N	\N	f	0	\N
3215	24	255	\N	0	\N	\N	f	0	\N
3216	24	254	\N	0	\N	\N	f	0	\N
3217	24	253	\N	0	\N	\N	f	0	\N
3218	24	252	\N	0	\N	\N	f	0	\N
3219	24	251	\N	0	\N	\N	f	0	\N
3220	24	250	\N	0	\N	\N	f	0	\N
3221	24	249	\N	0	\N	\N	f	0	\N
3222	24	248	\N	0	\N	\N	f	0	\N
3223	24	247	\N	0	\N	\N	f	0	\N
3224	24	246	\N	0	\N	\N	f	0	\N
3225	24	245	\N	0	\N	\N	f	0	\N
3226	24	244	\N	0	\N	\N	f	0	\N
3227	24	243	\N	0	\N	\N	f	0	\N
3228	24	242	\N	0	\N	\N	f	0	\N
3229	24	241	\N	0	\N	\N	f	0	\N
3230	24	240	\N	0	\N	\N	f	0	\N
3231	24	239	\N	0	\N	\N	f	0	\N
3232	24	238	\N	0	\N	\N	f	0	\N
3233	24	237	\N	0	\N	\N	f	0	\N
3234	24	236	\N	0	\N	\N	f	0	\N
3235	24	235	\N	0	\N	\N	f	0	\N
3236	24	234	\N	0	\N	\N	f	0	\N
3237	24	233	\N	0	\N	\N	f	0	\N
3238	24	232	\N	0	\N	\N	f	0	\N
3239	24	231	\N	0	\N	\N	f	0	\N
3240	24	230	\N	0	\N	\N	f	0	\N
3241	24	229	\N	0	\N	\N	f	0	\N
3242	24	228	\N	0	\N	\N	f	0	\N
3243	24	227	\N	0	\N	\N	f	0	\N
3244	24	226	\N	0	\N	\N	f	0	\N
3245	24	225	\N	0	\N	\N	f	0	\N
3246	24	224	\N	0	\N	\N	f	0	\N
3247	24	223	\N	0	\N	\N	f	0	\N
3248	24	222	\N	0	\N	\N	f	0	\N
3249	24	221	\N	0	\N	\N	f	0	\N
3250	24	220	\N	0	\N	\N	f	0	\N
3251	24	219	\N	0	\N	\N	f	0	\N
3252	26	145	\N	0	\N	\N	f	0	\N
3253	26	144	\N	0	\N	\N	f	0	\N
3254	26	143	\N	0	\N	\N	f	0	\N
3255	26	142	\N	0	\N	\N	f	0	\N
3256	26	141	\N	0	\N	\N	f	0	\N
3257	26	140	\N	0	\N	\N	f	0	\N
3258	26	139	\N	0	\N	\N	f	0	\N
3259	26	138	\N	0	\N	\N	f	0	\N
3260	26	137	\N	0	\N	\N	f	0	\N
3261	26	136	\N	0	\N	\N	f	0	\N
3262	26	135	\N	0	\N	\N	f	0	\N
3263	26	134	\N	0	\N	\N	f	0	\N
3264	26	133	\N	0	\N	\N	f	0	\N
3265	26	132	\N	0	\N	\N	f	0	\N
3266	26	131	\N	0	\N	\N	f	0	\N
3267	26	130	\N	0	\N	\N	f	0	\N
3268	26	129	\N	0	\N	\N	f	0	\N
3269	26	128	\N	0	\N	\N	f	0	\N
3270	26	127	\N	0	\N	\N	f	0	\N
3271	26	126	\N	0	\N	\N	f	0	\N
3272	26	125	\N	0	\N	\N	f	0	\N
3273	26	124	\N	0	\N	\N	f	0	\N
3274	26	123	\N	0	\N	\N	f	0	\N
3275	26	122	\N	0	\N	\N	f	0	\N
3276	26	121	\N	0	\N	\N	f	0	\N
3277	26	120	\N	0	\N	\N	f	0	\N
3278	26	119	\N	0	\N	\N	f	0	\N
3279	26	118	\N	0	\N	\N	f	0	\N
3280	26	117	\N	0	\N	\N	f	0	\N
3281	26	116	\N	0	\N	\N	f	0	\N
3282	26	115	\N	0	\N	\N	f	0	\N
3283	26	114	\N	0	\N	\N	f	0	\N
3284	26	113	\N	0	\N	\N	f	0	\N
3285	26	112	\N	0	\N	\N	f	0	\N
3286	26	111	\N	0	\N	\N	f	0	\N
3287	26	110	\N	0	\N	\N	f	0	\N
3288	26	109	\N	0	\N	\N	f	0	\N
3289	26	108	\N	0	\N	\N	f	0	\N
3290	26	107	\N	0	\N	\N	f	0	\N
3291	26	106	\N	0	\N	\N	f	0	\N
3292	26	105	\N	0	\N	\N	f	0	\N
3293	26	104	\N	0	\N	\N	f	0	\N
3294	26	103	\N	0	\N	\N	f	0	\N
3295	26	102	\N	0	\N	\N	f	0	\N
3296	26	101	\N	0	\N	\N	f	0	\N
3297	26	100	\N	0	\N	\N	f	0	\N
3298	26	99	\N	0	\N	\N	f	0	\N
3299	26	98	\N	0	\N	\N	f	0	\N
3300	26	97	\N	0	\N	\N	f	0	\N
3301	26	96	\N	0	\N	\N	f	0	\N
3302	26	95	\N	0	\N	\N	f	0	\N
3303	26	94	\N	0	\N	\N	f	0	\N
3304	26	93	\N	0	\N	\N	f	0	\N
3305	26	92	\N	0	\N	\N	f	0	\N
3306	26	91	\N	0	\N	\N	f	0	\N
3307	26	90	\N	0	\N	\N	f	0	\N
3308	26	89	\N	0	\N	\N	f	0	\N
3309	26	88	\N	0	\N	\N	f	0	\N
3310	26	87	\N	0	\N	\N	f	0	\N
3311	26	86	\N	0	\N	\N	f	0	\N
3312	26	85	\N	0	\N	\N	f	0	\N
3313	26	84	\N	0	\N	\N	f	0	\N
3314	26	83	\N	0	\N	\N	f	0	\N
3315	26	82	\N	0	\N	\N	f	0	\N
3316	26	81	\N	0	\N	\N	f	0	\N
3317	26	80	\N	0	\N	\N	f	0	\N
3318	26	79	\N	0	\N	\N	f	0	\N
3319	26	78	\N	0	\N	\N	f	0	\N
3320	26	77	\N	0	\N	\N	f	0	\N
3321	26	76	\N	0	\N	\N	f	0	\N
3322	26	75	\N	0	\N	\N	f	0	\N
3323	26	254	\N	0	\N	\N	f	0	\N
3324	26	253	\N	0	\N	\N	f	0	\N
3325	26	252	\N	0	\N	\N	f	0	\N
3326	26	251	\N	0	\N	\N	f	0	\N
3327	26	250	\N	0	\N	\N	f	0	\N
3328	26	249	\N	0	\N	\N	f	0	\N
3329	26	248	\N	0	\N	\N	f	0	\N
3330	26	247	\N	0	\N	\N	f	0	\N
3331	26	246	\N	0	\N	\N	f	0	\N
3332	26	245	\N	0	\N	\N	f	0	\N
3333	26	244	\N	0	\N	\N	f	0	\N
3334	26	243	\N	0	\N	\N	f	0	\N
3335	26	242	\N	0	\N	\N	f	0	\N
3336	26	241	\N	0	\N	\N	f	0	\N
3337	26	240	\N	0	\N	\N	f	0	\N
3338	26	239	\N	0	\N	\N	f	0	\N
3339	26	238	\N	0	\N	\N	f	0	\N
3340	26	237	\N	0	\N	\N	f	0	\N
3341	26	236	\N	0	\N	\N	f	0	\N
3342	26	235	\N	0	\N	\N	f	0	\N
3343	26	234	\N	0	\N	\N	f	0	\N
3344	26	233	\N	0	\N	\N	f	0	\N
3345	26	232	\N	0	\N	\N	f	0	\N
3346	26	231	\N	0	\N	\N	f	0	\N
3347	26	230	\N	0	\N	\N	f	0	\N
3348	26	229	\N	0	\N	\N	f	0	\N
3349	26	228	\N	0	\N	\N	f	0	\N
3350	26	227	\N	0	\N	\N	f	0	\N
3351	26	226	\N	0	\N	\N	f	0	\N
3352	26	225	\N	0	\N	\N	f	0	\N
3353	26	224	\N	0	\N	\N	f	0	\N
3354	26	223	\N	0	\N	\N	f	0	\N
3355	26	222	\N	0	\N	\N	f	0	\N
3356	26	221	\N	0	\N	\N	f	0	\N
3357	26	220	\N	0	\N	\N	f	0	\N
3358	26	219	\N	0	\N	\N	f	0	\N
3359	26	290	\N	0	\N	\N	f	0	\N
3360	26	289	\N	0	\N	\N	f	0	\N
3361	26	288	\N	0	\N	\N	f	0	\N
3362	26	287	\N	0	\N	\N	f	0	\N
3363	26	286	\N	0	\N	\N	f	0	\N
3364	26	285	\N	0	\N	\N	f	0	\N
3365	26	284	\N	0	\N	\N	f	0	\N
3366	26	283	\N	0	\N	\N	f	0	\N
3367	26	282	\N	0	\N	\N	f	0	\N
3368	26	281	\N	0	\N	\N	f	0	\N
3369	26	280	\N	0	\N	\N	f	0	\N
3370	26	279	\N	0	\N	\N	f	0	\N
3371	26	278	\N	0	\N	\N	f	0	\N
3372	26	277	\N	0	\N	\N	f	0	\N
3373	26	276	\N	0	\N	\N	f	0	\N
3374	26	275	\N	0	\N	\N	f	0	\N
3375	26	274	\N	0	\N	\N	f	0	\N
3376	26	273	\N	0	\N	\N	f	0	\N
3377	26	272	\N	0	\N	\N	f	0	\N
3378	26	271	\N	0	\N	\N	f	0	\N
3379	26	270	\N	0	\N	\N	f	0	\N
3380	26	269	\N	0	\N	\N	f	0	\N
3381	26	268	\N	0	\N	\N	f	0	\N
3382	26	267	\N	0	\N	\N	f	0	\N
3383	26	266	\N	0	\N	\N	f	0	\N
3384	26	265	\N	0	\N	\N	f	0	\N
3385	26	264	\N	0	\N	\N	f	0	\N
3386	26	263	\N	0	\N	\N	f	0	\N
3387	26	262	\N	0	\N	\N	f	0	\N
3388	26	261	\N	0	\N	\N	f	0	\N
3389	26	260	\N	0	\N	\N	f	0	\N
3390	26	259	\N	0	\N	\N	f	0	\N
3391	26	258	\N	0	\N	\N	f	0	\N
3392	26	257	\N	0	\N	\N	f	0	\N
3393	26	256	\N	0	\N	\N	f	0	\N
3394	26	255	\N	0	\N	\N	f	0	\N
3395	26	360	\N	0	\N	\N	f	0	\N
3396	26	359	\N	0	\N	\N	f	0	\N
3397	26	358	\N	0	\N	\N	f	0	\N
3398	26	357	\N	0	\N	\N	f	0	\N
3399	26	356	\N	0	\N	\N	f	0	\N
3400	26	355	\N	0	\N	\N	f	0	\N
3401	26	354	\N	0	\N	\N	f	0	\N
3402	26	353	\N	0	\N	\N	f	0	\N
3403	26	352	\N	0	\N	\N	f	0	\N
3404	26	351	\N	0	\N	\N	f	0	\N
3405	26	350	\N	0	\N	\N	f	0	\N
3406	26	349	\N	0	\N	\N	f	0	\N
3407	26	348	\N	0	\N	\N	f	0	\N
3408	26	347	\N	0	\N	\N	f	0	\N
3409	26	346	\N	0	\N	\N	f	0	\N
3410	26	345	\N	0	\N	\N	f	0	\N
3411	26	344	\N	0	\N	\N	f	0	\N
3412	26	343	\N	0	\N	\N	f	0	\N
3413	26	342	\N	0	\N	\N	f	0	\N
3414	26	341	\N	0	\N	\N	f	0	\N
3415	26	340	\N	0	\N	\N	f	0	\N
3416	26	339	\N	0	\N	\N	f	0	\N
3417	26	338	\N	0	\N	\N	f	0	\N
3418	26	337	\N	0	\N	\N	f	0	\N
3419	26	336	\N	0	\N	\N	f	0	\N
3420	26	335	\N	0	\N	\N	f	0	\N
3421	26	334	\N	0	\N	\N	f	0	\N
3422	26	333	\N	0	\N	\N	f	0	\N
3423	26	332	\N	0	\N	\N	f	0	\N
3424	26	331	\N	0	\N	\N	f	0	\N
3425	26	330	\N	0	\N	\N	f	0	\N
3426	26	329	\N	0	\N	\N	f	0	\N
3427	26	328	\N	0	\N	\N	f	0	\N
3428	26	327	\N	0	\N	\N	f	0	\N
3429	26	326	\N	0	\N	\N	f	0	\N
3430	26	325	\N	0	\N	\N	f	0	\N
3431	26	324	\N	0	\N	\N	f	0	\N
3432	26	218	\N	0	\N	\N	f	0	\N
3433	26	217	\N	0	\N	\N	f	0	\N
3434	26	216	\N	0	\N	\N	f	0	\N
3435	26	215	\N	0	\N	\N	f	0	\N
3436	26	214	\N	0	\N	\N	f	0	\N
3437	26	213	\N	0	\N	\N	f	0	\N
3438	26	212	\N	0	\N	\N	f	0	\N
3439	26	211	\N	0	\N	\N	f	0	\N
3440	26	210	\N	0	\N	\N	f	0	\N
3441	26	209	\N	0	\N	\N	f	0	\N
3442	26	208	\N	0	\N	\N	f	0	\N
3443	26	207	\N	0	\N	\N	f	0	\N
3444	26	206	\N	0	\N	\N	f	0	\N
3445	26	205	\N	0	\N	\N	f	0	\N
3446	26	204	\N	0	\N	\N	f	0	\N
3447	26	203	\N	0	\N	\N	f	0	\N
3448	26	202	\N	0	\N	\N	f	0	\N
3449	26	201	\N	0	\N	\N	f	0	\N
3450	26	200	\N	0	\N	\N	f	0	\N
3451	26	199	\N	0	\N	\N	f	0	\N
3452	26	198	\N	0	\N	\N	f	0	\N
3453	26	197	\N	0	\N	\N	f	0	\N
3454	26	196	\N	0	\N	\N	f	0	\N
3455	26	195	\N	0	\N	\N	f	0	\N
3456	26	194	\N	0	\N	\N	f	0	\N
3457	26	193	\N	0	\N	\N	f	0	\N
3458	26	192	\N	0	\N	\N	f	0	\N
3459	26	191	\N	0	\N	\N	f	0	\N
3460	26	190	\N	0	\N	\N	f	0	\N
3461	26	189	\N	0	\N	\N	f	0	\N
3462	26	188	\N	0	\N	\N	f	0	\N
3463	26	187	\N	0	\N	\N	f	0	\N
3464	26	186	\N	0	\N	\N	f	0	\N
3465	26	185	\N	0	\N	\N	f	0	\N
3466	26	184	\N	0	\N	\N	f	0	\N
3467	26	183	\N	0	\N	\N	f	0	\N
3468	26	182	\N	0	\N	\N	f	0	\N
3469	26	181	\N	0	\N	\N	f	0	\N
3470	26	39	\N	0	\N	\N	f	0	\N
3471	26	38	\N	0	\N	\N	f	0	\N
3472	26	37	\N	0	\N	\N	f	0	\N
3473	26	36	\N	0	\N	\N	f	0	\N
3474	26	35	\N	0	\N	\N	f	0	\N
3475	26	34	\N	0	\N	\N	f	0	\N
3476	26	33	\N	0	\N	\N	f	0	\N
3477	26	32	\N	0	\N	\N	f	0	\N
3478	26	31	\N	0	\N	\N	f	0	\N
3479	26	30	\N	0	\N	\N	f	0	\N
3480	26	29	\N	0	\N	\N	f	0	\N
3481	26	28	\N	0	\N	\N	f	0	\N
3482	26	27	\N	0	\N	\N	f	0	\N
3483	26	26	\N	0	\N	\N	f	0	\N
3484	26	25	\N	0	\N	\N	f	0	\N
3485	26	24	\N	0	\N	\N	f	0	\N
3486	26	23	\N	0	\N	\N	f	0	\N
3487	26	22	\N	0	\N	\N	f	0	\N
3488	26	21	\N	0	\N	\N	f	0	\N
3489	26	20	\N	0	\N	\N	f	0	\N
3490	26	19	\N	0	\N	\N	f	0	\N
3491	26	18	\N	0	\N	\N	f	0	\N
3492	26	17	\N	0	\N	\N	f	0	\N
3493	26	16	\N	0	\N	\N	f	0	\N
3494	26	15	\N	0	\N	\N	f	0	\N
3495	26	14	\N	0	\N	\N	f	0	\N
3496	26	13	\N	0	\N	\N	f	0	\N
3497	26	12	\N	0	\N	\N	f	0	\N
3498	26	11	\N	0	\N	\N	f	0	\N
3499	26	10	\N	0	\N	\N	f	0	\N
3500	26	9	\N	0	\N	\N	f	0	\N
3501	26	8	\N	0	\N	\N	f	0	\N
3502	26	7	\N	0	\N	\N	f	0	\N
3503	26	6	\N	0	\N	\N	f	0	\N
3504	26	5	\N	0	\N	\N	f	0	\N
3505	26	4	\N	0	\N	\N	f	0	\N
3506	26	3	\N	0	\N	\N	f	0	\N
3507	26	2	\N	0	\N	\N	f	0	\N
3508	26	1	\N	0	\N	\N	f	0	\N
3509	26	180	\N	0	\N	\N	f	0	\N
3510	26	179	\N	0	\N	\N	f	0	\N
3511	26	178	\N	0	\N	\N	f	0	\N
3512	26	177	\N	0	\N	\N	f	0	\N
3513	26	176	\N	0	\N	\N	f	0	\N
3514	26	175	\N	0	\N	\N	f	0	\N
3515	26	174	\N	0	\N	\N	f	0	\N
3516	26	173	\N	0	\N	\N	f	0	\N
3517	26	172	\N	0	\N	\N	f	0	\N
3518	26	171	\N	0	\N	\N	f	0	\N
3519	26	170	\N	0	\N	\N	f	0	\N
3520	26	169	\N	0	\N	\N	f	0	\N
3521	26	168	\N	0	\N	\N	f	0	\N
3522	26	167	\N	0	\N	\N	f	0	\N
3523	26	166	\N	0	\N	\N	f	0	\N
3524	26	165	\N	0	\N	\N	f	0	\N
3525	26	164	\N	0	\N	\N	f	0	\N
3526	26	163	\N	0	\N	\N	f	0	\N
3527	26	162	\N	0	\N	\N	f	0	\N
3528	26	161	\N	0	\N	\N	f	0	\N
3529	26	160	\N	0	\N	\N	f	0	\N
3530	26	159	\N	0	\N	\N	f	0	\N
3531	26	158	\N	0	\N	\N	f	0	\N
3532	26	157	\N	0	\N	\N	f	0	\N
3533	26	156	\N	0	\N	\N	f	0	\N
3534	26	155	\N	0	\N	\N	f	0	\N
3535	26	154	\N	0	\N	\N	f	0	\N
3536	26	153	\N	0	\N	\N	f	0	\N
3537	26	152	\N	0	\N	\N	f	0	\N
3538	26	151	\N	0	\N	\N	f	0	\N
3539	26	150	\N	0	\N	\N	f	0	\N
3540	26	149	\N	0	\N	\N	f	0	\N
3541	26	148	\N	0	\N	\N	f	0	\N
3542	26	147	\N	0	\N	\N	f	0	\N
3543	26	146	\N	0	\N	\N	f	0	\N
3544	26	74	\N	0	\N	\N	f	0	\N
3545	26	73	\N	0	\N	\N	f	0	\N
3546	26	72	\N	0	\N	\N	f	0	\N
3547	26	71	\N	0	\N	\N	f	0	\N
3548	26	70	\N	0	\N	\N	f	0	\N
3549	26	69	\N	0	\N	\N	f	0	\N
3550	26	68	\N	0	\N	\N	f	0	\N
3551	26	67	\N	0	\N	\N	f	0	\N
3552	26	66	\N	0	\N	\N	f	0	\N
3553	26	65	\N	0	\N	\N	f	0	\N
3554	26	64	\N	0	\N	\N	f	0	\N
3555	26	63	\N	0	\N	\N	f	0	\N
3556	26	62	\N	0	\N	\N	f	0	\N
3557	26	61	\N	0	\N	\N	f	0	\N
3558	26	60	\N	0	\N	\N	f	0	\N
3559	26	59	\N	0	\N	\N	f	0	\N
3560	26	58	\N	0	\N	\N	f	0	\N
3561	26	57	\N	0	\N	\N	f	0	\N
3562	26	56	\N	0	\N	\N	f	0	\N
3563	26	55	\N	0	\N	\N	f	0	\N
3564	26	54	\N	0	\N	\N	f	0	\N
3565	26	53	\N	0	\N	\N	f	0	\N
3566	26	52	\N	0	\N	\N	f	0	\N
3567	26	51	\N	0	\N	\N	f	0	\N
3568	26	50	\N	0	\N	\N	f	0	\N
3569	26	49	\N	0	\N	\N	f	0	\N
3570	26	48	\N	0	\N	\N	f	0	\N
3571	26	47	\N	0	\N	\N	f	0	\N
3572	26	46	\N	0	\N	\N	f	0	\N
3573	26	45	\N	0	\N	\N	f	0	\N
3574	26	44	\N	0	\N	\N	f	0	\N
3575	26	43	\N	0	\N	\N	f	0	\N
3576	26	42	\N	0	\N	\N	f	0	\N
3577	26	41	\N	0	\N	\N	f	0	\N
3578	26	40	\N	0	\N	\N	f	0	\N
3579	27	39	\N	0	\N	\N	f	0	\N
3580	27	38	\N	0	\N	\N	f	0	\N
3581	27	37	\N	0	\N	\N	f	0	\N
3582	27	36	\N	0	\N	\N	f	0	\N
3583	27	35	\N	0	\N	\N	f	0	\N
3584	27	34	\N	0	\N	\N	f	0	\N
3585	27	33	\N	0	\N	\N	f	0	\N
3586	27	32	\N	0	\N	\N	f	0	\N
3587	27	31	\N	0	\N	\N	f	0	\N
3588	27	30	\N	0	\N	\N	f	0	\N
3589	27	29	\N	0	\N	\N	f	0	\N
3590	27	28	\N	0	\N	\N	f	0	\N
3591	27	27	\N	0	\N	\N	f	0	\N
3592	27	26	\N	0	\N	\N	f	0	\N
3593	27	25	\N	0	\N	\N	f	0	\N
3594	27	24	\N	0	\N	\N	f	0	\N
3595	27	23	\N	0	\N	\N	f	0	\N
3596	27	22	\N	0	\N	\N	f	0	\N
3597	27	21	\N	0	\N	\N	f	0	\N
3598	27	20	\N	0	\N	\N	f	0	\N
3599	27	19	\N	0	\N	\N	f	0	\N
3600	27	18	\N	0	\N	\N	f	0	\N
3601	27	17	\N	0	\N	\N	f	0	\N
3602	27	16	\N	0	\N	\N	f	0	\N
3603	27	15	\N	0	\N	\N	f	0	\N
3604	27	14	\N	0	\N	\N	f	0	\N
3605	27	13	\N	0	\N	\N	f	0	\N
3606	27	12	\N	0	\N	\N	f	0	\N
3607	27	11	\N	0	\N	\N	f	0	\N
3608	27	10	\N	0	\N	\N	f	0	\N
3609	27	9	\N	0	\N	\N	f	0	\N
3610	27	8	\N	0	\N	\N	f	0	\N
3611	27	7	\N	0	\N	\N	f	0	\N
3612	27	6	\N	0	\N	\N	f	0	\N
3613	27	5	\N	0	\N	\N	f	0	\N
3614	27	4	\N	0	\N	\N	f	0	\N
3615	27	3	\N	0	\N	\N	f	0	\N
3616	27	2	\N	0	\N	\N	f	0	\N
3617	27	1	\N	0	\N	\N	f	0	\N
3618	27	145	\N	0	\N	\N	f	0	\N
3619	27	144	\N	0	\N	\N	f	0	\N
3620	27	143	\N	0	\N	\N	f	0	\N
3621	27	142	\N	0	\N	\N	f	0	\N
3622	27	141	\N	0	\N	\N	f	0	\N
3623	27	140	\N	0	\N	\N	f	0	\N
3624	27	139	\N	0	\N	\N	f	0	\N
3625	27	138	\N	0	\N	\N	f	0	\N
3626	27	137	\N	0	\N	\N	f	0	\N
3627	27	136	\N	0	\N	\N	f	0	\N
3628	27	135	\N	0	\N	\N	f	0	\N
3629	27	134	\N	0	\N	\N	f	0	\N
3630	27	133	\N	0	\N	\N	f	0	\N
3631	27	132	\N	0	\N	\N	f	0	\N
3632	27	131	\N	0	\N	\N	f	0	\N
3633	27	130	\N	0	\N	\N	f	0	\N
3634	27	129	\N	0	\N	\N	f	0	\N
3635	27	128	\N	0	\N	\N	f	0	\N
3636	27	127	\N	0	\N	\N	f	0	\N
3637	27	126	\N	0	\N	\N	f	0	\N
3638	27	125	\N	0	\N	\N	f	0	\N
3639	27	124	\N	0	\N	\N	f	0	\N
3640	27	123	\N	0	\N	\N	f	0	\N
3641	27	122	\N	0	\N	\N	f	0	\N
3642	27	121	\N	0	\N	\N	f	0	\N
3643	27	120	\N	0	\N	\N	f	0	\N
3644	27	119	\N	0	\N	\N	f	0	\N
3645	27	118	\N	0	\N	\N	f	0	\N
3646	27	117	\N	0	\N	\N	f	0	\N
3647	27	116	\N	0	\N	\N	f	0	\N
3648	27	115	\N	0	\N	\N	f	0	\N
3649	27	114	\N	0	\N	\N	f	0	\N
3650	27	113	\N	0	\N	\N	f	0	\N
3651	27	112	\N	0	\N	\N	f	0	\N
3652	27	111	\N	0	\N	\N	f	0	\N
3653	27	110	\N	0	\N	\N	f	0	\N
3654	28	401	\N	0	\N	\N	f	0	\N
3655	28	400	\N	0	\N	\N	f	0	\N
3656	28	399	\N	0	\N	\N	f	0	\N
3657	28	398	\N	0	\N	\N	f	0	\N
3658	28	397	\N	0	\N	\N	f	0	\N
3659	28	396	\N	0	\N	\N	f	0	\N
3660	28	395	\N	0	\N	\N	f	0	\N
3661	28	394	\N	0	\N	\N	f	0	\N
3662	28	393	\N	0	\N	\N	f	0	\N
3663	28	392	\N	0	\N	\N	f	0	\N
3664	28	391	\N	0	\N	\N	f	0	\N
3665	28	390	\N	0	\N	\N	f	0	\N
3666	28	389	\N	0	\N	\N	f	0	\N
3667	28	388	\N	0	\N	\N	f	0	\N
3668	28	387	\N	0	\N	\N	f	0	\N
3669	28	386	\N	0	\N	\N	f	0	\N
3670	28	385	\N	0	\N	\N	f	0	\N
3671	28	384	\N	0	\N	\N	f	0	\N
3672	28	383	\N	0	\N	\N	f	0	\N
3673	28	382	\N	0	\N	\N	f	0	\N
3674	28	381	\N	0	\N	\N	f	0	\N
3675	28	380	\N	0	\N	\N	f	0	\N
3676	28	379	\N	0	\N	\N	f	0	\N
3677	28	378	\N	0	\N	\N	f	0	\N
3678	28	377	\N	0	\N	\N	f	0	\N
3679	28	376	\N	0	\N	\N	f	0	\N
3680	28	375	\N	0	\N	\N	f	0	\N
3681	28	374	\N	0	\N	\N	f	0	\N
3682	28	373	\N	0	\N	\N	f	0	\N
3683	28	372	\N	0	\N	\N	f	0	\N
3684	28	371	\N	0	\N	\N	f	0	\N
3685	28	370	\N	0	\N	\N	f	0	\N
3686	28	369	\N	0	\N	\N	f	0	\N
3687	28	368	\N	0	\N	\N	f	0	\N
3688	28	367	\N	0	\N	\N	f	0	\N
3689	28	366	\N	0	\N	\N	f	0	\N
3690	28	365	\N	0	\N	\N	f	0	\N
3691	28	364	\N	0	\N	\N	f	0	\N
3692	28	363	\N	0	\N	\N	f	0	\N
3693	28	362	\N	0	\N	\N	f	0	\N
3694	28	361	\N	0	\N	\N	f	0	\N
3695	28	74	\N	0	\N	\N	f	0	\N
3696	28	73	\N	0	\N	\N	f	0	\N
3697	28	72	\N	0	\N	\N	f	0	\N
3698	28	71	\N	0	\N	\N	f	0	\N
3699	28	70	\N	0	\N	\N	f	0	\N
3700	28	69	\N	0	\N	\N	f	0	\N
3701	28	68	\N	0	\N	\N	f	0	\N
3702	28	67	\N	0	\N	\N	f	0	\N
3703	28	66	\N	0	\N	\N	f	0	\N
3704	28	65	\N	0	\N	\N	f	0	\N
3705	28	64	\N	0	\N	\N	f	0	\N
3706	28	63	\N	0	\N	\N	f	0	\N
3707	28	62	\N	0	\N	\N	f	0	\N
3708	28	61	\N	0	\N	\N	f	0	\N
3709	28	60	\N	0	\N	\N	f	0	\N
3710	28	59	\N	0	\N	\N	f	0	\N
3711	28	58	\N	0	\N	\N	f	0	\N
3712	28	57	\N	0	\N	\N	f	0	\N
3713	28	56	\N	0	\N	\N	f	0	\N
3714	28	55	\N	0	\N	\N	f	0	\N
3715	28	54	\N	0	\N	\N	f	0	\N
3716	28	53	\N	0	\N	\N	f	0	\N
3717	28	52	\N	0	\N	\N	f	0	\N
3718	28	51	\N	0	\N	\N	f	0	\N
3719	28	50	\N	0	\N	\N	f	0	\N
3720	28	49	\N	0	\N	\N	f	0	\N
3721	28	48	\N	0	\N	\N	f	0	\N
3722	28	47	\N	0	\N	\N	f	0	\N
3723	28	46	\N	0	\N	\N	f	0	\N
3724	28	45	\N	0	\N	\N	f	0	\N
3725	28	44	\N	0	\N	\N	f	0	\N
3726	28	43	\N	0	\N	\N	f	0	\N
3727	28	42	\N	0	\N	\N	f	0	\N
3728	28	41	\N	0	\N	\N	f	0	\N
3729	28	40	\N	0	\N	\N	f	0	\N
3730	29	39	\N	0	\N	\N	f	0	\N
3731	29	38	\N	0	\N	\N	f	0	\N
3732	29	37	\N	0	\N	\N	f	0	\N
3733	29	36	\N	0	\N	\N	f	0	\N
3734	29	35	\N	0	\N	\N	f	0	\N
3735	29	34	\N	0	\N	\N	f	0	\N
3736	29	33	\N	0	\N	\N	f	0	\N
3737	29	32	\N	0	\N	\N	f	0	\N
3738	29	31	\N	0	\N	\N	f	0	\N
3739	29	30	\N	0	\N	\N	f	0	\N
3740	29	29	\N	0	\N	\N	f	0	\N
3741	29	28	\N	0	\N	\N	f	0	\N
3742	29	27	\N	0	\N	\N	f	0	\N
3743	29	26	\N	0	\N	\N	f	0	\N
3744	29	25	\N	0	\N	\N	f	0	\N
3745	29	24	\N	0	\N	\N	f	0	\N
3746	29	23	\N	0	\N	\N	f	0	\N
3747	29	22	\N	0	\N	\N	f	0	\N
3748	29	21	\N	0	\N	\N	f	0	\N
3749	29	20	\N	0	\N	\N	f	0	\N
3750	29	19	\N	0	\N	\N	f	0	\N
3751	29	18	\N	0	\N	\N	f	0	\N
3752	29	17	\N	0	\N	\N	f	0	\N
3753	29	16	\N	0	\N	\N	f	0	\N
3754	29	15	\N	0	\N	\N	f	0	\N
3755	29	14	\N	0	\N	\N	f	0	\N
3756	29	13	\N	0	\N	\N	f	0	\N
3757	29	12	\N	0	\N	\N	f	0	\N
3758	29	11	\N	0	\N	\N	f	0	\N
3759	29	10	\N	0	\N	\N	f	0	\N
3760	29	9	\N	0	\N	\N	f	0	\N
3761	29	8	\N	0	\N	\N	f	0	\N
3762	29	7	\N	0	\N	\N	f	0	\N
3763	29	6	\N	0	\N	\N	f	0	\N
3764	29	5	\N	0	\N	\N	f	0	\N
3765	29	4	\N	0	\N	\N	f	0	\N
3766	29	3	\N	0	\N	\N	f	0	\N
3767	29	2	\N	0	\N	\N	f	0	\N
3768	29	1	\N	0	\N	\N	f	0	\N
3769	30	360	\N	0	\N	\N	f	0	\N
3770	30	359	\N	0	\N	\N	f	0	\N
3771	30	358	\N	0	\N	\N	f	0	\N
3772	30	357	\N	0	\N	\N	f	0	\N
3773	30	356	\N	0	\N	\N	f	0	\N
3774	30	355	\N	0	\N	\N	f	0	\N
3775	30	354	\N	0	\N	\N	f	0	\N
3776	30	353	\N	0	\N	\N	f	0	\N
3777	30	352	\N	0	\N	\N	f	0	\N
3778	30	351	\N	0	\N	\N	f	0	\N
3779	30	350	\N	0	\N	\N	f	0	\N
3780	30	349	\N	0	\N	\N	f	0	\N
3781	30	348	\N	0	\N	\N	f	0	\N
3782	30	347	\N	0	\N	\N	f	0	\N
3783	30	346	\N	0	\N	\N	f	0	\N
3784	30	345	\N	0	\N	\N	f	0	\N
3785	30	344	\N	0	\N	\N	f	0	\N
3786	30	343	\N	0	\N	\N	f	0	\N
3787	30	342	\N	0	\N	\N	f	0	\N
3788	30	341	\N	0	\N	\N	f	0	\N
3789	30	340	\N	0	\N	\N	f	0	\N
3790	30	339	\N	0	\N	\N	f	0	\N
3791	30	338	\N	0	\N	\N	f	0	\N
3792	30	337	\N	0	\N	\N	f	0	\N
3793	30	336	\N	0	\N	\N	f	0	\N
3794	30	335	\N	0	\N	\N	f	0	\N
3795	30	334	\N	0	\N	\N	f	0	\N
3796	30	333	\N	0	\N	\N	f	0	\N
3797	30	332	\N	0	\N	\N	f	0	\N
3798	30	331	\N	0	\N	\N	f	0	\N
3799	30	330	\N	0	\N	\N	f	0	\N
3800	30	329	\N	0	\N	\N	f	0	\N
3801	30	328	\N	0	\N	\N	f	0	\N
3802	30	327	\N	0	\N	\N	f	0	\N
3803	30	326	\N	0	\N	\N	f	0	\N
3804	30	325	\N	0	\N	\N	f	0	\N
3805	30	324	\N	0	\N	\N	f	0	\N
3806	31	360	\N	0	\N	\N	f	0	\N
3807	31	359	\N	0	\N	\N	f	0	\N
3808	31	358	\N	0	\N	\N	f	0	\N
3809	31	357	\N	0	\N	\N	f	0	\N
3810	31	356	\N	0	\N	\N	f	0	\N
3811	31	355	\N	0	\N	\N	f	0	\N
3812	31	354	\N	0	\N	\N	f	0	\N
3813	31	353	\N	0	\N	\N	f	0	\N
3814	31	352	\N	0	\N	\N	f	0	\N
3815	31	351	\N	0	\N	\N	f	0	\N
3816	31	350	\N	0	\N	\N	f	0	\N
3817	31	349	\N	0	\N	\N	f	0	\N
3818	31	348	\N	0	\N	\N	f	0	\N
3819	31	347	\N	0	\N	\N	f	0	\N
3820	31	346	\N	0	\N	\N	f	0	\N
3821	31	345	\N	0	\N	\N	f	0	\N
3822	31	344	\N	0	\N	\N	f	0	\N
3823	31	343	\N	0	\N	\N	f	0	\N
3824	31	342	\N	0	\N	\N	f	0	\N
3825	31	341	\N	0	\N	\N	f	0	\N
3826	31	340	\N	0	\N	\N	f	0	\N
3827	31	339	\N	0	\N	\N	f	0	\N
3828	31	338	\N	0	\N	\N	f	0	\N
3829	31	337	\N	0	\N	\N	f	0	\N
3830	31	336	\N	0	\N	\N	f	0	\N
3831	31	335	\N	0	\N	\N	f	0	\N
3832	31	334	\N	0	\N	\N	f	0	\N
3833	31	333	\N	0	\N	\N	f	0	\N
3834	31	332	\N	0	\N	\N	f	0	\N
3835	31	331	\N	0	\N	\N	f	0	\N
3836	31	330	\N	0	\N	\N	f	0	\N
3837	31	329	\N	0	\N	\N	f	0	\N
3838	31	328	\N	0	\N	\N	f	0	\N
3839	31	327	\N	0	\N	\N	f	0	\N
3840	31	326	\N	0	\N	\N	f	0	\N
3841	31	325	\N	0	\N	\N	f	0	\N
3842	31	324	\N	0	\N	\N	f	0	\N
3843	32	360	\N	0	\N	\N	f	0	\N
3844	32	359	\N	0	\N	\N	f	0	\N
3845	32	358	\N	0	\N	\N	f	0	\N
3846	32	357	\N	0	\N	\N	f	0	\N
3847	32	356	\N	0	\N	\N	f	0	\N
3848	32	355	\N	0	\N	\N	f	0	\N
3849	32	354	\N	0	\N	\N	f	0	\N
3850	32	353	\N	0	\N	\N	f	0	\N
3851	32	352	\N	0	\N	\N	f	0	\N
3852	32	351	\N	0	\N	\N	f	0	\N
3853	32	350	\N	0	\N	\N	f	0	\N
3854	32	349	\N	0	\N	\N	f	0	\N
3855	32	348	\N	0	\N	\N	f	0	\N
3856	32	347	\N	0	\N	\N	f	0	\N
3857	32	346	\N	0	\N	\N	f	0	\N
3858	32	345	\N	0	\N	\N	f	0	\N
3859	32	344	\N	0	\N	\N	f	0	\N
3860	32	343	\N	0	\N	\N	f	0	\N
3861	32	342	\N	0	\N	\N	f	0	\N
3862	32	341	\N	0	\N	\N	f	0	\N
3863	32	340	\N	0	\N	\N	f	0	\N
3864	32	339	\N	0	\N	\N	f	0	\N
3865	32	338	\N	0	\N	\N	f	0	\N
3866	32	337	\N	0	\N	\N	f	0	\N
3867	32	336	\N	0	\N	\N	f	0	\N
3868	32	335	\N	0	\N	\N	f	0	\N
3869	32	334	\N	0	\N	\N	f	0	\N
3870	32	333	\N	0	\N	\N	f	0	\N
3871	32	332	\N	0	\N	\N	f	0	\N
3872	32	331	\N	0	\N	\N	f	0	\N
3873	32	330	\N	0	\N	\N	f	0	\N
3874	32	329	\N	0	\N	\N	f	0	\N
3875	32	328	\N	0	\N	\N	f	0	\N
3876	32	327	\N	0	\N	\N	f	0	\N
3877	32	326	\N	0	\N	\N	f	0	\N
3878	32	325	\N	0	\N	\N	f	0	\N
3879	32	324	\N	0	\N	\N	f	0	\N
3880	32	290	\N	0	\N	\N	f	0	\N
3881	32	289	\N	0	\N	\N	f	0	\N
3882	32	288	\N	0	\N	\N	f	0	\N
3883	32	287	\N	0	\N	\N	f	0	\N
3884	32	286	\N	0	\N	\N	f	0	\N
3885	32	285	\N	0	\N	\N	f	0	\N
3886	32	284	\N	0	\N	\N	f	0	\N
3887	32	283	\N	0	\N	\N	f	0	\N
3888	32	282	\N	0	\N	\N	f	0	\N
3889	32	281	\N	0	\N	\N	f	0	\N
3890	32	280	\N	0	\N	\N	f	0	\N
3891	32	279	\N	0	\N	\N	f	0	\N
3892	32	278	\N	0	\N	\N	f	0	\N
3893	32	277	\N	0	\N	\N	f	0	\N
3894	32	276	\N	0	\N	\N	f	0	\N
3895	32	275	\N	0	\N	\N	f	0	\N
3896	32	274	\N	0	\N	\N	f	0	\N
3897	32	273	\N	0	\N	\N	f	0	\N
3898	32	272	\N	0	\N	\N	f	0	\N
3899	32	271	\N	0	\N	\N	f	0	\N
3900	32	270	\N	0	\N	\N	f	0	\N
3901	32	269	\N	0	\N	\N	f	0	\N
3902	32	268	\N	0	\N	\N	f	0	\N
3903	32	267	\N	0	\N	\N	f	0	\N
3904	32	266	\N	0	\N	\N	f	0	\N
3905	32	265	\N	0	\N	\N	f	0	\N
3906	32	264	\N	0	\N	\N	f	0	\N
3907	32	263	\N	0	\N	\N	f	0	\N
3908	32	262	\N	0	\N	\N	f	0	\N
3909	32	261	\N	0	\N	\N	f	0	\N
3910	32	260	\N	0	\N	\N	f	0	\N
3911	32	259	\N	0	\N	\N	f	0	\N
3912	32	258	\N	0	\N	\N	f	0	\N
3913	32	257	\N	0	\N	\N	f	0	\N
3914	32	256	\N	0	\N	\N	f	0	\N
3915	32	255	\N	0	\N	\N	f	0	\N
3916	32	180	\N	0	\N	\N	f	0	\N
3917	32	179	\N	0	\N	\N	f	0	\N
3918	32	178	\N	0	\N	\N	f	0	\N
3919	32	177	\N	0	\N	\N	f	0	\N
3920	32	176	\N	0	\N	\N	f	0	\N
3921	32	175	\N	0	\N	\N	f	0	\N
3922	32	174	\N	0	\N	\N	f	0	\N
3923	32	173	\N	0	\N	\N	f	0	\N
3924	32	172	\N	0	\N	\N	f	0	\N
3925	32	171	\N	0	\N	\N	f	0	\N
3926	32	170	\N	0	\N	\N	f	0	\N
3927	32	169	\N	0	\N	\N	f	0	\N
3928	32	168	\N	0	\N	\N	f	0	\N
3929	32	167	\N	0	\N	\N	f	0	\N
3930	32	166	\N	0	\N	\N	f	0	\N
3931	32	165	\N	0	\N	\N	f	0	\N
3932	32	164	\N	0	\N	\N	f	0	\N
3933	32	163	\N	0	\N	\N	f	0	\N
3934	32	162	\N	0	\N	\N	f	0	\N
3935	32	161	\N	0	\N	\N	f	0	\N
3936	32	160	\N	0	\N	\N	f	0	\N
3937	32	159	\N	0	\N	\N	f	0	\N
3938	32	158	\N	0	\N	\N	f	0	\N
3939	32	157	\N	0	\N	\N	f	0	\N
3940	32	156	\N	0	\N	\N	f	0	\N
3941	32	155	\N	0	\N	\N	f	0	\N
3942	32	154	\N	0	\N	\N	f	0	\N
3943	32	153	\N	0	\N	\N	f	0	\N
3944	32	152	\N	0	\N	\N	f	0	\N
3945	32	151	\N	0	\N	\N	f	0	\N
3946	32	150	\N	0	\N	\N	f	0	\N
3947	32	149	\N	0	\N	\N	f	0	\N
3948	32	148	\N	0	\N	\N	f	0	\N
3949	32	147	\N	0	\N	\N	f	0	\N
3950	32	146	\N	0	\N	\N	f	0	\N
3951	32	109	\N	0	\N	\N	f	0	\N
3952	32	108	\N	0	\N	\N	f	0	\N
3953	32	107	\N	0	\N	\N	f	0	\N
3954	32	106	\N	0	\N	\N	f	0	\N
3955	32	105	\N	0	\N	\N	f	0	\N
3956	32	104	\N	0	\N	\N	f	0	\N
3957	32	103	\N	0	\N	\N	f	0	\N
3958	32	102	\N	0	\N	\N	f	0	\N
3959	32	101	\N	0	\N	\N	f	0	\N
3960	32	100	\N	0	\N	\N	f	0	\N
3961	32	99	\N	0	\N	\N	f	0	\N
3962	32	98	\N	0	\N	\N	f	0	\N
3963	32	97	\N	0	\N	\N	f	0	\N
3964	32	96	\N	0	\N	\N	f	0	\N
3965	32	95	\N	0	\N	\N	f	0	\N
3966	32	94	\N	0	\N	\N	f	0	\N
3967	32	93	\N	0	\N	\N	f	0	\N
3968	32	92	\N	0	\N	\N	f	0	\N
3969	32	91	\N	0	\N	\N	f	0	\N
3970	32	90	\N	0	\N	\N	f	0	\N
3971	32	89	\N	0	\N	\N	f	0	\N
3972	32	88	\N	0	\N	\N	f	0	\N
3973	32	87	\N	0	\N	\N	f	0	\N
3974	32	86	\N	0	\N	\N	f	0	\N
3975	32	85	\N	0	\N	\N	f	0	\N
3976	32	84	\N	0	\N	\N	f	0	\N
3977	32	83	\N	0	\N	\N	f	0	\N
3978	32	82	\N	0	\N	\N	f	0	\N
3979	32	81	\N	0	\N	\N	f	0	\N
3980	32	80	\N	0	\N	\N	f	0	\N
3981	32	79	\N	0	\N	\N	f	0	\N
3982	32	78	\N	0	\N	\N	f	0	\N
3983	32	77	\N	0	\N	\N	f	0	\N
3984	32	76	\N	0	\N	\N	f	0	\N
3985	32	75	\N	0	\N	\N	f	0	\N
3986	32	74	\N	0	\N	\N	f	0	\N
3987	32	73	\N	0	\N	\N	f	0	\N
3988	32	72	\N	0	\N	\N	f	0	\N
3989	32	71	\N	0	\N	\N	f	0	\N
3990	32	70	\N	0	\N	\N	f	0	\N
3991	32	69	\N	0	\N	\N	f	0	\N
3992	32	68	\N	0	\N	\N	f	0	\N
3993	32	67	\N	0	\N	\N	f	0	\N
3994	32	66	\N	0	\N	\N	f	0	\N
3995	32	65	\N	0	\N	\N	f	0	\N
3996	32	64	\N	0	\N	\N	f	0	\N
3997	32	63	\N	0	\N	\N	f	0	\N
3998	32	62	\N	0	\N	\N	f	0	\N
3999	32	61	\N	0	\N	\N	f	0	\N
4000	32	60	\N	0	\N	\N	f	0	\N
4001	32	59	\N	0	\N	\N	f	0	\N
4002	32	58	\N	0	\N	\N	f	0	\N
4003	32	57	\N	0	\N	\N	f	0	\N
4004	32	56	\N	0	\N	\N	f	0	\N
4005	32	55	\N	0	\N	\N	f	0	\N
4006	32	54	\N	0	\N	\N	f	0	\N
4007	32	53	\N	0	\N	\N	f	0	\N
4008	32	52	\N	0	\N	\N	f	0	\N
4009	32	51	\N	0	\N	\N	f	0	\N
4010	32	50	\N	0	\N	\N	f	0	\N
4011	32	49	\N	0	\N	\N	f	0	\N
4012	32	48	\N	0	\N	\N	f	0	\N
4013	32	47	\N	0	\N	\N	f	0	\N
4014	32	46	\N	0	\N	\N	f	0	\N
4015	32	45	\N	0	\N	\N	f	0	\N
4016	32	44	\N	0	\N	\N	f	0	\N
4017	32	43	\N	0	\N	\N	f	0	\N
4018	32	42	\N	0	\N	\N	f	0	\N
4019	32	41	\N	0	\N	\N	f	0	\N
4020	32	40	\N	0	\N	\N	f	0	\N
4021	32	145	\N	0	\N	\N	f	0	\N
4022	32	144	\N	0	\N	\N	f	0	\N
4023	32	143	\N	0	\N	\N	f	0	\N
4024	32	142	\N	0	\N	\N	f	0	\N
4025	32	141	\N	0	\N	\N	f	0	\N
4026	32	140	\N	0	\N	\N	f	0	\N
4027	32	139	\N	0	\N	\N	f	0	\N
4028	32	138	\N	0	\N	\N	f	0	\N
4029	32	137	\N	0	\N	\N	f	0	\N
4030	32	136	\N	0	\N	\N	f	0	\N
4031	32	135	\N	0	\N	\N	f	0	\N
4032	32	134	\N	0	\N	\N	f	0	\N
4033	32	133	\N	0	\N	\N	f	0	\N
4034	32	132	\N	0	\N	\N	f	0	\N
4035	32	131	\N	0	\N	\N	f	0	\N
4036	32	130	\N	0	\N	\N	f	0	\N
4037	32	129	\N	0	\N	\N	f	0	\N
4038	32	128	\N	0	\N	\N	f	0	\N
4039	32	127	\N	0	\N	\N	f	0	\N
4040	32	126	\N	0	\N	\N	f	0	\N
4041	32	125	\N	0	\N	\N	f	0	\N
4042	32	124	\N	0	\N	\N	f	0	\N
4043	32	123	\N	0	\N	\N	f	0	\N
4044	32	122	\N	0	\N	\N	f	0	\N
4045	32	121	\N	0	\N	\N	f	0	\N
4046	32	120	\N	0	\N	\N	f	0	\N
4047	32	119	\N	0	\N	\N	f	0	\N
4048	32	118	\N	0	\N	\N	f	0	\N
4049	32	117	\N	0	\N	\N	f	0	\N
4050	32	116	\N	0	\N	\N	f	0	\N
4051	32	115	\N	0	\N	\N	f	0	\N
4052	32	114	\N	0	\N	\N	f	0	\N
4053	32	113	\N	0	\N	\N	f	0	\N
4054	32	112	\N	0	\N	\N	f	0	\N
4055	32	111	\N	0	\N	\N	f	0	\N
4056	32	110	\N	0	\N	\N	f	0	\N
4057	32	323	\N	0	\N	\N	f	0	\N
4058	32	322	\N	0	\N	\N	f	0	\N
4059	32	321	\N	0	\N	\N	f	0	\N
4060	32	320	\N	0	\N	\N	f	0	\N
4061	32	319	\N	0	\N	\N	f	0	\N
4062	32	318	\N	0	\N	\N	f	0	\N
4063	32	317	\N	0	\N	\N	f	0	\N
4064	32	316	\N	0	\N	\N	f	0	\N
4065	32	315	\N	0	\N	\N	f	0	\N
4066	32	314	\N	0	\N	\N	f	0	\N
4067	32	313	\N	0	\N	\N	f	0	\N
4068	32	312	\N	0	\N	\N	f	0	\N
4069	32	311	\N	0	\N	\N	f	0	\N
4070	32	310	\N	0	\N	\N	f	0	\N
4071	32	309	\N	0	\N	\N	f	0	\N
4072	32	308	\N	0	\N	\N	f	0	\N
4073	32	307	\N	0	\N	\N	f	0	\N
4074	32	306	\N	0	\N	\N	f	0	\N
4075	32	305	\N	0	\N	\N	f	0	\N
4076	32	304	\N	0	\N	\N	f	0	\N
4077	32	303	\N	0	\N	\N	f	0	\N
4078	32	302	\N	0	\N	\N	f	0	\N
4079	32	301	\N	0	\N	\N	f	0	\N
4080	32	300	\N	0	\N	\N	f	0	\N
4081	32	299	\N	0	\N	\N	f	0	\N
4082	32	298	\N	0	\N	\N	f	0	\N
4083	32	297	\N	0	\N	\N	f	0	\N
4084	32	296	\N	0	\N	\N	f	0	\N
4085	32	295	\N	0	\N	\N	f	0	\N
4086	32	294	\N	0	\N	\N	f	0	\N
4087	32	293	\N	0	\N	\N	f	0	\N
4088	32	292	\N	0	\N	\N	f	0	\N
4089	32	291	\N	0	\N	\N	f	0	\N
4090	32	432	\N	0	\N	\N	f	0	\N
4091	32	431	\N	0	\N	\N	f	0	\N
4092	32	430	\N	0	\N	\N	f	0	\N
4093	32	429	\N	0	\N	\N	f	0	\N
4094	32	428	\N	0	\N	\N	f	0	\N
4095	32	427	\N	0	\N	\N	f	0	\N
4096	32	426	\N	0	\N	\N	f	0	\N
4097	32	425	\N	0	\N	\N	f	0	\N
4098	32	424	\N	0	\N	\N	f	0	\N
4099	32	423	\N	0	\N	\N	f	0	\N
4100	32	422	\N	0	\N	\N	f	0	\N
4101	32	421	\N	0	\N	\N	f	0	\N
4102	32	420	\N	0	\N	\N	f	0	\N
4103	32	419	\N	0	\N	\N	f	0	\N
4104	32	418	\N	0	\N	\N	f	0	\N
4105	32	417	\N	0	\N	\N	f	0	\N
4106	32	416	\N	0	\N	\N	f	0	\N
4107	32	415	\N	0	\N	\N	f	0	\N
4108	32	414	\N	0	\N	\N	f	0	\N
4109	32	413	\N	0	\N	\N	f	0	\N
4110	32	412	\N	0	\N	\N	f	0	\N
4111	32	411	\N	0	\N	\N	f	0	\N
4112	32	410	\N	0	\N	\N	f	0	\N
4113	32	409	\N	0	\N	\N	f	0	\N
4114	32	408	\N	0	\N	\N	f	0	\N
4115	32	407	\N	0	\N	\N	f	0	\N
4116	32	406	\N	0	\N	\N	f	0	\N
4117	32	405	\N	0	\N	\N	f	0	\N
4118	32	404	\N	0	\N	\N	f	0	\N
4119	32	403	\N	0	\N	\N	f	0	\N
4120	32	402	\N	0	\N	\N	f	0	\N
4121	32	401	\N	0	\N	\N	f	0	\N
4122	32	400	\N	0	\N	\N	f	0	\N
4123	32	399	\N	0	\N	\N	f	0	\N
4124	32	398	\N	0	\N	\N	f	0	\N
4125	32	397	\N	0	\N	\N	f	0	\N
4126	32	396	\N	0	\N	\N	f	0	\N
4127	32	395	\N	0	\N	\N	f	0	\N
4128	32	394	\N	0	\N	\N	f	0	\N
4129	32	393	\N	0	\N	\N	f	0	\N
4130	32	392	\N	0	\N	\N	f	0	\N
4131	32	391	\N	0	\N	\N	f	0	\N
4132	32	390	\N	0	\N	\N	f	0	\N
4133	32	389	\N	0	\N	\N	f	0	\N
4134	32	388	\N	0	\N	\N	f	0	\N
4135	32	387	\N	0	\N	\N	f	0	\N
4136	32	386	\N	0	\N	\N	f	0	\N
4137	32	385	\N	0	\N	\N	f	0	\N
4138	32	384	\N	0	\N	\N	f	0	\N
4139	32	383	\N	0	\N	\N	f	0	\N
4140	32	382	\N	0	\N	\N	f	0	\N
4141	32	381	\N	0	\N	\N	f	0	\N
4142	32	380	\N	0	\N	\N	f	0	\N
4143	32	379	\N	0	\N	\N	f	0	\N
4144	32	378	\N	0	\N	\N	f	0	\N
4145	32	377	\N	0	\N	\N	f	0	\N
4146	32	376	\N	0	\N	\N	f	0	\N
4147	32	375	\N	0	\N	\N	f	0	\N
4148	32	374	\N	0	\N	\N	f	0	\N
4149	32	373	\N	0	\N	\N	f	0	\N
4150	32	372	\N	0	\N	\N	f	0	\N
4151	32	371	\N	0	\N	\N	f	0	\N
4152	32	370	\N	0	\N	\N	f	0	\N
4153	32	369	\N	0	\N	\N	f	0	\N
4154	32	368	\N	0	\N	\N	f	0	\N
4155	32	367	\N	0	\N	\N	f	0	\N
4156	32	366	\N	0	\N	\N	f	0	\N
4157	32	365	\N	0	\N	\N	f	0	\N
4158	32	364	\N	0	\N	\N	f	0	\N
4159	32	363	\N	0	\N	\N	f	0	\N
4160	32	362	\N	0	\N	\N	f	0	\N
4161	32	361	\N	0	\N	\N	f	0	\N
4162	32	218	\N	0	\N	\N	f	0	\N
4163	32	217	\N	0	\N	\N	f	0	\N
4164	32	216	\N	0	\N	\N	f	0	\N
4165	32	215	\N	0	\N	\N	f	0	\N
4166	32	214	\N	0	\N	\N	f	0	\N
4167	32	213	\N	0	\N	\N	f	0	\N
4168	32	212	\N	0	\N	\N	f	0	\N
4169	32	211	\N	0	\N	\N	f	0	\N
4170	32	210	\N	0	\N	\N	f	0	\N
4171	32	209	\N	0	\N	\N	f	0	\N
4172	32	208	\N	0	\N	\N	f	0	\N
4173	32	207	\N	0	\N	\N	f	0	\N
4174	32	206	\N	0	\N	\N	f	0	\N
4175	32	205	\N	0	\N	\N	f	0	\N
4176	32	204	\N	0	\N	\N	f	0	\N
4177	32	203	\N	0	\N	\N	f	0	\N
4178	32	202	\N	0	\N	\N	f	0	\N
4179	32	201	\N	0	\N	\N	f	0	\N
4180	32	200	\N	0	\N	\N	f	0	\N
4181	32	199	\N	0	\N	\N	f	0	\N
4182	32	198	\N	0	\N	\N	f	0	\N
4183	32	197	\N	0	\N	\N	f	0	\N
4184	32	196	\N	0	\N	\N	f	0	\N
4185	32	195	\N	0	\N	\N	f	0	\N
4186	32	194	\N	0	\N	\N	f	0	\N
4187	32	193	\N	0	\N	\N	f	0	\N
4188	32	192	\N	0	\N	\N	f	0	\N
4189	32	191	\N	0	\N	\N	f	0	\N
4190	32	190	\N	0	\N	\N	f	0	\N
4191	32	189	\N	0	\N	\N	f	0	\N
4192	32	188	\N	0	\N	\N	f	0	\N
4193	32	187	\N	0	\N	\N	f	0	\N
4194	32	186	\N	0	\N	\N	f	0	\N
4195	32	185	\N	0	\N	\N	f	0	\N
4196	32	184	\N	0	\N	\N	f	0	\N
4197	32	183	\N	0	\N	\N	f	0	\N
4198	32	182	\N	0	\N	\N	f	0	\N
4199	32	181	\N	0	\N	\N	f	0	\N
4200	33	290	\N	0	\N	\N	f	0	\N
4201	33	289	\N	0	\N	\N	f	0	\N
4202	33	288	\N	0	\N	\N	f	0	\N
4203	33	287	\N	0	\N	\N	f	0	\N
4204	33	286	\N	0	\N	\N	f	0	\N
4205	33	285	\N	0	\N	\N	f	0	\N
4206	33	284	\N	0	\N	\N	f	0	\N
4207	33	283	\N	0	\N	\N	f	0	\N
4208	33	282	\N	0	\N	\N	f	0	\N
4209	33	281	\N	0	\N	\N	f	0	\N
4210	33	280	\N	0	\N	\N	f	0	\N
4211	33	279	\N	0	\N	\N	f	0	\N
4212	33	278	\N	0	\N	\N	f	0	\N
4213	33	277	\N	0	\N	\N	f	0	\N
4214	33	276	\N	0	\N	\N	f	0	\N
4215	33	275	\N	0	\N	\N	f	0	\N
4216	33	274	\N	0	\N	\N	f	0	\N
4217	33	273	\N	0	\N	\N	f	0	\N
4218	33	272	\N	0	\N	\N	f	0	\N
4219	33	271	\N	0	\N	\N	f	0	\N
4220	33	270	\N	0	\N	\N	f	0	\N
4221	33	269	\N	0	\N	\N	f	0	\N
4222	33	268	\N	0	\N	\N	f	0	\N
4223	33	267	\N	0	\N	\N	f	0	\N
4224	33	266	\N	0	\N	\N	f	0	\N
4225	33	265	\N	0	\N	\N	f	0	\N
4226	33	264	\N	0	\N	\N	f	0	\N
4227	33	263	\N	0	\N	\N	f	0	\N
4228	33	262	\N	0	\N	\N	f	0	\N
4229	33	261	\N	0	\N	\N	f	0	\N
4230	33	260	\N	0	\N	\N	f	0	\N
4231	33	259	\N	0	\N	\N	f	0	\N
4232	33	258	\N	0	\N	\N	f	0	\N
4233	33	257	\N	0	\N	\N	f	0	\N
4234	33	256	\N	0	\N	\N	f	0	\N
4235	33	255	\N	0	\N	\N	f	0	\N
4236	35	180	\N	0	\N	\N	f	0	\N
4237	35	179	\N	0	\N	\N	f	0	\N
4238	35	178	\N	0	\N	\N	f	0	\N
4239	35	177	\N	0	\N	\N	f	0	\N
4240	35	176	\N	0	\N	\N	f	0	\N
4241	35	175	\N	0	\N	\N	f	0	\N
4242	35	174	\N	0	\N	\N	f	0	\N
4243	35	173	\N	0	\N	\N	f	0	\N
4244	35	172	\N	0	\N	\N	f	0	\N
4245	35	171	\N	0	\N	\N	f	0	\N
4246	35	170	\N	0	\N	\N	f	0	\N
4247	35	169	\N	0	\N	\N	f	0	\N
4248	35	168	\N	0	\N	\N	f	0	\N
4249	35	167	\N	0	\N	\N	f	0	\N
4250	35	166	\N	0	\N	\N	f	0	\N
4251	35	165	\N	0	\N	\N	f	0	\N
4252	35	164	\N	0	\N	\N	f	0	\N
4253	35	163	\N	0	\N	\N	f	0	\N
4254	35	162	\N	0	\N	\N	f	0	\N
4255	35	161	\N	0	\N	\N	f	0	\N
4256	35	160	\N	0	\N	\N	f	0	\N
4257	35	159	\N	0	\N	\N	f	0	\N
4258	35	158	\N	0	\N	\N	f	0	\N
4259	35	157	\N	0	\N	\N	f	0	\N
4260	35	156	\N	0	\N	\N	f	0	\N
4261	35	155	\N	0	\N	\N	f	0	\N
4262	35	154	\N	0	\N	\N	f	0	\N
4263	35	153	\N	0	\N	\N	f	0	\N
4264	35	152	\N	0	\N	\N	f	0	\N
4265	35	151	\N	0	\N	\N	f	0	\N
4266	35	150	\N	0	\N	\N	f	0	\N
4267	35	149	\N	0	\N	\N	f	0	\N
4268	35	148	\N	0	\N	\N	f	0	\N
4269	35	147	\N	0	\N	\N	f	0	\N
4270	35	146	\N	0	\N	\N	f	0	\N
4271	36	39	\N	0	\N	\N	f	0	\N
4272	36	38	\N	0	\N	\N	f	0	\N
4273	36	37	\N	0	\N	\N	f	0	\N
4274	36	36	\N	0	\N	\N	f	0	\N
4275	36	35	\N	0	\N	\N	f	0	\N
4276	36	34	\N	0	\N	\N	f	0	\N
4277	36	33	\N	0	\N	\N	f	0	\N
4278	36	32	\N	0	\N	\N	f	0	\N
4279	36	31	\N	0	\N	\N	f	0	\N
4280	36	30	\N	0	\N	\N	f	0	\N
4281	36	29	\N	0	\N	\N	f	0	\N
4282	36	28	\N	0	\N	\N	f	0	\N
4283	36	27	\N	0	\N	\N	f	0	\N
4284	36	26	\N	0	\N	\N	f	0	\N
4285	36	25	\N	0	\N	\N	f	0	\N
4286	36	24	\N	0	\N	\N	f	0	\N
4287	36	23	\N	0	\N	\N	f	0	\N
4288	36	22	\N	0	\N	\N	f	0	\N
4289	36	21	\N	0	\N	\N	f	0	\N
4290	36	20	\N	0	\N	\N	f	0	\N
4291	36	19	\N	0	\N	\N	f	0	\N
4292	36	18	\N	0	\N	\N	f	0	\N
4293	36	17	\N	0	\N	\N	f	0	\N
4294	36	16	\N	0	\N	\N	f	0	\N
4295	36	15	\N	0	\N	\N	f	0	\N
4296	36	14	\N	0	\N	\N	f	0	\N
4297	36	13	\N	0	\N	\N	f	0	\N
4298	36	12	\N	0	\N	\N	f	0	\N
4299	36	11	\N	0	\N	\N	f	0	\N
4300	36	10	\N	0	\N	\N	f	0	\N
4301	36	9	\N	0	\N	\N	f	0	\N
4302	36	8	\N	0	\N	\N	f	0	\N
4303	36	7	\N	0	\N	\N	f	0	\N
4304	36	6	\N	0	\N	\N	f	0	\N
4305	36	5	\N	0	\N	\N	f	0	\N
4306	36	4	\N	0	\N	\N	f	0	\N
4307	36	3	\N	0	\N	\N	f	0	\N
4308	36	2	\N	0	\N	\N	f	0	\N
4309	36	1	\N	0	\N	\N	f	0	\N
4310	36	360	\N	0	\N	\N	f	0	\N
4311	36	359	\N	0	\N	\N	f	0	\N
4312	36	358	\N	0	\N	\N	f	0	\N
4313	36	357	\N	0	\N	\N	f	0	\N
4314	36	356	\N	0	\N	\N	f	0	\N
4315	36	355	\N	0	\N	\N	f	0	\N
4316	36	354	\N	0	\N	\N	f	0	\N
4317	36	353	\N	0	\N	\N	f	0	\N
4318	36	352	\N	0	\N	\N	f	0	\N
4319	36	351	\N	0	\N	\N	f	0	\N
4320	36	350	\N	0	\N	\N	f	0	\N
4321	36	349	\N	0	\N	\N	f	0	\N
4322	36	348	\N	0	\N	\N	f	0	\N
4323	36	347	\N	0	\N	\N	f	0	\N
4324	36	346	\N	0	\N	\N	f	0	\N
4325	36	345	\N	0	\N	\N	f	0	\N
4326	36	344	\N	0	\N	\N	f	0	\N
4327	36	343	\N	0	\N	\N	f	0	\N
4328	36	342	\N	0	\N	\N	f	0	\N
4329	36	341	\N	0	\N	\N	f	0	\N
4330	36	340	\N	0	\N	\N	f	0	\N
4331	36	339	\N	0	\N	\N	f	0	\N
4332	36	338	\N	0	\N	\N	f	0	\N
4333	36	337	\N	0	\N	\N	f	0	\N
4334	36	336	\N	0	\N	\N	f	0	\N
4335	36	335	\N	0	\N	\N	f	0	\N
4336	36	334	\N	0	\N	\N	f	0	\N
4337	36	333	\N	0	\N	\N	f	0	\N
4338	36	332	\N	0	\N	\N	f	0	\N
4339	36	331	\N	0	\N	\N	f	0	\N
4340	36	330	\N	0	\N	\N	f	0	\N
4341	36	329	\N	0	\N	\N	f	0	\N
4342	36	328	\N	0	\N	\N	f	0	\N
4343	36	327	\N	0	\N	\N	f	0	\N
4344	36	326	\N	0	\N	\N	f	0	\N
4345	36	325	\N	0	\N	\N	f	0	\N
4346	36	324	\N	0	\N	\N	f	0	\N
4347	36	432	\N	0	\N	\N	f	0	\N
4348	36	431	\N	0	\N	\N	f	0	\N
4349	36	430	\N	0	\N	\N	f	0	\N
4350	36	429	\N	0	\N	\N	f	0	\N
4351	36	428	\N	0	\N	\N	f	0	\N
4352	36	427	\N	0	\N	\N	f	0	\N
4353	36	426	\N	0	\N	\N	f	0	\N
4354	36	425	\N	0	\N	\N	f	0	\N
4355	36	424	\N	0	\N	\N	f	0	\N
4356	36	423	\N	0	\N	\N	f	0	\N
4357	36	422	\N	0	\N	\N	f	0	\N
4358	36	421	\N	0	\N	\N	f	0	\N
4359	36	420	\N	0	\N	\N	f	0	\N
4360	36	419	\N	0	\N	\N	f	0	\N
4361	36	418	\N	0	\N	\N	f	0	\N
4362	36	417	\N	0	\N	\N	f	0	\N
4363	36	416	\N	0	\N	\N	f	0	\N
4364	36	415	\N	0	\N	\N	f	0	\N
4365	36	414	\N	0	\N	\N	f	0	\N
4366	36	413	\N	0	\N	\N	f	0	\N
4367	36	412	\N	0	\N	\N	f	0	\N
4368	36	411	\N	0	\N	\N	f	0	\N
4369	36	410	\N	0	\N	\N	f	0	\N
4370	36	409	\N	0	\N	\N	f	0	\N
4371	36	408	\N	0	\N	\N	f	0	\N
4372	36	407	\N	0	\N	\N	f	0	\N
4373	36	406	\N	0	\N	\N	f	0	\N
4374	36	405	\N	0	\N	\N	f	0	\N
4375	36	404	\N	0	\N	\N	f	0	\N
4376	36	403	\N	0	\N	\N	f	0	\N
4377	36	402	\N	0	\N	\N	f	0	\N
4378	36	323	\N	0	\N	\N	f	0	\N
4379	36	322	\N	0	\N	\N	f	0	\N
4380	36	321	\N	0	\N	\N	f	0	\N
4381	36	320	\N	0	\N	\N	f	0	\N
4382	36	319	\N	0	\N	\N	f	0	\N
4383	36	318	\N	0	\N	\N	f	0	\N
4384	36	317	\N	0	\N	\N	f	0	\N
4385	36	316	\N	0	\N	\N	f	0	\N
4386	36	315	\N	0	\N	\N	f	0	\N
4387	36	314	\N	0	\N	\N	f	0	\N
4388	36	313	\N	0	\N	\N	f	0	\N
4389	36	312	\N	0	\N	\N	f	0	\N
4390	36	311	\N	0	\N	\N	f	0	\N
4391	36	310	\N	0	\N	\N	f	0	\N
4392	36	309	\N	0	\N	\N	f	0	\N
4393	36	308	\N	0	\N	\N	f	0	\N
4394	36	307	\N	0	\N	\N	f	0	\N
4395	36	306	\N	0	\N	\N	f	0	\N
4396	36	305	\N	0	\N	\N	f	0	\N
4397	36	304	\N	0	\N	\N	f	0	\N
4398	36	303	\N	0	\N	\N	f	0	\N
4399	36	302	\N	0	\N	\N	f	0	\N
4400	36	301	\N	0	\N	\N	f	0	\N
4401	36	300	\N	0	\N	\N	f	0	\N
4402	36	299	\N	0	\N	\N	f	0	\N
4403	36	298	\N	0	\N	\N	f	0	\N
4404	36	297	\N	0	\N	\N	f	0	\N
4405	36	296	\N	0	\N	\N	f	0	\N
4406	36	295	\N	0	\N	\N	f	0	\N
4407	36	294	\N	0	\N	\N	f	0	\N
4408	36	293	\N	0	\N	\N	f	0	\N
4409	36	292	\N	0	\N	\N	f	0	\N
4410	36	291	\N	0	\N	\N	f	0	\N
4411	37	180	\N	0	\N	\N	f	0	\N
4412	37	179	\N	0	\N	\N	f	0	\N
4413	37	178	\N	0	\N	\N	f	0	\N
4414	37	177	\N	0	\N	\N	f	0	\N
4415	37	176	\N	0	\N	\N	f	0	\N
4416	37	175	\N	0	\N	\N	f	0	\N
4417	37	174	\N	0	\N	\N	f	0	\N
4418	37	173	\N	0	\N	\N	f	0	\N
4419	37	172	\N	0	\N	\N	f	0	\N
4420	37	171	\N	0	\N	\N	f	0	\N
4421	37	170	\N	0	\N	\N	f	0	\N
4422	37	169	\N	0	\N	\N	f	0	\N
4423	37	168	\N	0	\N	\N	f	0	\N
4424	37	167	\N	0	\N	\N	f	0	\N
4425	37	166	\N	0	\N	\N	f	0	\N
4426	37	165	\N	0	\N	\N	f	0	\N
4427	37	164	\N	0	\N	\N	f	0	\N
4428	37	163	\N	0	\N	\N	f	0	\N
4429	37	162	\N	0	\N	\N	f	0	\N
4430	37	161	\N	0	\N	\N	f	0	\N
4431	37	160	\N	0	\N	\N	f	0	\N
4432	37	159	\N	0	\N	\N	f	0	\N
4433	37	158	\N	0	\N	\N	f	0	\N
4434	37	157	\N	0	\N	\N	f	0	\N
4435	37	156	\N	0	\N	\N	f	0	\N
4436	37	155	\N	0	\N	\N	f	0	\N
4437	37	154	\N	0	\N	\N	f	0	\N
4438	37	153	\N	0	\N	\N	f	0	\N
4439	37	152	\N	0	\N	\N	f	0	\N
4440	37	151	\N	0	\N	\N	f	0	\N
4441	37	150	\N	0	\N	\N	f	0	\N
4442	37	149	\N	0	\N	\N	f	0	\N
4443	37	148	\N	0	\N	\N	f	0	\N
4444	37	147	\N	0	\N	\N	f	0	\N
4445	37	146	\N	0	\N	\N	f	0	\N
4446	37	74	\N	0	\N	\N	f	0	\N
4447	37	73	\N	0	\N	\N	f	0	\N
4448	37	72	\N	0	\N	\N	f	0	\N
4449	37	71	\N	0	\N	\N	f	0	\N
4450	37	70	\N	0	\N	\N	f	0	\N
4451	37	69	\N	0	\N	\N	f	0	\N
4452	37	68	\N	0	\N	\N	f	0	\N
4453	37	67	\N	0	\N	\N	f	0	\N
4454	37	66	\N	0	\N	\N	f	0	\N
4455	37	65	\N	0	\N	\N	f	0	\N
4456	37	64	\N	0	\N	\N	f	0	\N
4457	37	63	\N	0	\N	\N	f	0	\N
4458	37	62	\N	0	\N	\N	f	0	\N
4459	37	61	\N	0	\N	\N	f	0	\N
4460	37	60	\N	0	\N	\N	f	0	\N
4461	37	59	\N	0	\N	\N	f	0	\N
4462	37	58	\N	0	\N	\N	f	0	\N
4463	37	57	\N	0	\N	\N	f	0	\N
4464	37	56	\N	0	\N	\N	f	0	\N
4465	37	55	\N	0	\N	\N	f	0	\N
4466	37	54	\N	0	\N	\N	f	0	\N
4467	37	53	\N	0	\N	\N	f	0	\N
4468	37	52	\N	0	\N	\N	f	0	\N
4469	37	51	\N	0	\N	\N	f	0	\N
4470	37	50	\N	0	\N	\N	f	0	\N
4471	37	49	\N	0	\N	\N	f	0	\N
4472	37	48	\N	0	\N	\N	f	0	\N
4473	37	47	\N	0	\N	\N	f	0	\N
4474	37	46	\N	0	\N	\N	f	0	\N
4475	37	45	\N	0	\N	\N	f	0	\N
4476	37	44	\N	0	\N	\N	f	0	\N
4477	37	43	\N	0	\N	\N	f	0	\N
4478	37	42	\N	0	\N	\N	f	0	\N
4479	37	41	\N	0	\N	\N	f	0	\N
4480	37	40	\N	0	\N	\N	f	0	\N
4481	37	109	\N	0	\N	\N	f	0	\N
4482	37	108	\N	0	\N	\N	f	0	\N
4483	37	107	\N	0	\N	\N	f	0	\N
4484	37	106	\N	0	\N	\N	f	0	\N
4485	37	105	\N	0	\N	\N	f	0	\N
4486	37	104	\N	0	\N	\N	f	0	\N
4487	37	103	\N	0	\N	\N	f	0	\N
4488	37	102	\N	0	\N	\N	f	0	\N
4489	37	101	\N	0	\N	\N	f	0	\N
4490	37	100	\N	0	\N	\N	f	0	\N
4491	37	99	\N	0	\N	\N	f	0	\N
4492	37	98	\N	0	\N	\N	f	0	\N
4493	37	97	\N	0	\N	\N	f	0	\N
4494	37	96	\N	0	\N	\N	f	0	\N
4495	37	95	\N	0	\N	\N	f	0	\N
4496	37	94	\N	0	\N	\N	f	0	\N
4497	37	93	\N	0	\N	\N	f	0	\N
4498	37	92	\N	0	\N	\N	f	0	\N
4499	37	91	\N	0	\N	\N	f	0	\N
4500	37	90	\N	0	\N	\N	f	0	\N
4501	37	89	\N	0	\N	\N	f	0	\N
4502	37	88	\N	0	\N	\N	f	0	\N
4503	37	87	\N	0	\N	\N	f	0	\N
4504	37	86	\N	0	\N	\N	f	0	\N
4505	37	85	\N	0	\N	\N	f	0	\N
4506	37	84	\N	0	\N	\N	f	0	\N
4507	37	83	\N	0	\N	\N	f	0	\N
4508	37	82	\N	0	\N	\N	f	0	\N
4509	37	81	\N	0	\N	\N	f	0	\N
4510	37	80	\N	0	\N	\N	f	0	\N
4511	37	79	\N	0	\N	\N	f	0	\N
4512	37	78	\N	0	\N	\N	f	0	\N
4513	37	77	\N	0	\N	\N	f	0	\N
4514	37	76	\N	0	\N	\N	f	0	\N
4515	37	75	\N	0	\N	\N	f	0	\N
4516	37	360	\N	0	\N	\N	f	0	\N
4517	37	359	\N	0	\N	\N	f	0	\N
4518	37	358	\N	0	\N	\N	f	0	\N
4519	37	357	\N	0	\N	\N	f	0	\N
4520	37	356	\N	0	\N	\N	f	0	\N
4521	37	355	\N	0	\N	\N	f	0	\N
4522	37	354	\N	0	\N	\N	f	0	\N
4523	37	353	\N	0	\N	\N	f	0	\N
4524	37	352	\N	0	\N	\N	f	0	\N
4525	37	351	\N	0	\N	\N	f	0	\N
4526	37	350	\N	0	\N	\N	f	0	\N
4527	37	349	\N	0	\N	\N	f	0	\N
4528	37	348	\N	0	\N	\N	f	0	\N
4529	37	347	\N	0	\N	\N	f	0	\N
4530	37	346	\N	0	\N	\N	f	0	\N
4531	37	345	\N	0	\N	\N	f	0	\N
4532	37	344	\N	0	\N	\N	f	0	\N
4533	37	343	\N	0	\N	\N	f	0	\N
4534	37	342	\N	0	\N	\N	f	0	\N
4535	37	341	\N	0	\N	\N	f	0	\N
4536	37	340	\N	0	\N	\N	f	0	\N
4537	37	339	\N	0	\N	\N	f	0	\N
4538	37	338	\N	0	\N	\N	f	0	\N
4539	37	337	\N	0	\N	\N	f	0	\N
4540	37	336	\N	0	\N	\N	f	0	\N
4541	37	335	\N	0	\N	\N	f	0	\N
4542	37	334	\N	0	\N	\N	f	0	\N
4543	37	333	\N	0	\N	\N	f	0	\N
4544	37	332	\N	0	\N	\N	f	0	\N
4545	37	331	\N	0	\N	\N	f	0	\N
4546	37	330	\N	0	\N	\N	f	0	\N
4547	37	329	\N	0	\N	\N	f	0	\N
4548	37	328	\N	0	\N	\N	f	0	\N
4549	37	327	\N	0	\N	\N	f	0	\N
4550	37	326	\N	0	\N	\N	f	0	\N
4551	37	325	\N	0	\N	\N	f	0	\N
4552	37	324	\N	0	\N	\N	f	0	\N
4553	37	432	\N	0	\N	\N	f	0	\N
4554	37	431	\N	0	\N	\N	f	0	\N
4555	37	430	\N	0	\N	\N	f	0	\N
4556	37	429	\N	0	\N	\N	f	0	\N
4557	37	428	\N	0	\N	\N	f	0	\N
4558	37	427	\N	0	\N	\N	f	0	\N
4559	37	426	\N	0	\N	\N	f	0	\N
4560	37	425	\N	0	\N	\N	f	0	\N
4561	37	424	\N	0	\N	\N	f	0	\N
4562	37	423	\N	0	\N	\N	f	0	\N
4563	37	422	\N	0	\N	\N	f	0	\N
4564	37	421	\N	0	\N	\N	f	0	\N
4565	37	420	\N	0	\N	\N	f	0	\N
4566	37	419	\N	0	\N	\N	f	0	\N
4567	37	418	\N	0	\N	\N	f	0	\N
4568	37	417	\N	0	\N	\N	f	0	\N
4569	37	416	\N	0	\N	\N	f	0	\N
4570	37	415	\N	0	\N	\N	f	0	\N
4571	37	414	\N	0	\N	\N	f	0	\N
4572	37	413	\N	0	\N	\N	f	0	\N
4573	37	412	\N	0	\N	\N	f	0	\N
4574	37	411	\N	0	\N	\N	f	0	\N
4575	37	410	\N	0	\N	\N	f	0	\N
4576	37	409	\N	0	\N	\N	f	0	\N
4577	37	408	\N	0	\N	\N	f	0	\N
4578	37	407	\N	0	\N	\N	f	0	\N
4579	37	406	\N	0	\N	\N	f	0	\N
4580	37	405	\N	0	\N	\N	f	0	\N
4581	37	404	\N	0	\N	\N	f	0	\N
4582	37	403	\N	0	\N	\N	f	0	\N
4583	37	402	\N	0	\N	\N	f	0	\N
4584	37	39	\N	0	\N	\N	f	0	\N
4585	37	38	\N	0	\N	\N	f	0	\N
4586	37	37	\N	0	\N	\N	f	0	\N
4587	37	36	\N	0	\N	\N	f	0	\N
4588	37	35	\N	0	\N	\N	f	0	\N
4589	37	34	\N	0	\N	\N	f	0	\N
4590	37	33	\N	0	\N	\N	f	0	\N
4591	37	32	\N	0	\N	\N	f	0	\N
4592	37	31	\N	0	\N	\N	f	0	\N
4593	37	30	\N	0	\N	\N	f	0	\N
4594	37	29	\N	0	\N	\N	f	0	\N
4595	37	28	\N	0	\N	\N	f	0	\N
4596	37	27	\N	0	\N	\N	f	0	\N
4597	37	26	\N	0	\N	\N	f	0	\N
4598	37	25	\N	0	\N	\N	f	0	\N
4599	37	24	\N	0	\N	\N	f	0	\N
4600	37	23	\N	0	\N	\N	f	0	\N
4601	37	22	\N	0	\N	\N	f	0	\N
4602	37	21	\N	0	\N	\N	f	0	\N
4603	37	20	\N	0	\N	\N	f	0	\N
4604	37	19	\N	0	\N	\N	f	0	\N
4605	37	18	\N	0	\N	\N	f	0	\N
4606	37	17	\N	0	\N	\N	f	0	\N
4607	37	16	\N	0	\N	\N	f	0	\N
4608	37	15	\N	0	\N	\N	f	0	\N
4609	37	14	\N	0	\N	\N	f	0	\N
4610	37	13	\N	0	\N	\N	f	0	\N
4611	37	12	\N	0	\N	\N	f	0	\N
4612	37	11	\N	0	\N	\N	f	0	\N
4613	37	10	\N	0	\N	\N	f	0	\N
4614	37	9	\N	0	\N	\N	f	0	\N
4615	37	8	\N	0	\N	\N	f	0	\N
4616	37	7	\N	0	\N	\N	f	0	\N
4617	37	6	\N	0	\N	\N	f	0	\N
4618	37	5	\N	0	\N	\N	f	0	\N
4619	37	4	\N	0	\N	\N	f	0	\N
4620	37	3	\N	0	\N	\N	f	0	\N
4621	37	2	\N	0	\N	\N	f	0	\N
4622	37	1	\N	0	\N	\N	f	0	\N
4623	37	401	\N	0	\N	\N	f	0	\N
4624	37	400	\N	0	\N	\N	f	0	\N
4625	37	399	\N	0	\N	\N	f	0	\N
4626	37	398	\N	0	\N	\N	f	0	\N
4627	37	397	\N	0	\N	\N	f	0	\N
4628	37	396	\N	0	\N	\N	f	0	\N
4629	37	395	\N	0	\N	\N	f	0	\N
4630	37	394	\N	0	\N	\N	f	0	\N
4631	37	393	\N	0	\N	\N	f	0	\N
4632	37	392	\N	0	\N	\N	f	0	\N
4633	37	391	\N	0	\N	\N	f	0	\N
4634	37	390	\N	0	\N	\N	f	0	\N
4635	37	389	\N	0	\N	\N	f	0	\N
4636	37	388	\N	0	\N	\N	f	0	\N
4637	37	387	\N	0	\N	\N	f	0	\N
4638	37	386	\N	0	\N	\N	f	0	\N
4639	37	385	\N	0	\N	\N	f	0	\N
4640	37	384	\N	0	\N	\N	f	0	\N
4641	37	383	\N	0	\N	\N	f	0	\N
4642	37	382	\N	0	\N	\N	f	0	\N
4643	37	381	\N	0	\N	\N	f	0	\N
4644	37	380	\N	0	\N	\N	f	0	\N
4645	37	379	\N	0	\N	\N	f	0	\N
4646	37	378	\N	0	\N	\N	f	0	\N
4647	37	377	\N	0	\N	\N	f	0	\N
4648	37	376	\N	0	\N	\N	f	0	\N
4649	37	375	\N	0	\N	\N	f	0	\N
4650	37	374	\N	0	\N	\N	f	0	\N
4651	37	373	\N	0	\N	\N	f	0	\N
4652	37	372	\N	0	\N	\N	f	0	\N
4653	37	371	\N	0	\N	\N	f	0	\N
4654	37	370	\N	0	\N	\N	f	0	\N
4655	37	369	\N	0	\N	\N	f	0	\N
4656	37	368	\N	0	\N	\N	f	0	\N
4657	37	367	\N	0	\N	\N	f	0	\N
4658	37	366	\N	0	\N	\N	f	0	\N
4659	37	365	\N	0	\N	\N	f	0	\N
4660	37	364	\N	0	\N	\N	f	0	\N
4661	37	363	\N	0	\N	\N	f	0	\N
4662	37	362	\N	0	\N	\N	f	0	\N
4663	37	361	\N	0	\N	\N	f	0	\N
4664	37	254	\N	0	\N	\N	f	0	\N
4665	37	253	\N	0	\N	\N	f	0	\N
4666	37	252	\N	0	\N	\N	f	0	\N
4667	37	251	\N	0	\N	\N	f	0	\N
4668	37	250	\N	0	\N	\N	f	0	\N
4669	37	249	\N	0	\N	\N	f	0	\N
4670	37	248	\N	0	\N	\N	f	0	\N
4671	37	247	\N	0	\N	\N	f	0	\N
4672	37	246	\N	0	\N	\N	f	0	\N
4673	37	245	\N	0	\N	\N	f	0	\N
4674	37	244	\N	0	\N	\N	f	0	\N
4675	37	243	\N	0	\N	\N	f	0	\N
4676	37	242	\N	0	\N	\N	f	0	\N
4677	37	241	\N	0	\N	\N	f	0	\N
4678	37	240	\N	0	\N	\N	f	0	\N
4679	37	239	\N	0	\N	\N	f	0	\N
4680	37	238	\N	0	\N	\N	f	0	\N
4681	37	237	\N	0	\N	\N	f	0	\N
4682	37	236	\N	0	\N	\N	f	0	\N
4683	37	235	\N	0	\N	\N	f	0	\N
4684	37	234	\N	0	\N	\N	f	0	\N
4685	37	233	\N	0	\N	\N	f	0	\N
4686	37	232	\N	0	\N	\N	f	0	\N
4687	37	231	\N	0	\N	\N	f	0	\N
4688	37	230	\N	0	\N	\N	f	0	\N
4689	37	229	\N	0	\N	\N	f	0	\N
4690	37	228	\N	0	\N	\N	f	0	\N
4691	37	227	\N	0	\N	\N	f	0	\N
4692	37	226	\N	0	\N	\N	f	0	\N
4693	37	225	\N	0	\N	\N	f	0	\N
4694	37	224	\N	0	\N	\N	f	0	\N
4695	37	223	\N	0	\N	\N	f	0	\N
4696	37	222	\N	0	\N	\N	f	0	\N
4697	37	221	\N	0	\N	\N	f	0	\N
4698	37	220	\N	0	\N	\N	f	0	\N
4699	37	219	\N	0	\N	\N	f	0	\N
4700	37	323	\N	0	\N	\N	f	0	\N
4701	37	322	\N	0	\N	\N	f	0	\N
4702	37	321	\N	0	\N	\N	f	0	\N
4703	37	320	\N	0	\N	\N	f	0	\N
4704	37	319	\N	0	\N	\N	f	0	\N
4705	37	318	\N	0	\N	\N	f	0	\N
4706	37	317	\N	0	\N	\N	f	0	\N
4707	37	316	\N	0	\N	\N	f	0	\N
4708	37	315	\N	0	\N	\N	f	0	\N
4709	37	314	\N	0	\N	\N	f	0	\N
4710	37	313	\N	0	\N	\N	f	0	\N
4711	37	312	\N	0	\N	\N	f	0	\N
4712	37	311	\N	0	\N	\N	f	0	\N
4713	37	310	\N	0	\N	\N	f	0	\N
4714	37	309	\N	0	\N	\N	f	0	\N
4715	37	308	\N	0	\N	\N	f	0	\N
4716	37	307	\N	0	\N	\N	f	0	\N
4717	37	306	\N	0	\N	\N	f	0	\N
4718	37	305	\N	0	\N	\N	f	0	\N
4719	37	304	\N	0	\N	\N	f	0	\N
4720	37	303	\N	0	\N	\N	f	0	\N
4721	37	302	\N	0	\N	\N	f	0	\N
4722	37	301	\N	0	\N	\N	f	0	\N
4723	37	300	\N	0	\N	\N	f	0	\N
4724	37	299	\N	0	\N	\N	f	0	\N
4725	37	298	\N	0	\N	\N	f	0	\N
4726	37	297	\N	0	\N	\N	f	0	\N
4727	37	296	\N	0	\N	\N	f	0	\N
4728	37	295	\N	0	\N	\N	f	0	\N
4729	37	294	\N	0	\N	\N	f	0	\N
4730	37	293	\N	0	\N	\N	f	0	\N
4731	37	292	\N	0	\N	\N	f	0	\N
4732	37	291	\N	0	\N	\N	f	0	\N
4733	37	145	\N	0	\N	\N	f	0	\N
4734	37	144	\N	0	\N	\N	f	0	\N
4735	37	143	\N	0	\N	\N	f	0	\N
4736	37	142	\N	0	\N	\N	f	0	\N
4737	37	141	\N	0	\N	\N	f	0	\N
4738	37	140	\N	0	\N	\N	f	0	\N
4739	37	139	\N	0	\N	\N	f	0	\N
4740	37	138	\N	0	\N	\N	f	0	\N
4741	37	137	\N	0	\N	\N	f	0	\N
4742	37	136	\N	0	\N	\N	f	0	\N
4743	37	135	\N	0	\N	\N	f	0	\N
4744	37	134	\N	0	\N	\N	f	0	\N
4745	37	133	\N	0	\N	\N	f	0	\N
4746	37	132	\N	0	\N	\N	f	0	\N
4747	37	131	\N	0	\N	\N	f	0	\N
4748	37	130	\N	0	\N	\N	f	0	\N
4749	37	129	\N	0	\N	\N	f	0	\N
4750	37	128	\N	0	\N	\N	f	0	\N
4751	37	127	\N	0	\N	\N	f	0	\N
4752	37	126	\N	0	\N	\N	f	0	\N
4753	37	125	\N	0	\N	\N	f	0	\N
4754	37	124	\N	0	\N	\N	f	0	\N
4755	37	123	\N	0	\N	\N	f	0	\N
4756	37	122	\N	0	\N	\N	f	0	\N
4757	37	121	\N	0	\N	\N	f	0	\N
4758	37	120	\N	0	\N	\N	f	0	\N
4759	37	119	\N	0	\N	\N	f	0	\N
4760	37	118	\N	0	\N	\N	f	0	\N
4761	37	117	\N	0	\N	\N	f	0	\N
4762	37	116	\N	0	\N	\N	f	0	\N
4763	37	115	\N	0	\N	\N	f	0	\N
4764	37	114	\N	0	\N	\N	f	0	\N
4765	37	113	\N	0	\N	\N	f	0	\N
4766	37	112	\N	0	\N	\N	f	0	\N
4767	37	111	\N	0	\N	\N	f	0	\N
4768	37	110	\N	0	\N	\N	f	0	\N
4769	37	290	\N	0	\N	\N	f	0	\N
4770	37	289	\N	0	\N	\N	f	0	\N
4771	37	288	\N	0	\N	\N	f	0	\N
4772	37	287	\N	0	\N	\N	f	0	\N
4773	37	286	\N	0	\N	\N	f	0	\N
4774	37	285	\N	0	\N	\N	f	0	\N
4775	37	284	\N	0	\N	\N	f	0	\N
4776	37	283	\N	0	\N	\N	f	0	\N
4777	37	282	\N	0	\N	\N	f	0	\N
4778	37	281	\N	0	\N	\N	f	0	\N
4779	37	280	\N	0	\N	\N	f	0	\N
4780	37	279	\N	0	\N	\N	f	0	\N
4781	37	278	\N	0	\N	\N	f	0	\N
4782	37	277	\N	0	\N	\N	f	0	\N
4783	37	276	\N	0	\N	\N	f	0	\N
4784	37	275	\N	0	\N	\N	f	0	\N
4785	37	274	\N	0	\N	\N	f	0	\N
4786	37	273	\N	0	\N	\N	f	0	\N
4787	37	272	\N	0	\N	\N	f	0	\N
4788	37	271	\N	0	\N	\N	f	0	\N
4789	37	270	\N	0	\N	\N	f	0	\N
4790	37	269	\N	0	\N	\N	f	0	\N
4791	37	268	\N	0	\N	\N	f	0	\N
4792	37	267	\N	0	\N	\N	f	0	\N
4793	37	266	\N	0	\N	\N	f	0	\N
4794	37	265	\N	0	\N	\N	f	0	\N
4795	37	264	\N	0	\N	\N	f	0	\N
4796	37	263	\N	0	\N	\N	f	0	\N
4797	37	262	\N	0	\N	\N	f	0	\N
4798	37	261	\N	0	\N	\N	f	0	\N
4799	37	260	\N	0	\N	\N	f	0	\N
4800	37	259	\N	0	\N	\N	f	0	\N
4801	37	258	\N	0	\N	\N	f	0	\N
4802	37	257	\N	0	\N	\N	f	0	\N
4803	37	256	\N	0	\N	\N	f	0	\N
4804	37	255	\N	0	\N	\N	f	0	\N
4805	38	401	\N	0	\N	\N	f	0	\N
4806	38	400	\N	0	\N	\N	f	0	\N
4807	38	399	\N	0	\N	\N	f	0	\N
4808	38	398	\N	0	\N	\N	f	0	\N
4809	38	397	\N	0	\N	\N	f	0	\N
4810	38	396	\N	0	\N	\N	f	0	\N
4811	38	395	\N	0	\N	\N	f	0	\N
4812	38	394	\N	0	\N	\N	f	0	\N
4813	38	393	\N	0	\N	\N	f	0	\N
4814	38	392	\N	0	\N	\N	f	0	\N
4815	38	391	\N	0	\N	\N	f	0	\N
4816	38	390	\N	0	\N	\N	f	0	\N
4817	38	389	\N	0	\N	\N	f	0	\N
4818	38	388	\N	0	\N	\N	f	0	\N
4819	38	387	\N	0	\N	\N	f	0	\N
4820	38	386	\N	0	\N	\N	f	0	\N
4821	38	385	\N	0	\N	\N	f	0	\N
4822	38	384	\N	0	\N	\N	f	0	\N
4823	38	383	\N	0	\N	\N	f	0	\N
4824	38	382	\N	0	\N	\N	f	0	\N
4825	38	381	\N	0	\N	\N	f	0	\N
4826	38	380	\N	0	\N	\N	f	0	\N
4827	38	379	\N	0	\N	\N	f	0	\N
4828	38	378	\N	0	\N	\N	f	0	\N
4829	38	377	\N	0	\N	\N	f	0	\N
4830	38	376	\N	0	\N	\N	f	0	\N
4831	38	375	\N	0	\N	\N	f	0	\N
4832	38	374	\N	0	\N	\N	f	0	\N
4833	38	373	\N	0	\N	\N	f	0	\N
4834	38	372	\N	0	\N	\N	f	0	\N
4835	38	371	\N	0	\N	\N	f	0	\N
4836	38	370	\N	0	\N	\N	f	0	\N
4837	38	369	\N	0	\N	\N	f	0	\N
4838	38	368	\N	0	\N	\N	f	0	\N
4839	38	367	\N	0	\N	\N	f	0	\N
4840	38	366	\N	0	\N	\N	f	0	\N
4841	38	365	\N	0	\N	\N	f	0	\N
4842	38	364	\N	0	\N	\N	f	0	\N
4843	38	363	\N	0	\N	\N	f	0	\N
4844	38	362	\N	0	\N	\N	f	0	\N
4845	38	361	\N	0	\N	\N	f	0	\N
4846	39	254	\N	0	\N	\N	f	0	\N
4847	39	253	\N	0	\N	\N	f	0	\N
4848	39	252	\N	0	\N	\N	f	0	\N
4849	39	251	\N	0	\N	\N	f	0	\N
4850	39	250	\N	0	\N	\N	f	0	\N
4851	39	249	\N	0	\N	\N	f	0	\N
4852	39	248	\N	0	\N	\N	f	0	\N
4853	39	247	\N	0	\N	\N	f	0	\N
4854	39	246	\N	0	\N	\N	f	0	\N
4855	39	245	\N	0	\N	\N	f	0	\N
4856	39	244	\N	0	\N	\N	f	0	\N
4857	39	243	\N	0	\N	\N	f	0	\N
4858	39	242	\N	0	\N	\N	f	0	\N
4859	39	241	\N	0	\N	\N	f	0	\N
4860	39	240	\N	0	\N	\N	f	0	\N
4861	39	239	\N	0	\N	\N	f	0	\N
4862	39	238	\N	0	\N	\N	f	0	\N
4863	39	237	\N	0	\N	\N	f	0	\N
4864	39	236	\N	0	\N	\N	f	0	\N
4865	39	235	\N	0	\N	\N	f	0	\N
4866	39	234	\N	0	\N	\N	f	0	\N
4867	39	233	\N	0	\N	\N	f	0	\N
4868	39	232	\N	0	\N	\N	f	0	\N
4869	39	231	\N	0	\N	\N	f	0	\N
4870	39	230	\N	0	\N	\N	f	0	\N
4871	39	229	\N	0	\N	\N	f	0	\N
4872	39	228	\N	0	\N	\N	f	0	\N
4873	39	227	\N	0	\N	\N	f	0	\N
4874	39	226	\N	0	\N	\N	f	0	\N
4875	39	225	\N	0	\N	\N	f	0	\N
4876	39	224	\N	0	\N	\N	f	0	\N
4877	39	223	\N	0	\N	\N	f	0	\N
4878	39	222	\N	0	\N	\N	f	0	\N
4879	39	221	\N	0	\N	\N	f	0	\N
4880	39	220	\N	0	\N	\N	f	0	\N
4881	39	219	\N	0	\N	\N	f	0	\N
4882	39	180	\N	0	\N	\N	f	0	\N
4883	39	179	\N	0	\N	\N	f	0	\N
4884	39	178	\N	0	\N	\N	f	0	\N
4885	39	177	\N	0	\N	\N	f	0	\N
4886	39	176	\N	0	\N	\N	f	0	\N
4887	39	175	\N	0	\N	\N	f	0	\N
4888	39	174	\N	0	\N	\N	f	0	\N
4889	39	173	\N	0	\N	\N	f	0	\N
4890	39	172	\N	0	\N	\N	f	0	\N
4891	39	171	\N	0	\N	\N	f	0	\N
4892	39	170	\N	0	\N	\N	f	0	\N
4893	39	169	\N	0	\N	\N	f	0	\N
4894	39	168	\N	0	\N	\N	f	0	\N
4895	39	167	\N	0	\N	\N	f	0	\N
4896	39	166	\N	0	\N	\N	f	0	\N
4897	39	165	\N	0	\N	\N	f	0	\N
4898	39	164	\N	0	\N	\N	f	0	\N
4899	39	163	\N	0	\N	\N	f	0	\N
4900	39	162	\N	0	\N	\N	f	0	\N
4901	39	161	\N	0	\N	\N	f	0	\N
4902	39	160	\N	0	\N	\N	f	0	\N
4903	39	159	\N	0	\N	\N	f	0	\N
4904	39	158	\N	0	\N	\N	f	0	\N
4905	39	157	\N	0	\N	\N	f	0	\N
4906	39	156	\N	0	\N	\N	f	0	\N
4907	39	155	\N	0	\N	\N	f	0	\N
4908	39	154	\N	0	\N	\N	f	0	\N
4909	39	153	\N	0	\N	\N	f	0	\N
4910	39	152	\N	0	\N	\N	f	0	\N
4911	39	151	\N	0	\N	\N	f	0	\N
4912	39	150	\N	0	\N	\N	f	0	\N
4913	39	149	\N	0	\N	\N	f	0	\N
4914	39	148	\N	0	\N	\N	f	0	\N
4915	39	147	\N	0	\N	\N	f	0	\N
4916	39	146	\N	0	\N	\N	f	0	\N
4917	39	145	\N	0	\N	\N	f	0	\N
4918	39	144	\N	0	\N	\N	f	0	\N
4919	39	143	\N	0	\N	\N	f	0	\N
4920	39	142	\N	0	\N	\N	f	0	\N
4921	39	141	\N	0	\N	\N	f	0	\N
4922	39	140	\N	0	\N	\N	f	0	\N
4923	39	139	\N	0	\N	\N	f	0	\N
4924	39	138	\N	0	\N	\N	f	0	\N
4925	39	137	\N	0	\N	\N	f	0	\N
4926	39	136	\N	0	\N	\N	f	0	\N
4927	39	135	\N	0	\N	\N	f	0	\N
4928	39	134	\N	0	\N	\N	f	0	\N
4929	39	133	\N	0	\N	\N	f	0	\N
4930	39	132	\N	0	\N	\N	f	0	\N
4931	39	131	\N	0	\N	\N	f	0	\N
4932	39	130	\N	0	\N	\N	f	0	\N
4933	39	129	\N	0	\N	\N	f	0	\N
4934	39	128	\N	0	\N	\N	f	0	\N
4935	39	127	\N	0	\N	\N	f	0	\N
4936	39	126	\N	0	\N	\N	f	0	\N
4937	39	125	\N	0	\N	\N	f	0	\N
4938	39	124	\N	0	\N	\N	f	0	\N
4939	39	123	\N	0	\N	\N	f	0	\N
4940	39	122	\N	0	\N	\N	f	0	\N
4941	39	121	\N	0	\N	\N	f	0	\N
4942	39	120	\N	0	\N	\N	f	0	\N
4943	39	119	\N	0	\N	\N	f	0	\N
4944	39	118	\N	0	\N	\N	f	0	\N
4945	39	117	\N	0	\N	\N	f	0	\N
4946	39	116	\N	0	\N	\N	f	0	\N
4947	39	115	\N	0	\N	\N	f	0	\N
4948	39	114	\N	0	\N	\N	f	0	\N
4949	39	113	\N	0	\N	\N	f	0	\N
4950	39	112	\N	0	\N	\N	f	0	\N
4951	39	111	\N	0	\N	\N	f	0	\N
4952	39	110	\N	0	\N	\N	f	0	\N
4953	40	109	\N	0	\N	\N	f	0	\N
4954	40	108	\N	0	\N	\N	f	0	\N
4955	40	107	\N	0	\N	\N	f	0	\N
4956	40	106	\N	0	\N	\N	f	0	\N
4957	40	105	\N	0	\N	\N	f	0	\N
4958	40	104	\N	0	\N	\N	f	0	\N
4959	40	103	\N	0	\N	\N	f	0	\N
4960	40	102	\N	0	\N	\N	f	0	\N
4961	40	101	\N	0	\N	\N	f	0	\N
4962	40	100	\N	0	\N	\N	f	0	\N
4963	40	99	\N	0	\N	\N	f	0	\N
4964	40	98	\N	0	\N	\N	f	0	\N
4965	40	97	\N	0	\N	\N	f	0	\N
4966	40	96	\N	0	\N	\N	f	0	\N
4967	40	95	\N	0	\N	\N	f	0	\N
4968	40	94	\N	0	\N	\N	f	0	\N
4969	40	93	\N	0	\N	\N	f	0	\N
4970	40	92	\N	0	\N	\N	f	0	\N
4971	40	91	\N	0	\N	\N	f	0	\N
4972	40	90	\N	0	\N	\N	f	0	\N
4973	40	89	\N	0	\N	\N	f	0	\N
4974	40	88	\N	0	\N	\N	f	0	\N
4975	40	87	\N	0	\N	\N	f	0	\N
4976	40	86	\N	0	\N	\N	f	0	\N
4977	40	85	\N	0	\N	\N	f	0	\N
4978	40	84	\N	0	\N	\N	f	0	\N
4979	40	83	\N	0	\N	\N	f	0	\N
4980	40	82	\N	0	\N	\N	f	0	\N
4981	40	81	\N	0	\N	\N	f	0	\N
4982	40	80	\N	0	\N	\N	f	0	\N
4983	40	79	\N	0	\N	\N	f	0	\N
4984	40	78	\N	0	\N	\N	f	0	\N
4985	40	77	\N	0	\N	\N	f	0	\N
4986	40	76	\N	0	\N	\N	f	0	\N
4987	40	75	\N	0	\N	\N	f	0	\N
4988	40	290	\N	0	\N	\N	f	0	\N
4989	40	289	\N	0	\N	\N	f	0	\N
4990	40	288	\N	0	\N	\N	f	0	\N
4991	40	287	\N	0	\N	\N	f	0	\N
4992	40	286	\N	0	\N	\N	f	0	\N
4993	40	285	\N	0	\N	\N	f	0	\N
4994	40	284	\N	0	\N	\N	f	0	\N
4995	40	283	\N	0	\N	\N	f	0	\N
4996	40	282	\N	0	\N	\N	f	0	\N
4997	40	281	\N	0	\N	\N	f	0	\N
4998	40	280	\N	0	\N	\N	f	0	\N
4999	40	279	\N	0	\N	\N	f	0	\N
5000	40	278	\N	0	\N	\N	f	0	\N
5001	40	277	\N	0	\N	\N	f	0	\N
5002	40	276	\N	0	\N	\N	f	0	\N
5003	40	275	\N	0	\N	\N	f	0	\N
5004	40	274	\N	0	\N	\N	f	0	\N
5005	40	273	\N	0	\N	\N	f	0	\N
5006	40	272	\N	0	\N	\N	f	0	\N
5007	40	271	\N	0	\N	\N	f	0	\N
5008	40	270	\N	0	\N	\N	f	0	\N
5009	40	269	\N	0	\N	\N	f	0	\N
5010	40	268	\N	0	\N	\N	f	0	\N
5011	40	267	\N	0	\N	\N	f	0	\N
5012	40	266	\N	0	\N	\N	f	0	\N
5013	40	265	\N	0	\N	\N	f	0	\N
5014	40	264	\N	0	\N	\N	f	0	\N
5015	40	263	\N	0	\N	\N	f	0	\N
5016	40	262	\N	0	\N	\N	f	0	\N
5017	40	261	\N	0	\N	\N	f	0	\N
5018	40	260	\N	0	\N	\N	f	0	\N
5019	40	259	\N	0	\N	\N	f	0	\N
5020	40	258	\N	0	\N	\N	f	0	\N
5021	40	257	\N	0	\N	\N	f	0	\N
5022	40	256	\N	0	\N	\N	f	0	\N
5023	40	255	\N	0	\N	\N	f	0	\N
5024	40	74	\N	0	\N	\N	f	0	\N
5025	40	73	\N	0	\N	\N	f	0	\N
5026	40	72	\N	0	\N	\N	f	0	\N
5027	40	71	\N	0	\N	\N	f	0	\N
5028	40	70	\N	0	\N	\N	f	0	\N
5029	40	69	\N	0	\N	\N	f	0	\N
5030	40	68	\N	0	\N	\N	f	0	\N
5031	40	67	\N	0	\N	\N	f	0	\N
5032	40	66	\N	0	\N	\N	f	0	\N
5033	40	65	\N	0	\N	\N	f	0	\N
5034	40	64	\N	0	\N	\N	f	0	\N
5035	40	63	\N	0	\N	\N	f	0	\N
5036	40	62	\N	0	\N	\N	f	0	\N
5037	40	61	\N	0	\N	\N	f	0	\N
5038	40	60	\N	0	\N	\N	f	0	\N
5039	40	59	\N	0	\N	\N	f	0	\N
5040	40	58	\N	0	\N	\N	f	0	\N
5041	40	57	\N	0	\N	\N	f	0	\N
5042	40	56	\N	0	\N	\N	f	0	\N
5043	40	55	\N	0	\N	\N	f	0	\N
5044	40	54	\N	0	\N	\N	f	0	\N
5045	40	53	\N	0	\N	\N	f	0	\N
5046	40	52	\N	0	\N	\N	f	0	\N
5047	40	51	\N	0	\N	\N	f	0	\N
5048	40	50	\N	0	\N	\N	f	0	\N
5049	40	49	\N	0	\N	\N	f	0	\N
5050	40	48	\N	0	\N	\N	f	0	\N
5051	40	47	\N	0	\N	\N	f	0	\N
5052	40	46	\N	0	\N	\N	f	0	\N
5053	40	45	\N	0	\N	\N	f	0	\N
5054	40	44	\N	0	\N	\N	f	0	\N
5055	40	43	\N	0	\N	\N	f	0	\N
5056	40	42	\N	0	\N	\N	f	0	\N
5057	40	41	\N	0	\N	\N	f	0	\N
5058	40	40	\N	0	\N	\N	f	0	\N
5059	42	74	\N	0	\N	\N	f	0	\N
5060	42	73	\N	0	\N	\N	f	0	\N
5061	42	72	\N	0	\N	\N	f	0	\N
5062	42	71	\N	0	\N	\N	f	0	\N
5063	42	70	\N	0	\N	\N	f	0	\N
5064	42	69	\N	0	\N	\N	f	0	\N
5065	42	68	\N	0	\N	\N	f	0	\N
5066	42	67	\N	0	\N	\N	f	0	\N
5067	42	66	\N	0	\N	\N	f	0	\N
5068	42	65	\N	0	\N	\N	f	0	\N
5069	42	64	\N	0	\N	\N	f	0	\N
5070	42	63	\N	0	\N	\N	f	0	\N
5071	42	62	\N	0	\N	\N	f	0	\N
5072	42	61	\N	0	\N	\N	f	0	\N
5073	42	60	\N	0	\N	\N	f	0	\N
5074	42	59	\N	0	\N	\N	f	0	\N
5075	42	58	\N	0	\N	\N	f	0	\N
5076	42	57	\N	0	\N	\N	f	0	\N
5077	42	56	\N	0	\N	\N	f	0	\N
5078	42	55	\N	0	\N	\N	f	0	\N
5079	42	54	\N	0	\N	\N	f	0	\N
5080	42	53	\N	0	\N	\N	f	0	\N
5081	42	52	\N	0	\N	\N	f	0	\N
5082	42	51	\N	0	\N	\N	f	0	\N
5083	42	50	\N	0	\N	\N	f	0	\N
5084	42	49	\N	0	\N	\N	f	0	\N
5085	42	48	\N	0	\N	\N	f	0	\N
5086	42	47	\N	0	\N	\N	f	0	\N
5087	42	46	\N	0	\N	\N	f	0	\N
5088	42	45	\N	0	\N	\N	f	0	\N
5089	42	44	\N	0	\N	\N	f	0	\N
5090	42	43	\N	0	\N	\N	f	0	\N
5091	42	42	\N	0	\N	\N	f	0	\N
5092	42	41	\N	0	\N	\N	f	0	\N
5093	42	40	\N	0	\N	\N	f	0	\N
5094	42	180	\N	0	\N	\N	f	0	\N
5095	42	179	\N	0	\N	\N	f	0	\N
5096	42	178	\N	0	\N	\N	f	0	\N
5097	42	177	\N	0	\N	\N	f	0	\N
5098	42	176	\N	0	\N	\N	f	0	\N
5099	42	175	\N	0	\N	\N	f	0	\N
5100	42	174	\N	0	\N	\N	f	0	\N
5101	42	173	\N	0	\N	\N	f	0	\N
5102	42	172	\N	0	\N	\N	f	0	\N
5103	42	171	\N	0	\N	\N	f	0	\N
5104	42	170	\N	0	\N	\N	f	0	\N
5105	42	169	\N	0	\N	\N	f	0	\N
5106	42	168	\N	0	\N	\N	f	0	\N
5107	42	167	\N	0	\N	\N	f	0	\N
5108	42	166	\N	0	\N	\N	f	0	\N
5109	42	165	\N	0	\N	\N	f	0	\N
5110	42	164	\N	0	\N	\N	f	0	\N
5111	42	163	\N	0	\N	\N	f	0	\N
5112	42	162	\N	0	\N	\N	f	0	\N
5113	42	161	\N	0	\N	\N	f	0	\N
5114	42	160	\N	0	\N	\N	f	0	\N
5115	42	159	\N	0	\N	\N	f	0	\N
5116	42	158	\N	0	\N	\N	f	0	\N
5117	42	157	\N	0	\N	\N	f	0	\N
5118	42	156	\N	0	\N	\N	f	0	\N
5119	42	155	\N	0	\N	\N	f	0	\N
5120	42	154	\N	0	\N	\N	f	0	\N
5121	42	153	\N	0	\N	\N	f	0	\N
5122	42	152	\N	0	\N	\N	f	0	\N
5123	42	151	\N	0	\N	\N	f	0	\N
5124	42	150	\N	0	\N	\N	f	0	\N
5125	42	149	\N	0	\N	\N	f	0	\N
5126	42	148	\N	0	\N	\N	f	0	\N
5127	42	147	\N	0	\N	\N	f	0	\N
5128	42	146	\N	0	\N	\N	f	0	\N
5129	42	254	\N	0	\N	\N	f	0	\N
5130	42	253	\N	0	\N	\N	f	0	\N
5131	42	252	\N	0	\N	\N	f	0	\N
5132	42	251	\N	0	\N	\N	f	0	\N
5133	42	250	\N	0	\N	\N	f	0	\N
5134	42	249	\N	0	\N	\N	f	0	\N
5135	42	248	\N	0	\N	\N	f	0	\N
5136	42	247	\N	0	\N	\N	f	0	\N
5137	42	246	\N	0	\N	\N	f	0	\N
5138	42	245	\N	0	\N	\N	f	0	\N
5139	42	244	\N	0	\N	\N	f	0	\N
5140	42	243	\N	0	\N	\N	f	0	\N
5141	42	242	\N	0	\N	\N	f	0	\N
5142	42	241	\N	0	\N	\N	f	0	\N
5143	42	240	\N	0	\N	\N	f	0	\N
5144	42	239	\N	0	\N	\N	f	0	\N
5145	42	238	\N	0	\N	\N	f	0	\N
5146	42	237	\N	0	\N	\N	f	0	\N
5147	42	236	\N	0	\N	\N	f	0	\N
5148	42	235	\N	0	\N	\N	f	0	\N
5149	42	234	\N	0	\N	\N	f	0	\N
5150	42	233	\N	0	\N	\N	f	0	\N
5151	42	232	\N	0	\N	\N	f	0	\N
5152	42	231	\N	0	\N	\N	f	0	\N
5153	42	230	\N	0	\N	\N	f	0	\N
5154	42	229	\N	0	\N	\N	f	0	\N
5155	42	228	\N	0	\N	\N	f	0	\N
5156	42	227	\N	0	\N	\N	f	0	\N
5157	42	226	\N	0	\N	\N	f	0	\N
5158	42	225	\N	0	\N	\N	f	0	\N
5159	42	224	\N	0	\N	\N	f	0	\N
5160	42	223	\N	0	\N	\N	f	0	\N
5161	42	222	\N	0	\N	\N	f	0	\N
5162	42	221	\N	0	\N	\N	f	0	\N
5163	42	220	\N	0	\N	\N	f	0	\N
5164	42	219	\N	0	\N	\N	f	0	\N
5165	42	432	\N	0	\N	\N	f	0	\N
5166	42	431	\N	0	\N	\N	f	0	\N
5167	42	430	\N	0	\N	\N	f	0	\N
5168	42	429	\N	0	\N	\N	f	0	\N
5169	42	428	\N	0	\N	\N	f	0	\N
5170	42	427	\N	0	\N	\N	f	0	\N
5171	42	426	\N	0	\N	\N	f	0	\N
5172	42	425	\N	0	\N	\N	f	0	\N
5173	42	424	\N	0	\N	\N	f	0	\N
5174	42	423	\N	0	\N	\N	f	0	\N
5175	42	422	\N	0	\N	\N	f	0	\N
5176	42	421	\N	0	\N	\N	f	0	\N
5177	42	420	\N	0	\N	\N	f	0	\N
5178	42	419	\N	0	\N	\N	f	0	\N
5179	42	418	\N	0	\N	\N	f	0	\N
5180	42	417	\N	0	\N	\N	f	0	\N
5181	42	416	\N	0	\N	\N	f	0	\N
5182	42	415	\N	0	\N	\N	f	0	\N
5183	42	414	\N	0	\N	\N	f	0	\N
5184	42	413	\N	0	\N	\N	f	0	\N
5185	42	412	\N	0	\N	\N	f	0	\N
5186	42	411	\N	0	\N	\N	f	0	\N
5187	42	410	\N	0	\N	\N	f	0	\N
5188	42	409	\N	0	\N	\N	f	0	\N
5189	42	408	\N	0	\N	\N	f	0	\N
5190	42	407	\N	0	\N	\N	f	0	\N
5191	42	406	\N	0	\N	\N	f	0	\N
5192	42	405	\N	0	\N	\N	f	0	\N
5193	42	404	\N	0	\N	\N	f	0	\N
5194	42	403	\N	0	\N	\N	f	0	\N
5195	42	402	\N	0	\N	\N	f	0	\N
5196	43	254	\N	0	\N	\N	f	0	\N
5197	43	253	\N	0	\N	\N	f	0	\N
5198	43	252	\N	0	\N	\N	f	0	\N
5199	43	251	\N	0	\N	\N	f	0	\N
5200	43	250	\N	0	\N	\N	f	0	\N
5201	43	249	\N	0	\N	\N	f	0	\N
5202	43	248	\N	0	\N	\N	f	0	\N
5203	43	247	\N	0	\N	\N	f	0	\N
5204	43	246	\N	0	\N	\N	f	0	\N
5205	43	245	\N	0	\N	\N	f	0	\N
5206	43	244	\N	0	\N	\N	f	0	\N
5207	43	243	\N	0	\N	\N	f	0	\N
5208	43	242	\N	0	\N	\N	f	0	\N
5209	43	241	\N	0	\N	\N	f	0	\N
5210	43	240	\N	0	\N	\N	f	0	\N
5211	43	239	\N	0	\N	\N	f	0	\N
5212	43	238	\N	0	\N	\N	f	0	\N
5213	43	237	\N	0	\N	\N	f	0	\N
5214	43	236	\N	0	\N	\N	f	0	\N
5215	43	235	\N	0	\N	\N	f	0	\N
5216	43	234	\N	0	\N	\N	f	0	\N
5217	43	233	\N	0	\N	\N	f	0	\N
5218	43	232	\N	0	\N	\N	f	0	\N
5219	43	231	\N	0	\N	\N	f	0	\N
5220	43	230	\N	0	\N	\N	f	0	\N
5221	43	229	\N	0	\N	\N	f	0	\N
5222	43	228	\N	0	\N	\N	f	0	\N
5223	43	227	\N	0	\N	\N	f	0	\N
5224	43	226	\N	0	\N	\N	f	0	\N
5225	43	225	\N	0	\N	\N	f	0	\N
5226	43	224	\N	0	\N	\N	f	0	\N
5227	43	223	\N	0	\N	\N	f	0	\N
5228	43	222	\N	0	\N	\N	f	0	\N
5229	43	221	\N	0	\N	\N	f	0	\N
5230	43	220	\N	0	\N	\N	f	0	\N
5231	43	219	\N	0	\N	\N	f	0	\N
5232	43	39	\N	0	\N	\N	f	0	\N
5233	43	38	\N	0	\N	\N	f	0	\N
5234	43	37	\N	0	\N	\N	f	0	\N
5235	43	36	\N	0	\N	\N	f	0	\N
5236	43	35	\N	0	\N	\N	f	0	\N
5237	43	34	\N	0	\N	\N	f	0	\N
5238	43	33	\N	0	\N	\N	f	0	\N
5239	43	32	\N	0	\N	\N	f	0	\N
5240	43	31	\N	0	\N	\N	f	0	\N
5241	43	30	\N	0	\N	\N	f	0	\N
5242	43	29	\N	0	\N	\N	f	0	\N
5243	43	28	\N	0	\N	\N	f	0	\N
5244	43	27	\N	0	\N	\N	f	0	\N
5245	43	26	\N	0	\N	\N	f	0	\N
5246	43	25	\N	0	\N	\N	f	0	\N
5247	43	24	\N	0	\N	\N	f	0	\N
5248	43	23	\N	0	\N	\N	f	0	\N
5249	43	22	\N	0	\N	\N	f	0	\N
5250	43	21	\N	0	\N	\N	f	0	\N
5251	43	20	\N	0	\N	\N	f	0	\N
5252	43	19	\N	0	\N	\N	f	0	\N
5253	43	18	\N	0	\N	\N	f	0	\N
5254	43	17	\N	0	\N	\N	f	0	\N
5255	43	16	\N	0	\N	\N	f	0	\N
5256	43	15	\N	0	\N	\N	f	0	\N
5257	43	14	\N	0	\N	\N	f	0	\N
5258	43	13	\N	0	\N	\N	f	0	\N
5259	43	12	\N	0	\N	\N	f	0	\N
5260	43	11	\N	0	\N	\N	f	0	\N
5261	43	10	\N	0	\N	\N	f	0	\N
5262	43	9	\N	0	\N	\N	f	0	\N
5263	43	8	\N	0	\N	\N	f	0	\N
5264	43	7	\N	0	\N	\N	f	0	\N
5265	43	6	\N	0	\N	\N	f	0	\N
5266	43	5	\N	0	\N	\N	f	0	\N
5267	43	4	\N	0	\N	\N	f	0	\N
5268	43	3	\N	0	\N	\N	f	0	\N
5269	43	2	\N	0	\N	\N	f	0	\N
5270	43	1	\N	0	\N	\N	f	0	\N
5271	43	360	\N	0	\N	\N	f	0	\N
5272	43	359	\N	0	\N	\N	f	0	\N
5273	43	358	\N	0	\N	\N	f	0	\N
5274	43	357	\N	0	\N	\N	f	0	\N
5275	43	356	\N	0	\N	\N	f	0	\N
5276	43	355	\N	0	\N	\N	f	0	\N
5277	43	354	\N	0	\N	\N	f	0	\N
5278	43	353	\N	0	\N	\N	f	0	\N
5279	43	352	\N	0	\N	\N	f	0	\N
5280	43	351	\N	0	\N	\N	f	0	\N
5281	43	350	\N	0	\N	\N	f	0	\N
5282	43	349	\N	0	\N	\N	f	0	\N
5283	43	348	\N	0	\N	\N	f	0	\N
5284	43	347	\N	0	\N	\N	f	0	\N
5285	43	346	\N	0	\N	\N	f	0	\N
5286	43	345	\N	0	\N	\N	f	0	\N
5287	43	344	\N	0	\N	\N	f	0	\N
5288	43	343	\N	0	\N	\N	f	0	\N
5289	43	342	\N	0	\N	\N	f	0	\N
5290	43	341	\N	0	\N	\N	f	0	\N
5291	43	340	\N	0	\N	\N	f	0	\N
5292	43	339	\N	0	\N	\N	f	0	\N
5293	43	338	\N	0	\N	\N	f	0	\N
5294	43	337	\N	0	\N	\N	f	0	\N
5295	43	336	\N	0	\N	\N	f	0	\N
5296	43	335	\N	0	\N	\N	f	0	\N
5297	43	334	\N	0	\N	\N	f	0	\N
5298	43	333	\N	0	\N	\N	f	0	\N
5299	43	332	\N	0	\N	\N	f	0	\N
5300	43	331	\N	0	\N	\N	f	0	\N
5301	43	330	\N	0	\N	\N	f	0	\N
5302	43	329	\N	0	\N	\N	f	0	\N
5303	43	328	\N	0	\N	\N	f	0	\N
5304	43	327	\N	0	\N	\N	f	0	\N
5305	43	326	\N	0	\N	\N	f	0	\N
5306	43	325	\N	0	\N	\N	f	0	\N
5307	43	324	\N	0	\N	\N	f	0	\N
5308	43	74	\N	0	\N	\N	f	0	\N
5309	43	73	\N	0	\N	\N	f	0	\N
5310	43	72	\N	0	\N	\N	f	0	\N
5311	43	71	\N	0	\N	\N	f	0	\N
5312	43	70	\N	0	\N	\N	f	0	\N
5313	43	69	\N	0	\N	\N	f	0	\N
5314	43	68	\N	0	\N	\N	f	0	\N
5315	43	67	\N	0	\N	\N	f	0	\N
5316	43	66	\N	0	\N	\N	f	0	\N
5317	43	65	\N	0	\N	\N	f	0	\N
5318	43	64	\N	0	\N	\N	f	0	\N
5319	43	63	\N	0	\N	\N	f	0	\N
5320	43	62	\N	0	\N	\N	f	0	\N
5321	43	61	\N	0	\N	\N	f	0	\N
5322	43	60	\N	0	\N	\N	f	0	\N
5323	43	59	\N	0	\N	\N	f	0	\N
5324	43	58	\N	0	\N	\N	f	0	\N
5325	43	57	\N	0	\N	\N	f	0	\N
5326	43	56	\N	0	\N	\N	f	0	\N
5327	43	55	\N	0	\N	\N	f	0	\N
5328	43	54	\N	0	\N	\N	f	0	\N
5329	43	53	\N	0	\N	\N	f	0	\N
5330	43	52	\N	0	\N	\N	f	0	\N
5331	43	51	\N	0	\N	\N	f	0	\N
5332	43	50	\N	0	\N	\N	f	0	\N
5333	43	49	\N	0	\N	\N	f	0	\N
5334	43	48	\N	0	\N	\N	f	0	\N
5335	43	47	\N	0	\N	\N	f	0	\N
5336	43	46	\N	0	\N	\N	f	0	\N
5337	43	45	\N	0	\N	\N	f	0	\N
5338	43	44	\N	0	\N	\N	f	0	\N
5339	43	43	\N	0	\N	\N	f	0	\N
5340	43	42	\N	0	\N	\N	f	0	\N
5341	43	41	\N	0	\N	\N	f	0	\N
5342	43	40	\N	0	\N	\N	f	0	\N
5343	43	290	\N	0	\N	\N	f	0	\N
5344	43	289	\N	0	\N	\N	f	0	\N
5345	43	288	\N	0	\N	\N	f	0	\N
5346	43	287	\N	0	\N	\N	f	0	\N
5347	43	286	\N	0	\N	\N	f	0	\N
5348	43	285	\N	0	\N	\N	f	0	\N
5349	43	284	\N	0	\N	\N	f	0	\N
5350	43	283	\N	0	\N	\N	f	0	\N
5351	43	282	\N	0	\N	\N	f	0	\N
5352	43	281	\N	0	\N	\N	f	0	\N
5353	43	280	\N	0	\N	\N	f	0	\N
5354	43	279	\N	0	\N	\N	f	0	\N
5355	43	278	\N	0	\N	\N	f	0	\N
5356	43	277	\N	0	\N	\N	f	0	\N
5357	43	276	\N	0	\N	\N	f	0	\N
5358	43	275	\N	0	\N	\N	f	0	\N
5359	43	274	\N	0	\N	\N	f	0	\N
5360	43	273	\N	0	\N	\N	f	0	\N
5361	43	272	\N	0	\N	\N	f	0	\N
5362	43	271	\N	0	\N	\N	f	0	\N
5363	43	270	\N	0	\N	\N	f	0	\N
5364	43	269	\N	0	\N	\N	f	0	\N
5365	43	268	\N	0	\N	\N	f	0	\N
5366	43	267	\N	0	\N	\N	f	0	\N
5367	43	266	\N	0	\N	\N	f	0	\N
5368	43	265	\N	0	\N	\N	f	0	\N
5369	43	264	\N	0	\N	\N	f	0	\N
5370	43	263	\N	0	\N	\N	f	0	\N
5371	43	262	\N	0	\N	\N	f	0	\N
5372	43	261	\N	0	\N	\N	f	0	\N
5373	43	260	\N	0	\N	\N	f	0	\N
5374	43	259	\N	0	\N	\N	f	0	\N
5375	43	258	\N	0	\N	\N	f	0	\N
5376	43	257	\N	0	\N	\N	f	0	\N
5377	43	256	\N	0	\N	\N	f	0	\N
5378	43	255	\N	0	\N	\N	f	0	\N
5379	43	218	\N	0	\N	\N	f	0	\N
5380	43	217	\N	0	\N	\N	f	0	\N
5381	43	216	\N	0	\N	\N	f	0	\N
5382	43	215	\N	0	\N	\N	f	0	\N
5383	43	214	\N	0	\N	\N	f	0	\N
5384	43	213	\N	0	\N	\N	f	0	\N
5385	43	212	\N	0	\N	\N	f	0	\N
5386	43	211	\N	0	\N	\N	f	0	\N
5387	43	210	\N	0	\N	\N	f	0	\N
5388	43	209	\N	0	\N	\N	f	0	\N
5389	43	208	\N	0	\N	\N	f	0	\N
5390	43	207	\N	0	\N	\N	f	0	\N
5391	43	206	\N	0	\N	\N	f	0	\N
5392	43	205	\N	0	\N	\N	f	0	\N
5393	43	204	\N	0	\N	\N	f	0	\N
5394	43	203	\N	0	\N	\N	f	0	\N
5395	43	202	\N	0	\N	\N	f	0	\N
5396	43	201	\N	0	\N	\N	f	0	\N
5397	43	200	\N	0	\N	\N	f	0	\N
5398	43	199	\N	0	\N	\N	f	0	\N
5399	43	198	\N	0	\N	\N	f	0	\N
5400	43	197	\N	0	\N	\N	f	0	\N
5401	43	196	\N	0	\N	\N	f	0	\N
5402	43	195	\N	0	\N	\N	f	0	\N
5403	43	194	\N	0	\N	\N	f	0	\N
5404	43	193	\N	0	\N	\N	f	0	\N
5405	43	192	\N	0	\N	\N	f	0	\N
5406	43	191	\N	0	\N	\N	f	0	\N
5407	43	190	\N	0	\N	\N	f	0	\N
5408	43	189	\N	0	\N	\N	f	0	\N
5409	43	188	\N	0	\N	\N	f	0	\N
5410	43	187	\N	0	\N	\N	f	0	\N
5411	43	186	\N	0	\N	\N	f	0	\N
5412	43	185	\N	0	\N	\N	f	0	\N
5413	43	184	\N	0	\N	\N	f	0	\N
5414	43	183	\N	0	\N	\N	f	0	\N
5415	43	182	\N	0	\N	\N	f	0	\N
5416	43	181	\N	0	\N	\N	f	0	\N
5417	44	145	\N	0	\N	\N	f	0	\N
5418	44	144	\N	0	\N	\N	f	0	\N
5419	44	143	\N	0	\N	\N	f	0	\N
5420	44	142	\N	0	\N	\N	f	0	\N
5421	44	141	\N	0	\N	\N	f	0	\N
5422	44	140	\N	0	\N	\N	f	0	\N
5423	44	139	\N	0	\N	\N	f	0	\N
5424	44	138	\N	0	\N	\N	f	0	\N
5425	44	137	\N	0	\N	\N	f	0	\N
5426	44	136	\N	0	\N	\N	f	0	\N
5427	44	135	\N	0	\N	\N	f	0	\N
5428	44	134	\N	0	\N	\N	f	0	\N
5429	44	133	\N	0	\N	\N	f	0	\N
5430	44	132	\N	0	\N	\N	f	0	\N
5431	44	131	\N	0	\N	\N	f	0	\N
5432	44	130	\N	0	\N	\N	f	0	\N
5433	44	129	\N	0	\N	\N	f	0	\N
5434	44	128	\N	0	\N	\N	f	0	\N
5435	44	127	\N	0	\N	\N	f	0	\N
5436	44	126	\N	0	\N	\N	f	0	\N
5437	44	125	\N	0	\N	\N	f	0	\N
5438	44	124	\N	0	\N	\N	f	0	\N
5439	44	123	\N	0	\N	\N	f	0	\N
5440	44	122	\N	0	\N	\N	f	0	\N
5441	44	121	\N	0	\N	\N	f	0	\N
5442	44	120	\N	0	\N	\N	f	0	\N
5443	44	119	\N	0	\N	\N	f	0	\N
5444	44	118	\N	0	\N	\N	f	0	\N
5445	44	117	\N	0	\N	\N	f	0	\N
5446	44	116	\N	0	\N	\N	f	0	\N
5447	44	115	\N	0	\N	\N	f	0	\N
5448	44	114	\N	0	\N	\N	f	0	\N
5449	44	113	\N	0	\N	\N	f	0	\N
5450	44	112	\N	0	\N	\N	f	0	\N
5451	44	111	\N	0	\N	\N	f	0	\N
5452	44	110	\N	0	\N	\N	f	0	\N
5453	44	432	\N	0	\N	\N	f	0	\N
5454	44	431	\N	0	\N	\N	f	0	\N
5455	44	430	\N	0	\N	\N	f	0	\N
5456	44	429	\N	0	\N	\N	f	0	\N
5457	44	428	\N	0	\N	\N	f	0	\N
5458	44	427	\N	0	\N	\N	f	0	\N
5459	44	426	\N	0	\N	\N	f	0	\N
5460	44	425	\N	0	\N	\N	f	0	\N
5461	44	424	\N	0	\N	\N	f	0	\N
5462	44	423	\N	0	\N	\N	f	0	\N
5463	44	422	\N	0	\N	\N	f	0	\N
5464	44	421	\N	0	\N	\N	f	0	\N
5465	44	420	\N	0	\N	\N	f	0	\N
5466	44	419	\N	0	\N	\N	f	0	\N
5467	44	418	\N	0	\N	\N	f	0	\N
5468	44	417	\N	0	\N	\N	f	0	\N
5469	44	416	\N	0	\N	\N	f	0	\N
5470	44	415	\N	0	\N	\N	f	0	\N
5471	44	414	\N	0	\N	\N	f	0	\N
5472	44	413	\N	0	\N	\N	f	0	\N
5473	44	412	\N	0	\N	\N	f	0	\N
5474	44	411	\N	0	\N	\N	f	0	\N
5475	44	410	\N	0	\N	\N	f	0	\N
5476	44	409	\N	0	\N	\N	f	0	\N
5477	44	408	\N	0	\N	\N	f	0	\N
5478	44	407	\N	0	\N	\N	f	0	\N
5479	44	406	\N	0	\N	\N	f	0	\N
5480	44	405	\N	0	\N	\N	f	0	\N
5481	44	404	\N	0	\N	\N	f	0	\N
5482	44	403	\N	0	\N	\N	f	0	\N
5483	44	402	\N	0	\N	\N	f	0	\N
5484	45	180	\N	0	\N	\N	f	0	\N
5485	45	179	\N	0	\N	\N	f	0	\N
5486	45	178	\N	0	\N	\N	f	0	\N
5487	45	177	\N	0	\N	\N	f	0	\N
5488	45	176	\N	0	\N	\N	f	0	\N
5489	45	175	\N	0	\N	\N	f	0	\N
5490	45	174	\N	0	\N	\N	f	0	\N
5491	45	173	\N	0	\N	\N	f	0	\N
5492	45	172	\N	0	\N	\N	f	0	\N
5493	45	171	\N	0	\N	\N	f	0	\N
5494	45	170	\N	0	\N	\N	f	0	\N
5495	45	169	\N	0	\N	\N	f	0	\N
5496	45	168	\N	0	\N	\N	f	0	\N
5497	45	167	\N	0	\N	\N	f	0	\N
5498	45	166	\N	0	\N	\N	f	0	\N
5499	45	165	\N	0	\N	\N	f	0	\N
5500	45	164	\N	0	\N	\N	f	0	\N
5501	45	163	\N	0	\N	\N	f	0	\N
5502	45	162	\N	0	\N	\N	f	0	\N
5503	45	161	\N	0	\N	\N	f	0	\N
5504	45	160	\N	0	\N	\N	f	0	\N
5505	45	159	\N	0	\N	\N	f	0	\N
5506	45	158	\N	0	\N	\N	f	0	\N
5507	45	157	\N	0	\N	\N	f	0	\N
5508	45	156	\N	0	\N	\N	f	0	\N
5509	45	155	\N	0	\N	\N	f	0	\N
5510	45	154	\N	0	\N	\N	f	0	\N
5511	45	153	\N	0	\N	\N	f	0	\N
5512	45	152	\N	0	\N	\N	f	0	\N
5513	45	151	\N	0	\N	\N	f	0	\N
5514	45	150	\N	0	\N	\N	f	0	\N
5515	45	149	\N	0	\N	\N	f	0	\N
5516	45	148	\N	0	\N	\N	f	0	\N
5517	45	147	\N	0	\N	\N	f	0	\N
5518	45	146	\N	0	\N	\N	f	0	\N
5519	46	254	\N	0	\N	\N	f	0	\N
5520	46	253	\N	0	\N	\N	f	0	\N
5521	46	252	\N	0	\N	\N	f	0	\N
5522	46	251	\N	0	\N	\N	f	0	\N
5523	46	250	\N	0	\N	\N	f	0	\N
5524	46	249	\N	0	\N	\N	f	0	\N
5525	46	248	\N	0	\N	\N	f	0	\N
5526	46	247	\N	0	\N	\N	f	0	\N
5527	46	246	\N	0	\N	\N	f	0	\N
5528	46	245	\N	0	\N	\N	f	0	\N
5529	46	244	\N	0	\N	\N	f	0	\N
5530	46	243	\N	0	\N	\N	f	0	\N
5531	46	242	\N	0	\N	\N	f	0	\N
5532	46	241	\N	0	\N	\N	f	0	\N
5533	46	240	\N	0	\N	\N	f	0	\N
5534	46	239	\N	0	\N	\N	f	0	\N
5535	46	238	\N	0	\N	\N	f	0	\N
5536	46	237	\N	0	\N	\N	f	0	\N
5537	46	236	\N	0	\N	\N	f	0	\N
5538	46	235	\N	0	\N	\N	f	0	\N
5539	46	234	\N	0	\N	\N	f	0	\N
5540	46	233	\N	0	\N	\N	f	0	\N
5541	46	232	\N	0	\N	\N	f	0	\N
5542	46	231	\N	0	\N	\N	f	0	\N
5543	46	230	\N	0	\N	\N	f	0	\N
5544	46	229	\N	0	\N	\N	f	0	\N
5545	46	228	\N	0	\N	\N	f	0	\N
5546	46	227	\N	0	\N	\N	f	0	\N
5547	46	226	\N	0	\N	\N	f	0	\N
5548	46	225	\N	0	\N	\N	f	0	\N
5549	46	224	\N	0	\N	\N	f	0	\N
5550	46	223	\N	0	\N	\N	f	0	\N
5551	46	222	\N	0	\N	\N	f	0	\N
5552	46	221	\N	0	\N	\N	f	0	\N
5553	46	220	\N	0	\N	\N	f	0	\N
5554	46	219	\N	0	\N	\N	f	0	\N
5555	46	39	\N	0	\N	\N	f	0	\N
5556	46	38	\N	0	\N	\N	f	0	\N
5557	46	37	\N	0	\N	\N	f	0	\N
5558	46	36	\N	0	\N	\N	f	0	\N
5559	46	35	\N	0	\N	\N	f	0	\N
5560	46	34	\N	0	\N	\N	f	0	\N
5561	46	33	\N	0	\N	\N	f	0	\N
5562	46	32	\N	0	\N	\N	f	0	\N
5563	46	31	\N	0	\N	\N	f	0	\N
5564	46	30	\N	0	\N	\N	f	0	\N
5565	46	29	\N	0	\N	\N	f	0	\N
5566	46	28	\N	0	\N	\N	f	0	\N
5567	46	27	\N	0	\N	\N	f	0	\N
5568	46	26	\N	0	\N	\N	f	0	\N
5569	46	25	\N	0	\N	\N	f	0	\N
5570	46	24	\N	0	\N	\N	f	0	\N
5571	46	23	\N	0	\N	\N	f	0	\N
5572	46	22	\N	0	\N	\N	f	0	\N
5573	46	21	\N	0	\N	\N	f	0	\N
5574	46	20	\N	0	\N	\N	f	0	\N
5575	46	19	\N	0	\N	\N	f	0	\N
5576	46	18	\N	0	\N	\N	f	0	\N
5577	46	17	\N	0	\N	\N	f	0	\N
5578	46	16	\N	0	\N	\N	f	0	\N
5579	46	15	\N	0	\N	\N	f	0	\N
5580	46	14	\N	0	\N	\N	f	0	\N
5581	46	13	\N	0	\N	\N	f	0	\N
5582	46	12	\N	0	\N	\N	f	0	\N
5583	46	11	\N	0	\N	\N	f	0	\N
5584	46	10	\N	0	\N	\N	f	0	\N
5585	46	9	\N	0	\N	\N	f	0	\N
5586	46	8	\N	0	\N	\N	f	0	\N
5587	46	7	\N	0	\N	\N	f	0	\N
5588	46	6	\N	0	\N	\N	f	0	\N
5589	46	5	\N	0	\N	\N	f	0	\N
5590	46	4	\N	0	\N	\N	f	0	\N
5591	46	3	\N	0	\N	\N	f	0	\N
5592	46	2	\N	0	\N	\N	f	0	\N
5593	46	1	\N	0	\N	\N	f	0	\N
5594	47	360	\N	0	\N	\N	f	0	\N
5595	47	359	\N	0	\N	\N	f	0	\N
5596	47	358	\N	0	\N	\N	f	0	\N
5597	47	357	\N	0	\N	\N	f	0	\N
5598	47	356	\N	0	\N	\N	f	0	\N
5599	47	355	\N	0	\N	\N	f	0	\N
5600	47	354	\N	0	\N	\N	f	0	\N
5601	47	353	\N	0	\N	\N	f	0	\N
5602	47	352	\N	0	\N	\N	f	0	\N
5603	47	351	\N	0	\N	\N	f	0	\N
5604	47	350	\N	0	\N	\N	f	0	\N
5605	47	349	\N	0	\N	\N	f	0	\N
5606	47	348	\N	0	\N	\N	f	0	\N
5607	47	347	\N	0	\N	\N	f	0	\N
5608	47	346	\N	0	\N	\N	f	0	\N
5609	47	345	\N	0	\N	\N	f	0	\N
5610	47	344	\N	0	\N	\N	f	0	\N
5611	47	343	\N	0	\N	\N	f	0	\N
5612	47	342	\N	0	\N	\N	f	0	\N
5613	47	341	\N	0	\N	\N	f	0	\N
5614	47	340	\N	0	\N	\N	f	0	\N
5615	47	339	\N	0	\N	\N	f	0	\N
5616	47	338	\N	0	\N	\N	f	0	\N
5617	47	337	\N	0	\N	\N	f	0	\N
5618	47	336	\N	0	\N	\N	f	0	\N
5619	47	335	\N	0	\N	\N	f	0	\N
5620	47	334	\N	0	\N	\N	f	0	\N
5621	47	333	\N	0	\N	\N	f	0	\N
5622	47	332	\N	0	\N	\N	f	0	\N
5623	47	331	\N	0	\N	\N	f	0	\N
5624	47	330	\N	0	\N	\N	f	0	\N
5625	47	329	\N	0	\N	\N	f	0	\N
5626	47	328	\N	0	\N	\N	f	0	\N
5627	47	327	\N	0	\N	\N	f	0	\N
5628	47	326	\N	0	\N	\N	f	0	\N
5629	47	325	\N	0	\N	\N	f	0	\N
5630	47	324	\N	0	\N	\N	f	0	\N
5631	47	254	\N	0	\N	\N	f	0	\N
5632	47	253	\N	0	\N	\N	f	0	\N
5633	47	252	\N	0	\N	\N	f	0	\N
5634	47	251	\N	0	\N	\N	f	0	\N
5635	47	250	\N	0	\N	\N	f	0	\N
5636	47	249	\N	0	\N	\N	f	0	\N
5637	47	248	\N	0	\N	\N	f	0	\N
5638	47	247	\N	0	\N	\N	f	0	\N
5639	47	246	\N	0	\N	\N	f	0	\N
5640	47	245	\N	0	\N	\N	f	0	\N
5641	47	244	\N	0	\N	\N	f	0	\N
5642	47	243	\N	0	\N	\N	f	0	\N
5643	47	242	\N	0	\N	\N	f	0	\N
5644	47	241	\N	0	\N	\N	f	0	\N
5645	47	240	\N	0	\N	\N	f	0	\N
5646	47	239	\N	0	\N	\N	f	0	\N
5647	47	238	\N	0	\N	\N	f	0	\N
5648	47	237	\N	0	\N	\N	f	0	\N
5649	47	236	\N	0	\N	\N	f	0	\N
5650	47	235	\N	0	\N	\N	f	0	\N
5651	47	234	\N	0	\N	\N	f	0	\N
5652	47	233	\N	0	\N	\N	f	0	\N
5653	47	232	\N	0	\N	\N	f	0	\N
5654	47	231	\N	0	\N	\N	f	0	\N
5655	47	230	\N	0	\N	\N	f	0	\N
5656	47	229	\N	0	\N	\N	f	0	\N
5657	47	228	\N	0	\N	\N	f	0	\N
5658	47	227	\N	0	\N	\N	f	0	\N
5659	47	226	\N	0	\N	\N	f	0	\N
5660	47	225	\N	0	\N	\N	f	0	\N
5661	47	224	\N	0	\N	\N	f	0	\N
5662	47	223	\N	0	\N	\N	f	0	\N
5663	47	222	\N	0	\N	\N	f	0	\N
5664	47	221	\N	0	\N	\N	f	0	\N
5665	47	220	\N	0	\N	\N	f	0	\N
5666	47	219	\N	0	\N	\N	f	0	\N
5667	47	145	\N	0	\N	\N	f	0	\N
5668	47	144	\N	0	\N	\N	f	0	\N
5669	47	143	\N	0	\N	\N	f	0	\N
5670	47	142	\N	0	\N	\N	f	0	\N
5671	47	141	\N	0	\N	\N	f	0	\N
5672	47	140	\N	0	\N	\N	f	0	\N
5673	47	139	\N	0	\N	\N	f	0	\N
5674	47	138	\N	0	\N	\N	f	0	\N
5675	47	137	\N	0	\N	\N	f	0	\N
5676	47	136	\N	0	\N	\N	f	0	\N
5677	47	135	\N	0	\N	\N	f	0	\N
5678	47	134	\N	0	\N	\N	f	0	\N
5679	47	133	\N	0	\N	\N	f	0	\N
5680	47	132	\N	0	\N	\N	f	0	\N
5681	47	131	\N	0	\N	\N	f	0	\N
5682	47	130	\N	0	\N	\N	f	0	\N
5683	47	129	\N	0	\N	\N	f	0	\N
5684	47	128	\N	0	\N	\N	f	0	\N
5685	47	127	\N	0	\N	\N	f	0	\N
5686	47	126	\N	0	\N	\N	f	0	\N
5687	47	125	\N	0	\N	\N	f	0	\N
5688	47	124	\N	0	\N	\N	f	0	\N
5689	47	123	\N	0	\N	\N	f	0	\N
5690	47	122	\N	0	\N	\N	f	0	\N
5691	47	121	\N	0	\N	\N	f	0	\N
5692	47	120	\N	0	\N	\N	f	0	\N
5693	47	119	\N	0	\N	\N	f	0	\N
5694	47	118	\N	0	\N	\N	f	0	\N
5695	47	117	\N	0	\N	\N	f	0	\N
5696	47	116	\N	0	\N	\N	f	0	\N
5697	47	115	\N	0	\N	\N	f	0	\N
5698	47	114	\N	0	\N	\N	f	0	\N
5699	47	113	\N	0	\N	\N	f	0	\N
5700	47	112	\N	0	\N	\N	f	0	\N
5701	47	111	\N	0	\N	\N	f	0	\N
5702	47	110	\N	0	\N	\N	f	0	\N
5703	47	180	\N	0	\N	\N	f	0	\N
5704	47	179	\N	0	\N	\N	f	0	\N
5705	47	178	\N	0	\N	\N	f	0	\N
5706	47	177	\N	0	\N	\N	f	0	\N
5707	47	176	\N	0	\N	\N	f	0	\N
5708	47	175	\N	0	\N	\N	f	0	\N
5709	47	174	\N	0	\N	\N	f	0	\N
5710	47	173	\N	0	\N	\N	f	0	\N
5711	47	172	\N	0	\N	\N	f	0	\N
5712	47	171	\N	0	\N	\N	f	0	\N
5713	47	170	\N	0	\N	\N	f	0	\N
5714	47	169	\N	0	\N	\N	f	0	\N
5715	47	168	\N	0	\N	\N	f	0	\N
5716	47	167	\N	0	\N	\N	f	0	\N
5717	47	166	\N	0	\N	\N	f	0	\N
5718	47	165	\N	0	\N	\N	f	0	\N
5719	47	164	\N	0	\N	\N	f	0	\N
5720	47	163	\N	0	\N	\N	f	0	\N
5721	47	162	\N	0	\N	\N	f	0	\N
5722	47	161	\N	0	\N	\N	f	0	\N
5723	47	160	\N	0	\N	\N	f	0	\N
5724	47	159	\N	0	\N	\N	f	0	\N
5725	47	158	\N	0	\N	\N	f	0	\N
5726	47	157	\N	0	\N	\N	f	0	\N
5727	47	156	\N	0	\N	\N	f	0	\N
5728	47	155	\N	0	\N	\N	f	0	\N
5729	47	154	\N	0	\N	\N	f	0	\N
5730	47	153	\N	0	\N	\N	f	0	\N
5731	47	152	\N	0	\N	\N	f	0	\N
5732	47	151	\N	0	\N	\N	f	0	\N
5733	47	150	\N	0	\N	\N	f	0	\N
5734	47	149	\N	0	\N	\N	f	0	\N
5735	47	148	\N	0	\N	\N	f	0	\N
5736	47	147	\N	0	\N	\N	f	0	\N
5737	47	146	\N	0	\N	\N	f	0	\N
5738	47	39	\N	0	\N	\N	f	0	\N
5739	47	38	\N	0	\N	\N	f	0	\N
5740	47	37	\N	0	\N	\N	f	0	\N
5741	47	36	\N	0	\N	\N	f	0	\N
5742	47	35	\N	0	\N	\N	f	0	\N
5743	47	34	\N	0	\N	\N	f	0	\N
5744	47	33	\N	0	\N	\N	f	0	\N
5745	47	32	\N	0	\N	\N	f	0	\N
5746	47	31	\N	0	\N	\N	f	0	\N
5747	47	30	\N	0	\N	\N	f	0	\N
5748	47	29	\N	0	\N	\N	f	0	\N
5749	47	28	\N	0	\N	\N	f	0	\N
5750	47	27	\N	0	\N	\N	f	0	\N
5751	47	26	\N	0	\N	\N	f	0	\N
5752	47	25	\N	0	\N	\N	f	0	\N
5753	47	24	\N	0	\N	\N	f	0	\N
5754	47	23	\N	0	\N	\N	f	0	\N
5755	47	22	\N	0	\N	\N	f	0	\N
5756	47	21	\N	0	\N	\N	f	0	\N
5757	47	20	\N	0	\N	\N	f	0	\N
5758	47	19	\N	0	\N	\N	f	0	\N
5759	47	18	\N	0	\N	\N	f	0	\N
5760	47	17	\N	0	\N	\N	f	0	\N
5761	47	16	\N	0	\N	\N	f	0	\N
5762	47	15	\N	0	\N	\N	f	0	\N
5763	47	14	\N	0	\N	\N	f	0	\N
5764	47	13	\N	0	\N	\N	f	0	\N
5765	47	12	\N	0	\N	\N	f	0	\N
5766	47	11	\N	0	\N	\N	f	0	\N
5767	47	10	\N	0	\N	\N	f	0	\N
5768	47	9	\N	0	\N	\N	f	0	\N
5769	47	8	\N	0	\N	\N	f	0	\N
5770	47	7	\N	0	\N	\N	f	0	\N
5771	47	6	\N	0	\N	\N	f	0	\N
5772	47	5	\N	0	\N	\N	f	0	\N
5773	47	4	\N	0	\N	\N	f	0	\N
5774	47	3	\N	0	\N	\N	f	0	\N
5775	47	2	\N	0	\N	\N	f	0	\N
5776	47	1	\N	0	\N	\N	f	0	\N
5777	47	323	\N	0	\N	\N	f	0	\N
5778	47	322	\N	0	\N	\N	f	0	\N
5779	47	321	\N	0	\N	\N	f	0	\N
5780	47	320	\N	0	\N	\N	f	0	\N
5781	47	319	\N	0	\N	\N	f	0	\N
5782	47	318	\N	0	\N	\N	f	0	\N
5783	47	317	\N	0	\N	\N	f	0	\N
5784	47	316	\N	0	\N	\N	f	0	\N
5785	47	315	\N	0	\N	\N	f	0	\N
5786	47	314	\N	0	\N	\N	f	0	\N
5787	47	313	\N	0	\N	\N	f	0	\N
5788	47	312	\N	0	\N	\N	f	0	\N
5789	47	311	\N	0	\N	\N	f	0	\N
5790	47	310	\N	0	\N	\N	f	0	\N
5791	47	309	\N	0	\N	\N	f	0	\N
5792	47	308	\N	0	\N	\N	f	0	\N
5793	47	307	\N	0	\N	\N	f	0	\N
5794	47	306	\N	0	\N	\N	f	0	\N
5795	47	305	\N	0	\N	\N	f	0	\N
5796	47	304	\N	0	\N	\N	f	0	\N
5797	47	303	\N	0	\N	\N	f	0	\N
5798	47	302	\N	0	\N	\N	f	0	\N
5799	47	301	\N	0	\N	\N	f	0	\N
5800	47	300	\N	0	\N	\N	f	0	\N
5801	47	299	\N	0	\N	\N	f	0	\N
5802	47	298	\N	0	\N	\N	f	0	\N
5803	47	297	\N	0	\N	\N	f	0	\N
5804	47	296	\N	0	\N	\N	f	0	\N
5805	47	295	\N	0	\N	\N	f	0	\N
5806	47	294	\N	0	\N	\N	f	0	\N
5807	47	293	\N	0	\N	\N	f	0	\N
5808	47	292	\N	0	\N	\N	f	0	\N
5809	47	291	\N	0	\N	\N	f	0	\N
5810	47	290	\N	0	\N	\N	f	0	\N
5811	47	289	\N	0	\N	\N	f	0	\N
5812	47	288	\N	0	\N	\N	f	0	\N
5813	47	287	\N	0	\N	\N	f	0	\N
5814	47	286	\N	0	\N	\N	f	0	\N
5815	47	285	\N	0	\N	\N	f	0	\N
5816	47	284	\N	0	\N	\N	f	0	\N
5817	47	283	\N	0	\N	\N	f	0	\N
5818	47	282	\N	0	\N	\N	f	0	\N
5819	47	281	\N	0	\N	\N	f	0	\N
5820	47	280	\N	0	\N	\N	f	0	\N
5821	47	279	\N	0	\N	\N	f	0	\N
5822	47	278	\N	0	\N	\N	f	0	\N
5823	47	277	\N	0	\N	\N	f	0	\N
5824	47	276	\N	0	\N	\N	f	0	\N
5825	47	275	\N	0	\N	\N	f	0	\N
5826	47	274	\N	0	\N	\N	f	0	\N
5827	47	273	\N	0	\N	\N	f	0	\N
5828	47	272	\N	0	\N	\N	f	0	\N
5829	47	271	\N	0	\N	\N	f	0	\N
5830	47	270	\N	0	\N	\N	f	0	\N
5831	47	269	\N	0	\N	\N	f	0	\N
5832	47	268	\N	0	\N	\N	f	0	\N
5833	47	267	\N	0	\N	\N	f	0	\N
5834	47	266	\N	0	\N	\N	f	0	\N
5835	47	265	\N	0	\N	\N	f	0	\N
5836	47	264	\N	0	\N	\N	f	0	\N
5837	47	263	\N	0	\N	\N	f	0	\N
5838	47	262	\N	0	\N	\N	f	0	\N
5839	47	261	\N	0	\N	\N	f	0	\N
5840	47	260	\N	0	\N	\N	f	0	\N
5841	47	259	\N	0	\N	\N	f	0	\N
5842	47	258	\N	0	\N	\N	f	0	\N
5843	47	257	\N	0	\N	\N	f	0	\N
5844	47	256	\N	0	\N	\N	f	0	\N
5845	47	255	\N	0	\N	\N	f	0	\N
5846	47	401	\N	0	\N	\N	f	0	\N
5847	47	400	\N	0	\N	\N	f	0	\N
5848	47	399	\N	0	\N	\N	f	0	\N
5849	47	398	\N	0	\N	\N	f	0	\N
5850	47	397	\N	0	\N	\N	f	0	\N
5851	47	396	\N	0	\N	\N	f	0	\N
5852	47	395	\N	0	\N	\N	f	0	\N
5853	47	394	\N	0	\N	\N	f	0	\N
5854	47	393	\N	0	\N	\N	f	0	\N
5855	47	392	\N	0	\N	\N	f	0	\N
5856	47	391	\N	0	\N	\N	f	0	\N
5857	47	390	\N	0	\N	\N	f	0	\N
5858	47	389	\N	0	\N	\N	f	0	\N
5859	47	388	\N	0	\N	\N	f	0	\N
5860	47	387	\N	0	\N	\N	f	0	\N
5861	47	386	\N	0	\N	\N	f	0	\N
5862	47	385	\N	0	\N	\N	f	0	\N
5863	47	384	\N	0	\N	\N	f	0	\N
5864	47	383	\N	0	\N	\N	f	0	\N
5865	47	382	\N	0	\N	\N	f	0	\N
5866	47	381	\N	0	\N	\N	f	0	\N
5867	47	380	\N	0	\N	\N	f	0	\N
5868	47	379	\N	0	\N	\N	f	0	\N
5869	47	378	\N	0	\N	\N	f	0	\N
5870	47	377	\N	0	\N	\N	f	0	\N
5871	47	376	\N	0	\N	\N	f	0	\N
5872	47	375	\N	0	\N	\N	f	0	\N
5873	47	374	\N	0	\N	\N	f	0	\N
5874	47	373	\N	0	\N	\N	f	0	\N
5875	47	372	\N	0	\N	\N	f	0	\N
5876	47	371	\N	0	\N	\N	f	0	\N
5877	47	370	\N	0	\N	\N	f	0	\N
5878	47	369	\N	0	\N	\N	f	0	\N
5879	47	368	\N	0	\N	\N	f	0	\N
5880	47	367	\N	0	\N	\N	f	0	\N
5881	47	366	\N	0	\N	\N	f	0	\N
5882	47	365	\N	0	\N	\N	f	0	\N
5883	47	364	\N	0	\N	\N	f	0	\N
5884	47	363	\N	0	\N	\N	f	0	\N
5885	47	362	\N	0	\N	\N	f	0	\N
5886	47	361	\N	0	\N	\N	f	0	\N
5887	47	432	\N	0	\N	\N	f	0	\N
5888	47	431	\N	0	\N	\N	f	0	\N
5889	47	430	\N	0	\N	\N	f	0	\N
5890	47	429	\N	0	\N	\N	f	0	\N
5891	47	428	\N	0	\N	\N	f	0	\N
5892	47	427	\N	0	\N	\N	f	0	\N
5893	47	426	\N	0	\N	\N	f	0	\N
5894	47	425	\N	0	\N	\N	f	0	\N
5895	47	424	\N	0	\N	\N	f	0	\N
5896	47	423	\N	0	\N	\N	f	0	\N
5897	47	422	\N	0	\N	\N	f	0	\N
5898	47	421	\N	0	\N	\N	f	0	\N
5899	47	420	\N	0	\N	\N	f	0	\N
5900	47	419	\N	0	\N	\N	f	0	\N
5901	47	418	\N	0	\N	\N	f	0	\N
5902	47	417	\N	0	\N	\N	f	0	\N
5903	47	416	\N	0	\N	\N	f	0	\N
5904	47	415	\N	0	\N	\N	f	0	\N
5905	47	414	\N	0	\N	\N	f	0	\N
5906	47	413	\N	0	\N	\N	f	0	\N
5907	47	412	\N	0	\N	\N	f	0	\N
5908	47	411	\N	0	\N	\N	f	0	\N
5909	47	410	\N	0	\N	\N	f	0	\N
5910	47	409	\N	0	\N	\N	f	0	\N
5911	47	408	\N	0	\N	\N	f	0	\N
5912	47	407	\N	0	\N	\N	f	0	\N
5913	47	406	\N	0	\N	\N	f	0	\N
5914	47	405	\N	0	\N	\N	f	0	\N
5915	47	404	\N	0	\N	\N	f	0	\N
5916	47	403	\N	0	\N	\N	f	0	\N
5917	47	402	\N	0	\N	\N	f	0	\N
5918	47	218	\N	0	\N	\N	f	0	\N
5919	47	217	\N	0	\N	\N	f	0	\N
5920	47	216	\N	0	\N	\N	f	0	\N
5921	47	215	\N	0	\N	\N	f	0	\N
5922	47	214	\N	0	\N	\N	f	0	\N
5923	47	213	\N	0	\N	\N	f	0	\N
5924	47	212	\N	0	\N	\N	f	0	\N
5925	47	211	\N	0	\N	\N	f	0	\N
5926	47	210	\N	0	\N	\N	f	0	\N
5927	47	209	\N	0	\N	\N	f	0	\N
5928	47	208	\N	0	\N	\N	f	0	\N
5929	47	207	\N	0	\N	\N	f	0	\N
5930	47	206	\N	0	\N	\N	f	0	\N
5931	47	205	\N	0	\N	\N	f	0	\N
5932	47	204	\N	0	\N	\N	f	0	\N
5933	47	203	\N	0	\N	\N	f	0	\N
5934	47	202	\N	0	\N	\N	f	0	\N
5935	47	201	\N	0	\N	\N	f	0	\N
5936	47	200	\N	0	\N	\N	f	0	\N
5937	47	199	\N	0	\N	\N	f	0	\N
5938	47	198	\N	0	\N	\N	f	0	\N
5939	47	197	\N	0	\N	\N	f	0	\N
5940	47	196	\N	0	\N	\N	f	0	\N
5941	47	195	\N	0	\N	\N	f	0	\N
5942	47	194	\N	0	\N	\N	f	0	\N
5943	47	193	\N	0	\N	\N	f	0	\N
5944	47	192	\N	0	\N	\N	f	0	\N
5945	47	191	\N	0	\N	\N	f	0	\N
5946	47	190	\N	0	\N	\N	f	0	\N
5947	47	189	\N	0	\N	\N	f	0	\N
5948	47	188	\N	0	\N	\N	f	0	\N
5949	47	187	\N	0	\N	\N	f	0	\N
5950	47	186	\N	0	\N	\N	f	0	\N
5951	47	185	\N	0	\N	\N	f	0	\N
5952	47	184	\N	0	\N	\N	f	0	\N
5953	47	183	\N	0	\N	\N	f	0	\N
5954	47	182	\N	0	\N	\N	f	0	\N
5955	47	181	\N	0	\N	\N	f	0	\N
5956	48	401	\N	0	\N	\N	f	0	\N
5957	48	400	\N	0	\N	\N	f	0	\N
5958	48	399	\N	0	\N	\N	f	0	\N
5959	48	398	\N	0	\N	\N	f	0	\N
5960	48	397	\N	0	\N	\N	f	0	\N
5961	48	396	\N	0	\N	\N	f	0	\N
5962	48	395	\N	0	\N	\N	f	0	\N
5963	48	394	\N	0	\N	\N	f	0	\N
5964	48	393	\N	0	\N	\N	f	0	\N
5965	48	392	\N	0	\N	\N	f	0	\N
5966	48	391	\N	0	\N	\N	f	0	\N
5967	48	390	\N	0	\N	\N	f	0	\N
5968	48	389	\N	0	\N	\N	f	0	\N
5969	48	388	\N	0	\N	\N	f	0	\N
5970	48	387	\N	0	\N	\N	f	0	\N
5971	48	386	\N	0	\N	\N	f	0	\N
5972	48	385	\N	0	\N	\N	f	0	\N
5973	48	384	\N	0	\N	\N	f	0	\N
5974	48	383	\N	0	\N	\N	f	0	\N
5975	48	382	\N	0	\N	\N	f	0	\N
5976	48	381	\N	0	\N	\N	f	0	\N
5977	48	380	\N	0	\N	\N	f	0	\N
5978	48	379	\N	0	\N	\N	f	0	\N
5979	48	378	\N	0	\N	\N	f	0	\N
5980	48	377	\N	0	\N	\N	f	0	\N
5981	48	376	\N	0	\N	\N	f	0	\N
5982	48	375	\N	0	\N	\N	f	0	\N
5983	48	374	\N	0	\N	\N	f	0	\N
5984	48	373	\N	0	\N	\N	f	0	\N
5985	48	372	\N	0	\N	\N	f	0	\N
5986	48	371	\N	0	\N	\N	f	0	\N
5987	48	370	\N	0	\N	\N	f	0	\N
5988	48	369	\N	0	\N	\N	f	0	\N
5989	48	368	\N	0	\N	\N	f	0	\N
5990	48	367	\N	0	\N	\N	f	0	\N
5991	48	366	\N	0	\N	\N	f	0	\N
5992	48	365	\N	0	\N	\N	f	0	\N
5993	48	364	\N	0	\N	\N	f	0	\N
5994	48	363	\N	0	\N	\N	f	0	\N
5995	48	362	\N	0	\N	\N	f	0	\N
5996	48	361	\N	0	\N	\N	f	0	\N
5997	48	432	\N	0	\N	\N	f	0	\N
5998	48	431	\N	0	\N	\N	f	0	\N
5999	48	430	\N	0	\N	\N	f	0	\N
6000	48	429	\N	0	\N	\N	f	0	\N
6001	48	428	\N	0	\N	\N	f	0	\N
6002	48	427	\N	0	\N	\N	f	0	\N
6003	48	426	\N	0	\N	\N	f	0	\N
6004	48	425	\N	0	\N	\N	f	0	\N
6005	48	424	\N	0	\N	\N	f	0	\N
6006	48	423	\N	0	\N	\N	f	0	\N
6007	48	422	\N	0	\N	\N	f	0	\N
6008	48	421	\N	0	\N	\N	f	0	\N
6009	48	420	\N	0	\N	\N	f	0	\N
6010	48	419	\N	0	\N	\N	f	0	\N
6011	48	418	\N	0	\N	\N	f	0	\N
6012	48	417	\N	0	\N	\N	f	0	\N
6013	48	416	\N	0	\N	\N	f	0	\N
6014	48	415	\N	0	\N	\N	f	0	\N
6015	48	414	\N	0	\N	\N	f	0	\N
6016	48	413	\N	0	\N	\N	f	0	\N
6017	48	412	\N	0	\N	\N	f	0	\N
6018	48	411	\N	0	\N	\N	f	0	\N
6019	48	410	\N	0	\N	\N	f	0	\N
6020	48	409	\N	0	\N	\N	f	0	\N
6021	48	408	\N	0	\N	\N	f	0	\N
6022	48	407	\N	0	\N	\N	f	0	\N
6023	48	406	\N	0	\N	\N	f	0	\N
6024	48	405	\N	0	\N	\N	f	0	\N
6025	48	404	\N	0	\N	\N	f	0	\N
6026	48	403	\N	0	\N	\N	f	0	\N
6027	48	402	\N	0	\N	\N	f	0	\N
6028	50	323	\N	0	\N	\N	f	0	\N
6029	50	322	\N	0	\N	\N	f	0	\N
6030	50	321	\N	0	\N	\N	f	0	\N
6031	50	320	\N	0	\N	\N	f	0	\N
6032	50	319	\N	0	\N	\N	f	0	\N
6033	50	318	\N	0	\N	\N	f	0	\N
6034	50	317	\N	0	\N	\N	f	0	\N
6035	50	316	\N	0	\N	\N	f	0	\N
6036	50	315	\N	0	\N	\N	f	0	\N
6037	50	314	\N	0	\N	\N	f	0	\N
6038	50	313	\N	0	\N	\N	f	0	\N
6039	50	312	\N	0	\N	\N	f	0	\N
6040	50	311	\N	0	\N	\N	f	0	\N
6041	50	310	\N	0	\N	\N	f	0	\N
6042	50	309	\N	0	\N	\N	f	0	\N
6043	50	308	\N	0	\N	\N	f	0	\N
6044	50	307	\N	0	\N	\N	f	0	\N
6045	50	306	\N	0	\N	\N	f	0	\N
6046	50	305	\N	0	\N	\N	f	0	\N
6047	50	304	\N	0	\N	\N	f	0	\N
6048	50	303	\N	0	\N	\N	f	0	\N
6049	50	302	\N	0	\N	\N	f	0	\N
6050	50	301	\N	0	\N	\N	f	0	\N
6051	50	300	\N	0	\N	\N	f	0	\N
6052	50	299	\N	0	\N	\N	f	0	\N
6053	50	298	\N	0	\N	\N	f	0	\N
6054	50	297	\N	0	\N	\N	f	0	\N
6055	50	296	\N	0	\N	\N	f	0	\N
6056	50	295	\N	0	\N	\N	f	0	\N
6057	50	294	\N	0	\N	\N	f	0	\N
6058	50	293	\N	0	\N	\N	f	0	\N
6059	50	292	\N	0	\N	\N	f	0	\N
6060	50	291	\N	0	\N	\N	f	0	\N
6061	53	290	\N	0	\N	\N	f	0	\N
6062	53	289	\N	0	\N	\N	f	0	\N
6063	53	288	\N	0	\N	\N	f	0	\N
6064	53	287	\N	0	\N	\N	f	0	\N
6065	53	286	\N	0	\N	\N	f	0	\N
6066	53	285	\N	0	\N	\N	f	0	\N
6067	53	284	\N	0	\N	\N	f	0	\N
6068	53	283	\N	0	\N	\N	f	0	\N
6069	53	282	\N	0	\N	\N	f	0	\N
6070	53	281	\N	0	\N	\N	f	0	\N
6071	53	280	\N	0	\N	\N	f	0	\N
6072	53	279	\N	0	\N	\N	f	0	\N
6073	53	278	\N	0	\N	\N	f	0	\N
6074	53	277	\N	0	\N	\N	f	0	\N
6075	53	276	\N	0	\N	\N	f	0	\N
6076	53	275	\N	0	\N	\N	f	0	\N
6077	53	274	\N	0	\N	\N	f	0	\N
6078	53	273	\N	0	\N	\N	f	0	\N
6079	53	272	\N	0	\N	\N	f	0	\N
6080	53	271	\N	0	\N	\N	f	0	\N
6081	53	270	\N	0	\N	\N	f	0	\N
6082	53	269	\N	0	\N	\N	f	0	\N
6083	53	268	\N	0	\N	\N	f	0	\N
6084	53	267	\N	0	\N	\N	f	0	\N
6085	53	266	\N	0	\N	\N	f	0	\N
6086	53	265	\N	0	\N	\N	f	0	\N
6087	53	264	\N	0	\N	\N	f	0	\N
6088	53	263	\N	0	\N	\N	f	0	\N
6089	53	262	\N	0	\N	\N	f	0	\N
6090	53	261	\N	0	\N	\N	f	0	\N
6091	53	260	\N	0	\N	\N	f	0	\N
6092	53	259	\N	0	\N	\N	f	0	\N
6093	53	258	\N	0	\N	\N	f	0	\N
6094	53	257	\N	0	\N	\N	f	0	\N
6095	53	256	\N	0	\N	\N	f	0	\N
6096	53	255	\N	0	\N	\N	f	0	\N
6097	53	360	\N	0	\N	\N	f	0	\N
6098	53	359	\N	0	\N	\N	f	0	\N
6099	53	358	\N	0	\N	\N	f	0	\N
6100	53	357	\N	0	\N	\N	f	0	\N
6101	53	356	\N	0	\N	\N	f	0	\N
6102	53	355	\N	0	\N	\N	f	0	\N
6103	53	354	\N	0	\N	\N	f	0	\N
6104	53	353	\N	0	\N	\N	f	0	\N
6105	53	352	\N	0	\N	\N	f	0	\N
6106	53	351	\N	0	\N	\N	f	0	\N
6107	53	350	\N	0	\N	\N	f	0	\N
6108	53	349	\N	0	\N	\N	f	0	\N
6109	53	348	\N	0	\N	\N	f	0	\N
6110	53	347	\N	0	\N	\N	f	0	\N
6111	53	346	\N	0	\N	\N	f	0	\N
6112	53	345	\N	0	\N	\N	f	0	\N
6113	53	344	\N	0	\N	\N	f	0	\N
6114	53	343	\N	0	\N	\N	f	0	\N
6115	53	342	\N	0	\N	\N	f	0	\N
6116	53	341	\N	0	\N	\N	f	0	\N
6117	53	340	\N	0	\N	\N	f	0	\N
6118	53	339	\N	0	\N	\N	f	0	\N
6119	53	338	\N	0	\N	\N	f	0	\N
6120	53	337	\N	0	\N	\N	f	0	\N
6121	53	336	\N	0	\N	\N	f	0	\N
6122	53	335	\N	0	\N	\N	f	0	\N
6123	53	334	\N	0	\N	\N	f	0	\N
6124	53	333	\N	0	\N	\N	f	0	\N
6125	53	332	\N	0	\N	\N	f	0	\N
6126	53	331	\N	0	\N	\N	f	0	\N
6127	53	330	\N	0	\N	\N	f	0	\N
6128	53	329	\N	0	\N	\N	f	0	\N
6129	53	328	\N	0	\N	\N	f	0	\N
6130	53	327	\N	0	\N	\N	f	0	\N
6131	53	326	\N	0	\N	\N	f	0	\N
6132	53	325	\N	0	\N	\N	f	0	\N
6133	53	324	\N	0	\N	\N	f	0	\N
6134	53	109	\N	0	\N	\N	f	0	\N
6135	53	108	\N	0	\N	\N	f	0	\N
6136	53	107	\N	0	\N	\N	f	0	\N
6137	53	106	\N	0	\N	\N	f	0	\N
6138	53	105	\N	0	\N	\N	f	0	\N
6139	53	104	\N	0	\N	\N	f	0	\N
6140	53	103	\N	0	\N	\N	f	0	\N
6141	53	102	\N	0	\N	\N	f	0	\N
6142	53	101	\N	0	\N	\N	f	0	\N
6143	53	100	\N	0	\N	\N	f	0	\N
6144	53	99	\N	0	\N	\N	f	0	\N
6145	53	98	\N	0	\N	\N	f	0	\N
6146	53	97	\N	0	\N	\N	f	0	\N
6147	53	96	\N	0	\N	\N	f	0	\N
6148	53	95	\N	0	\N	\N	f	0	\N
6149	53	94	\N	0	\N	\N	f	0	\N
6150	53	93	\N	0	\N	\N	f	0	\N
6151	53	92	\N	0	\N	\N	f	0	\N
6152	53	91	\N	0	\N	\N	f	0	\N
6153	53	90	\N	0	\N	\N	f	0	\N
6154	53	89	\N	0	\N	\N	f	0	\N
6155	53	88	\N	0	\N	\N	f	0	\N
6156	53	87	\N	0	\N	\N	f	0	\N
6157	53	86	\N	0	\N	\N	f	0	\N
6158	53	85	\N	0	\N	\N	f	0	\N
6159	53	84	\N	0	\N	\N	f	0	\N
6160	53	83	\N	0	\N	\N	f	0	\N
6161	53	82	\N	0	\N	\N	f	0	\N
6162	53	81	\N	0	\N	\N	f	0	\N
6163	53	80	\N	0	\N	\N	f	0	\N
6164	53	79	\N	0	\N	\N	f	0	\N
6165	53	78	\N	0	\N	\N	f	0	\N
6166	53	77	\N	0	\N	\N	f	0	\N
6167	53	76	\N	0	\N	\N	f	0	\N
6168	53	75	\N	0	\N	\N	f	0	\N
6169	54	145	\N	0	\N	\N	f	0	\N
6170	54	144	\N	0	\N	\N	f	0	\N
6171	54	143	\N	0	\N	\N	f	0	\N
6172	54	142	\N	0	\N	\N	f	0	\N
6173	54	141	\N	0	\N	\N	f	0	\N
6174	54	140	\N	0	\N	\N	f	0	\N
6175	54	139	\N	0	\N	\N	f	0	\N
6176	54	138	\N	0	\N	\N	f	0	\N
6177	54	137	\N	0	\N	\N	f	0	\N
6178	54	136	\N	0	\N	\N	f	0	\N
6179	54	135	\N	0	\N	\N	f	0	\N
6180	54	134	\N	0	\N	\N	f	0	\N
6181	54	133	\N	0	\N	\N	f	0	\N
6182	54	132	\N	0	\N	\N	f	0	\N
6183	54	131	\N	0	\N	\N	f	0	\N
6184	54	130	\N	0	\N	\N	f	0	\N
6185	54	129	\N	0	\N	\N	f	0	\N
6186	54	128	\N	0	\N	\N	f	0	\N
6187	54	127	\N	0	\N	\N	f	0	\N
6188	54	126	\N	0	\N	\N	f	0	\N
6189	54	125	\N	0	\N	\N	f	0	\N
6190	54	124	\N	0	\N	\N	f	0	\N
6191	54	123	\N	0	\N	\N	f	0	\N
6192	54	122	\N	0	\N	\N	f	0	\N
6193	54	121	\N	0	\N	\N	f	0	\N
6194	54	120	\N	0	\N	\N	f	0	\N
6195	54	119	\N	0	\N	\N	f	0	\N
6196	54	118	\N	0	\N	\N	f	0	\N
6197	54	117	\N	0	\N	\N	f	0	\N
6198	54	116	\N	0	\N	\N	f	0	\N
6199	54	115	\N	0	\N	\N	f	0	\N
6200	54	114	\N	0	\N	\N	f	0	\N
6201	54	113	\N	0	\N	\N	f	0	\N
6202	54	112	\N	0	\N	\N	f	0	\N
6203	54	111	\N	0	\N	\N	f	0	\N
6204	54	110	\N	0	\N	\N	f	0	\N
6205	54	401	\N	0	\N	\N	f	0	\N
6206	54	400	\N	0	\N	\N	f	0	\N
6207	54	399	\N	0	\N	\N	f	0	\N
6208	54	398	\N	0	\N	\N	f	0	\N
6209	54	397	\N	0	\N	\N	f	0	\N
6210	54	396	\N	0	\N	\N	f	0	\N
6211	54	395	\N	0	\N	\N	f	0	\N
6212	54	394	\N	0	\N	\N	f	0	\N
6213	54	393	\N	0	\N	\N	f	0	\N
6214	54	392	\N	0	\N	\N	f	0	\N
6215	54	391	\N	0	\N	\N	f	0	\N
6216	54	390	\N	0	\N	\N	f	0	\N
6217	54	389	\N	0	\N	\N	f	0	\N
6218	54	388	\N	0	\N	\N	f	0	\N
6219	54	387	\N	0	\N	\N	f	0	\N
6220	54	386	\N	0	\N	\N	f	0	\N
6221	54	385	\N	0	\N	\N	f	0	\N
6222	54	384	\N	0	\N	\N	f	0	\N
6223	54	383	\N	0	\N	\N	f	0	\N
6224	54	382	\N	0	\N	\N	f	0	\N
6225	54	381	\N	0	\N	\N	f	0	\N
6226	54	380	\N	0	\N	\N	f	0	\N
6227	54	379	\N	0	\N	\N	f	0	\N
6228	54	378	\N	0	\N	\N	f	0	\N
6229	54	377	\N	0	\N	\N	f	0	\N
6230	54	376	\N	0	\N	\N	f	0	\N
6231	54	375	\N	0	\N	\N	f	0	\N
6232	54	374	\N	0	\N	\N	f	0	\N
6233	54	373	\N	0	\N	\N	f	0	\N
6234	54	372	\N	0	\N	\N	f	0	\N
6235	54	371	\N	0	\N	\N	f	0	\N
6236	54	370	\N	0	\N	\N	f	0	\N
6237	54	369	\N	0	\N	\N	f	0	\N
6238	54	368	\N	0	\N	\N	f	0	\N
6239	54	367	\N	0	\N	\N	f	0	\N
6240	54	366	\N	0	\N	\N	f	0	\N
6241	54	365	\N	0	\N	\N	f	0	\N
6242	54	364	\N	0	\N	\N	f	0	\N
6243	54	363	\N	0	\N	\N	f	0	\N
6244	54	362	\N	0	\N	\N	f	0	\N
6245	54	361	\N	0	\N	\N	f	0	\N
6246	54	254	\N	0	\N	\N	f	0	\N
6247	54	253	\N	0	\N	\N	f	0	\N
6248	54	252	\N	0	\N	\N	f	0	\N
6249	54	251	\N	0	\N	\N	f	0	\N
6250	54	250	\N	0	\N	\N	f	0	\N
6251	54	249	\N	0	\N	\N	f	0	\N
6252	54	248	\N	0	\N	\N	f	0	\N
6253	54	247	\N	0	\N	\N	f	0	\N
6254	54	246	\N	0	\N	\N	f	0	\N
6255	54	245	\N	0	\N	\N	f	0	\N
6256	54	244	\N	0	\N	\N	f	0	\N
6257	54	243	\N	0	\N	\N	f	0	\N
6258	54	242	\N	0	\N	\N	f	0	\N
6259	54	241	\N	0	\N	\N	f	0	\N
6260	54	240	\N	0	\N	\N	f	0	\N
6261	54	239	\N	0	\N	\N	f	0	\N
6262	54	238	\N	0	\N	\N	f	0	\N
6263	54	237	\N	0	\N	\N	f	0	\N
6264	54	236	\N	0	\N	\N	f	0	\N
6265	54	235	\N	0	\N	\N	f	0	\N
6266	54	234	\N	0	\N	\N	f	0	\N
6267	54	233	\N	0	\N	\N	f	0	\N
6268	54	232	\N	0	\N	\N	f	0	\N
6269	54	231	\N	0	\N	\N	f	0	\N
6270	54	230	\N	0	\N	\N	f	0	\N
6271	54	229	\N	0	\N	\N	f	0	\N
6272	54	228	\N	0	\N	\N	f	0	\N
6273	54	227	\N	0	\N	\N	f	0	\N
6274	54	226	\N	0	\N	\N	f	0	\N
6275	54	225	\N	0	\N	\N	f	0	\N
6276	54	224	\N	0	\N	\N	f	0	\N
6277	54	223	\N	0	\N	\N	f	0	\N
6278	54	222	\N	0	\N	\N	f	0	\N
6279	54	221	\N	0	\N	\N	f	0	\N
6280	54	220	\N	0	\N	\N	f	0	\N
6281	54	219	\N	0	\N	\N	f	0	\N
6282	54	218	\N	0	\N	\N	f	0	\N
6283	54	217	\N	0	\N	\N	f	0	\N
6284	54	216	\N	0	\N	\N	f	0	\N
6285	54	215	\N	0	\N	\N	f	0	\N
6286	54	214	\N	0	\N	\N	f	0	\N
6287	54	213	\N	0	\N	\N	f	0	\N
6288	54	212	\N	0	\N	\N	f	0	\N
6289	54	211	\N	0	\N	\N	f	0	\N
6290	54	210	\N	0	\N	\N	f	0	\N
6291	54	209	\N	0	\N	\N	f	0	\N
6292	54	208	\N	0	\N	\N	f	0	\N
6293	54	207	\N	0	\N	\N	f	0	\N
6294	54	206	\N	0	\N	\N	f	0	\N
6295	54	205	\N	0	\N	\N	f	0	\N
6296	54	204	\N	0	\N	\N	f	0	\N
6297	54	203	\N	0	\N	\N	f	0	\N
6298	54	202	\N	0	\N	\N	f	0	\N
6299	54	201	\N	0	\N	\N	f	0	\N
6300	54	200	\N	0	\N	\N	f	0	\N
6301	54	199	\N	0	\N	\N	f	0	\N
6302	54	198	\N	0	\N	\N	f	0	\N
6303	54	197	\N	0	\N	\N	f	0	\N
6304	54	196	\N	0	\N	\N	f	0	\N
6305	54	195	\N	0	\N	\N	f	0	\N
6306	54	194	\N	0	\N	\N	f	0	\N
6307	54	193	\N	0	\N	\N	f	0	\N
6308	54	192	\N	0	\N	\N	f	0	\N
6309	54	191	\N	0	\N	\N	f	0	\N
6310	54	190	\N	0	\N	\N	f	0	\N
6311	54	189	\N	0	\N	\N	f	0	\N
6312	54	188	\N	0	\N	\N	f	0	\N
6313	54	187	\N	0	\N	\N	f	0	\N
6314	54	186	\N	0	\N	\N	f	0	\N
6315	54	185	\N	0	\N	\N	f	0	\N
6316	54	184	\N	0	\N	\N	f	0	\N
6317	54	183	\N	0	\N	\N	f	0	\N
6318	54	182	\N	0	\N	\N	f	0	\N
6319	54	181	\N	0	\N	\N	f	0	\N
6320	54	432	\N	0	\N	\N	f	0	\N
6321	54	431	\N	0	\N	\N	f	0	\N
6322	54	430	\N	0	\N	\N	f	0	\N
6323	54	429	\N	0	\N	\N	f	0	\N
6324	54	428	\N	0	\N	\N	f	0	\N
6325	54	427	\N	0	\N	\N	f	0	\N
6326	54	426	\N	0	\N	\N	f	0	\N
6327	54	425	\N	0	\N	\N	f	0	\N
6328	54	424	\N	0	\N	\N	f	0	\N
6329	54	423	\N	0	\N	\N	f	0	\N
6330	54	422	\N	0	\N	\N	f	0	\N
6331	54	421	\N	0	\N	\N	f	0	\N
6332	54	420	\N	0	\N	\N	f	0	\N
6333	54	419	\N	0	\N	\N	f	0	\N
6334	54	418	\N	0	\N	\N	f	0	\N
6335	54	417	\N	0	\N	\N	f	0	\N
6336	54	416	\N	0	\N	\N	f	0	\N
6337	54	415	\N	0	\N	\N	f	0	\N
6338	54	414	\N	0	\N	\N	f	0	\N
6339	54	413	\N	0	\N	\N	f	0	\N
6340	54	412	\N	0	\N	\N	f	0	\N
6341	54	411	\N	0	\N	\N	f	0	\N
6342	54	410	\N	0	\N	\N	f	0	\N
6343	54	409	\N	0	\N	\N	f	0	\N
6344	54	408	\N	0	\N	\N	f	0	\N
6345	54	407	\N	0	\N	\N	f	0	\N
6346	54	406	\N	0	\N	\N	f	0	\N
6347	54	405	\N	0	\N	\N	f	0	\N
6348	54	404	\N	0	\N	\N	f	0	\N
6349	54	403	\N	0	\N	\N	f	0	\N
6350	54	402	\N	0	\N	\N	f	0	\N
6351	55	218	\N	0	\N	\N	f	0	\N
6352	55	217	\N	0	\N	\N	f	0	\N
6353	55	216	\N	0	\N	\N	f	0	\N
6354	55	215	\N	0	\N	\N	f	0	\N
6355	55	214	\N	0	\N	\N	f	0	\N
6356	55	213	\N	0	\N	\N	f	0	\N
6357	55	212	\N	0	\N	\N	f	0	\N
6358	55	211	\N	0	\N	\N	f	0	\N
6359	55	210	\N	0	\N	\N	f	0	\N
6360	55	209	\N	0	\N	\N	f	0	\N
6361	55	208	\N	0	\N	\N	f	0	\N
6362	55	207	\N	0	\N	\N	f	0	\N
6363	55	206	\N	0	\N	\N	f	0	\N
6364	55	205	\N	0	\N	\N	f	0	\N
6365	55	204	\N	0	\N	\N	f	0	\N
6366	55	203	\N	0	\N	\N	f	0	\N
6367	55	202	\N	0	\N	\N	f	0	\N
6368	55	201	\N	0	\N	\N	f	0	\N
6369	55	200	\N	0	\N	\N	f	0	\N
6370	55	199	\N	0	\N	\N	f	0	\N
6371	55	198	\N	0	\N	\N	f	0	\N
6372	55	197	\N	0	\N	\N	f	0	\N
6373	55	196	\N	0	\N	\N	f	0	\N
6374	55	195	\N	0	\N	\N	f	0	\N
6375	55	194	\N	0	\N	\N	f	0	\N
6376	55	193	\N	0	\N	\N	f	0	\N
6377	55	192	\N	0	\N	\N	f	0	\N
6378	55	191	\N	0	\N	\N	f	0	\N
6379	55	190	\N	0	\N	\N	f	0	\N
6380	55	189	\N	0	\N	\N	f	0	\N
6381	55	188	\N	0	\N	\N	f	0	\N
6382	55	187	\N	0	\N	\N	f	0	\N
6383	55	186	\N	0	\N	\N	f	0	\N
6384	55	185	\N	0	\N	\N	f	0	\N
6385	55	184	\N	0	\N	\N	f	0	\N
6386	55	183	\N	0	\N	\N	f	0	\N
6387	55	182	\N	0	\N	\N	f	0	\N
6388	55	181	\N	0	\N	\N	f	0	\N
6389	55	401	\N	0	\N	\N	f	0	\N
6390	55	400	\N	0	\N	\N	f	0	\N
6391	55	399	\N	0	\N	\N	f	0	\N
6392	55	398	\N	0	\N	\N	f	0	\N
6393	55	397	\N	0	\N	\N	f	0	\N
6394	55	396	\N	0	\N	\N	f	0	\N
6395	55	395	\N	0	\N	\N	f	0	\N
6396	55	394	\N	0	\N	\N	f	0	\N
6397	55	393	\N	0	\N	\N	f	0	\N
6398	55	392	\N	0	\N	\N	f	0	\N
6399	55	391	\N	0	\N	\N	f	0	\N
6400	55	390	\N	0	\N	\N	f	0	\N
6401	55	389	\N	0	\N	\N	f	0	\N
6402	55	388	\N	0	\N	\N	f	0	\N
6403	55	387	\N	0	\N	\N	f	0	\N
6404	55	386	\N	0	\N	\N	f	0	\N
6405	55	385	\N	0	\N	\N	f	0	\N
6406	55	384	\N	0	\N	\N	f	0	\N
6407	55	383	\N	0	\N	\N	f	0	\N
6408	55	382	\N	0	\N	\N	f	0	\N
6409	55	381	\N	0	\N	\N	f	0	\N
6410	55	380	\N	0	\N	\N	f	0	\N
6411	55	379	\N	0	\N	\N	f	0	\N
6412	55	378	\N	0	\N	\N	f	0	\N
6413	55	377	\N	0	\N	\N	f	0	\N
6414	55	376	\N	0	\N	\N	f	0	\N
6415	55	375	\N	0	\N	\N	f	0	\N
6416	55	374	\N	0	\N	\N	f	0	\N
6417	55	373	\N	0	\N	\N	f	0	\N
6418	55	372	\N	0	\N	\N	f	0	\N
6419	55	371	\N	0	\N	\N	f	0	\N
6420	55	370	\N	0	\N	\N	f	0	\N
6421	55	369	\N	0	\N	\N	f	0	\N
6422	55	368	\N	0	\N	\N	f	0	\N
6423	55	367	\N	0	\N	\N	f	0	\N
6424	55	366	\N	0	\N	\N	f	0	\N
6425	55	365	\N	0	\N	\N	f	0	\N
6426	55	364	\N	0	\N	\N	f	0	\N
6427	55	363	\N	0	\N	\N	f	0	\N
6428	55	362	\N	0	\N	\N	f	0	\N
6429	55	361	\N	0	\N	\N	f	0	\N
6430	56	39	\N	0	\N	\N	f	0	\N
6431	56	38	\N	0	\N	\N	f	0	\N
6432	56	37	\N	0	\N	\N	f	0	\N
6433	56	36	\N	0	\N	\N	f	0	\N
6434	56	35	\N	0	\N	\N	f	0	\N
6435	56	34	\N	0	\N	\N	f	0	\N
6436	56	33	\N	0	\N	\N	f	0	\N
6437	56	32	\N	0	\N	\N	f	0	\N
6438	56	31	\N	0	\N	\N	f	0	\N
6439	56	30	\N	0	\N	\N	f	0	\N
6440	56	29	\N	0	\N	\N	f	0	\N
6441	56	28	\N	0	\N	\N	f	0	\N
6442	56	27	\N	0	\N	\N	f	0	\N
6443	56	26	\N	0	\N	\N	f	0	\N
6444	56	25	\N	0	\N	\N	f	0	\N
6445	56	24	\N	0	\N	\N	f	0	\N
6446	56	23	\N	0	\N	\N	f	0	\N
6447	56	22	\N	0	\N	\N	f	0	\N
6448	56	21	\N	0	\N	\N	f	0	\N
6449	56	20	\N	0	\N	\N	f	0	\N
6450	56	19	\N	0	\N	\N	f	0	\N
6451	56	18	\N	0	\N	\N	f	0	\N
6452	56	17	\N	0	\N	\N	f	0	\N
6453	56	16	\N	0	\N	\N	f	0	\N
6454	56	15	\N	0	\N	\N	f	0	\N
6455	56	14	\N	0	\N	\N	f	0	\N
6456	56	13	\N	0	\N	\N	f	0	\N
6457	56	12	\N	0	\N	\N	f	0	\N
6458	56	11	\N	0	\N	\N	f	0	\N
6459	56	10	\N	0	\N	\N	f	0	\N
6460	56	9	\N	0	\N	\N	f	0	\N
6461	56	8	\N	0	\N	\N	f	0	\N
6462	56	7	\N	0	\N	\N	f	0	\N
6463	56	6	\N	0	\N	\N	f	0	\N
6464	56	5	\N	0	\N	\N	f	0	\N
6465	56	4	\N	0	\N	\N	f	0	\N
6466	56	3	\N	0	\N	\N	f	0	\N
6467	56	2	\N	0	\N	\N	f	0	\N
6468	56	1	\N	0	\N	\N	f	0	\N
6469	56	109	\N	0	\N	\N	f	0	\N
6470	56	108	\N	0	\N	\N	f	0	\N
6471	56	107	\N	0	\N	\N	f	0	\N
6472	56	106	\N	0	\N	\N	f	0	\N
6473	56	105	\N	0	\N	\N	f	0	\N
6474	56	104	\N	0	\N	\N	f	0	\N
6475	56	103	\N	0	\N	\N	f	0	\N
6476	56	102	\N	0	\N	\N	f	0	\N
6477	56	101	\N	0	\N	\N	f	0	\N
6478	56	100	\N	0	\N	\N	f	0	\N
6479	56	99	\N	0	\N	\N	f	0	\N
6480	56	98	\N	0	\N	\N	f	0	\N
6481	56	97	\N	0	\N	\N	f	0	\N
6482	56	96	\N	0	\N	\N	f	0	\N
6483	56	95	\N	0	\N	\N	f	0	\N
6484	56	94	\N	0	\N	\N	f	0	\N
6485	56	93	\N	0	\N	\N	f	0	\N
6486	56	92	\N	0	\N	\N	f	0	\N
6487	56	91	\N	0	\N	\N	f	0	\N
6488	56	90	\N	0	\N	\N	f	0	\N
6489	56	89	\N	0	\N	\N	f	0	\N
6490	56	88	\N	0	\N	\N	f	0	\N
6491	56	87	\N	0	\N	\N	f	0	\N
6492	56	86	\N	0	\N	\N	f	0	\N
6493	56	85	\N	0	\N	\N	f	0	\N
6494	56	84	\N	0	\N	\N	f	0	\N
6495	56	83	\N	0	\N	\N	f	0	\N
6496	56	82	\N	0	\N	\N	f	0	\N
6497	56	81	\N	0	\N	\N	f	0	\N
6498	56	80	\N	0	\N	\N	f	0	\N
6499	56	79	\N	0	\N	\N	f	0	\N
6500	56	78	\N	0	\N	\N	f	0	\N
6501	56	77	\N	0	\N	\N	f	0	\N
6502	56	76	\N	0	\N	\N	f	0	\N
6503	56	75	\N	0	\N	\N	f	0	\N
6504	56	74	\N	0	\N	\N	f	0	\N
6505	56	73	\N	0	\N	\N	f	0	\N
6506	56	72	\N	0	\N	\N	f	0	\N
6507	56	71	\N	0	\N	\N	f	0	\N
6508	56	70	\N	0	\N	\N	f	0	\N
6509	56	69	\N	0	\N	\N	f	0	\N
6510	56	68	\N	0	\N	\N	f	0	\N
6511	56	67	\N	0	\N	\N	f	0	\N
6512	56	66	\N	0	\N	\N	f	0	\N
6513	56	65	\N	0	\N	\N	f	0	\N
6514	56	64	\N	0	\N	\N	f	0	\N
6515	56	63	\N	0	\N	\N	f	0	\N
6516	56	62	\N	0	\N	\N	f	0	\N
6517	56	61	\N	0	\N	\N	f	0	\N
6518	56	60	\N	0	\N	\N	f	0	\N
6519	56	59	\N	0	\N	\N	f	0	\N
6520	56	58	\N	0	\N	\N	f	0	\N
6521	56	57	\N	0	\N	\N	f	0	\N
6522	56	56	\N	0	\N	\N	f	0	\N
6523	56	55	\N	0	\N	\N	f	0	\N
6524	56	54	\N	0	\N	\N	f	0	\N
6525	56	53	\N	0	\N	\N	f	0	\N
6526	56	52	\N	0	\N	\N	f	0	\N
6527	56	51	\N	0	\N	\N	f	0	\N
6528	56	50	\N	0	\N	\N	f	0	\N
6529	56	49	\N	0	\N	\N	f	0	\N
6530	56	48	\N	0	\N	\N	f	0	\N
6531	56	47	\N	0	\N	\N	f	0	\N
6532	56	46	\N	0	\N	\N	f	0	\N
6533	56	45	\N	0	\N	\N	f	0	\N
6534	56	44	\N	0	\N	\N	f	0	\N
6535	56	43	\N	0	\N	\N	f	0	\N
6536	56	42	\N	0	\N	\N	f	0	\N
6537	56	41	\N	0	\N	\N	f	0	\N
6538	56	40	\N	0	\N	\N	f	0	\N
6539	56	145	\N	0	\N	\N	f	0	\N
6540	56	144	\N	0	\N	\N	f	0	\N
6541	56	143	\N	0	\N	\N	f	0	\N
6542	56	142	\N	0	\N	\N	f	0	\N
6543	56	141	\N	0	\N	\N	f	0	\N
6544	56	140	\N	0	\N	\N	f	0	\N
6545	56	139	\N	0	\N	\N	f	0	\N
6546	56	138	\N	0	\N	\N	f	0	\N
6547	56	137	\N	0	\N	\N	f	0	\N
6548	56	136	\N	0	\N	\N	f	0	\N
6549	56	135	\N	0	\N	\N	f	0	\N
6550	56	134	\N	0	\N	\N	f	0	\N
6551	56	133	\N	0	\N	\N	f	0	\N
6552	56	132	\N	0	\N	\N	f	0	\N
6553	56	131	\N	0	\N	\N	f	0	\N
6554	56	130	\N	0	\N	\N	f	0	\N
6555	56	129	\N	0	\N	\N	f	0	\N
6556	56	128	\N	0	\N	\N	f	0	\N
6557	56	127	\N	0	\N	\N	f	0	\N
6558	56	126	\N	0	\N	\N	f	0	\N
6559	56	125	\N	0	\N	\N	f	0	\N
6560	56	124	\N	0	\N	\N	f	0	\N
6561	56	123	\N	0	\N	\N	f	0	\N
6562	56	122	\N	0	\N	\N	f	0	\N
6563	56	121	\N	0	\N	\N	f	0	\N
6564	56	120	\N	0	\N	\N	f	0	\N
6565	56	119	\N	0	\N	\N	f	0	\N
6566	56	118	\N	0	\N	\N	f	0	\N
6567	56	117	\N	0	\N	\N	f	0	\N
6568	56	116	\N	0	\N	\N	f	0	\N
6569	56	115	\N	0	\N	\N	f	0	\N
6570	56	114	\N	0	\N	\N	f	0	\N
6571	56	113	\N	0	\N	\N	f	0	\N
6572	56	112	\N	0	\N	\N	f	0	\N
6573	56	111	\N	0	\N	\N	f	0	\N
6574	56	110	\N	0	\N	\N	f	0	\N
6575	56	180	\N	0	\N	\N	f	0	\N
6576	56	179	\N	0	\N	\N	f	0	\N
6577	56	178	\N	0	\N	\N	f	0	\N
6578	56	177	\N	0	\N	\N	f	0	\N
6579	56	176	\N	0	\N	\N	f	0	\N
6580	56	175	\N	0	\N	\N	f	0	\N
6581	56	174	\N	0	\N	\N	f	0	\N
6582	56	173	\N	0	\N	\N	f	0	\N
6583	56	172	\N	0	\N	\N	f	0	\N
6584	56	171	\N	0	\N	\N	f	0	\N
6585	56	170	\N	0	\N	\N	f	0	\N
6586	56	169	\N	0	\N	\N	f	0	\N
6587	56	168	\N	0	\N	\N	f	0	\N
6588	56	167	\N	0	\N	\N	f	0	\N
6589	56	166	\N	0	\N	\N	f	0	\N
6590	56	165	\N	0	\N	\N	f	0	\N
6591	56	164	\N	0	\N	\N	f	0	\N
6592	56	163	\N	0	\N	\N	f	0	\N
6593	56	162	\N	0	\N	\N	f	0	\N
6594	56	161	\N	0	\N	\N	f	0	\N
6595	56	160	\N	0	\N	\N	f	0	\N
6596	56	159	\N	0	\N	\N	f	0	\N
6597	56	158	\N	0	\N	\N	f	0	\N
6598	56	157	\N	0	\N	\N	f	0	\N
6599	56	156	\N	0	\N	\N	f	0	\N
6600	56	155	\N	0	\N	\N	f	0	\N
6601	56	154	\N	0	\N	\N	f	0	\N
6602	56	153	\N	0	\N	\N	f	0	\N
6603	56	152	\N	0	\N	\N	f	0	\N
6604	56	151	\N	0	\N	\N	f	0	\N
6605	56	150	\N	0	\N	\N	f	0	\N
6606	56	149	\N	0	\N	\N	f	0	\N
6607	56	148	\N	0	\N	\N	f	0	\N
6608	56	147	\N	0	\N	\N	f	0	\N
6609	56	146	\N	0	\N	\N	f	0	\N
6610	56	323	\N	0	\N	\N	f	0	\N
6611	56	322	\N	0	\N	\N	f	0	\N
6612	56	321	\N	0	\N	\N	f	0	\N
6613	56	320	\N	0	\N	\N	f	0	\N
6614	56	319	\N	0	\N	\N	f	0	\N
6615	56	318	\N	0	\N	\N	f	0	\N
6616	56	317	\N	0	\N	\N	f	0	\N
6617	56	316	\N	0	\N	\N	f	0	\N
6618	56	315	\N	0	\N	\N	f	0	\N
6619	56	314	\N	0	\N	\N	f	0	\N
6620	56	313	\N	0	\N	\N	f	0	\N
6621	56	312	\N	0	\N	\N	f	0	\N
6622	56	311	\N	0	\N	\N	f	0	\N
6623	56	310	\N	0	\N	\N	f	0	\N
6624	56	309	\N	0	\N	\N	f	0	\N
6625	56	308	\N	0	\N	\N	f	0	\N
6626	56	307	\N	0	\N	\N	f	0	\N
6627	56	306	\N	0	\N	\N	f	0	\N
6628	56	305	\N	0	\N	\N	f	0	\N
6629	56	304	\N	0	\N	\N	f	0	\N
6630	56	303	\N	0	\N	\N	f	0	\N
6631	56	302	\N	0	\N	\N	f	0	\N
6632	56	301	\N	0	\N	\N	f	0	\N
6633	56	300	\N	0	\N	\N	f	0	\N
6634	56	299	\N	0	\N	\N	f	0	\N
6635	56	298	\N	0	\N	\N	f	0	\N
6636	56	297	\N	0	\N	\N	f	0	\N
6637	56	296	\N	0	\N	\N	f	0	\N
6638	56	295	\N	0	\N	\N	f	0	\N
6639	56	294	\N	0	\N	\N	f	0	\N
6640	56	293	\N	0	\N	\N	f	0	\N
6641	56	292	\N	0	\N	\N	f	0	\N
6642	56	291	\N	0	\N	\N	f	0	\N
6643	56	254	\N	0	\N	\N	f	0	\N
6644	56	253	\N	0	\N	\N	f	0	\N
6645	56	252	\N	0	\N	\N	f	0	\N
6646	56	251	\N	0	\N	\N	f	0	\N
6647	56	250	\N	0	\N	\N	f	0	\N
6648	56	249	\N	0	\N	\N	f	0	\N
6649	56	248	\N	0	\N	\N	f	0	\N
6650	56	247	\N	0	\N	\N	f	0	\N
6651	56	246	\N	0	\N	\N	f	0	\N
6652	56	245	\N	0	\N	\N	f	0	\N
6653	56	244	\N	0	\N	\N	f	0	\N
6654	56	243	\N	0	\N	\N	f	0	\N
6655	56	242	\N	0	\N	\N	f	0	\N
6656	56	241	\N	0	\N	\N	f	0	\N
6657	56	240	\N	0	\N	\N	f	0	\N
6658	56	239	\N	0	\N	\N	f	0	\N
6659	56	238	\N	0	\N	\N	f	0	\N
6660	56	237	\N	0	\N	\N	f	0	\N
6661	56	236	\N	0	\N	\N	f	0	\N
6662	56	235	\N	0	\N	\N	f	0	\N
6663	56	234	\N	0	\N	\N	f	0	\N
6664	56	233	\N	0	\N	\N	f	0	\N
6665	56	232	\N	0	\N	\N	f	0	\N
6666	56	231	\N	0	\N	\N	f	0	\N
6667	56	230	\N	0	\N	\N	f	0	\N
6668	56	229	\N	0	\N	\N	f	0	\N
6669	56	228	\N	0	\N	\N	f	0	\N
6670	56	227	\N	0	\N	\N	f	0	\N
6671	56	226	\N	0	\N	\N	f	0	\N
6672	56	225	\N	0	\N	\N	f	0	\N
6673	56	224	\N	0	\N	\N	f	0	\N
6674	56	223	\N	0	\N	\N	f	0	\N
6675	56	222	\N	0	\N	\N	f	0	\N
6676	56	221	\N	0	\N	\N	f	0	\N
6677	56	220	\N	0	\N	\N	f	0	\N
6678	56	219	\N	0	\N	\N	f	0	\N
6679	56	432	\N	0	\N	\N	f	0	\N
6680	56	431	\N	0	\N	\N	f	0	\N
6681	56	430	\N	0	\N	\N	f	0	\N
6682	56	429	\N	0	\N	\N	f	0	\N
6683	56	428	\N	0	\N	\N	f	0	\N
6684	56	427	\N	0	\N	\N	f	0	\N
6685	56	426	\N	0	\N	\N	f	0	\N
6686	56	425	\N	0	\N	\N	f	0	\N
6687	56	424	\N	0	\N	\N	f	0	\N
6688	56	423	\N	0	\N	\N	f	0	\N
6689	56	422	\N	0	\N	\N	f	0	\N
6690	56	421	\N	0	\N	\N	f	0	\N
6691	56	420	\N	0	\N	\N	f	0	\N
6692	56	419	\N	0	\N	\N	f	0	\N
6693	56	418	\N	0	\N	\N	f	0	\N
6694	56	417	\N	0	\N	\N	f	0	\N
6695	56	416	\N	0	\N	\N	f	0	\N
6696	56	415	\N	0	\N	\N	f	0	\N
6697	56	414	\N	0	\N	\N	f	0	\N
6698	56	413	\N	0	\N	\N	f	0	\N
6699	56	412	\N	0	\N	\N	f	0	\N
6700	56	411	\N	0	\N	\N	f	0	\N
6701	56	410	\N	0	\N	\N	f	0	\N
6702	56	409	\N	0	\N	\N	f	0	\N
6703	56	408	\N	0	\N	\N	f	0	\N
6704	56	407	\N	0	\N	\N	f	0	\N
6705	56	406	\N	0	\N	\N	f	0	\N
6706	56	405	\N	0	\N	\N	f	0	\N
6707	56	404	\N	0	\N	\N	f	0	\N
6708	56	403	\N	0	\N	\N	f	0	\N
6709	56	402	\N	0	\N	\N	f	0	\N
6710	56	401	\N	0	\N	\N	f	0	\N
6711	56	400	\N	0	\N	\N	f	0	\N
6712	56	399	\N	0	\N	\N	f	0	\N
6713	56	398	\N	0	\N	\N	f	0	\N
6714	56	397	\N	0	\N	\N	f	0	\N
6715	56	396	\N	0	\N	\N	f	0	\N
6716	56	395	\N	0	\N	\N	f	0	\N
6717	56	394	\N	0	\N	\N	f	0	\N
6718	56	393	\N	0	\N	\N	f	0	\N
6719	56	392	\N	0	\N	\N	f	0	\N
6720	56	391	\N	0	\N	\N	f	0	\N
6721	56	390	\N	0	\N	\N	f	0	\N
6722	56	389	\N	0	\N	\N	f	0	\N
6723	56	388	\N	0	\N	\N	f	0	\N
6724	56	387	\N	0	\N	\N	f	0	\N
6725	56	386	\N	0	\N	\N	f	0	\N
6726	56	385	\N	0	\N	\N	f	0	\N
6727	56	384	\N	0	\N	\N	f	0	\N
6728	56	383	\N	0	\N	\N	f	0	\N
6729	56	382	\N	0	\N	\N	f	0	\N
6730	56	381	\N	0	\N	\N	f	0	\N
6731	56	380	\N	0	\N	\N	f	0	\N
6732	56	379	\N	0	\N	\N	f	0	\N
6733	56	378	\N	0	\N	\N	f	0	\N
6734	56	377	\N	0	\N	\N	f	0	\N
6735	56	376	\N	0	\N	\N	f	0	\N
6736	56	375	\N	0	\N	\N	f	0	\N
6737	56	374	\N	0	\N	\N	f	0	\N
6738	56	373	\N	0	\N	\N	f	0	\N
6739	56	372	\N	0	\N	\N	f	0	\N
6740	56	371	\N	0	\N	\N	f	0	\N
6741	56	370	\N	0	\N	\N	f	0	\N
6742	56	369	\N	0	\N	\N	f	0	\N
6743	56	368	\N	0	\N	\N	f	0	\N
6744	56	367	\N	0	\N	\N	f	0	\N
6745	56	366	\N	0	\N	\N	f	0	\N
6746	56	365	\N	0	\N	\N	f	0	\N
6747	56	364	\N	0	\N	\N	f	0	\N
6748	56	363	\N	0	\N	\N	f	0	\N
6749	56	362	\N	0	\N	\N	f	0	\N
6750	56	361	\N	0	\N	\N	f	0	\N
6751	57	74	\N	0	\N	\N	f	0	\N
6752	57	73	\N	0	\N	\N	f	0	\N
6753	57	72	\N	0	\N	\N	f	0	\N
6754	57	71	\N	0	\N	\N	f	0	\N
6755	57	70	\N	0	\N	\N	f	0	\N
6756	57	69	\N	0	\N	\N	f	0	\N
6757	57	68	\N	0	\N	\N	f	0	\N
6758	57	67	\N	0	\N	\N	f	0	\N
6759	57	66	\N	0	\N	\N	f	0	\N
6760	57	65	\N	0	\N	\N	f	0	\N
6761	57	64	\N	0	\N	\N	f	0	\N
6762	57	63	\N	0	\N	\N	f	0	\N
6763	57	62	\N	0	\N	\N	f	0	\N
6764	57	61	\N	0	\N	\N	f	0	\N
6765	57	60	\N	0	\N	\N	f	0	\N
6766	57	59	\N	0	\N	\N	f	0	\N
6767	57	58	\N	0	\N	\N	f	0	\N
6768	57	57	\N	0	\N	\N	f	0	\N
6769	57	56	\N	0	\N	\N	f	0	\N
6770	57	55	\N	0	\N	\N	f	0	\N
6771	57	54	\N	0	\N	\N	f	0	\N
6772	57	53	\N	0	\N	\N	f	0	\N
6773	57	52	\N	0	\N	\N	f	0	\N
6774	57	51	\N	0	\N	\N	f	0	\N
6775	57	50	\N	0	\N	\N	f	0	\N
6776	57	49	\N	0	\N	\N	f	0	\N
6777	57	48	\N	0	\N	\N	f	0	\N
6778	57	47	\N	0	\N	\N	f	0	\N
6779	57	46	\N	0	\N	\N	f	0	\N
6780	57	45	\N	0	\N	\N	f	0	\N
6781	57	44	\N	0	\N	\N	f	0	\N
6782	57	43	\N	0	\N	\N	f	0	\N
6783	57	42	\N	0	\N	\N	f	0	\N
6784	57	41	\N	0	\N	\N	f	0	\N
6785	57	40	\N	0	\N	\N	f	0	\N
6786	59	254	\N	0	\N	\N	f	0	\N
6787	59	253	\N	0	\N	\N	f	0	\N
6788	59	252	\N	0	\N	\N	f	0	\N
6789	59	251	\N	0	\N	\N	f	0	\N
6790	59	250	\N	0	\N	\N	f	0	\N
6791	59	249	\N	0	\N	\N	f	0	\N
6792	59	248	\N	0	\N	\N	f	0	\N
6793	59	247	\N	0	\N	\N	f	0	\N
6794	59	246	\N	0	\N	\N	f	0	\N
6795	59	245	\N	0	\N	\N	f	0	\N
6796	59	244	\N	0	\N	\N	f	0	\N
6797	59	243	\N	0	\N	\N	f	0	\N
6798	59	242	\N	0	\N	\N	f	0	\N
6799	59	241	\N	0	\N	\N	f	0	\N
6800	59	240	\N	0	\N	\N	f	0	\N
6801	59	239	\N	0	\N	\N	f	0	\N
6802	59	238	\N	0	\N	\N	f	0	\N
6803	59	237	\N	0	\N	\N	f	0	\N
6804	59	236	\N	0	\N	\N	f	0	\N
6805	59	235	\N	0	\N	\N	f	0	\N
6806	59	234	\N	0	\N	\N	f	0	\N
6807	59	233	\N	0	\N	\N	f	0	\N
6808	59	232	\N	0	\N	\N	f	0	\N
6809	59	231	\N	0	\N	\N	f	0	\N
6810	59	230	\N	0	\N	\N	f	0	\N
6811	59	229	\N	0	\N	\N	f	0	\N
6812	59	228	\N	0	\N	\N	f	0	\N
6813	59	227	\N	0	\N	\N	f	0	\N
6814	59	226	\N	0	\N	\N	f	0	\N
6815	59	225	\N	0	\N	\N	f	0	\N
6816	59	224	\N	0	\N	\N	f	0	\N
6817	59	223	\N	0	\N	\N	f	0	\N
6818	59	222	\N	0	\N	\N	f	0	\N
6819	59	221	\N	0	\N	\N	f	0	\N
6820	59	220	\N	0	\N	\N	f	0	\N
6821	59	219	\N	0	\N	\N	f	0	\N
6822	59	360	\N	0	\N	\N	f	0	\N
6823	59	359	\N	0	\N	\N	f	0	\N
6824	59	358	\N	0	\N	\N	f	0	\N
6825	59	357	\N	0	\N	\N	f	0	\N
6826	59	356	\N	0	\N	\N	f	0	\N
6827	59	355	\N	0	\N	\N	f	0	\N
6828	59	354	\N	0	\N	\N	f	0	\N
6829	59	353	\N	0	\N	\N	f	0	\N
6830	59	352	\N	0	\N	\N	f	0	\N
6831	59	351	\N	0	\N	\N	f	0	\N
6832	59	350	\N	0	\N	\N	f	0	\N
6833	59	349	\N	0	\N	\N	f	0	\N
6834	59	348	\N	0	\N	\N	f	0	\N
6835	59	347	\N	0	\N	\N	f	0	\N
6836	59	346	\N	0	\N	\N	f	0	\N
6837	59	345	\N	0	\N	\N	f	0	\N
6838	59	344	\N	0	\N	\N	f	0	\N
6839	59	343	\N	0	\N	\N	f	0	\N
6840	59	342	\N	0	\N	\N	f	0	\N
6841	59	341	\N	0	\N	\N	f	0	\N
6842	59	340	\N	0	\N	\N	f	0	\N
6843	59	339	\N	0	\N	\N	f	0	\N
6844	59	338	\N	0	\N	\N	f	0	\N
6845	59	337	\N	0	\N	\N	f	0	\N
6846	59	336	\N	0	\N	\N	f	0	\N
6847	59	335	\N	0	\N	\N	f	0	\N
6848	59	334	\N	0	\N	\N	f	0	\N
6849	59	333	\N	0	\N	\N	f	0	\N
6850	59	332	\N	0	\N	\N	f	0	\N
6851	59	331	\N	0	\N	\N	f	0	\N
6852	59	330	\N	0	\N	\N	f	0	\N
6853	59	329	\N	0	\N	\N	f	0	\N
6854	59	328	\N	0	\N	\N	f	0	\N
6855	59	327	\N	0	\N	\N	f	0	\N
6856	59	326	\N	0	\N	\N	f	0	\N
6857	59	325	\N	0	\N	\N	f	0	\N
6858	59	324	\N	0	\N	\N	f	0	\N
6859	59	180	\N	0	\N	\N	f	0	\N
6860	59	179	\N	0	\N	\N	f	0	\N
6861	59	178	\N	0	\N	\N	f	0	\N
6862	59	177	\N	0	\N	\N	f	0	\N
6863	59	176	\N	0	\N	\N	f	0	\N
6864	59	175	\N	0	\N	\N	f	0	\N
6865	59	174	\N	0	\N	\N	f	0	\N
6866	59	173	\N	0	\N	\N	f	0	\N
6867	59	172	\N	0	\N	\N	f	0	\N
6868	59	171	\N	0	\N	\N	f	0	\N
6869	59	170	\N	0	\N	\N	f	0	\N
6870	59	169	\N	0	\N	\N	f	0	\N
6871	59	168	\N	0	\N	\N	f	0	\N
6872	59	167	\N	0	\N	\N	f	0	\N
6873	59	166	\N	0	\N	\N	f	0	\N
6874	59	165	\N	0	\N	\N	f	0	\N
6875	59	164	\N	0	\N	\N	f	0	\N
6876	59	163	\N	0	\N	\N	f	0	\N
6877	59	162	\N	0	\N	\N	f	0	\N
6878	59	161	\N	0	\N	\N	f	0	\N
6879	59	160	\N	0	\N	\N	f	0	\N
6880	59	159	\N	0	\N	\N	f	0	\N
6881	59	158	\N	0	\N	\N	f	0	\N
6882	59	157	\N	0	\N	\N	f	0	\N
6883	59	156	\N	0	\N	\N	f	0	\N
6884	59	155	\N	0	\N	\N	f	0	\N
6885	59	154	\N	0	\N	\N	f	0	\N
6886	59	153	\N	0	\N	\N	f	0	\N
6887	59	152	\N	0	\N	\N	f	0	\N
6888	59	151	\N	0	\N	\N	f	0	\N
6889	59	150	\N	0	\N	\N	f	0	\N
6890	59	149	\N	0	\N	\N	f	0	\N
6891	59	148	\N	0	\N	\N	f	0	\N
6892	59	147	\N	0	\N	\N	f	0	\N
6893	59	146	\N	0	\N	\N	f	0	\N
6894	59	290	\N	0	\N	\N	f	0	\N
6895	59	289	\N	0	\N	\N	f	0	\N
6896	59	288	\N	0	\N	\N	f	0	\N
6897	59	287	\N	0	\N	\N	f	0	\N
6898	59	286	\N	0	\N	\N	f	0	\N
6899	59	285	\N	0	\N	\N	f	0	\N
6900	59	284	\N	0	\N	\N	f	0	\N
6901	59	283	\N	0	\N	\N	f	0	\N
6902	59	282	\N	0	\N	\N	f	0	\N
6903	59	281	\N	0	\N	\N	f	0	\N
6904	59	280	\N	0	\N	\N	f	0	\N
6905	59	279	\N	0	\N	\N	f	0	\N
6906	59	278	\N	0	\N	\N	f	0	\N
6907	59	277	\N	0	\N	\N	f	0	\N
6908	59	276	\N	0	\N	\N	f	0	\N
6909	59	275	\N	0	\N	\N	f	0	\N
6910	59	274	\N	0	\N	\N	f	0	\N
6911	59	273	\N	0	\N	\N	f	0	\N
6912	59	272	\N	0	\N	\N	f	0	\N
6913	59	271	\N	0	\N	\N	f	0	\N
6914	59	270	\N	0	\N	\N	f	0	\N
6915	59	269	\N	0	\N	\N	f	0	\N
6916	59	268	\N	0	\N	\N	f	0	\N
6917	59	267	\N	0	\N	\N	f	0	\N
6918	59	266	\N	0	\N	\N	f	0	\N
6919	59	265	\N	0	\N	\N	f	0	\N
6920	59	264	\N	0	\N	\N	f	0	\N
6921	59	263	\N	0	\N	\N	f	0	\N
6922	59	262	\N	0	\N	\N	f	0	\N
6923	59	261	\N	0	\N	\N	f	0	\N
6924	59	260	\N	0	\N	\N	f	0	\N
6925	59	259	\N	0	\N	\N	f	0	\N
6926	59	258	\N	0	\N	\N	f	0	\N
6927	59	257	\N	0	\N	\N	f	0	\N
6928	59	256	\N	0	\N	\N	f	0	\N
6929	59	255	\N	0	\N	\N	f	0	\N
6930	59	74	\N	0	\N	\N	f	0	\N
6931	59	73	\N	0	\N	\N	f	0	\N
6932	59	72	\N	0	\N	\N	f	0	\N
6933	59	71	\N	0	\N	\N	f	0	\N
6934	59	70	\N	0	\N	\N	f	0	\N
6935	59	69	\N	0	\N	\N	f	0	\N
6936	59	68	\N	0	\N	\N	f	0	\N
6937	59	67	\N	0	\N	\N	f	0	\N
6938	59	66	\N	0	\N	\N	f	0	\N
6939	59	65	\N	0	\N	\N	f	0	\N
6940	59	64	\N	0	\N	\N	f	0	\N
6941	59	63	\N	0	\N	\N	f	0	\N
6942	59	62	\N	0	\N	\N	f	0	\N
6943	59	61	\N	0	\N	\N	f	0	\N
6944	59	60	\N	0	\N	\N	f	0	\N
6945	59	59	\N	0	\N	\N	f	0	\N
6946	59	58	\N	0	\N	\N	f	0	\N
6947	59	57	\N	0	\N	\N	f	0	\N
6948	59	56	\N	0	\N	\N	f	0	\N
6949	59	55	\N	0	\N	\N	f	0	\N
6950	59	54	\N	0	\N	\N	f	0	\N
6951	59	53	\N	0	\N	\N	f	0	\N
6952	59	52	\N	0	\N	\N	f	0	\N
6953	59	51	\N	0	\N	\N	f	0	\N
6954	59	50	\N	0	\N	\N	f	0	\N
6955	59	49	\N	0	\N	\N	f	0	\N
6956	59	48	\N	0	\N	\N	f	0	\N
6957	59	47	\N	0	\N	\N	f	0	\N
6958	59	46	\N	0	\N	\N	f	0	\N
6959	59	45	\N	0	\N	\N	f	0	\N
6960	59	44	\N	0	\N	\N	f	0	\N
6961	59	43	\N	0	\N	\N	f	0	\N
6962	59	42	\N	0	\N	\N	f	0	\N
6963	59	41	\N	0	\N	\N	f	0	\N
6964	59	40	\N	0	\N	\N	f	0	\N
6965	59	109	\N	0	\N	\N	f	0	\N
6966	59	108	\N	0	\N	\N	f	0	\N
6967	59	107	\N	0	\N	\N	f	0	\N
6968	59	106	\N	0	\N	\N	f	0	\N
6969	59	105	\N	0	\N	\N	f	0	\N
6970	59	104	\N	0	\N	\N	f	0	\N
6971	59	103	\N	0	\N	\N	f	0	\N
6972	59	102	\N	0	\N	\N	f	0	\N
6973	59	101	\N	0	\N	\N	f	0	\N
6974	59	100	\N	0	\N	\N	f	0	\N
6975	59	99	\N	0	\N	\N	f	0	\N
6976	59	98	\N	0	\N	\N	f	0	\N
6977	59	97	\N	0	\N	\N	f	0	\N
6978	59	96	\N	0	\N	\N	f	0	\N
6979	59	95	\N	0	\N	\N	f	0	\N
6980	59	94	\N	0	\N	\N	f	0	\N
6981	59	93	\N	0	\N	\N	f	0	\N
6982	59	92	\N	0	\N	\N	f	0	\N
6983	59	91	\N	0	\N	\N	f	0	\N
6984	59	90	\N	0	\N	\N	f	0	\N
6985	59	89	\N	0	\N	\N	f	0	\N
6986	59	88	\N	0	\N	\N	f	0	\N
6987	59	87	\N	0	\N	\N	f	0	\N
6988	59	86	\N	0	\N	\N	f	0	\N
6989	59	85	\N	0	\N	\N	f	0	\N
6990	59	84	\N	0	\N	\N	f	0	\N
6991	59	83	\N	0	\N	\N	f	0	\N
6992	59	82	\N	0	\N	\N	f	0	\N
6993	59	81	\N	0	\N	\N	f	0	\N
6994	59	80	\N	0	\N	\N	f	0	\N
6995	59	79	\N	0	\N	\N	f	0	\N
6996	59	78	\N	0	\N	\N	f	0	\N
6997	59	77	\N	0	\N	\N	f	0	\N
6998	59	76	\N	0	\N	\N	f	0	\N
6999	59	75	\N	0	\N	\N	f	0	\N
7000	59	432	\N	0	\N	\N	f	0	\N
7001	59	431	\N	0	\N	\N	f	0	\N
7002	59	430	\N	0	\N	\N	f	0	\N
7003	59	429	\N	0	\N	\N	f	0	\N
7004	59	428	\N	0	\N	\N	f	0	\N
7005	59	427	\N	0	\N	\N	f	0	\N
7006	59	426	\N	0	\N	\N	f	0	\N
7007	59	425	\N	0	\N	\N	f	0	\N
7008	59	424	\N	0	\N	\N	f	0	\N
7009	59	423	\N	0	\N	\N	f	0	\N
7010	59	422	\N	0	\N	\N	f	0	\N
7011	59	421	\N	0	\N	\N	f	0	\N
7012	59	420	\N	0	\N	\N	f	0	\N
7013	59	419	\N	0	\N	\N	f	0	\N
7014	59	418	\N	0	\N	\N	f	0	\N
7015	59	417	\N	0	\N	\N	f	0	\N
7016	59	416	\N	0	\N	\N	f	0	\N
7017	59	415	\N	0	\N	\N	f	0	\N
7018	59	414	\N	0	\N	\N	f	0	\N
7019	59	413	\N	0	\N	\N	f	0	\N
7020	59	412	\N	0	\N	\N	f	0	\N
7021	59	411	\N	0	\N	\N	f	0	\N
7022	59	410	\N	0	\N	\N	f	0	\N
7023	59	409	\N	0	\N	\N	f	0	\N
7024	59	408	\N	0	\N	\N	f	0	\N
7025	59	407	\N	0	\N	\N	f	0	\N
7026	59	406	\N	0	\N	\N	f	0	\N
7027	59	405	\N	0	\N	\N	f	0	\N
7028	59	404	\N	0	\N	\N	f	0	\N
7029	59	403	\N	0	\N	\N	f	0	\N
7030	59	402	\N	0	\N	\N	f	0	\N
7031	59	323	\N	0	\N	\N	f	0	\N
7032	59	322	\N	0	\N	\N	f	0	\N
7033	59	321	\N	0	\N	\N	f	0	\N
7034	59	320	\N	0	\N	\N	f	0	\N
7035	59	319	\N	0	\N	\N	f	0	\N
7036	59	318	\N	0	\N	\N	f	0	\N
7037	59	317	\N	0	\N	\N	f	0	\N
7038	59	316	\N	0	\N	\N	f	0	\N
7039	59	315	\N	0	\N	\N	f	0	\N
7040	59	314	\N	0	\N	\N	f	0	\N
7041	59	313	\N	0	\N	\N	f	0	\N
7042	59	312	\N	0	\N	\N	f	0	\N
7043	59	311	\N	0	\N	\N	f	0	\N
7044	59	310	\N	0	\N	\N	f	0	\N
7045	59	309	\N	0	\N	\N	f	0	\N
7046	59	308	\N	0	\N	\N	f	0	\N
7047	59	307	\N	0	\N	\N	f	0	\N
7048	59	306	\N	0	\N	\N	f	0	\N
7049	59	305	\N	0	\N	\N	f	0	\N
7050	59	304	\N	0	\N	\N	f	0	\N
7051	59	303	\N	0	\N	\N	f	0	\N
7052	59	302	\N	0	\N	\N	f	0	\N
7053	59	301	\N	0	\N	\N	f	0	\N
7054	59	300	\N	0	\N	\N	f	0	\N
7055	59	299	\N	0	\N	\N	f	0	\N
7056	59	298	\N	0	\N	\N	f	0	\N
7057	59	297	\N	0	\N	\N	f	0	\N
7058	59	296	\N	0	\N	\N	f	0	\N
7059	59	295	\N	0	\N	\N	f	0	\N
7060	59	294	\N	0	\N	\N	f	0	\N
7061	59	293	\N	0	\N	\N	f	0	\N
7062	59	292	\N	0	\N	\N	f	0	\N
7063	59	291	\N	0	\N	\N	f	0	\N
7064	59	39	\N	0	\N	\N	f	0	\N
7065	59	38	\N	0	\N	\N	f	0	\N
7066	59	37	\N	0	\N	\N	f	0	\N
7067	59	36	\N	0	\N	\N	f	0	\N
7068	59	35	\N	0	\N	\N	f	0	\N
7069	59	34	\N	0	\N	\N	f	0	\N
7070	59	33	\N	0	\N	\N	f	0	\N
7071	59	32	\N	0	\N	\N	f	0	\N
7072	59	31	\N	0	\N	\N	f	0	\N
7073	59	30	\N	0	\N	\N	f	0	\N
7074	59	29	\N	0	\N	\N	f	0	\N
7075	59	28	\N	0	\N	\N	f	0	\N
7076	59	27	\N	0	\N	\N	f	0	\N
7077	59	26	\N	0	\N	\N	f	0	\N
7078	59	25	\N	0	\N	\N	f	0	\N
7079	59	24	\N	0	\N	\N	f	0	\N
7080	59	23	\N	0	\N	\N	f	0	\N
7081	59	22	\N	0	\N	\N	f	0	\N
7082	59	21	\N	0	\N	\N	f	0	\N
7083	59	20	\N	0	\N	\N	f	0	\N
7084	59	19	\N	0	\N	\N	f	0	\N
7085	59	18	\N	0	\N	\N	f	0	\N
7086	59	17	\N	0	\N	\N	f	0	\N
7087	59	16	\N	0	\N	\N	f	0	\N
7088	59	15	\N	0	\N	\N	f	0	\N
7089	59	14	\N	0	\N	\N	f	0	\N
7090	59	13	\N	0	\N	\N	f	0	\N
7091	59	12	\N	0	\N	\N	f	0	\N
7092	59	11	\N	0	\N	\N	f	0	\N
7093	59	10	\N	0	\N	\N	f	0	\N
7094	59	9	\N	0	\N	\N	f	0	\N
7095	59	8	\N	0	\N	\N	f	0	\N
7096	59	7	\N	0	\N	\N	f	0	\N
7097	59	6	\N	0	\N	\N	f	0	\N
7098	59	5	\N	0	\N	\N	f	0	\N
7099	59	4	\N	0	\N	\N	f	0	\N
7100	59	3	\N	0	\N	\N	f	0	\N
7101	59	2	\N	0	\N	\N	f	0	\N
7102	59	1	\N	0	\N	\N	f	0	\N
7103	59	218	\N	0	\N	\N	f	0	\N
7104	59	217	\N	0	\N	\N	f	0	\N
7105	59	216	\N	0	\N	\N	f	0	\N
7106	59	215	\N	0	\N	\N	f	0	\N
7107	59	214	\N	0	\N	\N	f	0	\N
7108	59	213	\N	0	\N	\N	f	0	\N
7109	59	212	\N	0	\N	\N	f	0	\N
7110	59	211	\N	0	\N	\N	f	0	\N
7111	59	210	\N	0	\N	\N	f	0	\N
7112	59	209	\N	0	\N	\N	f	0	\N
7113	59	208	\N	0	\N	\N	f	0	\N
7114	59	207	\N	0	\N	\N	f	0	\N
7115	59	206	\N	0	\N	\N	f	0	\N
7116	59	205	\N	0	\N	\N	f	0	\N
7117	59	204	\N	0	\N	\N	f	0	\N
7118	59	203	\N	0	\N	\N	f	0	\N
7119	59	202	\N	0	\N	\N	f	0	\N
7120	59	201	\N	0	\N	\N	f	0	\N
7121	59	200	\N	0	\N	\N	f	0	\N
7122	59	199	\N	0	\N	\N	f	0	\N
7123	59	198	\N	0	\N	\N	f	0	\N
7124	59	197	\N	0	\N	\N	f	0	\N
7125	59	196	\N	0	\N	\N	f	0	\N
7126	59	195	\N	0	\N	\N	f	0	\N
7127	59	194	\N	0	\N	\N	f	0	\N
7128	59	193	\N	0	\N	\N	f	0	\N
7129	59	192	\N	0	\N	\N	f	0	\N
7130	59	191	\N	0	\N	\N	f	0	\N
7131	59	190	\N	0	\N	\N	f	0	\N
7132	59	189	\N	0	\N	\N	f	0	\N
7133	59	188	\N	0	\N	\N	f	0	\N
7134	59	187	\N	0	\N	\N	f	0	\N
7135	59	186	\N	0	\N	\N	f	0	\N
7136	59	185	\N	0	\N	\N	f	0	\N
7137	59	184	\N	0	\N	\N	f	0	\N
7138	59	183	\N	0	\N	\N	f	0	\N
7139	59	182	\N	0	\N	\N	f	0	\N
7140	59	181	\N	0	\N	\N	f	0	\N
7141	59	401	\N	0	\N	\N	f	0	\N
7142	59	400	\N	0	\N	\N	f	0	\N
7143	59	399	\N	0	\N	\N	f	0	\N
7144	59	398	\N	0	\N	\N	f	0	\N
7145	59	397	\N	0	\N	\N	f	0	\N
7146	59	396	\N	0	\N	\N	f	0	\N
7147	59	395	\N	0	\N	\N	f	0	\N
7148	59	394	\N	0	\N	\N	f	0	\N
7149	59	393	\N	0	\N	\N	f	0	\N
7150	59	392	\N	0	\N	\N	f	0	\N
7151	59	391	\N	0	\N	\N	f	0	\N
7152	59	390	\N	0	\N	\N	f	0	\N
7153	59	389	\N	0	\N	\N	f	0	\N
7154	59	388	\N	0	\N	\N	f	0	\N
7155	59	387	\N	0	\N	\N	f	0	\N
7156	59	386	\N	0	\N	\N	f	0	\N
7157	59	385	\N	0	\N	\N	f	0	\N
7158	59	384	\N	0	\N	\N	f	0	\N
7159	59	383	\N	0	\N	\N	f	0	\N
7160	59	382	\N	0	\N	\N	f	0	\N
7161	59	381	\N	0	\N	\N	f	0	\N
7162	59	380	\N	0	\N	\N	f	0	\N
7163	59	379	\N	0	\N	\N	f	0	\N
7164	59	378	\N	0	\N	\N	f	0	\N
7165	59	377	\N	0	\N	\N	f	0	\N
7166	59	376	\N	0	\N	\N	f	0	\N
7167	59	375	\N	0	\N	\N	f	0	\N
7168	59	374	\N	0	\N	\N	f	0	\N
7169	59	373	\N	0	\N	\N	f	0	\N
7170	59	372	\N	0	\N	\N	f	0	\N
7171	59	371	\N	0	\N	\N	f	0	\N
7172	59	370	\N	0	\N	\N	f	0	\N
7173	59	369	\N	0	\N	\N	f	0	\N
7174	59	368	\N	0	\N	\N	f	0	\N
7175	59	367	\N	0	\N	\N	f	0	\N
7176	59	366	\N	0	\N	\N	f	0	\N
7177	59	365	\N	0	\N	\N	f	0	\N
7178	59	364	\N	0	\N	\N	f	0	\N
7179	59	363	\N	0	\N	\N	f	0	\N
7180	59	362	\N	0	\N	\N	f	0	\N
7181	59	361	\N	0	\N	\N	f	0	\N
7182	61	145	\N	0	\N	\N	f	0	\N
7183	61	144	\N	0	\N	\N	f	0	\N
7184	61	143	\N	0	\N	\N	f	0	\N
7185	61	142	\N	0	\N	\N	f	0	\N
7186	61	141	\N	0	\N	\N	f	0	\N
7187	61	140	\N	0	\N	\N	f	0	\N
7188	61	139	\N	0	\N	\N	f	0	\N
7189	61	138	\N	0	\N	\N	f	0	\N
7190	61	137	\N	0	\N	\N	f	0	\N
7191	61	136	\N	0	\N	\N	f	0	\N
7192	61	135	\N	0	\N	\N	f	0	\N
7193	61	134	\N	0	\N	\N	f	0	\N
7194	61	133	\N	0	\N	\N	f	0	\N
7195	61	132	\N	0	\N	\N	f	0	\N
7196	61	131	\N	0	\N	\N	f	0	\N
7197	61	130	\N	0	\N	\N	f	0	\N
7198	61	129	\N	0	\N	\N	f	0	\N
7199	61	128	\N	0	\N	\N	f	0	\N
7200	61	127	\N	0	\N	\N	f	0	\N
7201	61	126	\N	0	\N	\N	f	0	\N
7202	61	125	\N	0	\N	\N	f	0	\N
7203	61	124	\N	0	\N	\N	f	0	\N
7204	61	123	\N	0	\N	\N	f	0	\N
7205	61	122	\N	0	\N	\N	f	0	\N
7206	61	121	\N	0	\N	\N	f	0	\N
7207	61	120	\N	0	\N	\N	f	0	\N
7208	61	119	\N	0	\N	\N	f	0	\N
7209	61	118	\N	0	\N	\N	f	0	\N
7210	61	117	\N	0	\N	\N	f	0	\N
7211	61	116	\N	0	\N	\N	f	0	\N
7212	61	115	\N	0	\N	\N	f	0	\N
7213	61	114	\N	0	\N	\N	f	0	\N
7214	61	113	\N	0	\N	\N	f	0	\N
7215	61	112	\N	0	\N	\N	f	0	\N
7216	61	111	\N	0	\N	\N	f	0	\N
7217	61	110	\N	0	\N	\N	f	0	\N
7218	61	254	\N	0	\N	\N	f	0	\N
7219	61	253	\N	0	\N	\N	f	0	\N
7220	61	252	\N	0	\N	\N	f	0	\N
7221	61	251	\N	0	\N	\N	f	0	\N
7222	61	250	\N	0	\N	\N	f	0	\N
7223	61	249	\N	0	\N	\N	f	0	\N
7224	61	248	\N	0	\N	\N	f	0	\N
7225	61	247	\N	0	\N	\N	f	0	\N
7226	61	246	\N	0	\N	\N	f	0	\N
7227	61	245	\N	0	\N	\N	f	0	\N
7228	61	244	\N	0	\N	\N	f	0	\N
7229	61	243	\N	0	\N	\N	f	0	\N
7230	61	242	\N	0	\N	\N	f	0	\N
7231	61	241	\N	0	\N	\N	f	0	\N
7232	61	240	\N	0	\N	\N	f	0	\N
7233	61	239	\N	0	\N	\N	f	0	\N
7234	61	238	\N	0	\N	\N	f	0	\N
7235	61	237	\N	0	\N	\N	f	0	\N
7236	61	236	\N	0	\N	\N	f	0	\N
7237	61	235	\N	0	\N	\N	f	0	\N
7238	61	234	\N	0	\N	\N	f	0	\N
7239	61	233	\N	0	\N	\N	f	0	\N
7240	61	232	\N	0	\N	\N	f	0	\N
7241	61	231	\N	0	\N	\N	f	0	\N
7242	61	230	\N	0	\N	\N	f	0	\N
7243	61	229	\N	0	\N	\N	f	0	\N
7244	61	228	\N	0	\N	\N	f	0	\N
7245	61	227	\N	0	\N	\N	f	0	\N
7246	61	226	\N	0	\N	\N	f	0	\N
7247	61	225	\N	0	\N	\N	f	0	\N
7248	61	224	\N	0	\N	\N	f	0	\N
7249	61	223	\N	0	\N	\N	f	0	\N
7250	61	222	\N	0	\N	\N	f	0	\N
7251	61	221	\N	0	\N	\N	f	0	\N
7252	61	220	\N	0	\N	\N	f	0	\N
7253	61	219	\N	0	\N	\N	f	0	\N
7254	61	39	\N	0	\N	\N	f	0	\N
7255	61	38	\N	0	\N	\N	f	0	\N
7256	61	37	\N	0	\N	\N	f	0	\N
7257	61	36	\N	0	\N	\N	f	0	\N
7258	61	35	\N	0	\N	\N	f	0	\N
7259	61	34	\N	0	\N	\N	f	0	\N
7260	61	33	\N	0	\N	\N	f	0	\N
7261	61	32	\N	0	\N	\N	f	0	\N
7262	61	31	\N	0	\N	\N	f	0	\N
7263	61	30	\N	0	\N	\N	f	0	\N
7264	61	29	\N	0	\N	\N	f	0	\N
7265	61	28	\N	0	\N	\N	f	0	\N
7266	61	27	\N	0	\N	\N	f	0	\N
7267	61	26	\N	0	\N	\N	f	0	\N
7268	61	25	\N	0	\N	\N	f	0	\N
7269	61	24	\N	0	\N	\N	f	0	\N
7270	61	23	\N	0	\N	\N	f	0	\N
7271	61	22	\N	0	\N	\N	f	0	\N
7272	61	21	\N	0	\N	\N	f	0	\N
7273	61	20	\N	0	\N	\N	f	0	\N
7274	61	19	\N	0	\N	\N	f	0	\N
7275	61	18	\N	0	\N	\N	f	0	\N
7276	61	17	\N	0	\N	\N	f	0	\N
7277	61	16	\N	0	\N	\N	f	0	\N
7278	61	15	\N	0	\N	\N	f	0	\N
7279	61	14	\N	0	\N	\N	f	0	\N
7280	61	13	\N	0	\N	\N	f	0	\N
7281	61	12	\N	0	\N	\N	f	0	\N
7282	61	11	\N	0	\N	\N	f	0	\N
7283	61	10	\N	0	\N	\N	f	0	\N
7284	61	9	\N	0	\N	\N	f	0	\N
7285	61	8	\N	0	\N	\N	f	0	\N
7286	61	7	\N	0	\N	\N	f	0	\N
7287	61	6	\N	0	\N	\N	f	0	\N
7288	61	5	\N	0	\N	\N	f	0	\N
7289	61	4	\N	0	\N	\N	f	0	\N
7290	61	3	\N	0	\N	\N	f	0	\N
7291	61	2	\N	0	\N	\N	f	0	\N
7292	61	1	\N	0	\N	\N	f	0	\N
7293	62	323	\N	0	\N	\N	f	0	\N
7294	62	322	\N	0	\N	\N	f	0	\N
7295	62	321	\N	0	\N	\N	f	0	\N
7296	62	320	\N	0	\N	\N	f	0	\N
7297	62	319	\N	0	\N	\N	f	0	\N
7298	62	318	\N	0	\N	\N	f	0	\N
7299	62	317	\N	0	\N	\N	f	0	\N
7300	62	316	\N	0	\N	\N	f	0	\N
7301	62	315	\N	0	\N	\N	f	0	\N
7302	62	314	\N	0	\N	\N	f	0	\N
7303	62	313	\N	0	\N	\N	f	0	\N
7304	62	312	\N	0	\N	\N	f	0	\N
7305	62	311	\N	0	\N	\N	f	0	\N
7306	62	310	\N	0	\N	\N	f	0	\N
7307	62	309	\N	0	\N	\N	f	0	\N
7308	62	308	\N	0	\N	\N	f	0	\N
7309	62	307	\N	0	\N	\N	f	0	\N
7310	62	306	\N	0	\N	\N	f	0	\N
7311	62	305	\N	0	\N	\N	f	0	\N
7312	62	304	\N	0	\N	\N	f	0	\N
7313	62	303	\N	0	\N	\N	f	0	\N
7314	62	302	\N	0	\N	\N	f	0	\N
7315	62	301	\N	0	\N	\N	f	0	\N
7316	62	300	\N	0	\N	\N	f	0	\N
7317	62	299	\N	0	\N	\N	f	0	\N
7318	62	298	\N	0	\N	\N	f	0	\N
7319	62	297	\N	0	\N	\N	f	0	\N
7320	62	296	\N	0	\N	\N	f	0	\N
7321	62	295	\N	0	\N	\N	f	0	\N
7322	62	294	\N	0	\N	\N	f	0	\N
7323	62	293	\N	0	\N	\N	f	0	\N
7324	62	292	\N	0	\N	\N	f	0	\N
7325	62	291	\N	0	\N	\N	f	0	\N
7326	62	180	\N	0	\N	\N	f	0	\N
7327	62	179	\N	0	\N	\N	f	0	\N
7328	62	178	\N	0	\N	\N	f	0	\N
7329	62	177	\N	0	\N	\N	f	0	\N
7330	62	176	\N	0	\N	\N	f	0	\N
7331	62	175	\N	0	\N	\N	f	0	\N
7332	62	174	\N	0	\N	\N	f	0	\N
7333	62	173	\N	0	\N	\N	f	0	\N
7334	62	172	\N	0	\N	\N	f	0	\N
7335	62	171	\N	0	\N	\N	f	0	\N
7336	62	170	\N	0	\N	\N	f	0	\N
7337	62	169	\N	0	\N	\N	f	0	\N
7338	62	168	\N	0	\N	\N	f	0	\N
7339	62	167	\N	0	\N	\N	f	0	\N
7340	62	166	\N	0	\N	\N	f	0	\N
7341	62	165	\N	0	\N	\N	f	0	\N
7342	62	164	\N	0	\N	\N	f	0	\N
7343	62	163	\N	0	\N	\N	f	0	\N
7344	62	162	\N	0	\N	\N	f	0	\N
7345	62	161	\N	0	\N	\N	f	0	\N
7346	62	160	\N	0	\N	\N	f	0	\N
7347	62	159	\N	0	\N	\N	f	0	\N
7348	62	158	\N	0	\N	\N	f	0	\N
7349	62	157	\N	0	\N	\N	f	0	\N
7350	62	156	\N	0	\N	\N	f	0	\N
7351	62	155	\N	0	\N	\N	f	0	\N
7352	62	154	\N	0	\N	\N	f	0	\N
7353	62	153	\N	0	\N	\N	f	0	\N
7354	62	152	\N	0	\N	\N	f	0	\N
7355	62	151	\N	0	\N	\N	f	0	\N
7356	62	150	\N	0	\N	\N	f	0	\N
7357	62	149	\N	0	\N	\N	f	0	\N
7358	62	148	\N	0	\N	\N	f	0	\N
7359	62	147	\N	0	\N	\N	f	0	\N
7360	62	146	\N	0	\N	\N	f	0	\N
7361	62	218	\N	0	\N	\N	f	0	\N
7362	62	217	\N	0	\N	\N	f	0	\N
7363	62	216	\N	0	\N	\N	f	0	\N
7364	62	215	\N	0	\N	\N	f	0	\N
7365	62	214	\N	0	\N	\N	f	0	\N
7366	62	213	\N	0	\N	\N	f	0	\N
7367	62	212	\N	0	\N	\N	f	0	\N
7368	62	211	\N	0	\N	\N	f	0	\N
7369	62	210	\N	0	\N	\N	f	0	\N
7370	62	209	\N	0	\N	\N	f	0	\N
7371	62	208	\N	0	\N	\N	f	0	\N
7372	62	207	\N	0	\N	\N	f	0	\N
7373	62	206	\N	0	\N	\N	f	0	\N
7374	62	205	\N	0	\N	\N	f	0	\N
7375	62	204	\N	0	\N	\N	f	0	\N
7376	62	203	\N	0	\N	\N	f	0	\N
7377	62	202	\N	0	\N	\N	f	0	\N
7378	62	201	\N	0	\N	\N	f	0	\N
7379	62	200	\N	0	\N	\N	f	0	\N
7380	62	199	\N	0	\N	\N	f	0	\N
7381	62	198	\N	0	\N	\N	f	0	\N
7382	62	197	\N	0	\N	\N	f	0	\N
7383	62	196	\N	0	\N	\N	f	0	\N
7384	62	195	\N	0	\N	\N	f	0	\N
7385	62	194	\N	0	\N	\N	f	0	\N
7386	62	193	\N	0	\N	\N	f	0	\N
7387	62	192	\N	0	\N	\N	f	0	\N
7388	62	191	\N	0	\N	\N	f	0	\N
7389	62	190	\N	0	\N	\N	f	0	\N
7390	62	189	\N	0	\N	\N	f	0	\N
7391	62	188	\N	0	\N	\N	f	0	\N
7392	62	187	\N	0	\N	\N	f	0	\N
7393	62	186	\N	0	\N	\N	f	0	\N
7394	62	185	\N	0	\N	\N	f	0	\N
7395	62	184	\N	0	\N	\N	f	0	\N
7396	62	183	\N	0	\N	\N	f	0	\N
7397	62	182	\N	0	\N	\N	f	0	\N
7398	62	181	\N	0	\N	\N	f	0	\N
7399	62	109	\N	0	\N	\N	f	0	\N
7400	62	108	\N	0	\N	\N	f	0	\N
7401	62	107	\N	0	\N	\N	f	0	\N
7402	62	106	\N	0	\N	\N	f	0	\N
7403	62	105	\N	0	\N	\N	f	0	\N
7404	62	104	\N	0	\N	\N	f	0	\N
7405	62	103	\N	0	\N	\N	f	0	\N
7406	62	102	\N	0	\N	\N	f	0	\N
7407	62	101	\N	0	\N	\N	f	0	\N
7408	62	100	\N	0	\N	\N	f	0	\N
7409	62	99	\N	0	\N	\N	f	0	\N
7410	62	98	\N	0	\N	\N	f	0	\N
7411	62	97	\N	0	\N	\N	f	0	\N
7412	62	96	\N	0	\N	\N	f	0	\N
7413	62	95	\N	0	\N	\N	f	0	\N
7414	62	94	\N	0	\N	\N	f	0	\N
7415	62	93	\N	0	\N	\N	f	0	\N
7416	62	92	\N	0	\N	\N	f	0	\N
7417	62	91	\N	0	\N	\N	f	0	\N
7418	62	90	\N	0	\N	\N	f	0	\N
7419	62	89	\N	0	\N	\N	f	0	\N
7420	62	88	\N	0	\N	\N	f	0	\N
7421	62	87	\N	0	\N	\N	f	0	\N
7422	62	86	\N	0	\N	\N	f	0	\N
7423	62	85	\N	0	\N	\N	f	0	\N
7424	62	84	\N	0	\N	\N	f	0	\N
7425	62	83	\N	0	\N	\N	f	0	\N
7426	62	82	\N	0	\N	\N	f	0	\N
7427	62	81	\N	0	\N	\N	f	0	\N
7428	62	80	\N	0	\N	\N	f	0	\N
7429	62	79	\N	0	\N	\N	f	0	\N
7430	62	78	\N	0	\N	\N	f	0	\N
7431	62	77	\N	0	\N	\N	f	0	\N
7432	62	76	\N	0	\N	\N	f	0	\N
7433	62	75	\N	0	\N	\N	f	0	\N
7434	62	360	\N	0	\N	\N	f	0	\N
7435	62	359	\N	0	\N	\N	f	0	\N
7436	62	358	\N	0	\N	\N	f	0	\N
7437	62	357	\N	0	\N	\N	f	0	\N
7438	62	356	\N	0	\N	\N	f	0	\N
7439	62	355	\N	0	\N	\N	f	0	\N
7440	62	354	\N	0	\N	\N	f	0	\N
7441	62	353	\N	0	\N	\N	f	0	\N
7442	62	352	\N	0	\N	\N	f	0	\N
7443	62	351	\N	0	\N	\N	f	0	\N
7444	62	350	\N	0	\N	\N	f	0	\N
7445	62	349	\N	0	\N	\N	f	0	\N
7446	62	348	\N	0	\N	\N	f	0	\N
7447	62	347	\N	0	\N	\N	f	0	\N
7448	62	346	\N	0	\N	\N	f	0	\N
7449	62	345	\N	0	\N	\N	f	0	\N
7450	62	344	\N	0	\N	\N	f	0	\N
7451	62	343	\N	0	\N	\N	f	0	\N
7452	62	342	\N	0	\N	\N	f	0	\N
7453	62	341	\N	0	\N	\N	f	0	\N
7454	62	340	\N	0	\N	\N	f	0	\N
7455	62	339	\N	0	\N	\N	f	0	\N
7456	62	338	\N	0	\N	\N	f	0	\N
7457	62	337	\N	0	\N	\N	f	0	\N
7458	62	336	\N	0	\N	\N	f	0	\N
7459	62	335	\N	0	\N	\N	f	0	\N
7460	62	334	\N	0	\N	\N	f	0	\N
7461	62	333	\N	0	\N	\N	f	0	\N
7462	62	332	\N	0	\N	\N	f	0	\N
7463	62	331	\N	0	\N	\N	f	0	\N
7464	62	330	\N	0	\N	\N	f	0	\N
7465	62	329	\N	0	\N	\N	f	0	\N
7466	62	328	\N	0	\N	\N	f	0	\N
7467	62	327	\N	0	\N	\N	f	0	\N
7468	62	326	\N	0	\N	\N	f	0	\N
7469	62	325	\N	0	\N	\N	f	0	\N
7470	62	324	\N	0	\N	\N	f	0	\N
7471	62	432	\N	0	\N	\N	f	0	\N
7472	62	431	\N	0	\N	\N	f	0	\N
7473	62	430	\N	0	\N	\N	f	0	\N
7474	62	429	\N	0	\N	\N	f	0	\N
7475	62	428	\N	0	\N	\N	f	0	\N
7476	62	427	\N	0	\N	\N	f	0	\N
7477	62	426	\N	0	\N	\N	f	0	\N
7478	62	425	\N	0	\N	\N	f	0	\N
7479	62	424	\N	0	\N	\N	f	0	\N
7480	62	423	\N	0	\N	\N	f	0	\N
7481	62	422	\N	0	\N	\N	f	0	\N
7482	62	421	\N	0	\N	\N	f	0	\N
7483	62	420	\N	0	\N	\N	f	0	\N
7484	62	419	\N	0	\N	\N	f	0	\N
7485	62	418	\N	0	\N	\N	f	0	\N
7486	62	417	\N	0	\N	\N	f	0	\N
7487	62	416	\N	0	\N	\N	f	0	\N
7488	62	415	\N	0	\N	\N	f	0	\N
7489	62	414	\N	0	\N	\N	f	0	\N
7490	62	413	\N	0	\N	\N	f	0	\N
7491	62	412	\N	0	\N	\N	f	0	\N
7492	62	411	\N	0	\N	\N	f	0	\N
7493	62	410	\N	0	\N	\N	f	0	\N
7494	62	409	\N	0	\N	\N	f	0	\N
7495	62	408	\N	0	\N	\N	f	0	\N
7496	62	407	\N	0	\N	\N	f	0	\N
7497	62	406	\N	0	\N	\N	f	0	\N
7498	62	405	\N	0	\N	\N	f	0	\N
7499	62	404	\N	0	\N	\N	f	0	\N
7500	62	403	\N	0	\N	\N	f	0	\N
7501	62	402	\N	0	\N	\N	f	0	\N
7502	62	74	\N	0	\N	\N	f	0	\N
7503	62	73	\N	0	\N	\N	f	0	\N
7504	62	72	\N	0	\N	\N	f	0	\N
7505	62	71	\N	0	\N	\N	f	0	\N
7506	62	70	\N	0	\N	\N	f	0	\N
7507	62	69	\N	0	\N	\N	f	0	\N
7508	62	68	\N	0	\N	\N	f	0	\N
7509	62	67	\N	0	\N	\N	f	0	\N
7510	62	66	\N	0	\N	\N	f	0	\N
7511	62	65	\N	0	\N	\N	f	0	\N
7512	62	64	\N	0	\N	\N	f	0	\N
7513	62	63	\N	0	\N	\N	f	0	\N
7514	62	62	\N	0	\N	\N	f	0	\N
7515	62	61	\N	0	\N	\N	f	0	\N
7516	62	60	\N	0	\N	\N	f	0	\N
7517	62	59	\N	0	\N	\N	f	0	\N
7518	62	58	\N	0	\N	\N	f	0	\N
7519	62	57	\N	0	\N	\N	f	0	\N
7520	62	56	\N	0	\N	\N	f	0	\N
7521	62	55	\N	0	\N	\N	f	0	\N
7522	62	54	\N	0	\N	\N	f	0	\N
7523	62	53	\N	0	\N	\N	f	0	\N
7524	62	52	\N	0	\N	\N	f	0	\N
7525	62	51	\N	0	\N	\N	f	0	\N
7526	62	50	\N	0	\N	\N	f	0	\N
7527	62	49	\N	0	\N	\N	f	0	\N
7528	62	48	\N	0	\N	\N	f	0	\N
7529	62	47	\N	0	\N	\N	f	0	\N
7530	62	46	\N	0	\N	\N	f	0	\N
7531	62	45	\N	0	\N	\N	f	0	\N
7532	62	44	\N	0	\N	\N	f	0	\N
7533	62	43	\N	0	\N	\N	f	0	\N
7534	62	42	\N	0	\N	\N	f	0	\N
7535	62	41	\N	0	\N	\N	f	0	\N
7536	62	40	\N	0	\N	\N	f	0	\N
7537	62	401	\N	0	\N	\N	f	0	\N
7538	62	400	\N	0	\N	\N	f	0	\N
7539	62	399	\N	0	\N	\N	f	0	\N
7540	62	398	\N	0	\N	\N	f	0	\N
7541	62	397	\N	0	\N	\N	f	0	\N
7542	62	396	\N	0	\N	\N	f	0	\N
7543	62	395	\N	0	\N	\N	f	0	\N
7544	62	394	\N	0	\N	\N	f	0	\N
7545	62	393	\N	0	\N	\N	f	0	\N
7546	62	392	\N	0	\N	\N	f	0	\N
7547	62	391	\N	0	\N	\N	f	0	\N
7548	62	390	\N	0	\N	\N	f	0	\N
7549	62	389	\N	0	\N	\N	f	0	\N
7550	62	388	\N	0	\N	\N	f	0	\N
7551	62	387	\N	0	\N	\N	f	0	\N
7552	62	386	\N	0	\N	\N	f	0	\N
7553	62	385	\N	0	\N	\N	f	0	\N
7554	62	384	\N	0	\N	\N	f	0	\N
7555	62	383	\N	0	\N	\N	f	0	\N
7556	62	382	\N	0	\N	\N	f	0	\N
7557	62	381	\N	0	\N	\N	f	0	\N
7558	62	380	\N	0	\N	\N	f	0	\N
7559	62	379	\N	0	\N	\N	f	0	\N
7560	62	378	\N	0	\N	\N	f	0	\N
7561	62	377	\N	0	\N	\N	f	0	\N
7562	62	376	\N	0	\N	\N	f	0	\N
7563	62	375	\N	0	\N	\N	f	0	\N
7564	62	374	\N	0	\N	\N	f	0	\N
7565	62	373	\N	0	\N	\N	f	0	\N
7566	62	372	\N	0	\N	\N	f	0	\N
7567	62	371	\N	0	\N	\N	f	0	\N
7568	62	370	\N	0	\N	\N	f	0	\N
7569	62	369	\N	0	\N	\N	f	0	\N
7570	62	368	\N	0	\N	\N	f	0	\N
7571	62	367	\N	0	\N	\N	f	0	\N
7572	62	366	\N	0	\N	\N	f	0	\N
7573	62	365	\N	0	\N	\N	f	0	\N
7574	62	364	\N	0	\N	\N	f	0	\N
7575	62	363	\N	0	\N	\N	f	0	\N
7576	62	362	\N	0	\N	\N	f	0	\N
7577	62	361	\N	0	\N	\N	f	0	\N
7578	62	290	\N	0	\N	\N	f	0	\N
7579	62	289	\N	0	\N	\N	f	0	\N
7580	62	288	\N	0	\N	\N	f	0	\N
7581	62	287	\N	0	\N	\N	f	0	\N
7582	62	286	\N	0	\N	\N	f	0	\N
7583	62	285	\N	0	\N	\N	f	0	\N
7584	62	284	\N	0	\N	\N	f	0	\N
7585	62	283	\N	0	\N	\N	f	0	\N
7586	62	282	\N	0	\N	\N	f	0	\N
7587	62	281	\N	0	\N	\N	f	0	\N
7588	62	280	\N	0	\N	\N	f	0	\N
7589	62	279	\N	0	\N	\N	f	0	\N
7590	62	278	\N	0	\N	\N	f	0	\N
7591	62	277	\N	0	\N	\N	f	0	\N
7592	62	276	\N	0	\N	\N	f	0	\N
7593	62	275	\N	0	\N	\N	f	0	\N
7594	62	274	\N	0	\N	\N	f	0	\N
7595	62	273	\N	0	\N	\N	f	0	\N
7596	62	272	\N	0	\N	\N	f	0	\N
7597	62	271	\N	0	\N	\N	f	0	\N
7598	62	270	\N	0	\N	\N	f	0	\N
7599	62	269	\N	0	\N	\N	f	0	\N
7600	62	268	\N	0	\N	\N	f	0	\N
7601	62	267	\N	0	\N	\N	f	0	\N
7602	62	266	\N	0	\N	\N	f	0	\N
7603	62	265	\N	0	\N	\N	f	0	\N
7604	62	264	\N	0	\N	\N	f	0	\N
7605	62	263	\N	0	\N	\N	f	0	\N
7606	62	262	\N	0	\N	\N	f	0	\N
7607	62	261	\N	0	\N	\N	f	0	\N
7608	62	260	\N	0	\N	\N	f	0	\N
7609	62	259	\N	0	\N	\N	f	0	\N
7610	62	258	\N	0	\N	\N	f	0	\N
7611	62	257	\N	0	\N	\N	f	0	\N
7612	62	256	\N	0	\N	\N	f	0	\N
7613	62	255	\N	0	\N	\N	f	0	\N
7614	63	323	\N	0	\N	\N	f	0	\N
7615	63	322	\N	0	\N	\N	f	0	\N
7616	63	321	\N	0	\N	\N	f	0	\N
7617	63	320	\N	0	\N	\N	f	0	\N
7618	63	319	\N	0	\N	\N	f	0	\N
7619	63	318	\N	0	\N	\N	f	0	\N
7620	63	317	\N	0	\N	\N	f	0	\N
7621	63	316	\N	0	\N	\N	f	0	\N
7622	63	315	\N	0	\N	\N	f	0	\N
7623	63	314	\N	0	\N	\N	f	0	\N
7624	63	313	\N	0	\N	\N	f	0	\N
7625	63	312	\N	0	\N	\N	f	0	\N
7626	63	311	\N	0	\N	\N	f	0	\N
7627	63	310	\N	0	\N	\N	f	0	\N
7628	63	309	\N	0	\N	\N	f	0	\N
7629	63	308	\N	0	\N	\N	f	0	\N
7630	63	307	\N	0	\N	\N	f	0	\N
7631	63	306	\N	0	\N	\N	f	0	\N
7632	63	305	\N	0	\N	\N	f	0	\N
7633	63	304	\N	0	\N	\N	f	0	\N
7634	63	303	\N	0	\N	\N	f	0	\N
7635	63	302	\N	0	\N	\N	f	0	\N
7636	63	301	\N	0	\N	\N	f	0	\N
7637	63	300	\N	0	\N	\N	f	0	\N
7638	63	299	\N	0	\N	\N	f	0	\N
7639	63	298	\N	0	\N	\N	f	0	\N
7640	63	297	\N	0	\N	\N	f	0	\N
7641	63	296	\N	0	\N	\N	f	0	\N
7642	63	295	\N	0	\N	\N	f	0	\N
7643	63	294	\N	0	\N	\N	f	0	\N
7644	63	293	\N	0	\N	\N	f	0	\N
7645	63	292	\N	0	\N	\N	f	0	\N
7646	63	291	\N	0	\N	\N	f	0	\N
7647	63	109	\N	0	\N	\N	f	0	\N
7648	63	108	\N	0	\N	\N	f	0	\N
7649	63	107	\N	0	\N	\N	f	0	\N
7650	63	106	\N	0	\N	\N	f	0	\N
7651	63	105	\N	0	\N	\N	f	0	\N
7652	63	104	\N	0	\N	\N	f	0	\N
7653	63	103	\N	0	\N	\N	f	0	\N
7654	63	102	\N	0	\N	\N	f	0	\N
7655	63	101	\N	0	\N	\N	f	0	\N
7656	63	100	\N	0	\N	\N	f	0	\N
7657	63	99	\N	0	\N	\N	f	0	\N
7658	63	98	\N	0	\N	\N	f	0	\N
7659	63	97	\N	0	\N	\N	f	0	\N
7660	63	96	\N	0	\N	\N	f	0	\N
7661	63	95	\N	0	\N	\N	f	0	\N
7662	63	94	\N	0	\N	\N	f	0	\N
7663	63	93	\N	0	\N	\N	f	0	\N
7664	63	92	\N	0	\N	\N	f	0	\N
7665	63	91	\N	0	\N	\N	f	0	\N
7666	63	90	\N	0	\N	\N	f	0	\N
7667	63	89	\N	0	\N	\N	f	0	\N
7668	63	88	\N	0	\N	\N	f	0	\N
7669	63	87	\N	0	\N	\N	f	0	\N
7670	63	86	\N	0	\N	\N	f	0	\N
7671	63	85	\N	0	\N	\N	f	0	\N
7672	63	84	\N	0	\N	\N	f	0	\N
7673	63	83	\N	0	\N	\N	f	0	\N
7674	63	82	\N	0	\N	\N	f	0	\N
7675	63	81	\N	0	\N	\N	f	0	\N
7676	63	80	\N	0	\N	\N	f	0	\N
7677	63	79	\N	0	\N	\N	f	0	\N
7678	63	78	\N	0	\N	\N	f	0	\N
7679	63	77	\N	0	\N	\N	f	0	\N
7680	63	76	\N	0	\N	\N	f	0	\N
7681	63	75	\N	0	\N	\N	f	0	\N
7682	63	180	\N	0	\N	\N	f	0	\N
7683	63	179	\N	0	\N	\N	f	0	\N
7684	63	178	\N	0	\N	\N	f	0	\N
7685	63	177	\N	0	\N	\N	f	0	\N
7686	63	176	\N	0	\N	\N	f	0	\N
7687	63	175	\N	0	\N	\N	f	0	\N
7688	63	174	\N	0	\N	\N	f	0	\N
7689	63	173	\N	0	\N	\N	f	0	\N
7690	63	172	\N	0	\N	\N	f	0	\N
7691	63	171	\N	0	\N	\N	f	0	\N
7692	63	170	\N	0	\N	\N	f	0	\N
7693	63	169	\N	0	\N	\N	f	0	\N
7694	63	168	\N	0	\N	\N	f	0	\N
7695	63	167	\N	0	\N	\N	f	0	\N
7696	63	166	\N	0	\N	\N	f	0	\N
7697	63	165	\N	0	\N	\N	f	0	\N
7698	63	164	\N	0	\N	\N	f	0	\N
7699	63	163	\N	0	\N	\N	f	0	\N
7700	63	162	\N	0	\N	\N	f	0	\N
7701	63	161	\N	0	\N	\N	f	0	\N
7702	63	160	\N	0	\N	\N	f	0	\N
7703	63	159	\N	0	\N	\N	f	0	\N
7704	63	158	\N	0	\N	\N	f	0	\N
7705	63	157	\N	0	\N	\N	f	0	\N
7706	63	156	\N	0	\N	\N	f	0	\N
7707	63	155	\N	0	\N	\N	f	0	\N
7708	63	154	\N	0	\N	\N	f	0	\N
7709	63	153	\N	0	\N	\N	f	0	\N
7710	63	152	\N	0	\N	\N	f	0	\N
7711	63	151	\N	0	\N	\N	f	0	\N
7712	63	150	\N	0	\N	\N	f	0	\N
7713	63	149	\N	0	\N	\N	f	0	\N
7714	63	148	\N	0	\N	\N	f	0	\N
7715	63	147	\N	0	\N	\N	f	0	\N
7716	63	146	\N	0	\N	\N	f	0	\N
7717	63	360	\N	0	\N	\N	f	0	\N
7718	63	359	\N	0	\N	\N	f	0	\N
7719	63	358	\N	0	\N	\N	f	0	\N
7720	63	357	\N	0	\N	\N	f	0	\N
7721	63	356	\N	0	\N	\N	f	0	\N
7722	63	355	\N	0	\N	\N	f	0	\N
7723	63	354	\N	0	\N	\N	f	0	\N
7724	63	353	\N	0	\N	\N	f	0	\N
7725	63	352	\N	0	\N	\N	f	0	\N
7726	63	351	\N	0	\N	\N	f	0	\N
7727	63	350	\N	0	\N	\N	f	0	\N
7728	63	349	\N	0	\N	\N	f	0	\N
7729	63	348	\N	0	\N	\N	f	0	\N
7730	63	347	\N	0	\N	\N	f	0	\N
7731	63	346	\N	0	\N	\N	f	0	\N
7732	63	345	\N	0	\N	\N	f	0	\N
7733	63	344	\N	0	\N	\N	f	0	\N
7734	63	343	\N	0	\N	\N	f	0	\N
7735	63	342	\N	0	\N	\N	f	0	\N
7736	63	341	\N	0	\N	\N	f	0	\N
7737	63	340	\N	0	\N	\N	f	0	\N
7738	63	339	\N	0	\N	\N	f	0	\N
7739	63	338	\N	0	\N	\N	f	0	\N
7740	63	337	\N	0	\N	\N	f	0	\N
7741	63	336	\N	0	\N	\N	f	0	\N
7742	63	335	\N	0	\N	\N	f	0	\N
7743	63	334	\N	0	\N	\N	f	0	\N
7744	63	333	\N	0	\N	\N	f	0	\N
7745	63	332	\N	0	\N	\N	f	0	\N
7746	63	331	\N	0	\N	\N	f	0	\N
7747	63	330	\N	0	\N	\N	f	0	\N
7748	63	329	\N	0	\N	\N	f	0	\N
7749	63	328	\N	0	\N	\N	f	0	\N
7750	63	327	\N	0	\N	\N	f	0	\N
7751	63	326	\N	0	\N	\N	f	0	\N
7752	63	325	\N	0	\N	\N	f	0	\N
7753	63	324	\N	0	\N	\N	f	0	\N
7754	63	254	\N	0	\N	\N	f	0	\N
7755	63	253	\N	0	\N	\N	f	0	\N
7756	63	252	\N	0	\N	\N	f	0	\N
7757	63	251	\N	0	\N	\N	f	0	\N
7758	63	250	\N	0	\N	\N	f	0	\N
7759	63	249	\N	0	\N	\N	f	0	\N
7760	63	248	\N	0	\N	\N	f	0	\N
7761	63	247	\N	0	\N	\N	f	0	\N
7762	63	246	\N	0	\N	\N	f	0	\N
7763	63	245	\N	0	\N	\N	f	0	\N
7764	63	244	\N	0	\N	\N	f	0	\N
7765	63	243	\N	0	\N	\N	f	0	\N
7766	63	242	\N	0	\N	\N	f	0	\N
7767	63	241	\N	0	\N	\N	f	0	\N
7768	63	240	\N	0	\N	\N	f	0	\N
7769	63	239	\N	0	\N	\N	f	0	\N
7770	63	238	\N	0	\N	\N	f	0	\N
7771	63	237	\N	0	\N	\N	f	0	\N
7772	63	236	\N	0	\N	\N	f	0	\N
7773	63	235	\N	0	\N	\N	f	0	\N
7774	63	234	\N	0	\N	\N	f	0	\N
7775	63	233	\N	0	\N	\N	f	0	\N
7776	63	232	\N	0	\N	\N	f	0	\N
7777	63	231	\N	0	\N	\N	f	0	\N
7778	63	230	\N	0	\N	\N	f	0	\N
7779	63	229	\N	0	\N	\N	f	0	\N
7780	63	228	\N	0	\N	\N	f	0	\N
7781	63	227	\N	0	\N	\N	f	0	\N
7782	63	226	\N	0	\N	\N	f	0	\N
7783	63	225	\N	0	\N	\N	f	0	\N
7784	63	224	\N	0	\N	\N	f	0	\N
7785	63	223	\N	0	\N	\N	f	0	\N
7786	63	222	\N	0	\N	\N	f	0	\N
7787	63	221	\N	0	\N	\N	f	0	\N
7788	63	220	\N	0	\N	\N	f	0	\N
7789	63	219	\N	0	\N	\N	f	0	\N
7790	63	74	\N	0	\N	\N	f	0	\N
7791	63	73	\N	0	\N	\N	f	0	\N
7792	63	72	\N	0	\N	\N	f	0	\N
7793	63	71	\N	0	\N	\N	f	0	\N
7794	63	70	\N	0	\N	\N	f	0	\N
7795	63	69	\N	0	\N	\N	f	0	\N
7796	63	68	\N	0	\N	\N	f	0	\N
7797	63	67	\N	0	\N	\N	f	0	\N
7798	63	66	\N	0	\N	\N	f	0	\N
7799	63	65	\N	0	\N	\N	f	0	\N
7800	63	64	\N	0	\N	\N	f	0	\N
7801	63	63	\N	0	\N	\N	f	0	\N
7802	63	62	\N	0	\N	\N	f	0	\N
7803	63	61	\N	0	\N	\N	f	0	\N
7804	63	60	\N	0	\N	\N	f	0	\N
7805	63	59	\N	0	\N	\N	f	0	\N
7806	63	58	\N	0	\N	\N	f	0	\N
7807	63	57	\N	0	\N	\N	f	0	\N
7808	63	56	\N	0	\N	\N	f	0	\N
7809	63	55	\N	0	\N	\N	f	0	\N
7810	63	54	\N	0	\N	\N	f	0	\N
7811	63	53	\N	0	\N	\N	f	0	\N
7812	63	52	\N	0	\N	\N	f	0	\N
7813	63	51	\N	0	\N	\N	f	0	\N
7814	63	50	\N	0	\N	\N	f	0	\N
7815	63	49	\N	0	\N	\N	f	0	\N
7816	63	48	\N	0	\N	\N	f	0	\N
7817	63	47	\N	0	\N	\N	f	0	\N
7818	63	46	\N	0	\N	\N	f	0	\N
7819	63	45	\N	0	\N	\N	f	0	\N
7820	63	44	\N	0	\N	\N	f	0	\N
7821	63	43	\N	0	\N	\N	f	0	\N
7822	63	42	\N	0	\N	\N	f	0	\N
7823	63	41	\N	0	\N	\N	f	0	\N
7824	63	40	\N	0	\N	\N	f	0	\N
7825	63	401	\N	0	\N	\N	f	0	\N
7826	63	400	\N	0	\N	\N	f	0	\N
7827	63	399	\N	0	\N	\N	f	0	\N
7828	63	398	\N	0	\N	\N	f	0	\N
7829	63	397	\N	0	\N	\N	f	0	\N
7830	63	396	\N	0	\N	\N	f	0	\N
7831	63	395	\N	0	\N	\N	f	0	\N
7832	63	394	\N	0	\N	\N	f	0	\N
7833	63	393	\N	0	\N	\N	f	0	\N
7834	63	392	\N	0	\N	\N	f	0	\N
7835	63	391	\N	0	\N	\N	f	0	\N
7836	63	390	\N	0	\N	\N	f	0	\N
7837	63	389	\N	0	\N	\N	f	0	\N
7838	63	388	\N	0	\N	\N	f	0	\N
7839	63	387	\N	0	\N	\N	f	0	\N
7840	63	386	\N	0	\N	\N	f	0	\N
7841	63	385	\N	0	\N	\N	f	0	\N
7842	63	384	\N	0	\N	\N	f	0	\N
7843	63	383	\N	0	\N	\N	f	0	\N
7844	63	382	\N	0	\N	\N	f	0	\N
7845	63	381	\N	0	\N	\N	f	0	\N
7846	63	380	\N	0	\N	\N	f	0	\N
7847	63	379	\N	0	\N	\N	f	0	\N
7848	63	378	\N	0	\N	\N	f	0	\N
7849	63	377	\N	0	\N	\N	f	0	\N
7850	63	376	\N	0	\N	\N	f	0	\N
7851	63	375	\N	0	\N	\N	f	0	\N
7852	63	374	\N	0	\N	\N	f	0	\N
7853	63	373	\N	0	\N	\N	f	0	\N
7854	63	372	\N	0	\N	\N	f	0	\N
7855	63	371	\N	0	\N	\N	f	0	\N
7856	63	370	\N	0	\N	\N	f	0	\N
7857	63	369	\N	0	\N	\N	f	0	\N
7858	63	368	\N	0	\N	\N	f	0	\N
7859	63	367	\N	0	\N	\N	f	0	\N
7860	63	366	\N	0	\N	\N	f	0	\N
7861	63	365	\N	0	\N	\N	f	0	\N
7862	63	364	\N	0	\N	\N	f	0	\N
7863	63	363	\N	0	\N	\N	f	0	\N
7864	63	362	\N	0	\N	\N	f	0	\N
7865	63	361	\N	0	\N	\N	f	0	\N
7866	63	432	\N	0	\N	\N	f	0	\N
7867	63	431	\N	0	\N	\N	f	0	\N
7868	63	430	\N	0	\N	\N	f	0	\N
7869	63	429	\N	0	\N	\N	f	0	\N
7870	63	428	\N	0	\N	\N	f	0	\N
7871	63	427	\N	0	\N	\N	f	0	\N
7872	63	426	\N	0	\N	\N	f	0	\N
7873	63	425	\N	0	\N	\N	f	0	\N
7874	63	424	\N	0	\N	\N	f	0	\N
7875	63	423	\N	0	\N	\N	f	0	\N
7876	63	422	\N	0	\N	\N	f	0	\N
7877	63	421	\N	0	\N	\N	f	0	\N
7878	63	420	\N	0	\N	\N	f	0	\N
7879	63	419	\N	0	\N	\N	f	0	\N
7880	63	418	\N	0	\N	\N	f	0	\N
7881	63	417	\N	0	\N	\N	f	0	\N
7882	63	416	\N	0	\N	\N	f	0	\N
7883	63	415	\N	0	\N	\N	f	0	\N
7884	63	414	\N	0	\N	\N	f	0	\N
7885	63	413	\N	0	\N	\N	f	0	\N
7886	63	412	\N	0	\N	\N	f	0	\N
7887	63	411	\N	0	\N	\N	f	0	\N
7888	63	410	\N	0	\N	\N	f	0	\N
7889	63	409	\N	0	\N	\N	f	0	\N
7890	63	408	\N	0	\N	\N	f	0	\N
7891	63	407	\N	0	\N	\N	f	0	\N
7892	63	406	\N	0	\N	\N	f	0	\N
7893	63	405	\N	0	\N	\N	f	0	\N
7894	63	404	\N	0	\N	\N	f	0	\N
7895	63	403	\N	0	\N	\N	f	0	\N
7896	63	402	\N	0	\N	\N	f	0	\N
7897	63	290	\N	0	\N	\N	f	0	\N
7898	63	289	\N	0	\N	\N	f	0	\N
7899	63	288	\N	0	\N	\N	f	0	\N
7900	63	287	\N	0	\N	\N	f	0	\N
7901	63	286	\N	0	\N	\N	f	0	\N
7902	63	285	\N	0	\N	\N	f	0	\N
7903	63	284	\N	0	\N	\N	f	0	\N
7904	63	283	\N	0	\N	\N	f	0	\N
7905	63	282	\N	0	\N	\N	f	0	\N
7906	63	281	\N	0	\N	\N	f	0	\N
7907	63	280	\N	0	\N	\N	f	0	\N
7908	63	279	\N	0	\N	\N	f	0	\N
7909	63	278	\N	0	\N	\N	f	0	\N
7910	63	277	\N	0	\N	\N	f	0	\N
7911	63	276	\N	0	\N	\N	f	0	\N
7912	63	275	\N	0	\N	\N	f	0	\N
7913	63	274	\N	0	\N	\N	f	0	\N
7914	63	273	\N	0	\N	\N	f	0	\N
7915	63	272	\N	0	\N	\N	f	0	\N
7916	63	271	\N	0	\N	\N	f	0	\N
7917	63	270	\N	0	\N	\N	f	0	\N
7918	63	269	\N	0	\N	\N	f	0	\N
7919	63	268	\N	0	\N	\N	f	0	\N
7920	63	267	\N	0	\N	\N	f	0	\N
7921	63	266	\N	0	\N	\N	f	0	\N
7922	63	265	\N	0	\N	\N	f	0	\N
7923	63	264	\N	0	\N	\N	f	0	\N
7924	63	263	\N	0	\N	\N	f	0	\N
7925	63	262	\N	0	\N	\N	f	0	\N
7926	63	261	\N	0	\N	\N	f	0	\N
7927	63	260	\N	0	\N	\N	f	0	\N
7928	63	259	\N	0	\N	\N	f	0	\N
7929	63	258	\N	0	\N	\N	f	0	\N
7930	63	257	\N	0	\N	\N	f	0	\N
7931	63	256	\N	0	\N	\N	f	0	\N
7932	63	255	\N	0	\N	\N	f	0	\N
7933	64	109	\N	0	\N	\N	f	0	\N
7934	64	108	\N	0	\N	\N	f	0	\N
7935	64	107	\N	0	\N	\N	f	0	\N
7936	64	106	\N	0	\N	\N	f	0	\N
7937	64	105	\N	0	\N	\N	f	0	\N
7938	64	104	\N	0	\N	\N	f	0	\N
7939	64	103	\N	0	\N	\N	f	0	\N
7940	64	102	\N	0	\N	\N	f	0	\N
7941	64	101	\N	0	\N	\N	f	0	\N
7942	64	100	\N	0	\N	\N	f	0	\N
7943	64	99	\N	0	\N	\N	f	0	\N
7944	64	98	\N	0	\N	\N	f	0	\N
7945	64	97	\N	0	\N	\N	f	0	\N
7946	64	96	\N	0	\N	\N	f	0	\N
7947	64	95	\N	0	\N	\N	f	0	\N
7948	64	94	\N	0	\N	\N	f	0	\N
7949	64	93	\N	0	\N	\N	f	0	\N
7950	64	92	\N	0	\N	\N	f	0	\N
7951	64	91	\N	0	\N	\N	f	0	\N
7952	64	90	\N	0	\N	\N	f	0	\N
7953	64	89	\N	0	\N	\N	f	0	\N
7954	64	88	\N	0	\N	\N	f	0	\N
7955	64	87	\N	0	\N	\N	f	0	\N
7956	64	86	\N	0	\N	\N	f	0	\N
7957	64	85	\N	0	\N	\N	f	0	\N
7958	64	84	\N	0	\N	\N	f	0	\N
7959	64	83	\N	0	\N	\N	f	0	\N
7960	64	82	\N	0	\N	\N	f	0	\N
7961	64	81	\N	0	\N	\N	f	0	\N
7962	64	80	\N	0	\N	\N	f	0	\N
7963	64	79	\N	0	\N	\N	f	0	\N
7964	64	78	\N	0	\N	\N	f	0	\N
7965	64	77	\N	0	\N	\N	f	0	\N
7966	64	76	\N	0	\N	\N	f	0	\N
7967	64	75	\N	0	\N	\N	f	0	\N
7968	65	360	\N	0	\N	\N	f	0	\N
7969	65	359	\N	0	\N	\N	f	0	\N
7970	65	358	\N	0	\N	\N	f	0	\N
7971	65	357	\N	0	\N	\N	f	0	\N
7972	65	356	\N	0	\N	\N	f	0	\N
7973	65	355	\N	0	\N	\N	f	0	\N
7974	65	354	\N	0	\N	\N	f	0	\N
7975	65	353	\N	0	\N	\N	f	0	\N
7976	65	352	\N	0	\N	\N	f	0	\N
7977	65	351	\N	0	\N	\N	f	0	\N
7978	65	350	\N	0	\N	\N	f	0	\N
7979	65	349	\N	0	\N	\N	f	0	\N
7980	65	348	\N	0	\N	\N	f	0	\N
7981	65	347	\N	0	\N	\N	f	0	\N
7982	65	346	\N	0	\N	\N	f	0	\N
7983	65	345	\N	0	\N	\N	f	0	\N
7984	65	344	\N	0	\N	\N	f	0	\N
7985	65	343	\N	0	\N	\N	f	0	\N
7986	65	342	\N	0	\N	\N	f	0	\N
7987	65	341	\N	0	\N	\N	f	0	\N
7988	65	340	\N	0	\N	\N	f	0	\N
7989	65	339	\N	0	\N	\N	f	0	\N
7990	65	338	\N	0	\N	\N	f	0	\N
7991	65	337	\N	0	\N	\N	f	0	\N
7992	65	336	\N	0	\N	\N	f	0	\N
7993	65	335	\N	0	\N	\N	f	0	\N
7994	65	334	\N	0	\N	\N	f	0	\N
7995	65	333	\N	0	\N	\N	f	0	\N
7996	65	332	\N	0	\N	\N	f	0	\N
7997	65	331	\N	0	\N	\N	f	0	\N
7998	65	330	\N	0	\N	\N	f	0	\N
7999	65	329	\N	0	\N	\N	f	0	\N
8000	65	328	\N	0	\N	\N	f	0	\N
8001	65	327	\N	0	\N	\N	f	0	\N
8002	65	326	\N	0	\N	\N	f	0	\N
8003	65	325	\N	0	\N	\N	f	0	\N
8004	65	324	\N	0	\N	\N	f	0	\N
8005	65	432	\N	0	\N	\N	f	0	\N
8006	65	431	\N	0	\N	\N	f	0	\N
8007	65	430	\N	0	\N	\N	f	0	\N
8008	65	429	\N	0	\N	\N	f	0	\N
8009	65	428	\N	0	\N	\N	f	0	\N
8010	65	427	\N	0	\N	\N	f	0	\N
8011	65	426	\N	0	\N	\N	f	0	\N
8012	65	425	\N	0	\N	\N	f	0	\N
8013	65	424	\N	0	\N	\N	f	0	\N
8014	65	423	\N	0	\N	\N	f	0	\N
8015	65	422	\N	0	\N	\N	f	0	\N
8016	65	421	\N	0	\N	\N	f	0	\N
8017	65	420	\N	0	\N	\N	f	0	\N
8018	65	419	\N	0	\N	\N	f	0	\N
8019	65	418	\N	0	\N	\N	f	0	\N
8020	65	417	\N	0	\N	\N	f	0	\N
8021	65	416	\N	0	\N	\N	f	0	\N
8022	65	415	\N	0	\N	\N	f	0	\N
8023	65	414	\N	0	\N	\N	f	0	\N
8024	65	413	\N	0	\N	\N	f	0	\N
8025	65	412	\N	0	\N	\N	f	0	\N
8026	65	411	\N	0	\N	\N	f	0	\N
8027	65	410	\N	0	\N	\N	f	0	\N
8028	65	409	\N	0	\N	\N	f	0	\N
8029	65	408	\N	0	\N	\N	f	0	\N
8030	65	407	\N	0	\N	\N	f	0	\N
8031	65	406	\N	0	\N	\N	f	0	\N
8032	65	405	\N	0	\N	\N	f	0	\N
8033	65	404	\N	0	\N	\N	f	0	\N
8034	65	403	\N	0	\N	\N	f	0	\N
8035	65	402	\N	0	\N	\N	f	0	\N
8036	65	39	\N	0	\N	\N	f	0	\N
8037	65	38	\N	0	\N	\N	f	0	\N
8038	65	37	\N	0	\N	\N	f	0	\N
8039	65	36	\N	0	\N	\N	f	0	\N
8040	65	35	\N	0	\N	\N	f	0	\N
8041	65	34	\N	0	\N	\N	f	0	\N
8042	65	33	\N	0	\N	\N	f	0	\N
8043	65	32	\N	0	\N	\N	f	0	\N
8044	65	31	\N	0	\N	\N	f	0	\N
8045	65	30	\N	0	\N	\N	f	0	\N
8046	65	29	\N	0	\N	\N	f	0	\N
8047	65	28	\N	0	\N	\N	f	0	\N
8048	65	27	\N	0	\N	\N	f	0	\N
8049	65	26	\N	0	\N	\N	f	0	\N
8050	65	25	\N	0	\N	\N	f	0	\N
8051	65	24	\N	0	\N	\N	f	0	\N
8052	65	23	\N	0	\N	\N	f	0	\N
8053	65	22	\N	0	\N	\N	f	0	\N
8054	65	21	\N	0	\N	\N	f	0	\N
8055	65	20	\N	0	\N	\N	f	0	\N
8056	65	19	\N	0	\N	\N	f	0	\N
8057	65	18	\N	0	\N	\N	f	0	\N
8058	65	17	\N	0	\N	\N	f	0	\N
8059	65	16	\N	0	\N	\N	f	0	\N
8060	65	15	\N	0	\N	\N	f	0	\N
8061	65	14	\N	0	\N	\N	f	0	\N
8062	65	13	\N	0	\N	\N	f	0	\N
8063	65	12	\N	0	\N	\N	f	0	\N
8064	65	11	\N	0	\N	\N	f	0	\N
8065	65	10	\N	0	\N	\N	f	0	\N
8066	65	9	\N	0	\N	\N	f	0	\N
8067	65	8	\N	0	\N	\N	f	0	\N
8068	65	7	\N	0	\N	\N	f	0	\N
8069	65	6	\N	0	\N	\N	f	0	\N
8070	65	5	\N	0	\N	\N	f	0	\N
8071	65	4	\N	0	\N	\N	f	0	\N
8072	65	3	\N	0	\N	\N	f	0	\N
8073	65	2	\N	0	\N	\N	f	0	\N
8074	65	1	\N	0	\N	\N	f	0	\N
8075	65	145	\N	0	\N	\N	f	0	\N
8076	65	144	\N	0	\N	\N	f	0	\N
8077	65	143	\N	0	\N	\N	f	0	\N
8078	65	142	\N	0	\N	\N	f	0	\N
8079	65	141	\N	0	\N	\N	f	0	\N
8080	65	140	\N	0	\N	\N	f	0	\N
8081	65	139	\N	0	\N	\N	f	0	\N
8082	65	138	\N	0	\N	\N	f	0	\N
8083	65	137	\N	0	\N	\N	f	0	\N
8084	65	136	\N	0	\N	\N	f	0	\N
8085	65	135	\N	0	\N	\N	f	0	\N
8086	65	134	\N	0	\N	\N	f	0	\N
8087	65	133	\N	0	\N	\N	f	0	\N
8088	65	132	\N	0	\N	\N	f	0	\N
8089	65	131	\N	0	\N	\N	f	0	\N
8090	65	130	\N	0	\N	\N	f	0	\N
8091	65	129	\N	0	\N	\N	f	0	\N
8092	65	128	\N	0	\N	\N	f	0	\N
8093	65	127	\N	0	\N	\N	f	0	\N
8094	65	126	\N	0	\N	\N	f	0	\N
8095	65	125	\N	0	\N	\N	f	0	\N
8096	65	124	\N	0	\N	\N	f	0	\N
8097	65	123	\N	0	\N	\N	f	0	\N
8098	65	122	\N	0	\N	\N	f	0	\N
8099	65	121	\N	0	\N	\N	f	0	\N
8100	65	120	\N	0	\N	\N	f	0	\N
8101	65	119	\N	0	\N	\N	f	0	\N
8102	65	118	\N	0	\N	\N	f	0	\N
8103	65	117	\N	0	\N	\N	f	0	\N
8104	65	116	\N	0	\N	\N	f	0	\N
8105	65	115	\N	0	\N	\N	f	0	\N
8106	65	114	\N	0	\N	\N	f	0	\N
8107	65	113	\N	0	\N	\N	f	0	\N
8108	65	112	\N	0	\N	\N	f	0	\N
8109	65	111	\N	0	\N	\N	f	0	\N
8110	65	110	\N	0	\N	\N	f	0	\N
8111	66	74	\N	0	\N	\N	f	0	\N
8112	66	73	\N	0	\N	\N	f	0	\N
8113	66	72	\N	0	\N	\N	f	0	\N
8114	66	71	\N	0	\N	\N	f	0	\N
8115	66	70	\N	0	\N	\N	f	0	\N
8116	66	69	\N	0	\N	\N	f	0	\N
8117	66	68	\N	0	\N	\N	f	0	\N
8118	66	67	\N	0	\N	\N	f	0	\N
8119	66	66	\N	0	\N	\N	f	0	\N
8120	66	65	\N	0	\N	\N	f	0	\N
8121	66	64	\N	0	\N	\N	f	0	\N
8122	66	63	\N	0	\N	\N	f	0	\N
8123	66	62	\N	0	\N	\N	f	0	\N
8124	66	61	\N	0	\N	\N	f	0	\N
8125	66	60	\N	0	\N	\N	f	0	\N
8126	66	59	\N	0	\N	\N	f	0	\N
8127	66	58	\N	0	\N	\N	f	0	\N
8128	66	57	\N	0	\N	\N	f	0	\N
8129	66	56	\N	0	\N	\N	f	0	\N
8130	66	55	\N	0	\N	\N	f	0	\N
8131	66	54	\N	0	\N	\N	f	0	\N
8132	66	53	\N	0	\N	\N	f	0	\N
8133	66	52	\N	0	\N	\N	f	0	\N
8134	66	51	\N	0	\N	\N	f	0	\N
8135	66	50	\N	0	\N	\N	f	0	\N
8136	66	49	\N	0	\N	\N	f	0	\N
8137	66	48	\N	0	\N	\N	f	0	\N
8138	66	47	\N	0	\N	\N	f	0	\N
8139	66	46	\N	0	\N	\N	f	0	\N
8140	66	45	\N	0	\N	\N	f	0	\N
8141	66	44	\N	0	\N	\N	f	0	\N
8142	66	43	\N	0	\N	\N	f	0	\N
8143	66	42	\N	0	\N	\N	f	0	\N
8144	66	41	\N	0	\N	\N	f	0	\N
8145	66	40	\N	0	\N	\N	f	0	\N
8146	66	323	\N	0	\N	\N	f	0	\N
8147	66	322	\N	0	\N	\N	f	0	\N
8148	66	321	\N	0	\N	\N	f	0	\N
8149	66	320	\N	0	\N	\N	f	0	\N
8150	66	319	\N	0	\N	\N	f	0	\N
8151	66	318	\N	0	\N	\N	f	0	\N
8152	66	317	\N	0	\N	\N	f	0	\N
8153	66	316	\N	0	\N	\N	f	0	\N
8154	66	315	\N	0	\N	\N	f	0	\N
8155	66	314	\N	0	\N	\N	f	0	\N
8156	66	313	\N	0	\N	\N	f	0	\N
8157	66	312	\N	0	\N	\N	f	0	\N
8158	66	311	\N	0	\N	\N	f	0	\N
8159	66	310	\N	0	\N	\N	f	0	\N
8160	66	309	\N	0	\N	\N	f	0	\N
8161	66	308	\N	0	\N	\N	f	0	\N
8162	66	307	\N	0	\N	\N	f	0	\N
8163	66	306	\N	0	\N	\N	f	0	\N
8164	66	305	\N	0	\N	\N	f	0	\N
8165	66	304	\N	0	\N	\N	f	0	\N
8166	66	303	\N	0	\N	\N	f	0	\N
8167	66	302	\N	0	\N	\N	f	0	\N
8168	66	301	\N	0	\N	\N	f	0	\N
8169	66	300	\N	0	\N	\N	f	0	\N
8170	66	299	\N	0	\N	\N	f	0	\N
8171	66	298	\N	0	\N	\N	f	0	\N
8172	66	297	\N	0	\N	\N	f	0	\N
8173	66	296	\N	0	\N	\N	f	0	\N
8174	66	295	\N	0	\N	\N	f	0	\N
8175	66	294	\N	0	\N	\N	f	0	\N
8176	66	293	\N	0	\N	\N	f	0	\N
8177	66	292	\N	0	\N	\N	f	0	\N
8178	66	291	\N	0	\N	\N	f	0	\N
8179	67	109	\N	0	\N	\N	f	0	\N
8180	67	108	\N	0	\N	\N	f	0	\N
8181	67	107	\N	0	\N	\N	f	0	\N
8182	67	106	\N	0	\N	\N	f	0	\N
8183	67	105	\N	0	\N	\N	f	0	\N
8184	67	104	\N	0	\N	\N	f	0	\N
8185	67	103	\N	0	\N	\N	f	0	\N
8186	67	102	\N	0	\N	\N	f	0	\N
8187	67	101	\N	0	\N	\N	f	0	\N
8188	67	100	\N	0	\N	\N	f	0	\N
8189	67	99	\N	0	\N	\N	f	0	\N
8190	67	98	\N	0	\N	\N	f	0	\N
8191	67	97	\N	0	\N	\N	f	0	\N
8192	67	96	\N	0	\N	\N	f	0	\N
8193	67	95	\N	0	\N	\N	f	0	\N
8194	67	94	\N	0	\N	\N	f	0	\N
8195	67	93	\N	0	\N	\N	f	0	\N
8196	67	92	\N	0	\N	\N	f	0	\N
8197	67	91	\N	0	\N	\N	f	0	\N
8198	67	90	\N	0	\N	\N	f	0	\N
8199	67	89	\N	0	\N	\N	f	0	\N
8200	67	88	\N	0	\N	\N	f	0	\N
8201	67	87	\N	0	\N	\N	f	0	\N
8202	67	86	\N	0	\N	\N	f	0	\N
8203	67	85	\N	0	\N	\N	f	0	\N
8204	67	84	\N	0	\N	\N	f	0	\N
8205	67	83	\N	0	\N	\N	f	0	\N
8206	67	82	\N	0	\N	\N	f	0	\N
8207	67	81	\N	0	\N	\N	f	0	\N
8208	67	80	\N	0	\N	\N	f	0	\N
8209	67	79	\N	0	\N	\N	f	0	\N
8210	67	78	\N	0	\N	\N	f	0	\N
8211	67	77	\N	0	\N	\N	f	0	\N
8212	67	76	\N	0	\N	\N	f	0	\N
8213	67	75	\N	0	\N	\N	f	0	\N
8214	67	218	\N	0	\N	\N	f	0	\N
8215	67	217	\N	0	\N	\N	f	0	\N
8216	67	216	\N	0	\N	\N	f	0	\N
8217	67	215	\N	0	\N	\N	f	0	\N
8218	67	214	\N	0	\N	\N	f	0	\N
8219	67	213	\N	0	\N	\N	f	0	\N
8220	67	212	\N	0	\N	\N	f	0	\N
8221	67	211	\N	0	\N	\N	f	0	\N
8222	67	210	\N	0	\N	\N	f	0	\N
8223	67	209	\N	0	\N	\N	f	0	\N
8224	67	208	\N	0	\N	\N	f	0	\N
8225	67	207	\N	0	\N	\N	f	0	\N
8226	67	206	\N	0	\N	\N	f	0	\N
8227	67	205	\N	0	\N	\N	f	0	\N
8228	67	204	\N	0	\N	\N	f	0	\N
8229	67	203	\N	0	\N	\N	f	0	\N
8230	67	202	\N	0	\N	\N	f	0	\N
8231	67	201	\N	0	\N	\N	f	0	\N
8232	67	200	\N	0	\N	\N	f	0	\N
8233	67	199	\N	0	\N	\N	f	0	\N
8234	67	198	\N	0	\N	\N	f	0	\N
8235	67	197	\N	0	\N	\N	f	0	\N
8236	67	196	\N	0	\N	\N	f	0	\N
8237	67	195	\N	0	\N	\N	f	0	\N
8238	67	194	\N	0	\N	\N	f	0	\N
8239	67	193	\N	0	\N	\N	f	0	\N
8240	67	192	\N	0	\N	\N	f	0	\N
8241	67	191	\N	0	\N	\N	f	0	\N
8242	67	190	\N	0	\N	\N	f	0	\N
8243	67	189	\N	0	\N	\N	f	0	\N
8244	67	188	\N	0	\N	\N	f	0	\N
8245	67	187	\N	0	\N	\N	f	0	\N
8246	67	186	\N	0	\N	\N	f	0	\N
8247	67	185	\N	0	\N	\N	f	0	\N
8248	67	184	\N	0	\N	\N	f	0	\N
8249	67	183	\N	0	\N	\N	f	0	\N
8250	67	182	\N	0	\N	\N	f	0	\N
8251	67	181	\N	0	\N	\N	f	0	\N
8252	67	180	\N	0	\N	\N	f	0	\N
8253	67	179	\N	0	\N	\N	f	0	\N
8254	67	178	\N	0	\N	\N	f	0	\N
8255	67	177	\N	0	\N	\N	f	0	\N
8256	67	176	\N	0	\N	\N	f	0	\N
8257	67	175	\N	0	\N	\N	f	0	\N
8258	67	174	\N	0	\N	\N	f	0	\N
8259	67	173	\N	0	\N	\N	f	0	\N
8260	67	172	\N	0	\N	\N	f	0	\N
8261	67	171	\N	0	\N	\N	f	0	\N
8262	67	170	\N	0	\N	\N	f	0	\N
8263	67	169	\N	0	\N	\N	f	0	\N
8264	67	168	\N	0	\N	\N	f	0	\N
8265	67	167	\N	0	\N	\N	f	0	\N
8266	67	166	\N	0	\N	\N	f	0	\N
8267	67	165	\N	0	\N	\N	f	0	\N
8268	67	164	\N	0	\N	\N	f	0	\N
8269	67	163	\N	0	\N	\N	f	0	\N
8270	67	162	\N	0	\N	\N	f	0	\N
8271	67	161	\N	0	\N	\N	f	0	\N
8272	67	160	\N	0	\N	\N	f	0	\N
8273	67	159	\N	0	\N	\N	f	0	\N
8274	67	158	\N	0	\N	\N	f	0	\N
8275	67	157	\N	0	\N	\N	f	0	\N
8276	67	156	\N	0	\N	\N	f	0	\N
8277	67	155	\N	0	\N	\N	f	0	\N
8278	67	154	\N	0	\N	\N	f	0	\N
8279	67	153	\N	0	\N	\N	f	0	\N
8280	67	152	\N	0	\N	\N	f	0	\N
8281	67	151	\N	0	\N	\N	f	0	\N
8282	67	150	\N	0	\N	\N	f	0	\N
8283	67	149	\N	0	\N	\N	f	0	\N
8284	67	148	\N	0	\N	\N	f	0	\N
8285	67	147	\N	0	\N	\N	f	0	\N
8286	67	146	\N	0	\N	\N	f	0	\N
8287	67	290	\N	0	\N	\N	f	0	\N
8288	67	289	\N	0	\N	\N	f	0	\N
8289	67	288	\N	0	\N	\N	f	0	\N
8290	67	287	\N	0	\N	\N	f	0	\N
8291	67	286	\N	0	\N	\N	f	0	\N
8292	67	285	\N	0	\N	\N	f	0	\N
8293	67	284	\N	0	\N	\N	f	0	\N
8294	67	283	\N	0	\N	\N	f	0	\N
8295	67	282	\N	0	\N	\N	f	0	\N
8296	67	281	\N	0	\N	\N	f	0	\N
8297	67	280	\N	0	\N	\N	f	0	\N
8298	67	279	\N	0	\N	\N	f	0	\N
8299	67	278	\N	0	\N	\N	f	0	\N
8300	67	277	\N	0	\N	\N	f	0	\N
8301	67	276	\N	0	\N	\N	f	0	\N
8302	67	275	\N	0	\N	\N	f	0	\N
8303	67	274	\N	0	\N	\N	f	0	\N
8304	67	273	\N	0	\N	\N	f	0	\N
8305	67	272	\N	0	\N	\N	f	0	\N
8306	67	271	\N	0	\N	\N	f	0	\N
8307	67	270	\N	0	\N	\N	f	0	\N
8308	67	269	\N	0	\N	\N	f	0	\N
8309	67	268	\N	0	\N	\N	f	0	\N
8310	67	267	\N	0	\N	\N	f	0	\N
8311	67	266	\N	0	\N	\N	f	0	\N
8312	67	265	\N	0	\N	\N	f	0	\N
8313	67	264	\N	0	\N	\N	f	0	\N
8314	67	263	\N	0	\N	\N	f	0	\N
8315	67	262	\N	0	\N	\N	f	0	\N
8316	67	261	\N	0	\N	\N	f	0	\N
8317	67	260	\N	0	\N	\N	f	0	\N
8318	67	259	\N	0	\N	\N	f	0	\N
8319	67	258	\N	0	\N	\N	f	0	\N
8320	67	257	\N	0	\N	\N	f	0	\N
8321	67	256	\N	0	\N	\N	f	0	\N
8322	67	255	\N	0	\N	\N	f	0	\N
8323	67	254	\N	0	\N	\N	f	0	\N
8324	67	253	\N	0	\N	\N	f	0	\N
8325	67	252	\N	0	\N	\N	f	0	\N
8326	67	251	\N	0	\N	\N	f	0	\N
8327	67	250	\N	0	\N	\N	f	0	\N
8328	67	249	\N	0	\N	\N	f	0	\N
8329	67	248	\N	0	\N	\N	f	0	\N
8330	67	247	\N	0	\N	\N	f	0	\N
8331	67	246	\N	0	\N	\N	f	0	\N
8332	67	245	\N	0	\N	\N	f	0	\N
8333	67	244	\N	0	\N	\N	f	0	\N
8334	67	243	\N	0	\N	\N	f	0	\N
8335	67	242	\N	0	\N	\N	f	0	\N
8336	67	241	\N	0	\N	\N	f	0	\N
8337	67	240	\N	0	\N	\N	f	0	\N
8338	67	239	\N	0	\N	\N	f	0	\N
8339	67	238	\N	0	\N	\N	f	0	\N
8340	67	237	\N	0	\N	\N	f	0	\N
8341	67	236	\N	0	\N	\N	f	0	\N
8342	67	235	\N	0	\N	\N	f	0	\N
8343	67	234	\N	0	\N	\N	f	0	\N
8344	67	233	\N	0	\N	\N	f	0	\N
8345	67	232	\N	0	\N	\N	f	0	\N
8346	67	231	\N	0	\N	\N	f	0	\N
8347	67	230	\N	0	\N	\N	f	0	\N
8348	67	229	\N	0	\N	\N	f	0	\N
8349	67	228	\N	0	\N	\N	f	0	\N
8350	67	227	\N	0	\N	\N	f	0	\N
8351	67	226	\N	0	\N	\N	f	0	\N
8352	67	225	\N	0	\N	\N	f	0	\N
8353	67	224	\N	0	\N	\N	f	0	\N
8354	67	223	\N	0	\N	\N	f	0	\N
8355	67	222	\N	0	\N	\N	f	0	\N
8356	67	221	\N	0	\N	\N	f	0	\N
8357	67	220	\N	0	\N	\N	f	0	\N
8358	67	219	\N	0	\N	\N	f	0	\N
8359	67	74	\N	0	\N	\N	f	0	\N
8360	67	73	\N	0	\N	\N	f	0	\N
8361	67	72	\N	0	\N	\N	f	0	\N
8362	67	71	\N	0	\N	\N	f	0	\N
8363	67	70	\N	0	\N	\N	f	0	\N
8364	67	69	\N	0	\N	\N	f	0	\N
8365	67	68	\N	0	\N	\N	f	0	\N
8366	67	67	\N	0	\N	\N	f	0	\N
8367	67	66	\N	0	\N	\N	f	0	\N
8368	67	65	\N	0	\N	\N	f	0	\N
8369	67	64	\N	0	\N	\N	f	0	\N
8370	67	63	\N	0	\N	\N	f	0	\N
8371	67	62	\N	0	\N	\N	f	0	\N
8372	67	61	\N	0	\N	\N	f	0	\N
8373	67	60	\N	0	\N	\N	f	0	\N
8374	67	59	\N	0	\N	\N	f	0	\N
8375	67	58	\N	0	\N	\N	f	0	\N
8376	67	57	\N	0	\N	\N	f	0	\N
8377	67	56	\N	0	\N	\N	f	0	\N
8378	67	55	\N	0	\N	\N	f	0	\N
8379	67	54	\N	0	\N	\N	f	0	\N
8380	67	53	\N	0	\N	\N	f	0	\N
8381	67	52	\N	0	\N	\N	f	0	\N
8382	67	51	\N	0	\N	\N	f	0	\N
8383	67	50	\N	0	\N	\N	f	0	\N
8384	67	49	\N	0	\N	\N	f	0	\N
8385	67	48	\N	0	\N	\N	f	0	\N
8386	67	47	\N	0	\N	\N	f	0	\N
8387	67	46	\N	0	\N	\N	f	0	\N
8388	67	45	\N	0	\N	\N	f	0	\N
8389	67	44	\N	0	\N	\N	f	0	\N
8390	67	43	\N	0	\N	\N	f	0	\N
8391	67	42	\N	0	\N	\N	f	0	\N
8392	67	41	\N	0	\N	\N	f	0	\N
8393	67	40	\N	0	\N	\N	f	0	\N
8394	67	145	\N	0	\N	\N	f	0	\N
8395	67	144	\N	0	\N	\N	f	0	\N
8396	67	143	\N	0	\N	\N	f	0	\N
8397	67	142	\N	0	\N	\N	f	0	\N
8398	67	141	\N	0	\N	\N	f	0	\N
8399	67	140	\N	0	\N	\N	f	0	\N
8400	67	139	\N	0	\N	\N	f	0	\N
8401	67	138	\N	0	\N	\N	f	0	\N
8402	67	137	\N	0	\N	\N	f	0	\N
8403	67	136	\N	0	\N	\N	f	0	\N
8404	67	135	\N	0	\N	\N	f	0	\N
8405	67	134	\N	0	\N	\N	f	0	\N
8406	67	133	\N	0	\N	\N	f	0	\N
8407	67	132	\N	0	\N	\N	f	0	\N
8408	67	131	\N	0	\N	\N	f	0	\N
8409	67	130	\N	0	\N	\N	f	0	\N
8410	67	129	\N	0	\N	\N	f	0	\N
8411	67	128	\N	0	\N	\N	f	0	\N
8412	67	127	\N	0	\N	\N	f	0	\N
8413	67	126	\N	0	\N	\N	f	0	\N
8414	67	125	\N	0	\N	\N	f	0	\N
8415	67	124	\N	0	\N	\N	f	0	\N
8416	67	123	\N	0	\N	\N	f	0	\N
8417	67	122	\N	0	\N	\N	f	0	\N
8418	67	121	\N	0	\N	\N	f	0	\N
8419	67	120	\N	0	\N	\N	f	0	\N
8420	67	119	\N	0	\N	\N	f	0	\N
8421	67	118	\N	0	\N	\N	f	0	\N
8422	67	117	\N	0	\N	\N	f	0	\N
8423	67	116	\N	0	\N	\N	f	0	\N
8424	67	115	\N	0	\N	\N	f	0	\N
8425	67	114	\N	0	\N	\N	f	0	\N
8426	67	113	\N	0	\N	\N	f	0	\N
8427	67	112	\N	0	\N	\N	f	0	\N
8428	67	111	\N	0	\N	\N	f	0	\N
8429	67	110	\N	0	\N	\N	f	0	\N
8430	67	432	\N	0	\N	\N	f	0	\N
8431	67	431	\N	0	\N	\N	f	0	\N
8432	67	430	\N	0	\N	\N	f	0	\N
8433	67	429	\N	0	\N	\N	f	0	\N
8434	67	428	\N	0	\N	\N	f	0	\N
8435	67	427	\N	0	\N	\N	f	0	\N
8436	67	426	\N	0	\N	\N	f	0	\N
8437	67	425	\N	0	\N	\N	f	0	\N
8438	67	424	\N	0	\N	\N	f	0	\N
8439	67	423	\N	0	\N	\N	f	0	\N
8440	67	422	\N	0	\N	\N	f	0	\N
8441	67	421	\N	0	\N	\N	f	0	\N
8442	67	420	\N	0	\N	\N	f	0	\N
8443	67	419	\N	0	\N	\N	f	0	\N
8444	67	418	\N	0	\N	\N	f	0	\N
8445	67	417	\N	0	\N	\N	f	0	\N
8446	67	416	\N	0	\N	\N	f	0	\N
8447	67	415	\N	0	\N	\N	f	0	\N
8448	67	414	\N	0	\N	\N	f	0	\N
8449	67	413	\N	0	\N	\N	f	0	\N
8450	67	412	\N	0	\N	\N	f	0	\N
8451	67	411	\N	0	\N	\N	f	0	\N
8452	67	410	\N	0	\N	\N	f	0	\N
8453	67	409	\N	0	\N	\N	f	0	\N
8454	67	408	\N	0	\N	\N	f	0	\N
8455	67	407	\N	0	\N	\N	f	0	\N
8456	67	406	\N	0	\N	\N	f	0	\N
8457	67	405	\N	0	\N	\N	f	0	\N
8458	67	404	\N	0	\N	\N	f	0	\N
8459	67	403	\N	0	\N	\N	f	0	\N
8460	67	402	\N	0	\N	\N	f	0	\N
8461	67	323	\N	0	\N	\N	f	0	\N
8462	67	322	\N	0	\N	\N	f	0	\N
8463	67	321	\N	0	\N	\N	f	0	\N
8464	67	320	\N	0	\N	\N	f	0	\N
8465	67	319	\N	0	\N	\N	f	0	\N
8466	67	318	\N	0	\N	\N	f	0	\N
8467	67	317	\N	0	\N	\N	f	0	\N
8468	67	316	\N	0	\N	\N	f	0	\N
8469	67	315	\N	0	\N	\N	f	0	\N
8470	67	314	\N	0	\N	\N	f	0	\N
8471	67	313	\N	0	\N	\N	f	0	\N
8472	67	312	\N	0	\N	\N	f	0	\N
8473	67	311	\N	0	\N	\N	f	0	\N
8474	67	310	\N	0	\N	\N	f	0	\N
8475	67	309	\N	0	\N	\N	f	0	\N
8476	67	308	\N	0	\N	\N	f	0	\N
8477	67	307	\N	0	\N	\N	f	0	\N
8478	67	306	\N	0	\N	\N	f	0	\N
8479	67	305	\N	0	\N	\N	f	0	\N
8480	67	304	\N	0	\N	\N	f	0	\N
8481	67	303	\N	0	\N	\N	f	0	\N
8482	67	302	\N	0	\N	\N	f	0	\N
8483	67	301	\N	0	\N	\N	f	0	\N
8484	67	300	\N	0	\N	\N	f	0	\N
8485	67	299	\N	0	\N	\N	f	0	\N
8486	67	298	\N	0	\N	\N	f	0	\N
8487	67	297	\N	0	\N	\N	f	0	\N
8488	67	296	\N	0	\N	\N	f	0	\N
8489	67	295	\N	0	\N	\N	f	0	\N
8490	67	294	\N	0	\N	\N	f	0	\N
8491	67	293	\N	0	\N	\N	f	0	\N
8492	67	292	\N	0	\N	\N	f	0	\N
8493	67	291	\N	0	\N	\N	f	0	\N
8494	67	360	\N	0	\N	\N	f	0	\N
8495	67	359	\N	0	\N	\N	f	0	\N
8496	67	358	\N	0	\N	\N	f	0	\N
8497	67	357	\N	0	\N	\N	f	0	\N
8498	67	356	\N	0	\N	\N	f	0	\N
8499	67	355	\N	0	\N	\N	f	0	\N
8500	67	354	\N	0	\N	\N	f	0	\N
8501	67	353	\N	0	\N	\N	f	0	\N
8502	67	352	\N	0	\N	\N	f	0	\N
8503	67	351	\N	0	\N	\N	f	0	\N
8504	67	350	\N	0	\N	\N	f	0	\N
8505	67	349	\N	0	\N	\N	f	0	\N
8506	67	348	\N	0	\N	\N	f	0	\N
8507	67	347	\N	0	\N	\N	f	0	\N
8508	67	346	\N	0	\N	\N	f	0	\N
8509	67	345	\N	0	\N	\N	f	0	\N
8510	67	344	\N	0	\N	\N	f	0	\N
8511	67	343	\N	0	\N	\N	f	0	\N
8512	67	342	\N	0	\N	\N	f	0	\N
8513	67	341	\N	0	\N	\N	f	0	\N
8514	67	340	\N	0	\N	\N	f	0	\N
8515	67	339	\N	0	\N	\N	f	0	\N
8516	67	338	\N	0	\N	\N	f	0	\N
8517	67	337	\N	0	\N	\N	f	0	\N
8518	67	336	\N	0	\N	\N	f	0	\N
8519	67	335	\N	0	\N	\N	f	0	\N
8520	67	334	\N	0	\N	\N	f	0	\N
8521	67	333	\N	0	\N	\N	f	0	\N
8522	67	332	\N	0	\N	\N	f	0	\N
8523	67	331	\N	0	\N	\N	f	0	\N
8524	67	330	\N	0	\N	\N	f	0	\N
8525	67	329	\N	0	\N	\N	f	0	\N
8526	67	328	\N	0	\N	\N	f	0	\N
8527	67	327	\N	0	\N	\N	f	0	\N
8528	67	326	\N	0	\N	\N	f	0	\N
8529	67	325	\N	0	\N	\N	f	0	\N
8530	67	324	\N	0	\N	\N	f	0	\N
8531	68	39	\N	0	\N	\N	f	0	\N
8532	68	38	\N	0	\N	\N	f	0	\N
8533	68	37	\N	0	\N	\N	f	0	\N
8534	68	36	\N	0	\N	\N	f	0	\N
8535	68	35	\N	0	\N	\N	f	0	\N
8536	68	34	\N	0	\N	\N	f	0	\N
8537	68	33	\N	0	\N	\N	f	0	\N
8538	68	32	\N	0	\N	\N	f	0	\N
8539	68	31	\N	0	\N	\N	f	0	\N
8540	68	30	\N	0	\N	\N	f	0	\N
8541	68	29	\N	0	\N	\N	f	0	\N
8542	68	28	\N	0	\N	\N	f	0	\N
8543	68	27	\N	0	\N	\N	f	0	\N
8544	68	26	\N	0	\N	\N	f	0	\N
8545	68	25	\N	0	\N	\N	f	0	\N
8546	68	24	\N	0	\N	\N	f	0	\N
8547	68	23	\N	0	\N	\N	f	0	\N
8548	68	22	\N	0	\N	\N	f	0	\N
8549	68	21	\N	0	\N	\N	f	0	\N
8550	68	20	\N	0	\N	\N	f	0	\N
8551	68	19	\N	0	\N	\N	f	0	\N
8552	68	18	\N	0	\N	\N	f	0	\N
8553	68	17	\N	0	\N	\N	f	0	\N
8554	68	16	\N	0	\N	\N	f	0	\N
8555	68	15	\N	0	\N	\N	f	0	\N
8556	68	14	\N	0	\N	\N	f	0	\N
8557	68	13	\N	0	\N	\N	f	0	\N
8558	68	12	\N	0	\N	\N	f	0	\N
8559	68	11	\N	0	\N	\N	f	0	\N
8560	68	10	\N	0	\N	\N	f	0	\N
8561	68	9	\N	0	\N	\N	f	0	\N
8562	68	8	\N	0	\N	\N	f	0	\N
8563	68	7	\N	0	\N	\N	f	0	\N
8564	68	6	\N	0	\N	\N	f	0	\N
8565	68	5	\N	0	\N	\N	f	0	\N
8566	68	4	\N	0	\N	\N	f	0	\N
8567	68	3	\N	0	\N	\N	f	0	\N
8568	68	2	\N	0	\N	\N	f	0	\N
8569	68	1	\N	0	\N	\N	f	0	\N
8570	68	432	\N	0	\N	\N	f	0	\N
8571	68	431	\N	0	\N	\N	f	0	\N
8572	68	430	\N	0	\N	\N	f	0	\N
8573	68	429	\N	0	\N	\N	f	0	\N
8574	68	428	\N	0	\N	\N	f	0	\N
8575	68	427	\N	0	\N	\N	f	0	\N
8576	68	426	\N	0	\N	\N	f	0	\N
8577	68	425	\N	0	\N	\N	f	0	\N
8578	68	424	\N	0	\N	\N	f	0	\N
8579	68	423	\N	0	\N	\N	f	0	\N
8580	68	422	\N	0	\N	\N	f	0	\N
8581	68	421	\N	0	\N	\N	f	0	\N
8582	68	420	\N	0	\N	\N	f	0	\N
8583	68	419	\N	0	\N	\N	f	0	\N
8584	68	418	\N	0	\N	\N	f	0	\N
8585	68	417	\N	0	\N	\N	f	0	\N
8586	68	416	\N	0	\N	\N	f	0	\N
8587	68	415	\N	0	\N	\N	f	0	\N
8588	68	414	\N	0	\N	\N	f	0	\N
8589	68	413	\N	0	\N	\N	f	0	\N
8590	68	412	\N	0	\N	\N	f	0	\N
8591	68	411	\N	0	\N	\N	f	0	\N
8592	68	410	\N	0	\N	\N	f	0	\N
8593	68	409	\N	0	\N	\N	f	0	\N
8594	68	408	\N	0	\N	\N	f	0	\N
8595	68	407	\N	0	\N	\N	f	0	\N
8596	68	406	\N	0	\N	\N	f	0	\N
8597	68	405	\N	0	\N	\N	f	0	\N
8598	68	404	\N	0	\N	\N	f	0	\N
8599	68	403	\N	0	\N	\N	f	0	\N
8600	68	402	\N	0	\N	\N	f	0	\N
8601	68	290	\N	0	\N	\N	f	0	\N
8602	68	289	\N	0	\N	\N	f	0	\N
8603	68	288	\N	0	\N	\N	f	0	\N
8604	68	287	\N	0	\N	\N	f	0	\N
8605	68	286	\N	0	\N	\N	f	0	\N
8606	68	285	\N	0	\N	\N	f	0	\N
8607	68	284	\N	0	\N	\N	f	0	\N
8608	68	283	\N	0	\N	\N	f	0	\N
8609	68	282	\N	0	\N	\N	f	0	\N
8610	68	281	\N	0	\N	\N	f	0	\N
8611	68	280	\N	0	\N	\N	f	0	\N
8612	68	279	\N	0	\N	\N	f	0	\N
8613	68	278	\N	0	\N	\N	f	0	\N
8614	68	277	\N	0	\N	\N	f	0	\N
8615	68	276	\N	0	\N	\N	f	0	\N
8616	68	275	\N	0	\N	\N	f	0	\N
8617	68	274	\N	0	\N	\N	f	0	\N
8618	68	273	\N	0	\N	\N	f	0	\N
8619	68	272	\N	0	\N	\N	f	0	\N
8620	68	271	\N	0	\N	\N	f	0	\N
8621	68	270	\N	0	\N	\N	f	0	\N
8622	68	269	\N	0	\N	\N	f	0	\N
8623	68	268	\N	0	\N	\N	f	0	\N
8624	68	267	\N	0	\N	\N	f	0	\N
8625	68	266	\N	0	\N	\N	f	0	\N
8626	68	265	\N	0	\N	\N	f	0	\N
8627	68	264	\N	0	\N	\N	f	0	\N
8628	68	263	\N	0	\N	\N	f	0	\N
8629	68	262	\N	0	\N	\N	f	0	\N
8630	68	261	\N	0	\N	\N	f	0	\N
8631	68	260	\N	0	\N	\N	f	0	\N
8632	68	259	\N	0	\N	\N	f	0	\N
8633	68	258	\N	0	\N	\N	f	0	\N
8634	68	257	\N	0	\N	\N	f	0	\N
8635	68	256	\N	0	\N	\N	f	0	\N
8636	68	255	\N	0	\N	\N	f	0	\N
8637	68	323	\N	0	\N	\N	f	0	\N
8638	68	322	\N	0	\N	\N	f	0	\N
8639	68	321	\N	0	\N	\N	f	0	\N
8640	68	320	\N	0	\N	\N	f	0	\N
8641	68	319	\N	0	\N	\N	f	0	\N
8642	68	318	\N	0	\N	\N	f	0	\N
8643	68	317	\N	0	\N	\N	f	0	\N
8644	68	316	\N	0	\N	\N	f	0	\N
8645	68	315	\N	0	\N	\N	f	0	\N
8646	68	314	\N	0	\N	\N	f	0	\N
8647	68	313	\N	0	\N	\N	f	0	\N
8648	68	312	\N	0	\N	\N	f	0	\N
8649	68	311	\N	0	\N	\N	f	0	\N
8650	68	310	\N	0	\N	\N	f	0	\N
8651	68	309	\N	0	\N	\N	f	0	\N
8652	68	308	\N	0	\N	\N	f	0	\N
8653	68	307	\N	0	\N	\N	f	0	\N
8654	68	306	\N	0	\N	\N	f	0	\N
8655	68	305	\N	0	\N	\N	f	0	\N
8656	68	304	\N	0	\N	\N	f	0	\N
8657	68	303	\N	0	\N	\N	f	0	\N
8658	68	302	\N	0	\N	\N	f	0	\N
8659	68	301	\N	0	\N	\N	f	0	\N
8660	68	300	\N	0	\N	\N	f	0	\N
8661	68	299	\N	0	\N	\N	f	0	\N
8662	68	298	\N	0	\N	\N	f	0	\N
8663	68	297	\N	0	\N	\N	f	0	\N
8664	68	296	\N	0	\N	\N	f	0	\N
8665	68	295	\N	0	\N	\N	f	0	\N
8666	68	294	\N	0	\N	\N	f	0	\N
8667	68	293	\N	0	\N	\N	f	0	\N
8668	68	292	\N	0	\N	\N	f	0	\N
8669	68	291	\N	0	\N	\N	f	0	\N
8670	68	401	\N	0	\N	\N	f	0	\N
8671	68	400	\N	0	\N	\N	f	0	\N
8672	68	399	\N	0	\N	\N	f	0	\N
8673	68	398	\N	0	\N	\N	f	0	\N
8674	68	397	\N	0	\N	\N	f	0	\N
8675	68	396	\N	0	\N	\N	f	0	\N
8676	68	395	\N	0	\N	\N	f	0	\N
8677	68	394	\N	0	\N	\N	f	0	\N
8678	68	393	\N	0	\N	\N	f	0	\N
8679	68	392	\N	0	\N	\N	f	0	\N
8680	68	391	\N	0	\N	\N	f	0	\N
8681	68	390	\N	0	\N	\N	f	0	\N
8682	68	389	\N	0	\N	\N	f	0	\N
8683	68	388	\N	0	\N	\N	f	0	\N
8684	68	387	\N	0	\N	\N	f	0	\N
8685	68	386	\N	0	\N	\N	f	0	\N
8686	68	385	\N	0	\N	\N	f	0	\N
8687	68	384	\N	0	\N	\N	f	0	\N
8688	68	383	\N	0	\N	\N	f	0	\N
8689	68	382	\N	0	\N	\N	f	0	\N
8690	68	381	\N	0	\N	\N	f	0	\N
8691	68	380	\N	0	\N	\N	f	0	\N
8692	68	379	\N	0	\N	\N	f	0	\N
8693	68	378	\N	0	\N	\N	f	0	\N
8694	68	377	\N	0	\N	\N	f	0	\N
8695	68	376	\N	0	\N	\N	f	0	\N
8696	68	375	\N	0	\N	\N	f	0	\N
8697	68	374	\N	0	\N	\N	f	0	\N
8698	68	373	\N	0	\N	\N	f	0	\N
8699	68	372	\N	0	\N	\N	f	0	\N
8700	68	371	\N	0	\N	\N	f	0	\N
8701	68	370	\N	0	\N	\N	f	0	\N
8702	68	369	\N	0	\N	\N	f	0	\N
8703	68	368	\N	0	\N	\N	f	0	\N
8704	68	367	\N	0	\N	\N	f	0	\N
8705	68	366	\N	0	\N	\N	f	0	\N
8706	68	365	\N	0	\N	\N	f	0	\N
8707	68	364	\N	0	\N	\N	f	0	\N
8708	68	363	\N	0	\N	\N	f	0	\N
8709	68	362	\N	0	\N	\N	f	0	\N
8710	68	361	\N	0	\N	\N	f	0	\N
8711	68	145	\N	0	\N	\N	f	0	\N
8712	68	144	\N	0	\N	\N	f	0	\N
8713	68	143	\N	0	\N	\N	f	0	\N
8714	68	142	\N	0	\N	\N	f	0	\N
8715	68	141	\N	0	\N	\N	f	0	\N
8716	68	140	\N	0	\N	\N	f	0	\N
8717	68	139	\N	0	\N	\N	f	0	\N
8718	68	138	\N	0	\N	\N	f	0	\N
8719	68	137	\N	0	\N	\N	f	0	\N
8720	68	136	\N	0	\N	\N	f	0	\N
8721	68	135	\N	0	\N	\N	f	0	\N
8722	68	134	\N	0	\N	\N	f	0	\N
8723	68	133	\N	0	\N	\N	f	0	\N
8724	68	132	\N	0	\N	\N	f	0	\N
8725	68	131	\N	0	\N	\N	f	0	\N
8726	68	130	\N	0	\N	\N	f	0	\N
8727	68	129	\N	0	\N	\N	f	0	\N
8728	68	128	\N	0	\N	\N	f	0	\N
8729	68	127	\N	0	\N	\N	f	0	\N
8730	68	126	\N	0	\N	\N	f	0	\N
8731	68	125	\N	0	\N	\N	f	0	\N
8732	68	124	\N	0	\N	\N	f	0	\N
8733	68	123	\N	0	\N	\N	f	0	\N
8734	68	122	\N	0	\N	\N	f	0	\N
8735	68	121	\N	0	\N	\N	f	0	\N
8736	68	120	\N	0	\N	\N	f	0	\N
8737	68	119	\N	0	\N	\N	f	0	\N
8738	68	118	\N	0	\N	\N	f	0	\N
8739	68	117	\N	0	\N	\N	f	0	\N
8740	68	116	\N	0	\N	\N	f	0	\N
8741	68	115	\N	0	\N	\N	f	0	\N
8742	68	114	\N	0	\N	\N	f	0	\N
8743	68	113	\N	0	\N	\N	f	0	\N
8744	68	112	\N	0	\N	\N	f	0	\N
8745	68	111	\N	0	\N	\N	f	0	\N
8746	68	110	\N	0	\N	\N	f	0	\N
8747	68	180	\N	0	\N	\N	f	0	\N
8748	68	179	\N	0	\N	\N	f	0	\N
8749	68	178	\N	0	\N	\N	f	0	\N
8750	68	177	\N	0	\N	\N	f	0	\N
8751	68	176	\N	0	\N	\N	f	0	\N
8752	68	175	\N	0	\N	\N	f	0	\N
8753	68	174	\N	0	\N	\N	f	0	\N
8754	68	173	\N	0	\N	\N	f	0	\N
8755	68	172	\N	0	\N	\N	f	0	\N
8756	68	171	\N	0	\N	\N	f	0	\N
8757	68	170	\N	0	\N	\N	f	0	\N
8758	68	169	\N	0	\N	\N	f	0	\N
8759	68	168	\N	0	\N	\N	f	0	\N
8760	68	167	\N	0	\N	\N	f	0	\N
8761	68	166	\N	0	\N	\N	f	0	\N
8762	68	165	\N	0	\N	\N	f	0	\N
8763	68	164	\N	0	\N	\N	f	0	\N
8764	68	163	\N	0	\N	\N	f	0	\N
8765	68	162	\N	0	\N	\N	f	0	\N
8766	68	161	\N	0	\N	\N	f	0	\N
8767	68	160	\N	0	\N	\N	f	0	\N
8768	68	159	\N	0	\N	\N	f	0	\N
8769	68	158	\N	0	\N	\N	f	0	\N
8770	68	157	\N	0	\N	\N	f	0	\N
8771	68	156	\N	0	\N	\N	f	0	\N
8772	68	155	\N	0	\N	\N	f	0	\N
8773	68	154	\N	0	\N	\N	f	0	\N
8774	68	153	\N	0	\N	\N	f	0	\N
8775	68	152	\N	0	\N	\N	f	0	\N
8776	68	151	\N	0	\N	\N	f	0	\N
8777	68	150	\N	0	\N	\N	f	0	\N
8778	68	149	\N	0	\N	\N	f	0	\N
8779	68	148	\N	0	\N	\N	f	0	\N
8780	68	147	\N	0	\N	\N	f	0	\N
8781	68	146	\N	0	\N	\N	f	0	\N
8782	68	218	\N	0	\N	\N	f	0	\N
8783	68	217	\N	0	\N	\N	f	0	\N
8784	68	216	\N	0	\N	\N	f	0	\N
8785	68	215	\N	0	\N	\N	f	0	\N
8786	68	214	\N	0	\N	\N	f	0	\N
8787	68	213	\N	0	\N	\N	f	0	\N
8788	68	212	\N	0	\N	\N	f	0	\N
8789	68	211	\N	0	\N	\N	f	0	\N
8790	68	210	\N	0	\N	\N	f	0	\N
8791	68	209	\N	0	\N	\N	f	0	\N
8792	68	208	\N	0	\N	\N	f	0	\N
8793	68	207	\N	0	\N	\N	f	0	\N
8794	68	206	\N	0	\N	\N	f	0	\N
8795	68	205	\N	0	\N	\N	f	0	\N
8796	68	204	\N	0	\N	\N	f	0	\N
8797	68	203	\N	0	\N	\N	f	0	\N
8798	68	202	\N	0	\N	\N	f	0	\N
8799	68	201	\N	0	\N	\N	f	0	\N
8800	68	200	\N	0	\N	\N	f	0	\N
8801	68	199	\N	0	\N	\N	f	0	\N
8802	68	198	\N	0	\N	\N	f	0	\N
8803	68	197	\N	0	\N	\N	f	0	\N
8804	68	196	\N	0	\N	\N	f	0	\N
8805	68	195	\N	0	\N	\N	f	0	\N
8806	68	194	\N	0	\N	\N	f	0	\N
8807	68	193	\N	0	\N	\N	f	0	\N
8808	68	192	\N	0	\N	\N	f	0	\N
8809	68	191	\N	0	\N	\N	f	0	\N
8810	68	190	\N	0	\N	\N	f	0	\N
8811	68	189	\N	0	\N	\N	f	0	\N
8812	68	188	\N	0	\N	\N	f	0	\N
8813	68	187	\N	0	\N	\N	f	0	\N
8814	68	186	\N	0	\N	\N	f	0	\N
8815	68	185	\N	0	\N	\N	f	0	\N
8816	68	184	\N	0	\N	\N	f	0	\N
8817	68	183	\N	0	\N	\N	f	0	\N
8818	68	182	\N	0	\N	\N	f	0	\N
8819	68	181	\N	0	\N	\N	f	0	\N
8820	68	74	\N	0	\N	\N	f	0	\N
8821	68	73	\N	0	\N	\N	f	0	\N
8822	68	72	\N	0	\N	\N	f	0	\N
8823	68	71	\N	0	\N	\N	f	0	\N
8824	68	70	\N	0	\N	\N	f	0	\N
8825	68	69	\N	0	\N	\N	f	0	\N
8826	68	68	\N	0	\N	\N	f	0	\N
8827	68	67	\N	0	\N	\N	f	0	\N
8828	68	66	\N	0	\N	\N	f	0	\N
8829	68	65	\N	0	\N	\N	f	0	\N
8830	68	64	\N	0	\N	\N	f	0	\N
8831	68	63	\N	0	\N	\N	f	0	\N
8832	68	62	\N	0	\N	\N	f	0	\N
8833	68	61	\N	0	\N	\N	f	0	\N
8834	68	60	\N	0	\N	\N	f	0	\N
8835	68	59	\N	0	\N	\N	f	0	\N
8836	68	58	\N	0	\N	\N	f	0	\N
8837	68	57	\N	0	\N	\N	f	0	\N
8838	68	56	\N	0	\N	\N	f	0	\N
8839	68	55	\N	0	\N	\N	f	0	\N
8840	68	54	\N	0	\N	\N	f	0	\N
8841	68	53	\N	0	\N	\N	f	0	\N
8842	68	52	\N	0	\N	\N	f	0	\N
8843	68	51	\N	0	\N	\N	f	0	\N
8844	68	50	\N	0	\N	\N	f	0	\N
8845	68	49	\N	0	\N	\N	f	0	\N
8846	68	48	\N	0	\N	\N	f	0	\N
8847	68	47	\N	0	\N	\N	f	0	\N
8848	68	46	\N	0	\N	\N	f	0	\N
8849	68	45	\N	0	\N	\N	f	0	\N
8850	68	44	\N	0	\N	\N	f	0	\N
8851	68	43	\N	0	\N	\N	f	0	\N
8852	68	42	\N	0	\N	\N	f	0	\N
8853	68	41	\N	0	\N	\N	f	0	\N
8854	68	40	\N	0	\N	\N	f	0	\N
8855	68	109	\N	0	\N	\N	f	0	\N
8856	68	108	\N	0	\N	\N	f	0	\N
8857	68	107	\N	0	\N	\N	f	0	\N
8858	68	106	\N	0	\N	\N	f	0	\N
8859	68	105	\N	0	\N	\N	f	0	\N
8860	68	104	\N	0	\N	\N	f	0	\N
8861	68	103	\N	0	\N	\N	f	0	\N
8862	68	102	\N	0	\N	\N	f	0	\N
8863	68	101	\N	0	\N	\N	f	0	\N
8864	68	100	\N	0	\N	\N	f	0	\N
8865	68	99	\N	0	\N	\N	f	0	\N
8866	68	98	\N	0	\N	\N	f	0	\N
8867	68	97	\N	0	\N	\N	f	0	\N
8868	68	96	\N	0	\N	\N	f	0	\N
8869	68	95	\N	0	\N	\N	f	0	\N
8870	68	94	\N	0	\N	\N	f	0	\N
8871	68	93	\N	0	\N	\N	f	0	\N
8872	68	92	\N	0	\N	\N	f	0	\N
8873	68	91	\N	0	\N	\N	f	0	\N
8874	68	90	\N	0	\N	\N	f	0	\N
8875	68	89	\N	0	\N	\N	f	0	\N
8876	68	88	\N	0	\N	\N	f	0	\N
8877	68	87	\N	0	\N	\N	f	0	\N
8878	68	86	\N	0	\N	\N	f	0	\N
8879	68	85	\N	0	\N	\N	f	0	\N
8880	68	84	\N	0	\N	\N	f	0	\N
8881	68	83	\N	0	\N	\N	f	0	\N
8882	68	82	\N	0	\N	\N	f	0	\N
8883	68	81	\N	0	\N	\N	f	0	\N
8884	68	80	\N	0	\N	\N	f	0	\N
8885	68	79	\N	0	\N	\N	f	0	\N
8886	68	78	\N	0	\N	\N	f	0	\N
8887	68	77	\N	0	\N	\N	f	0	\N
8888	68	76	\N	0	\N	\N	f	0	\N
8889	68	75	\N	0	\N	\N	f	0	\N
8890	69	290	\N	0	\N	\N	f	0	\N
8891	69	289	\N	0	\N	\N	f	0	\N
8892	69	288	\N	0	\N	\N	f	0	\N
8893	69	287	\N	0	\N	\N	f	0	\N
8894	69	286	\N	0	\N	\N	f	0	\N
8895	69	285	\N	0	\N	\N	f	0	\N
8896	69	284	\N	0	\N	\N	f	0	\N
8897	69	283	\N	0	\N	\N	f	0	\N
8898	69	282	\N	0	\N	\N	f	0	\N
8899	69	281	\N	0	\N	\N	f	0	\N
8900	69	280	\N	0	\N	\N	f	0	\N
8901	69	279	\N	0	\N	\N	f	0	\N
8902	69	278	\N	0	\N	\N	f	0	\N
8903	69	277	\N	0	\N	\N	f	0	\N
8904	69	276	\N	0	\N	\N	f	0	\N
8905	69	275	\N	0	\N	\N	f	0	\N
8906	69	274	\N	0	\N	\N	f	0	\N
8907	69	273	\N	0	\N	\N	f	0	\N
8908	69	272	\N	0	\N	\N	f	0	\N
8909	69	271	\N	0	\N	\N	f	0	\N
8910	69	270	\N	0	\N	\N	f	0	\N
8911	69	269	\N	0	\N	\N	f	0	\N
8912	69	268	\N	0	\N	\N	f	0	\N
8913	69	267	\N	0	\N	\N	f	0	\N
8914	69	266	\N	0	\N	\N	f	0	\N
8915	69	265	\N	0	\N	\N	f	0	\N
8916	69	264	\N	0	\N	\N	f	0	\N
8917	69	263	\N	0	\N	\N	f	0	\N
8918	69	262	\N	0	\N	\N	f	0	\N
8919	69	261	\N	0	\N	\N	f	0	\N
8920	69	260	\N	0	\N	\N	f	0	\N
8921	69	259	\N	0	\N	\N	f	0	\N
8922	69	258	\N	0	\N	\N	f	0	\N
8923	69	257	\N	0	\N	\N	f	0	\N
8924	69	256	\N	0	\N	\N	f	0	\N
8925	69	255	\N	0	\N	\N	f	0	\N
8926	69	360	\N	0	\N	\N	f	0	\N
8927	69	359	\N	0	\N	\N	f	0	\N
8928	69	358	\N	0	\N	\N	f	0	\N
8929	69	357	\N	0	\N	\N	f	0	\N
8930	69	356	\N	0	\N	\N	f	0	\N
8931	69	355	\N	0	\N	\N	f	0	\N
8932	69	354	\N	0	\N	\N	f	0	\N
8933	69	353	\N	0	\N	\N	f	0	\N
8934	69	352	\N	0	\N	\N	f	0	\N
8935	69	351	\N	0	\N	\N	f	0	\N
8936	69	350	\N	0	\N	\N	f	0	\N
8937	69	349	\N	0	\N	\N	f	0	\N
8938	69	348	\N	0	\N	\N	f	0	\N
8939	69	347	\N	0	\N	\N	f	0	\N
8940	69	346	\N	0	\N	\N	f	0	\N
8941	69	345	\N	0	\N	\N	f	0	\N
8942	69	344	\N	0	\N	\N	f	0	\N
8943	69	343	\N	0	\N	\N	f	0	\N
8944	69	342	\N	0	\N	\N	f	0	\N
8945	69	341	\N	0	\N	\N	f	0	\N
8946	69	340	\N	0	\N	\N	f	0	\N
8947	69	339	\N	0	\N	\N	f	0	\N
8948	69	338	\N	0	\N	\N	f	0	\N
8949	69	337	\N	0	\N	\N	f	0	\N
8950	69	336	\N	0	\N	\N	f	0	\N
8951	69	335	\N	0	\N	\N	f	0	\N
8952	69	334	\N	0	\N	\N	f	0	\N
8953	69	333	\N	0	\N	\N	f	0	\N
8954	69	332	\N	0	\N	\N	f	0	\N
8955	69	331	\N	0	\N	\N	f	0	\N
8956	69	330	\N	0	\N	\N	f	0	\N
8957	69	329	\N	0	\N	\N	f	0	\N
8958	69	328	\N	0	\N	\N	f	0	\N
8959	69	327	\N	0	\N	\N	f	0	\N
8960	69	326	\N	0	\N	\N	f	0	\N
8961	69	325	\N	0	\N	\N	f	0	\N
8962	69	324	\N	0	\N	\N	f	0	\N
8963	69	74	\N	0	\N	\N	f	0	\N
8964	69	73	\N	0	\N	\N	f	0	\N
8965	69	72	\N	0	\N	\N	f	0	\N
8966	69	71	\N	0	\N	\N	f	0	\N
8967	69	70	\N	0	\N	\N	f	0	\N
8968	69	69	\N	0	\N	\N	f	0	\N
8969	69	68	\N	0	\N	\N	f	0	\N
8970	69	67	\N	0	\N	\N	f	0	\N
8971	69	66	\N	0	\N	\N	f	0	\N
8972	69	65	\N	0	\N	\N	f	0	\N
8973	69	64	\N	0	\N	\N	f	0	\N
8974	69	63	\N	0	\N	\N	f	0	\N
8975	69	62	\N	0	\N	\N	f	0	\N
8976	69	61	\N	0	\N	\N	f	0	\N
8977	69	60	\N	0	\N	\N	f	0	\N
8978	69	59	\N	0	\N	\N	f	0	\N
8979	69	58	\N	0	\N	\N	f	0	\N
8980	69	57	\N	0	\N	\N	f	0	\N
8981	69	56	\N	0	\N	\N	f	0	\N
8982	69	55	\N	0	\N	\N	f	0	\N
8983	69	54	\N	0	\N	\N	f	0	\N
8984	69	53	\N	0	\N	\N	f	0	\N
8985	69	52	\N	0	\N	\N	f	0	\N
8986	69	51	\N	0	\N	\N	f	0	\N
8987	69	50	\N	0	\N	\N	f	0	\N
8988	69	49	\N	0	\N	\N	f	0	\N
8989	69	48	\N	0	\N	\N	f	0	\N
8990	69	47	\N	0	\N	\N	f	0	\N
8991	69	46	\N	0	\N	\N	f	0	\N
8992	69	45	\N	0	\N	\N	f	0	\N
8993	69	44	\N	0	\N	\N	f	0	\N
8994	69	43	\N	0	\N	\N	f	0	\N
8995	69	42	\N	0	\N	\N	f	0	\N
8996	69	41	\N	0	\N	\N	f	0	\N
8997	69	40	\N	0	\N	\N	f	0	\N
8998	69	218	\N	0	\N	\N	f	0	\N
8999	69	217	\N	0	\N	\N	f	0	\N
9000	69	216	\N	0	\N	\N	f	0	\N
9001	69	215	\N	0	\N	\N	f	0	\N
9002	69	214	\N	0	\N	\N	f	0	\N
9003	69	213	\N	0	\N	\N	f	0	\N
9004	69	212	\N	0	\N	\N	f	0	\N
9005	69	211	\N	0	\N	\N	f	0	\N
9006	69	210	\N	0	\N	\N	f	0	\N
9007	69	209	\N	0	\N	\N	f	0	\N
9008	69	208	\N	0	\N	\N	f	0	\N
9009	69	207	\N	0	\N	\N	f	0	\N
9010	69	206	\N	0	\N	\N	f	0	\N
9011	69	205	\N	0	\N	\N	f	0	\N
9012	69	204	\N	0	\N	\N	f	0	\N
9013	69	203	\N	0	\N	\N	f	0	\N
9014	69	202	\N	0	\N	\N	f	0	\N
9015	69	201	\N	0	\N	\N	f	0	\N
9016	69	200	\N	0	\N	\N	f	0	\N
9017	69	199	\N	0	\N	\N	f	0	\N
9018	69	198	\N	0	\N	\N	f	0	\N
9019	69	197	\N	0	\N	\N	f	0	\N
9020	69	196	\N	0	\N	\N	f	0	\N
9021	69	195	\N	0	\N	\N	f	0	\N
9022	69	194	\N	0	\N	\N	f	0	\N
9023	69	193	\N	0	\N	\N	f	0	\N
9024	69	192	\N	0	\N	\N	f	0	\N
9025	69	191	\N	0	\N	\N	f	0	\N
9026	69	190	\N	0	\N	\N	f	0	\N
9027	69	189	\N	0	\N	\N	f	0	\N
9028	69	188	\N	0	\N	\N	f	0	\N
9029	69	187	\N	0	\N	\N	f	0	\N
9030	69	186	\N	0	\N	\N	f	0	\N
9031	69	185	\N	0	\N	\N	f	0	\N
9032	69	184	\N	0	\N	\N	f	0	\N
9033	69	183	\N	0	\N	\N	f	0	\N
9034	69	182	\N	0	\N	\N	f	0	\N
9035	69	181	\N	0	\N	\N	f	0	\N
9036	69	323	\N	0	\N	\N	f	0	\N
9037	69	322	\N	0	\N	\N	f	0	\N
9038	69	321	\N	0	\N	\N	f	0	\N
9039	69	320	\N	0	\N	\N	f	0	\N
9040	69	319	\N	0	\N	\N	f	0	\N
9041	69	318	\N	0	\N	\N	f	0	\N
9042	69	317	\N	0	\N	\N	f	0	\N
9043	69	316	\N	0	\N	\N	f	0	\N
9044	69	315	\N	0	\N	\N	f	0	\N
9045	69	314	\N	0	\N	\N	f	0	\N
9046	69	313	\N	0	\N	\N	f	0	\N
9047	69	312	\N	0	\N	\N	f	0	\N
9048	69	311	\N	0	\N	\N	f	0	\N
9049	69	310	\N	0	\N	\N	f	0	\N
9050	69	309	\N	0	\N	\N	f	0	\N
9051	69	308	\N	0	\N	\N	f	0	\N
9052	69	307	\N	0	\N	\N	f	0	\N
9053	69	306	\N	0	\N	\N	f	0	\N
9054	69	305	\N	0	\N	\N	f	0	\N
9055	69	304	\N	0	\N	\N	f	0	\N
9056	69	303	\N	0	\N	\N	f	0	\N
9057	69	302	\N	0	\N	\N	f	0	\N
9058	69	301	\N	0	\N	\N	f	0	\N
9059	69	300	\N	0	\N	\N	f	0	\N
9060	69	299	\N	0	\N	\N	f	0	\N
9061	69	298	\N	0	\N	\N	f	0	\N
9062	69	297	\N	0	\N	\N	f	0	\N
9063	69	296	\N	0	\N	\N	f	0	\N
9064	69	295	\N	0	\N	\N	f	0	\N
9065	69	294	\N	0	\N	\N	f	0	\N
9066	69	293	\N	0	\N	\N	f	0	\N
9067	69	292	\N	0	\N	\N	f	0	\N
9068	69	291	\N	0	\N	\N	f	0	\N
9069	69	145	\N	0	\N	\N	f	0	\N
9070	69	144	\N	0	\N	\N	f	0	\N
9071	69	143	\N	0	\N	\N	f	0	\N
9072	69	142	\N	0	\N	\N	f	0	\N
9073	69	141	\N	0	\N	\N	f	0	\N
9074	69	140	\N	0	\N	\N	f	0	\N
9075	69	139	\N	0	\N	\N	f	0	\N
9076	69	138	\N	0	\N	\N	f	0	\N
9077	69	137	\N	0	\N	\N	f	0	\N
9078	69	136	\N	0	\N	\N	f	0	\N
9079	69	135	\N	0	\N	\N	f	0	\N
9080	69	134	\N	0	\N	\N	f	0	\N
9081	69	133	\N	0	\N	\N	f	0	\N
9082	69	132	\N	0	\N	\N	f	0	\N
9083	69	131	\N	0	\N	\N	f	0	\N
9084	69	130	\N	0	\N	\N	f	0	\N
9085	69	129	\N	0	\N	\N	f	0	\N
9086	69	128	\N	0	\N	\N	f	0	\N
9087	69	127	\N	0	\N	\N	f	0	\N
9088	69	126	\N	0	\N	\N	f	0	\N
9089	69	125	\N	0	\N	\N	f	0	\N
9090	69	124	\N	0	\N	\N	f	0	\N
9091	69	123	\N	0	\N	\N	f	0	\N
9092	69	122	\N	0	\N	\N	f	0	\N
9093	69	121	\N	0	\N	\N	f	0	\N
9094	69	120	\N	0	\N	\N	f	0	\N
9095	69	119	\N	0	\N	\N	f	0	\N
9096	69	118	\N	0	\N	\N	f	0	\N
9097	69	117	\N	0	\N	\N	f	0	\N
9098	69	116	\N	0	\N	\N	f	0	\N
9099	69	115	\N	0	\N	\N	f	0	\N
9100	69	114	\N	0	\N	\N	f	0	\N
9101	69	113	\N	0	\N	\N	f	0	\N
9102	69	112	\N	0	\N	\N	f	0	\N
9103	69	111	\N	0	\N	\N	f	0	\N
9104	69	110	\N	0	\N	\N	f	0	\N
9105	69	180	\N	0	\N	\N	f	0	\N
9106	69	179	\N	0	\N	\N	f	0	\N
9107	69	178	\N	0	\N	\N	f	0	\N
9108	69	177	\N	0	\N	\N	f	0	\N
9109	69	176	\N	0	\N	\N	f	0	\N
9110	69	175	\N	0	\N	\N	f	0	\N
9111	69	174	\N	0	\N	\N	f	0	\N
9112	69	173	\N	0	\N	\N	f	0	\N
9113	69	172	\N	0	\N	\N	f	0	\N
9114	69	171	\N	0	\N	\N	f	0	\N
9115	69	170	\N	0	\N	\N	f	0	\N
9116	69	169	\N	0	\N	\N	f	0	\N
9117	69	168	\N	0	\N	\N	f	0	\N
9118	69	167	\N	0	\N	\N	f	0	\N
9119	69	166	\N	0	\N	\N	f	0	\N
9120	69	165	\N	0	\N	\N	f	0	\N
9121	69	164	\N	0	\N	\N	f	0	\N
9122	69	163	\N	0	\N	\N	f	0	\N
9123	69	162	\N	0	\N	\N	f	0	\N
9124	69	161	\N	0	\N	\N	f	0	\N
9125	69	160	\N	0	\N	\N	f	0	\N
9126	69	159	\N	0	\N	\N	f	0	\N
9127	69	158	\N	0	\N	\N	f	0	\N
9128	69	157	\N	0	\N	\N	f	0	\N
9129	69	156	\N	0	\N	\N	f	0	\N
9130	69	155	\N	0	\N	\N	f	0	\N
9131	69	154	\N	0	\N	\N	f	0	\N
9132	69	153	\N	0	\N	\N	f	0	\N
9133	69	152	\N	0	\N	\N	f	0	\N
9134	69	151	\N	0	\N	\N	f	0	\N
9135	69	150	\N	0	\N	\N	f	0	\N
9136	69	149	\N	0	\N	\N	f	0	\N
9137	69	148	\N	0	\N	\N	f	0	\N
9138	69	147	\N	0	\N	\N	f	0	\N
9139	69	146	\N	0	\N	\N	f	0	\N
9140	69	254	\N	0	\N	\N	f	0	\N
9141	69	253	\N	0	\N	\N	f	0	\N
9142	69	252	\N	0	\N	\N	f	0	\N
9143	69	251	\N	0	\N	\N	f	0	\N
9144	69	250	\N	0	\N	\N	f	0	\N
9145	69	249	\N	0	\N	\N	f	0	\N
9146	69	248	\N	0	\N	\N	f	0	\N
9147	69	247	\N	0	\N	\N	f	0	\N
9148	69	246	\N	0	\N	\N	f	0	\N
9149	69	245	\N	0	\N	\N	f	0	\N
9150	69	244	\N	0	\N	\N	f	0	\N
9151	69	243	\N	0	\N	\N	f	0	\N
9152	69	242	\N	0	\N	\N	f	0	\N
9153	69	241	\N	0	\N	\N	f	0	\N
9154	69	240	\N	0	\N	\N	f	0	\N
9155	69	239	\N	0	\N	\N	f	0	\N
9156	69	238	\N	0	\N	\N	f	0	\N
9157	69	237	\N	0	\N	\N	f	0	\N
9158	69	236	\N	0	\N	\N	f	0	\N
9159	69	235	\N	0	\N	\N	f	0	\N
9160	69	234	\N	0	\N	\N	f	0	\N
9161	69	233	\N	0	\N	\N	f	0	\N
9162	69	232	\N	0	\N	\N	f	0	\N
9163	69	231	\N	0	\N	\N	f	0	\N
9164	69	230	\N	0	\N	\N	f	0	\N
9165	69	229	\N	0	\N	\N	f	0	\N
9166	69	228	\N	0	\N	\N	f	0	\N
9167	69	227	\N	0	\N	\N	f	0	\N
9168	69	226	\N	0	\N	\N	f	0	\N
9169	69	225	\N	0	\N	\N	f	0	\N
9170	69	224	\N	0	\N	\N	f	0	\N
9171	69	223	\N	0	\N	\N	f	0	\N
9172	69	222	\N	0	\N	\N	f	0	\N
9173	69	221	\N	0	\N	\N	f	0	\N
9174	69	220	\N	0	\N	\N	f	0	\N
9175	69	219	\N	0	\N	\N	f	0	\N
9176	69	432	\N	0	\N	\N	f	0	\N
9177	69	431	\N	0	\N	\N	f	0	\N
9178	69	430	\N	0	\N	\N	f	0	\N
9179	69	429	\N	0	\N	\N	f	0	\N
9180	69	428	\N	0	\N	\N	f	0	\N
9181	69	427	\N	0	\N	\N	f	0	\N
9182	69	426	\N	0	\N	\N	f	0	\N
9183	69	425	\N	0	\N	\N	f	0	\N
9184	69	424	\N	0	\N	\N	f	0	\N
9185	69	423	\N	0	\N	\N	f	0	\N
9186	69	422	\N	0	\N	\N	f	0	\N
9187	69	421	\N	0	\N	\N	f	0	\N
9188	69	420	\N	0	\N	\N	f	0	\N
9189	69	419	\N	0	\N	\N	f	0	\N
9190	69	418	\N	0	\N	\N	f	0	\N
9191	69	417	\N	0	\N	\N	f	0	\N
9192	69	416	\N	0	\N	\N	f	0	\N
9193	69	415	\N	0	\N	\N	f	0	\N
9194	69	414	\N	0	\N	\N	f	0	\N
9195	69	413	\N	0	\N	\N	f	0	\N
9196	69	412	\N	0	\N	\N	f	0	\N
9197	69	411	\N	0	\N	\N	f	0	\N
9198	69	410	\N	0	\N	\N	f	0	\N
9199	69	409	\N	0	\N	\N	f	0	\N
9200	69	408	\N	0	\N	\N	f	0	\N
9201	69	407	\N	0	\N	\N	f	0	\N
9202	69	406	\N	0	\N	\N	f	0	\N
9203	69	405	\N	0	\N	\N	f	0	\N
9204	69	404	\N	0	\N	\N	f	0	\N
9205	69	403	\N	0	\N	\N	f	0	\N
9206	69	402	\N	0	\N	\N	f	0	\N
9207	69	39	\N	0	\N	\N	f	0	\N
9208	69	38	\N	0	\N	\N	f	0	\N
9209	69	37	\N	0	\N	\N	f	0	\N
9210	69	36	\N	0	\N	\N	f	0	\N
9211	69	35	\N	0	\N	\N	f	0	\N
9212	69	34	\N	0	\N	\N	f	0	\N
9213	69	33	\N	0	\N	\N	f	0	\N
9214	69	32	\N	0	\N	\N	f	0	\N
9215	69	31	\N	0	\N	\N	f	0	\N
9216	69	30	\N	0	\N	\N	f	0	\N
9217	69	29	\N	0	\N	\N	f	0	\N
9218	69	28	\N	0	\N	\N	f	0	\N
9219	69	27	\N	0	\N	\N	f	0	\N
9220	69	26	\N	0	\N	\N	f	0	\N
9221	69	25	\N	0	\N	\N	f	0	\N
9222	69	24	\N	0	\N	\N	f	0	\N
9223	69	23	\N	0	\N	\N	f	0	\N
9224	69	22	\N	0	\N	\N	f	0	\N
9225	69	21	\N	0	\N	\N	f	0	\N
9226	69	20	\N	0	\N	\N	f	0	\N
9227	69	19	\N	0	\N	\N	f	0	\N
9228	69	18	\N	0	\N	\N	f	0	\N
9229	69	17	\N	0	\N	\N	f	0	\N
9230	69	16	\N	0	\N	\N	f	0	\N
9231	69	15	\N	0	\N	\N	f	0	\N
9232	69	14	\N	0	\N	\N	f	0	\N
9233	69	13	\N	0	\N	\N	f	0	\N
9234	69	12	\N	0	\N	\N	f	0	\N
9235	69	11	\N	0	\N	\N	f	0	\N
9236	69	10	\N	0	\N	\N	f	0	\N
9237	69	9	\N	0	\N	\N	f	0	\N
9238	69	8	\N	0	\N	\N	f	0	\N
9239	69	7	\N	0	\N	\N	f	0	\N
9240	69	6	\N	0	\N	\N	f	0	\N
9241	69	5	\N	0	\N	\N	f	0	\N
9242	69	4	\N	0	\N	\N	f	0	\N
9243	69	3	\N	0	\N	\N	f	0	\N
9244	69	2	\N	0	\N	\N	f	0	\N
9245	69	1	\N	0	\N	\N	f	0	\N
9246	69	401	\N	0	\N	\N	f	0	\N
9247	69	400	\N	0	\N	\N	f	0	\N
9248	69	399	\N	0	\N	\N	f	0	\N
9249	69	398	\N	0	\N	\N	f	0	\N
9250	69	397	\N	0	\N	\N	f	0	\N
9251	69	396	\N	0	\N	\N	f	0	\N
9252	69	395	\N	0	\N	\N	f	0	\N
9253	69	394	\N	0	\N	\N	f	0	\N
9254	69	393	\N	0	\N	\N	f	0	\N
9255	69	392	\N	0	\N	\N	f	0	\N
9256	69	391	\N	0	\N	\N	f	0	\N
9257	69	390	\N	0	\N	\N	f	0	\N
9258	69	389	\N	0	\N	\N	f	0	\N
9259	69	388	\N	0	\N	\N	f	0	\N
9260	69	387	\N	0	\N	\N	f	0	\N
9261	69	386	\N	0	\N	\N	f	0	\N
9262	69	385	\N	0	\N	\N	f	0	\N
9263	69	384	\N	0	\N	\N	f	0	\N
9264	69	383	\N	0	\N	\N	f	0	\N
9265	69	382	\N	0	\N	\N	f	0	\N
9266	69	381	\N	0	\N	\N	f	0	\N
9267	69	380	\N	0	\N	\N	f	0	\N
9268	69	379	\N	0	\N	\N	f	0	\N
9269	69	378	\N	0	\N	\N	f	0	\N
9270	69	377	\N	0	\N	\N	f	0	\N
9271	69	376	\N	0	\N	\N	f	0	\N
9272	69	375	\N	0	\N	\N	f	0	\N
9273	69	374	\N	0	\N	\N	f	0	\N
9274	69	373	\N	0	\N	\N	f	0	\N
9275	69	372	\N	0	\N	\N	f	0	\N
9276	69	371	\N	0	\N	\N	f	0	\N
9277	69	370	\N	0	\N	\N	f	0	\N
9278	69	369	\N	0	\N	\N	f	0	\N
9279	69	368	\N	0	\N	\N	f	0	\N
9280	69	367	\N	0	\N	\N	f	0	\N
9281	69	366	\N	0	\N	\N	f	0	\N
9282	69	365	\N	0	\N	\N	f	0	\N
9283	69	364	\N	0	\N	\N	f	0	\N
9284	69	363	\N	0	\N	\N	f	0	\N
9285	69	362	\N	0	\N	\N	f	0	\N
9286	69	361	\N	0	\N	\N	f	0	\N
9287	71	360	\N	0	\N	\N	f	0	\N
9288	71	359	\N	0	\N	\N	f	0	\N
9289	71	358	\N	0	\N	\N	f	0	\N
9290	71	357	\N	0	\N	\N	f	0	\N
9291	71	356	\N	0	\N	\N	f	0	\N
9292	71	355	\N	0	\N	\N	f	0	\N
9293	71	354	\N	0	\N	\N	f	0	\N
9294	71	353	\N	0	\N	\N	f	0	\N
9295	71	352	\N	0	\N	\N	f	0	\N
9296	71	351	\N	0	\N	\N	f	0	\N
9297	71	350	\N	0	\N	\N	f	0	\N
9298	71	349	\N	0	\N	\N	f	0	\N
9299	71	348	\N	0	\N	\N	f	0	\N
9300	71	347	\N	0	\N	\N	f	0	\N
9301	71	346	\N	0	\N	\N	f	0	\N
9302	71	345	\N	0	\N	\N	f	0	\N
9303	71	344	\N	0	\N	\N	f	0	\N
9304	71	343	\N	0	\N	\N	f	0	\N
9305	71	342	\N	0	\N	\N	f	0	\N
9306	71	341	\N	0	\N	\N	f	0	\N
9307	71	340	\N	0	\N	\N	f	0	\N
9308	71	339	\N	0	\N	\N	f	0	\N
9309	71	338	\N	0	\N	\N	f	0	\N
9310	71	337	\N	0	\N	\N	f	0	\N
9311	71	336	\N	0	\N	\N	f	0	\N
9312	71	335	\N	0	\N	\N	f	0	\N
9313	71	334	\N	0	\N	\N	f	0	\N
9314	71	333	\N	0	\N	\N	f	0	\N
9315	71	332	\N	0	\N	\N	f	0	\N
9316	71	331	\N	0	\N	\N	f	0	\N
9317	71	330	\N	0	\N	\N	f	0	\N
9318	71	329	\N	0	\N	\N	f	0	\N
9319	71	328	\N	0	\N	\N	f	0	\N
9320	71	327	\N	0	\N	\N	f	0	\N
9321	71	326	\N	0	\N	\N	f	0	\N
9322	71	325	\N	0	\N	\N	f	0	\N
9323	71	324	\N	0	\N	\N	f	0	\N
9324	71	401	\N	0	\N	\N	f	0	\N
9325	71	400	\N	0	\N	\N	f	0	\N
9326	71	399	\N	0	\N	\N	f	0	\N
9327	71	398	\N	0	\N	\N	f	0	\N
9328	71	397	\N	0	\N	\N	f	0	\N
9329	71	396	\N	0	\N	\N	f	0	\N
9330	71	395	\N	0	\N	\N	f	0	\N
9331	71	394	\N	0	\N	\N	f	0	\N
9332	71	393	\N	0	\N	\N	f	0	\N
9333	71	392	\N	0	\N	\N	f	0	\N
9334	71	391	\N	0	\N	\N	f	0	\N
9335	71	390	\N	0	\N	\N	f	0	\N
9336	71	389	\N	0	\N	\N	f	0	\N
9337	71	388	\N	0	\N	\N	f	0	\N
9338	71	387	\N	0	\N	\N	f	0	\N
9339	71	386	\N	0	\N	\N	f	0	\N
9340	71	385	\N	0	\N	\N	f	0	\N
9341	71	384	\N	0	\N	\N	f	0	\N
9342	71	383	\N	0	\N	\N	f	0	\N
9343	71	382	\N	0	\N	\N	f	0	\N
9344	71	381	\N	0	\N	\N	f	0	\N
9345	71	380	\N	0	\N	\N	f	0	\N
9346	71	379	\N	0	\N	\N	f	0	\N
9347	71	378	\N	0	\N	\N	f	0	\N
9348	71	377	\N	0	\N	\N	f	0	\N
9349	71	376	\N	0	\N	\N	f	0	\N
9350	71	375	\N	0	\N	\N	f	0	\N
9351	71	374	\N	0	\N	\N	f	0	\N
9352	71	373	\N	0	\N	\N	f	0	\N
9353	71	372	\N	0	\N	\N	f	0	\N
9354	71	371	\N	0	\N	\N	f	0	\N
9355	71	370	\N	0	\N	\N	f	0	\N
9356	71	369	\N	0	\N	\N	f	0	\N
9357	71	368	\N	0	\N	\N	f	0	\N
9358	71	367	\N	0	\N	\N	f	0	\N
9359	71	366	\N	0	\N	\N	f	0	\N
9360	71	365	\N	0	\N	\N	f	0	\N
9361	71	364	\N	0	\N	\N	f	0	\N
9362	71	363	\N	0	\N	\N	f	0	\N
9363	71	362	\N	0	\N	\N	f	0	\N
9364	71	361	\N	0	\N	\N	f	0	\N
9365	71	39	\N	0	\N	\N	f	0	\N
9366	71	38	\N	0	\N	\N	f	0	\N
9367	71	37	\N	0	\N	\N	f	0	\N
9368	71	36	\N	0	\N	\N	f	0	\N
9369	71	35	\N	0	\N	\N	f	0	\N
9370	71	34	\N	0	\N	\N	f	0	\N
9371	71	33	\N	0	\N	\N	f	0	\N
9372	71	32	\N	0	\N	\N	f	0	\N
9373	71	31	\N	0	\N	\N	f	0	\N
9374	71	30	\N	0	\N	\N	f	0	\N
9375	71	29	\N	0	\N	\N	f	0	\N
9376	71	28	\N	0	\N	\N	f	0	\N
9377	71	27	\N	0	\N	\N	f	0	\N
9378	71	26	\N	0	\N	\N	f	0	\N
9379	71	25	\N	0	\N	\N	f	0	\N
9380	71	24	\N	0	\N	\N	f	0	\N
9381	71	23	\N	0	\N	\N	f	0	\N
9382	71	22	\N	0	\N	\N	f	0	\N
9383	71	21	\N	0	\N	\N	f	0	\N
9384	71	20	\N	0	\N	\N	f	0	\N
9385	71	19	\N	0	\N	\N	f	0	\N
9386	71	18	\N	0	\N	\N	f	0	\N
9387	71	17	\N	0	\N	\N	f	0	\N
9388	71	16	\N	0	\N	\N	f	0	\N
9389	71	15	\N	0	\N	\N	f	0	\N
9390	71	14	\N	0	\N	\N	f	0	\N
9391	71	13	\N	0	\N	\N	f	0	\N
9392	71	12	\N	0	\N	\N	f	0	\N
9393	71	11	\N	0	\N	\N	f	0	\N
9394	71	10	\N	0	\N	\N	f	0	\N
9395	71	9	\N	0	\N	\N	f	0	\N
9396	71	8	\N	0	\N	\N	f	0	\N
9397	71	7	\N	0	\N	\N	f	0	\N
9398	71	6	\N	0	\N	\N	f	0	\N
9399	71	5	\N	0	\N	\N	f	0	\N
9400	71	4	\N	0	\N	\N	f	0	\N
9401	71	3	\N	0	\N	\N	f	0	\N
9402	71	2	\N	0	\N	\N	f	0	\N
9403	71	1	\N	0	\N	\N	f	0	\N
9404	71	74	\N	0	\N	\N	f	0	\N
9405	71	73	\N	0	\N	\N	f	0	\N
9406	71	72	\N	0	\N	\N	f	0	\N
9407	71	71	\N	0	\N	\N	f	0	\N
9408	71	70	\N	0	\N	\N	f	0	\N
9409	71	69	\N	0	\N	\N	f	0	\N
9410	71	68	\N	0	\N	\N	f	0	\N
9411	71	67	\N	0	\N	\N	f	0	\N
9412	71	66	\N	0	\N	\N	f	0	\N
9413	71	65	\N	0	\N	\N	f	0	\N
9414	71	64	\N	0	\N	\N	f	0	\N
9415	71	63	\N	0	\N	\N	f	0	\N
9416	71	62	\N	0	\N	\N	f	0	\N
9417	71	61	\N	0	\N	\N	f	0	\N
9418	71	60	\N	0	\N	\N	f	0	\N
9419	71	59	\N	0	\N	\N	f	0	\N
9420	71	58	\N	0	\N	\N	f	0	\N
9421	71	57	\N	0	\N	\N	f	0	\N
9422	71	56	\N	0	\N	\N	f	0	\N
9423	71	55	\N	0	\N	\N	f	0	\N
9424	71	54	\N	0	\N	\N	f	0	\N
9425	71	53	\N	0	\N	\N	f	0	\N
9426	71	52	\N	0	\N	\N	f	0	\N
9427	71	51	\N	0	\N	\N	f	0	\N
9428	71	50	\N	0	\N	\N	f	0	\N
9429	71	49	\N	0	\N	\N	f	0	\N
9430	71	48	\N	0	\N	\N	f	0	\N
9431	71	47	\N	0	\N	\N	f	0	\N
9432	71	46	\N	0	\N	\N	f	0	\N
9433	71	45	\N	0	\N	\N	f	0	\N
9434	71	44	\N	0	\N	\N	f	0	\N
9435	71	43	\N	0	\N	\N	f	0	\N
9436	71	42	\N	0	\N	\N	f	0	\N
9437	71	41	\N	0	\N	\N	f	0	\N
9438	71	40	\N	0	\N	\N	f	0	\N
9439	72	254	\N	0	\N	\N	f	0	\N
9440	72	253	\N	0	\N	\N	f	0	\N
9441	72	252	\N	0	\N	\N	f	0	\N
9442	72	251	\N	0	\N	\N	f	0	\N
9443	72	250	\N	0	\N	\N	f	0	\N
9444	72	249	\N	0	\N	\N	f	0	\N
9445	72	248	\N	0	\N	\N	f	0	\N
9446	72	247	\N	0	\N	\N	f	0	\N
9447	72	246	\N	0	\N	\N	f	0	\N
9448	72	245	\N	0	\N	\N	f	0	\N
9449	72	244	\N	0	\N	\N	f	0	\N
9450	72	243	\N	0	\N	\N	f	0	\N
9451	72	242	\N	0	\N	\N	f	0	\N
9452	72	241	\N	0	\N	\N	f	0	\N
9453	72	240	\N	0	\N	\N	f	0	\N
9454	72	239	\N	0	\N	\N	f	0	\N
9455	72	238	\N	0	\N	\N	f	0	\N
9456	72	237	\N	0	\N	\N	f	0	\N
9457	72	236	\N	0	\N	\N	f	0	\N
9458	72	235	\N	0	\N	\N	f	0	\N
9459	72	234	\N	0	\N	\N	f	0	\N
9460	72	233	\N	0	\N	\N	f	0	\N
9461	72	232	\N	0	\N	\N	f	0	\N
9462	72	231	\N	0	\N	\N	f	0	\N
9463	72	230	\N	0	\N	\N	f	0	\N
9464	72	229	\N	0	\N	\N	f	0	\N
9465	72	228	\N	0	\N	\N	f	0	\N
9466	72	227	\N	0	\N	\N	f	0	\N
9467	72	226	\N	0	\N	\N	f	0	\N
9468	72	225	\N	0	\N	\N	f	0	\N
9469	72	224	\N	0	\N	\N	f	0	\N
9470	72	223	\N	0	\N	\N	f	0	\N
9471	72	222	\N	0	\N	\N	f	0	\N
9472	72	221	\N	0	\N	\N	f	0	\N
9473	72	220	\N	0	\N	\N	f	0	\N
9474	72	219	\N	0	\N	\N	f	0	\N
9475	72	39	\N	0	\N	\N	f	0	\N
9476	72	38	\N	0	\N	\N	f	0	\N
9477	72	37	\N	0	\N	\N	f	0	\N
9478	72	36	\N	0	\N	\N	f	0	\N
9479	72	35	\N	0	\N	\N	f	0	\N
9480	72	34	\N	0	\N	\N	f	0	\N
9481	72	33	\N	0	\N	\N	f	0	\N
9482	72	32	\N	0	\N	\N	f	0	\N
9483	72	31	\N	0	\N	\N	f	0	\N
9484	72	30	\N	0	\N	\N	f	0	\N
9485	72	29	\N	0	\N	\N	f	0	\N
9486	72	28	\N	0	\N	\N	f	0	\N
9487	72	27	\N	0	\N	\N	f	0	\N
9488	72	26	\N	0	\N	\N	f	0	\N
9489	72	25	\N	0	\N	\N	f	0	\N
9490	72	24	\N	0	\N	\N	f	0	\N
9491	72	23	\N	0	\N	\N	f	0	\N
9492	72	22	\N	0	\N	\N	f	0	\N
9493	72	21	\N	0	\N	\N	f	0	\N
9494	72	20	\N	0	\N	\N	f	0	\N
9495	72	19	\N	0	\N	\N	f	0	\N
9496	72	18	\N	0	\N	\N	f	0	\N
9497	72	17	\N	0	\N	\N	f	0	\N
9498	72	16	\N	0	\N	\N	f	0	\N
9499	72	15	\N	0	\N	\N	f	0	\N
9500	72	14	\N	0	\N	\N	f	0	\N
9501	72	13	\N	0	\N	\N	f	0	\N
9502	72	12	\N	0	\N	\N	f	0	\N
9503	72	11	\N	0	\N	\N	f	0	\N
9504	72	10	\N	0	\N	\N	f	0	\N
9505	72	9	\N	0	\N	\N	f	0	\N
9506	72	8	\N	0	\N	\N	f	0	\N
9507	72	7	\N	0	\N	\N	f	0	\N
9508	72	6	\N	0	\N	\N	f	0	\N
9509	72	5	\N	0	\N	\N	f	0	\N
9510	72	4	\N	0	\N	\N	f	0	\N
9511	72	3	\N	0	\N	\N	f	0	\N
9512	72	2	\N	0	\N	\N	f	0	\N
9513	72	1	\N	0	\N	\N	f	0	\N
9514	72	360	\N	0	\N	\N	f	0	\N
9515	72	359	\N	0	\N	\N	f	0	\N
9516	72	358	\N	0	\N	\N	f	0	\N
9517	72	357	\N	0	\N	\N	f	0	\N
9518	72	356	\N	0	\N	\N	f	0	\N
9519	72	355	\N	0	\N	\N	f	0	\N
9520	72	354	\N	0	\N	\N	f	0	\N
9521	72	353	\N	0	\N	\N	f	0	\N
9522	72	352	\N	0	\N	\N	f	0	\N
9523	72	351	\N	0	\N	\N	f	0	\N
9524	72	350	\N	0	\N	\N	f	0	\N
9525	72	349	\N	0	\N	\N	f	0	\N
9526	72	348	\N	0	\N	\N	f	0	\N
9527	72	347	\N	0	\N	\N	f	0	\N
9528	72	346	\N	0	\N	\N	f	0	\N
9529	72	345	\N	0	\N	\N	f	0	\N
9530	72	344	\N	0	\N	\N	f	0	\N
9531	72	343	\N	0	\N	\N	f	0	\N
9532	72	342	\N	0	\N	\N	f	0	\N
9533	72	341	\N	0	\N	\N	f	0	\N
9534	72	340	\N	0	\N	\N	f	0	\N
9535	72	339	\N	0	\N	\N	f	0	\N
9536	72	338	\N	0	\N	\N	f	0	\N
9537	72	337	\N	0	\N	\N	f	0	\N
9538	72	336	\N	0	\N	\N	f	0	\N
9539	72	335	\N	0	\N	\N	f	0	\N
9540	72	334	\N	0	\N	\N	f	0	\N
9541	72	333	\N	0	\N	\N	f	0	\N
9542	72	332	\N	0	\N	\N	f	0	\N
9543	72	331	\N	0	\N	\N	f	0	\N
9544	72	330	\N	0	\N	\N	f	0	\N
9545	72	329	\N	0	\N	\N	f	0	\N
9546	72	328	\N	0	\N	\N	f	0	\N
9547	72	327	\N	0	\N	\N	f	0	\N
9548	72	326	\N	0	\N	\N	f	0	\N
9549	72	325	\N	0	\N	\N	f	0	\N
9550	72	324	\N	0	\N	\N	f	0	\N
9551	72	74	\N	0	\N	\N	f	0	\N
9552	72	73	\N	0	\N	\N	f	0	\N
9553	72	72	\N	0	\N	\N	f	0	\N
9554	72	71	\N	0	\N	\N	f	0	\N
9555	72	70	\N	0	\N	\N	f	0	\N
9556	72	69	\N	0	\N	\N	f	0	\N
9557	72	68	\N	0	\N	\N	f	0	\N
9558	72	67	\N	0	\N	\N	f	0	\N
9559	72	66	\N	0	\N	\N	f	0	\N
9560	72	65	\N	0	\N	\N	f	0	\N
9561	72	64	\N	0	\N	\N	f	0	\N
9562	72	63	\N	0	\N	\N	f	0	\N
9563	72	62	\N	0	\N	\N	f	0	\N
9564	72	61	\N	0	\N	\N	f	0	\N
9565	72	60	\N	0	\N	\N	f	0	\N
9566	72	59	\N	0	\N	\N	f	0	\N
9567	72	58	\N	0	\N	\N	f	0	\N
9568	72	57	\N	0	\N	\N	f	0	\N
9569	72	56	\N	0	\N	\N	f	0	\N
9570	72	55	\N	0	\N	\N	f	0	\N
9571	72	54	\N	0	\N	\N	f	0	\N
9572	72	53	\N	0	\N	\N	f	0	\N
9573	72	52	\N	0	\N	\N	f	0	\N
9574	72	51	\N	0	\N	\N	f	0	\N
9575	72	50	\N	0	\N	\N	f	0	\N
9576	72	49	\N	0	\N	\N	f	0	\N
9577	72	48	\N	0	\N	\N	f	0	\N
9578	72	47	\N	0	\N	\N	f	0	\N
9579	72	46	\N	0	\N	\N	f	0	\N
9580	72	45	\N	0	\N	\N	f	0	\N
9581	72	44	\N	0	\N	\N	f	0	\N
9582	72	43	\N	0	\N	\N	f	0	\N
9583	72	42	\N	0	\N	\N	f	0	\N
9584	72	41	\N	0	\N	\N	f	0	\N
9585	72	40	\N	0	\N	\N	f	0	\N
9586	72	290	\N	0	\N	\N	f	0	\N
9587	72	289	\N	0	\N	\N	f	0	\N
9588	72	288	\N	0	\N	\N	f	0	\N
9589	72	287	\N	0	\N	\N	f	0	\N
9590	72	286	\N	0	\N	\N	f	0	\N
9591	72	285	\N	0	\N	\N	f	0	\N
9592	72	284	\N	0	\N	\N	f	0	\N
9593	72	283	\N	0	\N	\N	f	0	\N
9594	72	282	\N	0	\N	\N	f	0	\N
9595	72	281	\N	0	\N	\N	f	0	\N
9596	72	280	\N	0	\N	\N	f	0	\N
9597	72	279	\N	0	\N	\N	f	0	\N
9598	72	278	\N	0	\N	\N	f	0	\N
9599	72	277	\N	0	\N	\N	f	0	\N
9600	72	276	\N	0	\N	\N	f	0	\N
9601	72	275	\N	0	\N	\N	f	0	\N
9602	72	274	\N	0	\N	\N	f	0	\N
9603	72	273	\N	0	\N	\N	f	0	\N
9604	72	272	\N	0	\N	\N	f	0	\N
9605	72	271	\N	0	\N	\N	f	0	\N
9606	72	270	\N	0	\N	\N	f	0	\N
9607	72	269	\N	0	\N	\N	f	0	\N
9608	72	268	\N	0	\N	\N	f	0	\N
9609	72	267	\N	0	\N	\N	f	0	\N
9610	72	266	\N	0	\N	\N	f	0	\N
9611	72	265	\N	0	\N	\N	f	0	\N
9612	72	264	\N	0	\N	\N	f	0	\N
9613	72	263	\N	0	\N	\N	f	0	\N
9614	72	262	\N	0	\N	\N	f	0	\N
9615	72	261	\N	0	\N	\N	f	0	\N
9616	72	260	\N	0	\N	\N	f	0	\N
9617	72	259	\N	0	\N	\N	f	0	\N
9618	72	258	\N	0	\N	\N	f	0	\N
9619	72	257	\N	0	\N	\N	f	0	\N
9620	72	256	\N	0	\N	\N	f	0	\N
9621	72	255	\N	0	\N	\N	f	0	\N
9622	72	218	\N	0	\N	\N	f	0	\N
9623	72	217	\N	0	\N	\N	f	0	\N
9624	72	216	\N	0	\N	\N	f	0	\N
9625	72	215	\N	0	\N	\N	f	0	\N
9626	72	214	\N	0	\N	\N	f	0	\N
9627	72	213	\N	0	\N	\N	f	0	\N
9628	72	212	\N	0	\N	\N	f	0	\N
9629	72	211	\N	0	\N	\N	f	0	\N
9630	72	210	\N	0	\N	\N	f	0	\N
9631	72	209	\N	0	\N	\N	f	0	\N
9632	72	208	\N	0	\N	\N	f	0	\N
9633	72	207	\N	0	\N	\N	f	0	\N
9634	72	206	\N	0	\N	\N	f	0	\N
9635	72	205	\N	0	\N	\N	f	0	\N
9636	72	204	\N	0	\N	\N	f	0	\N
9637	72	203	\N	0	\N	\N	f	0	\N
9638	72	202	\N	0	\N	\N	f	0	\N
9639	72	201	\N	0	\N	\N	f	0	\N
9640	72	200	\N	0	\N	\N	f	0	\N
9641	72	199	\N	0	\N	\N	f	0	\N
9642	72	198	\N	0	\N	\N	f	0	\N
9643	72	197	\N	0	\N	\N	f	0	\N
9644	72	196	\N	0	\N	\N	f	0	\N
9645	72	195	\N	0	\N	\N	f	0	\N
9646	72	194	\N	0	\N	\N	f	0	\N
9647	72	193	\N	0	\N	\N	f	0	\N
9648	72	192	\N	0	\N	\N	f	0	\N
9649	72	191	\N	0	\N	\N	f	0	\N
9650	72	190	\N	0	\N	\N	f	0	\N
9651	72	189	\N	0	\N	\N	f	0	\N
9652	72	188	\N	0	\N	\N	f	0	\N
9653	72	187	\N	0	\N	\N	f	0	\N
9654	72	186	\N	0	\N	\N	f	0	\N
9655	72	185	\N	0	\N	\N	f	0	\N
9656	72	184	\N	0	\N	\N	f	0	\N
9657	72	183	\N	0	\N	\N	f	0	\N
9658	72	182	\N	0	\N	\N	f	0	\N
9659	72	181	\N	0	\N	\N	f	0	\N
9660	72	109	\N	0	\N	\N	f	0	\N
9661	72	108	\N	0	\N	\N	f	0	\N
9662	72	107	\N	0	\N	\N	f	0	\N
9663	72	106	\N	0	\N	\N	f	0	\N
9664	72	105	\N	0	\N	\N	f	0	\N
9665	72	104	\N	0	\N	\N	f	0	\N
9666	72	103	\N	0	\N	\N	f	0	\N
9667	72	102	\N	0	\N	\N	f	0	\N
9668	72	101	\N	0	\N	\N	f	0	\N
9669	72	100	\N	0	\N	\N	f	0	\N
9670	72	99	\N	0	\N	\N	f	0	\N
9671	72	98	\N	0	\N	\N	f	0	\N
9672	72	97	\N	0	\N	\N	f	0	\N
9673	72	96	\N	0	\N	\N	f	0	\N
9674	72	95	\N	0	\N	\N	f	0	\N
9675	72	94	\N	0	\N	\N	f	0	\N
9676	72	93	\N	0	\N	\N	f	0	\N
9677	72	92	\N	0	\N	\N	f	0	\N
9678	72	91	\N	0	\N	\N	f	0	\N
9679	72	90	\N	0	\N	\N	f	0	\N
9680	72	89	\N	0	\N	\N	f	0	\N
9681	72	88	\N	0	\N	\N	f	0	\N
9682	72	87	\N	0	\N	\N	f	0	\N
9683	72	86	\N	0	\N	\N	f	0	\N
9684	72	85	\N	0	\N	\N	f	0	\N
9685	72	84	\N	0	\N	\N	f	0	\N
9686	72	83	\N	0	\N	\N	f	0	\N
9687	72	82	\N	0	\N	\N	f	0	\N
9688	72	81	\N	0	\N	\N	f	0	\N
9689	72	80	\N	0	\N	\N	f	0	\N
9690	72	79	\N	0	\N	\N	f	0	\N
9691	72	78	\N	0	\N	\N	f	0	\N
9692	72	77	\N	0	\N	\N	f	0	\N
9693	72	76	\N	0	\N	\N	f	0	\N
9694	72	75	\N	0	\N	\N	f	0	\N
9695	72	401	\N	0	\N	\N	f	0	\N
9696	72	400	\N	0	\N	\N	f	0	\N
9697	72	399	\N	0	\N	\N	f	0	\N
9698	72	398	\N	0	\N	\N	f	0	\N
9699	72	397	\N	0	\N	\N	f	0	\N
9700	72	396	\N	0	\N	\N	f	0	\N
9701	72	395	\N	0	\N	\N	f	0	\N
9702	72	394	\N	0	\N	\N	f	0	\N
9703	72	393	\N	0	\N	\N	f	0	\N
9704	72	392	\N	0	\N	\N	f	0	\N
9705	72	391	\N	0	\N	\N	f	0	\N
9706	72	390	\N	0	\N	\N	f	0	\N
9707	72	389	\N	0	\N	\N	f	0	\N
9708	72	388	\N	0	\N	\N	f	0	\N
9709	72	387	\N	0	\N	\N	f	0	\N
9710	72	386	\N	0	\N	\N	f	0	\N
9711	72	385	\N	0	\N	\N	f	0	\N
9712	72	384	\N	0	\N	\N	f	0	\N
9713	72	383	\N	0	\N	\N	f	0	\N
9714	72	382	\N	0	\N	\N	f	0	\N
9715	72	381	\N	0	\N	\N	f	0	\N
9716	72	380	\N	0	\N	\N	f	0	\N
9717	72	379	\N	0	\N	\N	f	0	\N
9718	72	378	\N	0	\N	\N	f	0	\N
9719	72	377	\N	0	\N	\N	f	0	\N
9720	72	376	\N	0	\N	\N	f	0	\N
9721	72	375	\N	0	\N	\N	f	0	\N
9722	72	374	\N	0	\N	\N	f	0	\N
9723	72	373	\N	0	\N	\N	f	0	\N
9724	72	372	\N	0	\N	\N	f	0	\N
9725	72	371	\N	0	\N	\N	f	0	\N
9726	72	370	\N	0	\N	\N	f	0	\N
9727	72	369	\N	0	\N	\N	f	0	\N
9728	72	368	\N	0	\N	\N	f	0	\N
9729	72	367	\N	0	\N	\N	f	0	\N
9730	72	366	\N	0	\N	\N	f	0	\N
9731	72	365	\N	0	\N	\N	f	0	\N
9732	72	364	\N	0	\N	\N	f	0	\N
9733	72	363	\N	0	\N	\N	f	0	\N
9734	72	362	\N	0	\N	\N	f	0	\N
9735	72	361	\N	0	\N	\N	f	0	\N
9736	72	323	\N	0	\N	\N	f	0	\N
9737	72	322	\N	0	\N	\N	f	0	\N
9738	72	321	\N	0	\N	\N	f	0	\N
9739	72	320	\N	0	\N	\N	f	0	\N
9740	72	319	\N	0	\N	\N	f	0	\N
9741	72	318	\N	0	\N	\N	f	0	\N
9742	72	317	\N	0	\N	\N	f	0	\N
9743	72	316	\N	0	\N	\N	f	0	\N
9744	72	315	\N	0	\N	\N	f	0	\N
9745	72	314	\N	0	\N	\N	f	0	\N
9746	72	313	\N	0	\N	\N	f	0	\N
9747	72	312	\N	0	\N	\N	f	0	\N
9748	72	311	\N	0	\N	\N	f	0	\N
9749	72	310	\N	0	\N	\N	f	0	\N
9750	72	309	\N	0	\N	\N	f	0	\N
9751	72	308	\N	0	\N	\N	f	0	\N
9752	72	307	\N	0	\N	\N	f	0	\N
9753	72	306	\N	0	\N	\N	f	0	\N
9754	72	305	\N	0	\N	\N	f	0	\N
9755	72	304	\N	0	\N	\N	f	0	\N
9756	72	303	\N	0	\N	\N	f	0	\N
9757	72	302	\N	0	\N	\N	f	0	\N
9758	72	301	\N	0	\N	\N	f	0	\N
9759	72	300	\N	0	\N	\N	f	0	\N
9760	72	299	\N	0	\N	\N	f	0	\N
9761	72	298	\N	0	\N	\N	f	0	\N
9762	72	297	\N	0	\N	\N	f	0	\N
9763	72	296	\N	0	\N	\N	f	0	\N
9764	72	295	\N	0	\N	\N	f	0	\N
9765	72	294	\N	0	\N	\N	f	0	\N
9766	72	293	\N	0	\N	\N	f	0	\N
9767	72	292	\N	0	\N	\N	f	0	\N
9768	72	291	\N	0	\N	\N	f	0	\N
9769	72	145	\N	0	\N	\N	f	0	\N
9770	72	144	\N	0	\N	\N	f	0	\N
9771	72	143	\N	0	\N	\N	f	0	\N
9772	72	142	\N	0	\N	\N	f	0	\N
9773	72	141	\N	0	\N	\N	f	0	\N
9774	72	140	\N	0	\N	\N	f	0	\N
9775	72	139	\N	0	\N	\N	f	0	\N
9776	72	138	\N	0	\N	\N	f	0	\N
9777	72	137	\N	0	\N	\N	f	0	\N
9778	72	136	\N	0	\N	\N	f	0	\N
9779	72	135	\N	0	\N	\N	f	0	\N
9780	72	134	\N	0	\N	\N	f	0	\N
9781	72	133	\N	0	\N	\N	f	0	\N
9782	72	132	\N	0	\N	\N	f	0	\N
9783	72	131	\N	0	\N	\N	f	0	\N
9784	72	130	\N	0	\N	\N	f	0	\N
9785	72	129	\N	0	\N	\N	f	0	\N
9786	72	128	\N	0	\N	\N	f	0	\N
9787	72	127	\N	0	\N	\N	f	0	\N
9788	72	126	\N	0	\N	\N	f	0	\N
9789	72	125	\N	0	\N	\N	f	0	\N
9790	72	124	\N	0	\N	\N	f	0	\N
9791	72	123	\N	0	\N	\N	f	0	\N
9792	72	122	\N	0	\N	\N	f	0	\N
9793	72	121	\N	0	\N	\N	f	0	\N
9794	72	120	\N	0	\N	\N	f	0	\N
9795	72	119	\N	0	\N	\N	f	0	\N
9796	72	118	\N	0	\N	\N	f	0	\N
9797	72	117	\N	0	\N	\N	f	0	\N
9798	72	116	\N	0	\N	\N	f	0	\N
9799	72	115	\N	0	\N	\N	f	0	\N
9800	72	114	\N	0	\N	\N	f	0	\N
9801	72	113	\N	0	\N	\N	f	0	\N
9802	72	112	\N	0	\N	\N	f	0	\N
9803	72	111	\N	0	\N	\N	f	0	\N
9804	72	110	\N	0	\N	\N	f	0	\N
9805	72	432	\N	0	\N	\N	f	0	\N
9806	72	431	\N	0	\N	\N	f	0	\N
9807	72	430	\N	0	\N	\N	f	0	\N
9808	72	429	\N	0	\N	\N	f	0	\N
9809	72	428	\N	0	\N	\N	f	0	\N
9810	72	427	\N	0	\N	\N	f	0	\N
9811	72	426	\N	0	\N	\N	f	0	\N
9812	72	425	\N	0	\N	\N	f	0	\N
9813	72	424	\N	0	\N	\N	f	0	\N
9814	72	423	\N	0	\N	\N	f	0	\N
9815	72	422	\N	0	\N	\N	f	0	\N
9816	72	421	\N	0	\N	\N	f	0	\N
9817	72	420	\N	0	\N	\N	f	0	\N
9818	72	419	\N	0	\N	\N	f	0	\N
9819	72	418	\N	0	\N	\N	f	0	\N
9820	72	417	\N	0	\N	\N	f	0	\N
9821	72	416	\N	0	\N	\N	f	0	\N
9822	72	415	\N	0	\N	\N	f	0	\N
9823	72	414	\N	0	\N	\N	f	0	\N
9824	72	413	\N	0	\N	\N	f	0	\N
9825	72	412	\N	0	\N	\N	f	0	\N
9826	72	411	\N	0	\N	\N	f	0	\N
9827	72	410	\N	0	\N	\N	f	0	\N
9828	72	409	\N	0	\N	\N	f	0	\N
9829	72	408	\N	0	\N	\N	f	0	\N
9830	72	407	\N	0	\N	\N	f	0	\N
9831	72	406	\N	0	\N	\N	f	0	\N
9832	72	405	\N	0	\N	\N	f	0	\N
9833	72	404	\N	0	\N	\N	f	0	\N
9834	72	403	\N	0	\N	\N	f	0	\N
9835	72	402	\N	0	\N	\N	f	0	\N
9836	72	180	\N	0	\N	\N	f	0	\N
9837	72	179	\N	0	\N	\N	f	0	\N
9838	72	178	\N	0	\N	\N	f	0	\N
9839	72	177	\N	0	\N	\N	f	0	\N
9840	72	176	\N	0	\N	\N	f	0	\N
9841	72	175	\N	0	\N	\N	f	0	\N
9842	72	174	\N	0	\N	\N	f	0	\N
9843	72	173	\N	0	\N	\N	f	0	\N
9844	72	172	\N	0	\N	\N	f	0	\N
9845	72	171	\N	0	\N	\N	f	0	\N
9846	72	170	\N	0	\N	\N	f	0	\N
9847	72	169	\N	0	\N	\N	f	0	\N
9848	72	168	\N	0	\N	\N	f	0	\N
9849	72	167	\N	0	\N	\N	f	0	\N
9850	72	166	\N	0	\N	\N	f	0	\N
9851	72	165	\N	0	\N	\N	f	0	\N
9852	72	164	\N	0	\N	\N	f	0	\N
9853	72	163	\N	0	\N	\N	f	0	\N
9854	72	162	\N	0	\N	\N	f	0	\N
9855	72	161	\N	0	\N	\N	f	0	\N
9856	72	160	\N	0	\N	\N	f	0	\N
9857	72	159	\N	0	\N	\N	f	0	\N
9858	72	158	\N	0	\N	\N	f	0	\N
9859	72	157	\N	0	\N	\N	f	0	\N
9860	72	156	\N	0	\N	\N	f	0	\N
9861	72	155	\N	0	\N	\N	f	0	\N
9862	72	154	\N	0	\N	\N	f	0	\N
9863	72	153	\N	0	\N	\N	f	0	\N
9864	72	152	\N	0	\N	\N	f	0	\N
9865	72	151	\N	0	\N	\N	f	0	\N
9866	72	150	\N	0	\N	\N	f	0	\N
9867	72	149	\N	0	\N	\N	f	0	\N
9868	72	148	\N	0	\N	\N	f	0	\N
9869	72	147	\N	0	\N	\N	f	0	\N
9870	72	146	\N	0	\N	\N	f	0	\N
9871	73	109	\N	0	\N	\N	f	0	\N
9872	73	108	\N	0	\N	\N	f	0	\N
9873	73	107	\N	0	\N	\N	f	0	\N
9874	73	106	\N	0	\N	\N	f	0	\N
9875	73	105	\N	0	\N	\N	f	0	\N
9876	73	104	\N	0	\N	\N	f	0	\N
9877	73	103	\N	0	\N	\N	f	0	\N
9878	73	102	\N	0	\N	\N	f	0	\N
9879	73	101	\N	0	\N	\N	f	0	\N
9880	73	100	\N	0	\N	\N	f	0	\N
9881	73	99	\N	0	\N	\N	f	0	\N
9882	73	98	\N	0	\N	\N	f	0	\N
9883	73	97	\N	0	\N	\N	f	0	\N
9884	73	96	\N	0	\N	\N	f	0	\N
9885	73	95	\N	0	\N	\N	f	0	\N
9886	73	94	\N	0	\N	\N	f	0	\N
9887	73	93	\N	0	\N	\N	f	0	\N
9888	73	92	\N	0	\N	\N	f	0	\N
9889	73	91	\N	0	\N	\N	f	0	\N
9890	73	90	\N	0	\N	\N	f	0	\N
9891	73	89	\N	0	\N	\N	f	0	\N
9892	73	88	\N	0	\N	\N	f	0	\N
9893	73	87	\N	0	\N	\N	f	0	\N
9894	73	86	\N	0	\N	\N	f	0	\N
9895	73	85	\N	0	\N	\N	f	0	\N
9896	73	84	\N	0	\N	\N	f	0	\N
9897	73	83	\N	0	\N	\N	f	0	\N
9898	73	82	\N	0	\N	\N	f	0	\N
9899	73	81	\N	0	\N	\N	f	0	\N
9900	73	80	\N	0	\N	\N	f	0	\N
9901	73	79	\N	0	\N	\N	f	0	\N
9902	73	78	\N	0	\N	\N	f	0	\N
9903	73	77	\N	0	\N	\N	f	0	\N
9904	73	76	\N	0	\N	\N	f	0	\N
9905	73	75	\N	0	\N	\N	f	0	\N
9906	73	290	\N	0	\N	\N	f	0	\N
9907	73	289	\N	0	\N	\N	f	0	\N
9908	73	288	\N	0	\N	\N	f	0	\N
9909	73	287	\N	0	\N	\N	f	0	\N
9910	73	286	\N	0	\N	\N	f	0	\N
9911	73	285	\N	0	\N	\N	f	0	\N
9912	73	284	\N	0	\N	\N	f	0	\N
9913	73	283	\N	0	\N	\N	f	0	\N
9914	73	282	\N	0	\N	\N	f	0	\N
9915	73	281	\N	0	\N	\N	f	0	\N
9916	73	280	\N	0	\N	\N	f	0	\N
9917	73	279	\N	0	\N	\N	f	0	\N
9918	73	278	\N	0	\N	\N	f	0	\N
9919	73	277	\N	0	\N	\N	f	0	\N
9920	73	276	\N	0	\N	\N	f	0	\N
9921	73	275	\N	0	\N	\N	f	0	\N
9922	73	274	\N	0	\N	\N	f	0	\N
9923	73	273	\N	0	\N	\N	f	0	\N
9924	73	272	\N	0	\N	\N	f	0	\N
9925	73	271	\N	0	\N	\N	f	0	\N
9926	73	270	\N	0	\N	\N	f	0	\N
9927	73	269	\N	0	\N	\N	f	0	\N
9928	73	268	\N	0	\N	\N	f	0	\N
9929	73	267	\N	0	\N	\N	f	0	\N
9930	73	266	\N	0	\N	\N	f	0	\N
9931	73	265	\N	0	\N	\N	f	0	\N
9932	73	264	\N	0	\N	\N	f	0	\N
9933	73	263	\N	0	\N	\N	f	0	\N
9934	73	262	\N	0	\N	\N	f	0	\N
9935	73	261	\N	0	\N	\N	f	0	\N
9936	73	260	\N	0	\N	\N	f	0	\N
9937	73	259	\N	0	\N	\N	f	0	\N
9938	73	258	\N	0	\N	\N	f	0	\N
9939	73	257	\N	0	\N	\N	f	0	\N
9940	73	256	\N	0	\N	\N	f	0	\N
9941	73	255	\N	0	\N	\N	f	0	\N
9942	73	74	\N	0	\N	\N	f	0	\N
9943	73	73	\N	0	\N	\N	f	0	\N
9944	73	72	\N	0	\N	\N	f	0	\N
9945	73	71	\N	0	\N	\N	f	0	\N
9946	73	70	\N	0	\N	\N	f	0	\N
9947	73	69	\N	0	\N	\N	f	0	\N
9948	73	68	\N	0	\N	\N	f	0	\N
9949	73	67	\N	0	\N	\N	f	0	\N
9950	73	66	\N	0	\N	\N	f	0	\N
9951	73	65	\N	0	\N	\N	f	0	\N
9952	73	64	\N	0	\N	\N	f	0	\N
9953	73	63	\N	0	\N	\N	f	0	\N
9954	73	62	\N	0	\N	\N	f	0	\N
9955	73	61	\N	0	\N	\N	f	0	\N
9956	73	60	\N	0	\N	\N	f	0	\N
9957	73	59	\N	0	\N	\N	f	0	\N
9958	73	58	\N	0	\N	\N	f	0	\N
9959	73	57	\N	0	\N	\N	f	0	\N
9960	73	56	\N	0	\N	\N	f	0	\N
9961	73	55	\N	0	\N	\N	f	0	\N
9962	73	54	\N	0	\N	\N	f	0	\N
9963	73	53	\N	0	\N	\N	f	0	\N
9964	73	52	\N	0	\N	\N	f	0	\N
9965	73	51	\N	0	\N	\N	f	0	\N
9966	73	50	\N	0	\N	\N	f	0	\N
9967	73	49	\N	0	\N	\N	f	0	\N
9968	73	48	\N	0	\N	\N	f	0	\N
9969	73	47	\N	0	\N	\N	f	0	\N
9970	73	46	\N	0	\N	\N	f	0	\N
9971	73	45	\N	0	\N	\N	f	0	\N
9972	73	44	\N	0	\N	\N	f	0	\N
9973	73	43	\N	0	\N	\N	f	0	\N
9974	73	42	\N	0	\N	\N	f	0	\N
9975	73	41	\N	0	\N	\N	f	0	\N
9976	73	40	\N	0	\N	\N	f	0	\N
9977	73	39	\N	0	\N	\N	f	0	\N
9978	73	38	\N	0	\N	\N	f	0	\N
9979	73	37	\N	0	\N	\N	f	0	\N
9980	73	36	\N	0	\N	\N	f	0	\N
9981	73	35	\N	0	\N	\N	f	0	\N
9982	73	34	\N	0	\N	\N	f	0	\N
9983	73	33	\N	0	\N	\N	f	0	\N
9984	73	32	\N	0	\N	\N	f	0	\N
9985	73	31	\N	0	\N	\N	f	0	\N
9986	73	30	\N	0	\N	\N	f	0	\N
9987	73	29	\N	0	\N	\N	f	0	\N
9988	73	28	\N	0	\N	\N	f	0	\N
9989	73	27	\N	0	\N	\N	f	0	\N
9990	73	26	\N	0	\N	\N	f	0	\N
9991	73	25	\N	0	\N	\N	f	0	\N
9992	73	24	\N	0	\N	\N	f	0	\N
9993	73	23	\N	0	\N	\N	f	0	\N
9994	73	22	\N	0	\N	\N	f	0	\N
9995	73	21	\N	0	\N	\N	f	0	\N
9996	73	20	\N	0	\N	\N	f	0	\N
9997	73	19	\N	0	\N	\N	f	0	\N
9998	73	18	\N	0	\N	\N	f	0	\N
9999	73	17	\N	0	\N	\N	f	0	\N
10000	73	16	\N	0	\N	\N	f	0	\N
10001	73	15	\N	0	\N	\N	f	0	\N
10002	73	14	\N	0	\N	\N	f	0	\N
10003	73	13	\N	0	\N	\N	f	0	\N
10004	73	12	\N	0	\N	\N	f	0	\N
10005	73	11	\N	0	\N	\N	f	0	\N
10006	73	10	\N	0	\N	\N	f	0	\N
10007	73	9	\N	0	\N	\N	f	0	\N
10008	73	8	\N	0	\N	\N	f	0	\N
10009	73	7	\N	0	\N	\N	f	0	\N
10010	73	6	\N	0	\N	\N	f	0	\N
10011	73	5	\N	0	\N	\N	f	0	\N
10012	73	4	\N	0	\N	\N	f	0	\N
10013	73	3	\N	0	\N	\N	f	0	\N
10014	73	2	\N	0	\N	\N	f	0	\N
10015	73	1	\N	0	\N	\N	f	0	\N
10016	73	360	\N	0	\N	\N	f	0	\N
10017	73	359	\N	0	\N	\N	f	0	\N
10018	73	358	\N	0	\N	\N	f	0	\N
10019	73	357	\N	0	\N	\N	f	0	\N
10020	73	356	\N	0	\N	\N	f	0	\N
10021	73	355	\N	0	\N	\N	f	0	\N
10022	73	354	\N	0	\N	\N	f	0	\N
10023	73	353	\N	0	\N	\N	f	0	\N
10024	73	352	\N	0	\N	\N	f	0	\N
10025	73	351	\N	0	\N	\N	f	0	\N
10026	73	350	\N	0	\N	\N	f	0	\N
10027	73	349	\N	0	\N	\N	f	0	\N
10028	73	348	\N	0	\N	\N	f	0	\N
10029	73	347	\N	0	\N	\N	f	0	\N
10030	73	346	\N	0	\N	\N	f	0	\N
10031	73	345	\N	0	\N	\N	f	0	\N
10032	73	344	\N	0	\N	\N	f	0	\N
10033	73	343	\N	0	\N	\N	f	0	\N
10034	73	342	\N	0	\N	\N	f	0	\N
10035	73	341	\N	0	\N	\N	f	0	\N
10036	73	340	\N	0	\N	\N	f	0	\N
10037	73	339	\N	0	\N	\N	f	0	\N
10038	73	338	\N	0	\N	\N	f	0	\N
10039	73	337	\N	0	\N	\N	f	0	\N
10040	73	336	\N	0	\N	\N	f	0	\N
10041	73	335	\N	0	\N	\N	f	0	\N
10042	73	334	\N	0	\N	\N	f	0	\N
10043	73	333	\N	0	\N	\N	f	0	\N
10044	73	332	\N	0	\N	\N	f	0	\N
10045	73	331	\N	0	\N	\N	f	0	\N
10046	73	330	\N	0	\N	\N	f	0	\N
10047	73	329	\N	0	\N	\N	f	0	\N
10048	73	328	\N	0	\N	\N	f	0	\N
10049	73	327	\N	0	\N	\N	f	0	\N
10050	73	326	\N	0	\N	\N	f	0	\N
10051	73	325	\N	0	\N	\N	f	0	\N
10052	73	324	\N	0	\N	\N	f	0	\N
10053	73	323	\N	0	\N	\N	f	0	\N
10054	73	322	\N	0	\N	\N	f	0	\N
10055	73	321	\N	0	\N	\N	f	0	\N
10056	73	320	\N	0	\N	\N	f	0	\N
10057	73	319	\N	0	\N	\N	f	0	\N
10058	73	318	\N	0	\N	\N	f	0	\N
10059	73	317	\N	0	\N	\N	f	0	\N
10060	73	316	\N	0	\N	\N	f	0	\N
10061	73	315	\N	0	\N	\N	f	0	\N
10062	73	314	\N	0	\N	\N	f	0	\N
10063	73	313	\N	0	\N	\N	f	0	\N
10064	73	312	\N	0	\N	\N	f	0	\N
10065	73	311	\N	0	\N	\N	f	0	\N
10066	73	310	\N	0	\N	\N	f	0	\N
10067	73	309	\N	0	\N	\N	f	0	\N
10068	73	308	\N	0	\N	\N	f	0	\N
10069	73	307	\N	0	\N	\N	f	0	\N
10070	73	306	\N	0	\N	\N	f	0	\N
10071	73	305	\N	0	\N	\N	f	0	\N
10072	73	304	\N	0	\N	\N	f	0	\N
10073	73	303	\N	0	\N	\N	f	0	\N
10074	73	302	\N	0	\N	\N	f	0	\N
10075	73	301	\N	0	\N	\N	f	0	\N
10076	73	300	\N	0	\N	\N	f	0	\N
10077	73	299	\N	0	\N	\N	f	0	\N
10078	73	298	\N	0	\N	\N	f	0	\N
10079	73	297	\N	0	\N	\N	f	0	\N
10080	73	296	\N	0	\N	\N	f	0	\N
10081	73	295	\N	0	\N	\N	f	0	\N
10082	73	294	\N	0	\N	\N	f	0	\N
10083	73	293	\N	0	\N	\N	f	0	\N
10084	73	292	\N	0	\N	\N	f	0	\N
10085	73	291	\N	0	\N	\N	f	0	\N
10086	73	432	\N	0	\N	\N	f	0	\N
10087	73	431	\N	0	\N	\N	f	0	\N
10088	73	430	\N	0	\N	\N	f	0	\N
10089	73	429	\N	0	\N	\N	f	0	\N
10090	73	428	\N	0	\N	\N	f	0	\N
10091	73	427	\N	0	\N	\N	f	0	\N
10092	73	426	\N	0	\N	\N	f	0	\N
10093	73	425	\N	0	\N	\N	f	0	\N
10094	73	424	\N	0	\N	\N	f	0	\N
10095	73	423	\N	0	\N	\N	f	0	\N
10096	73	422	\N	0	\N	\N	f	0	\N
10097	73	421	\N	0	\N	\N	f	0	\N
10098	73	420	\N	0	\N	\N	f	0	\N
10099	73	419	\N	0	\N	\N	f	0	\N
10100	73	418	\N	0	\N	\N	f	0	\N
10101	73	417	\N	0	\N	\N	f	0	\N
10102	73	416	\N	0	\N	\N	f	0	\N
10103	73	415	\N	0	\N	\N	f	0	\N
10104	73	414	\N	0	\N	\N	f	0	\N
10105	73	413	\N	0	\N	\N	f	0	\N
10106	73	412	\N	0	\N	\N	f	0	\N
10107	73	411	\N	0	\N	\N	f	0	\N
10108	73	410	\N	0	\N	\N	f	0	\N
10109	73	409	\N	0	\N	\N	f	0	\N
10110	73	408	\N	0	\N	\N	f	0	\N
10111	73	407	\N	0	\N	\N	f	0	\N
10112	73	406	\N	0	\N	\N	f	0	\N
10113	73	405	\N	0	\N	\N	f	0	\N
10114	73	404	\N	0	\N	\N	f	0	\N
10115	73	403	\N	0	\N	\N	f	0	\N
10116	73	402	\N	0	\N	\N	f	0	\N
10117	73	254	\N	0	\N	\N	f	0	\N
10118	73	253	\N	0	\N	\N	f	0	\N
10119	73	252	\N	0	\N	\N	f	0	\N
10120	73	251	\N	0	\N	\N	f	0	\N
10121	73	250	\N	0	\N	\N	f	0	\N
10122	73	249	\N	0	\N	\N	f	0	\N
10123	73	248	\N	0	\N	\N	f	0	\N
10124	73	247	\N	0	\N	\N	f	0	\N
10125	73	246	\N	0	\N	\N	f	0	\N
10126	73	245	\N	0	\N	\N	f	0	\N
10127	73	244	\N	0	\N	\N	f	0	\N
10128	73	243	\N	0	\N	\N	f	0	\N
10129	73	242	\N	0	\N	\N	f	0	\N
10130	73	241	\N	0	\N	\N	f	0	\N
10131	73	240	\N	0	\N	\N	f	0	\N
10132	73	239	\N	0	\N	\N	f	0	\N
10133	73	238	\N	0	\N	\N	f	0	\N
10134	73	237	\N	0	\N	\N	f	0	\N
10135	73	236	\N	0	\N	\N	f	0	\N
10136	73	235	\N	0	\N	\N	f	0	\N
10137	73	234	\N	0	\N	\N	f	0	\N
10138	73	233	\N	0	\N	\N	f	0	\N
10139	73	232	\N	0	\N	\N	f	0	\N
10140	73	231	\N	0	\N	\N	f	0	\N
10141	73	230	\N	0	\N	\N	f	0	\N
10142	73	229	\N	0	\N	\N	f	0	\N
10143	73	228	\N	0	\N	\N	f	0	\N
10144	73	227	\N	0	\N	\N	f	0	\N
10145	73	226	\N	0	\N	\N	f	0	\N
10146	73	225	\N	0	\N	\N	f	0	\N
10147	73	224	\N	0	\N	\N	f	0	\N
10148	73	223	\N	0	\N	\N	f	0	\N
10149	73	222	\N	0	\N	\N	f	0	\N
10150	73	221	\N	0	\N	\N	f	0	\N
10151	73	220	\N	0	\N	\N	f	0	\N
10152	73	219	\N	0	\N	\N	f	0	\N
10153	73	180	\N	0	\N	\N	f	0	\N
10154	73	179	\N	0	\N	\N	f	0	\N
10155	73	178	\N	0	\N	\N	f	0	\N
10156	73	177	\N	0	\N	\N	f	0	\N
10157	73	176	\N	0	\N	\N	f	0	\N
10158	73	175	\N	0	\N	\N	f	0	\N
10159	73	174	\N	0	\N	\N	f	0	\N
10160	73	173	\N	0	\N	\N	f	0	\N
10161	73	172	\N	0	\N	\N	f	0	\N
10162	73	171	\N	0	\N	\N	f	0	\N
10163	73	170	\N	0	\N	\N	f	0	\N
10164	73	169	\N	0	\N	\N	f	0	\N
10165	73	168	\N	0	\N	\N	f	0	\N
10166	73	167	\N	0	\N	\N	f	0	\N
10167	73	166	\N	0	\N	\N	f	0	\N
10168	73	165	\N	0	\N	\N	f	0	\N
10169	73	164	\N	0	\N	\N	f	0	\N
10170	73	163	\N	0	\N	\N	f	0	\N
10171	73	162	\N	0	\N	\N	f	0	\N
10172	73	161	\N	0	\N	\N	f	0	\N
10173	73	160	\N	0	\N	\N	f	0	\N
10174	73	159	\N	0	\N	\N	f	0	\N
10175	73	158	\N	0	\N	\N	f	0	\N
10176	73	157	\N	0	\N	\N	f	0	\N
10177	73	156	\N	0	\N	\N	f	0	\N
10178	73	155	\N	0	\N	\N	f	0	\N
10179	73	154	\N	0	\N	\N	f	0	\N
10180	73	153	\N	0	\N	\N	f	0	\N
10181	73	152	\N	0	\N	\N	f	0	\N
10182	73	151	\N	0	\N	\N	f	0	\N
10183	73	150	\N	0	\N	\N	f	0	\N
10184	73	149	\N	0	\N	\N	f	0	\N
10185	73	148	\N	0	\N	\N	f	0	\N
10186	73	147	\N	0	\N	\N	f	0	\N
10187	73	146	\N	0	\N	\N	f	0	\N
10188	73	145	\N	0	\N	\N	f	0	\N
10189	73	144	\N	0	\N	\N	f	0	\N
10190	73	143	\N	0	\N	\N	f	0	\N
10191	73	142	\N	0	\N	\N	f	0	\N
10192	73	141	\N	0	\N	\N	f	0	\N
10193	73	140	\N	0	\N	\N	f	0	\N
10194	73	139	\N	0	\N	\N	f	0	\N
10195	73	138	\N	0	\N	\N	f	0	\N
10196	73	137	\N	0	\N	\N	f	0	\N
10197	73	136	\N	0	\N	\N	f	0	\N
10198	73	135	\N	0	\N	\N	f	0	\N
10199	73	134	\N	0	\N	\N	f	0	\N
10200	73	133	\N	0	\N	\N	f	0	\N
10201	73	132	\N	0	\N	\N	f	0	\N
10202	73	131	\N	0	\N	\N	f	0	\N
10203	73	130	\N	0	\N	\N	f	0	\N
10204	73	129	\N	0	\N	\N	f	0	\N
10205	73	128	\N	0	\N	\N	f	0	\N
10206	73	127	\N	0	\N	\N	f	0	\N
10207	73	126	\N	0	\N	\N	f	0	\N
10208	73	125	\N	0	\N	\N	f	0	\N
10209	73	124	\N	0	\N	\N	f	0	\N
10210	73	123	\N	0	\N	\N	f	0	\N
10211	73	122	\N	0	\N	\N	f	0	\N
10212	73	121	\N	0	\N	\N	f	0	\N
10213	73	120	\N	0	\N	\N	f	0	\N
10214	73	119	\N	0	\N	\N	f	0	\N
10215	73	118	\N	0	\N	\N	f	0	\N
10216	73	117	\N	0	\N	\N	f	0	\N
10217	73	116	\N	0	\N	\N	f	0	\N
10218	73	115	\N	0	\N	\N	f	0	\N
10219	73	114	\N	0	\N	\N	f	0	\N
10220	73	113	\N	0	\N	\N	f	0	\N
10221	73	112	\N	0	\N	\N	f	0	\N
10222	73	111	\N	0	\N	\N	f	0	\N
10223	73	110	\N	0	\N	\N	f	0	\N
10224	73	218	\N	0	\N	\N	f	0	\N
10225	73	217	\N	0	\N	\N	f	0	\N
10226	73	216	\N	0	\N	\N	f	0	\N
10227	73	215	\N	0	\N	\N	f	0	\N
10228	73	214	\N	0	\N	\N	f	0	\N
10229	73	213	\N	0	\N	\N	f	0	\N
10230	73	212	\N	0	\N	\N	f	0	\N
10231	73	211	\N	0	\N	\N	f	0	\N
10232	73	210	\N	0	\N	\N	f	0	\N
10233	73	209	\N	0	\N	\N	f	0	\N
10234	73	208	\N	0	\N	\N	f	0	\N
10235	73	207	\N	0	\N	\N	f	0	\N
10236	73	206	\N	0	\N	\N	f	0	\N
10237	73	205	\N	0	\N	\N	f	0	\N
10238	73	204	\N	0	\N	\N	f	0	\N
10239	73	203	\N	0	\N	\N	f	0	\N
10240	73	202	\N	0	\N	\N	f	0	\N
10241	73	201	\N	0	\N	\N	f	0	\N
10242	73	200	\N	0	\N	\N	f	0	\N
10243	73	199	\N	0	\N	\N	f	0	\N
10244	73	198	\N	0	\N	\N	f	0	\N
10245	73	197	\N	0	\N	\N	f	0	\N
10246	73	196	\N	0	\N	\N	f	0	\N
10247	73	195	\N	0	\N	\N	f	0	\N
10248	73	194	\N	0	\N	\N	f	0	\N
10249	73	193	\N	0	\N	\N	f	0	\N
10250	73	192	\N	0	\N	\N	f	0	\N
10251	73	191	\N	0	\N	\N	f	0	\N
10252	73	190	\N	0	\N	\N	f	0	\N
10253	73	189	\N	0	\N	\N	f	0	\N
10254	73	188	\N	0	\N	\N	f	0	\N
10255	73	187	\N	0	\N	\N	f	0	\N
10256	73	186	\N	0	\N	\N	f	0	\N
10257	73	185	\N	0	\N	\N	f	0	\N
10258	73	184	\N	0	\N	\N	f	0	\N
10259	73	183	\N	0	\N	\N	f	0	\N
10260	73	182	\N	0	\N	\N	f	0	\N
10261	73	181	\N	0	\N	\N	f	0	\N
10262	73	401	\N	0	\N	\N	f	0	\N
10263	73	400	\N	0	\N	\N	f	0	\N
10264	73	399	\N	0	\N	\N	f	0	\N
10265	73	398	\N	0	\N	\N	f	0	\N
10266	73	397	\N	0	\N	\N	f	0	\N
10267	73	396	\N	0	\N	\N	f	0	\N
10268	73	395	\N	0	\N	\N	f	0	\N
10269	73	394	\N	0	\N	\N	f	0	\N
10270	73	393	\N	0	\N	\N	f	0	\N
10271	73	392	\N	0	\N	\N	f	0	\N
10272	73	391	\N	0	\N	\N	f	0	\N
10273	73	390	\N	0	\N	\N	f	0	\N
10274	73	389	\N	0	\N	\N	f	0	\N
10275	73	388	\N	0	\N	\N	f	0	\N
10276	73	387	\N	0	\N	\N	f	0	\N
10277	73	386	\N	0	\N	\N	f	0	\N
10278	73	385	\N	0	\N	\N	f	0	\N
10279	73	384	\N	0	\N	\N	f	0	\N
10280	73	383	\N	0	\N	\N	f	0	\N
10281	73	382	\N	0	\N	\N	f	0	\N
10282	73	381	\N	0	\N	\N	f	0	\N
10283	73	380	\N	0	\N	\N	f	0	\N
10284	73	379	\N	0	\N	\N	f	0	\N
10285	73	378	\N	0	\N	\N	f	0	\N
10286	73	377	\N	0	\N	\N	f	0	\N
10287	73	376	\N	0	\N	\N	f	0	\N
10288	73	375	\N	0	\N	\N	f	0	\N
10289	73	374	\N	0	\N	\N	f	0	\N
10290	73	373	\N	0	\N	\N	f	0	\N
10291	73	372	\N	0	\N	\N	f	0	\N
10292	73	371	\N	0	\N	\N	f	0	\N
10293	73	370	\N	0	\N	\N	f	0	\N
10294	73	369	\N	0	\N	\N	f	0	\N
10295	73	368	\N	0	\N	\N	f	0	\N
10296	73	367	\N	0	\N	\N	f	0	\N
10297	73	366	\N	0	\N	\N	f	0	\N
10298	73	365	\N	0	\N	\N	f	0	\N
10299	73	364	\N	0	\N	\N	f	0	\N
10300	73	363	\N	0	\N	\N	f	0	\N
10301	73	362	\N	0	\N	\N	f	0	\N
10302	73	361	\N	0	\N	\N	f	0	\N
10303	74	290	\N	0	\N	\N	f	0	\N
10304	74	289	\N	0	\N	\N	f	0	\N
10305	74	288	\N	0	\N	\N	f	0	\N
10306	74	287	\N	0	\N	\N	f	0	\N
10307	74	286	\N	0	\N	\N	f	0	\N
10308	74	285	\N	0	\N	\N	f	0	\N
10309	74	284	\N	0	\N	\N	f	0	\N
10310	74	283	\N	0	\N	\N	f	0	\N
10311	74	282	\N	0	\N	\N	f	0	\N
10312	74	281	\N	0	\N	\N	f	0	\N
10313	74	280	\N	0	\N	\N	f	0	\N
10314	74	279	\N	0	\N	\N	f	0	\N
10315	74	278	\N	0	\N	\N	f	0	\N
10316	74	277	\N	0	\N	\N	f	0	\N
10317	74	276	\N	0	\N	\N	f	0	\N
10318	74	275	\N	0	\N	\N	f	0	\N
10319	74	274	\N	0	\N	\N	f	0	\N
10320	74	273	\N	0	\N	\N	f	0	\N
10321	74	272	\N	0	\N	\N	f	0	\N
10322	74	271	\N	0	\N	\N	f	0	\N
10323	74	270	\N	0	\N	\N	f	0	\N
10324	74	269	\N	0	\N	\N	f	0	\N
10325	74	268	\N	0	\N	\N	f	0	\N
10326	74	267	\N	0	\N	\N	f	0	\N
10327	74	266	\N	0	\N	\N	f	0	\N
10328	74	265	\N	0	\N	\N	f	0	\N
10329	74	264	\N	0	\N	\N	f	0	\N
10330	74	263	\N	0	\N	\N	f	0	\N
10331	74	262	\N	0	\N	\N	f	0	\N
10332	74	261	\N	0	\N	\N	f	0	\N
10333	74	260	\N	0	\N	\N	f	0	\N
10334	74	259	\N	0	\N	\N	f	0	\N
10335	74	258	\N	0	\N	\N	f	0	\N
10336	74	257	\N	0	\N	\N	f	0	\N
10337	74	256	\N	0	\N	\N	f	0	\N
10338	74	255	\N	0	\N	\N	f	0	\N
10339	74	39	\N	0	\N	\N	f	0	\N
10340	74	38	\N	0	\N	\N	f	0	\N
10341	74	37	\N	0	\N	\N	f	0	\N
10342	74	36	\N	0	\N	\N	f	0	\N
10343	74	35	\N	0	\N	\N	f	0	\N
10344	74	34	\N	0	\N	\N	f	0	\N
10345	74	33	\N	0	\N	\N	f	0	\N
10346	74	32	\N	0	\N	\N	f	0	\N
10347	74	31	\N	0	\N	\N	f	0	\N
10348	74	30	\N	0	\N	\N	f	0	\N
10349	74	29	\N	0	\N	\N	f	0	\N
10350	74	28	\N	0	\N	\N	f	0	\N
10351	74	27	\N	0	\N	\N	f	0	\N
10352	74	26	\N	0	\N	\N	f	0	\N
10353	74	25	\N	0	\N	\N	f	0	\N
10354	74	24	\N	0	\N	\N	f	0	\N
10355	74	23	\N	0	\N	\N	f	0	\N
10356	74	22	\N	0	\N	\N	f	0	\N
10357	74	21	\N	0	\N	\N	f	0	\N
10358	74	20	\N	0	\N	\N	f	0	\N
10359	74	19	\N	0	\N	\N	f	0	\N
10360	74	18	\N	0	\N	\N	f	0	\N
10361	74	17	\N	0	\N	\N	f	0	\N
10362	74	16	\N	0	\N	\N	f	0	\N
10363	74	15	\N	0	\N	\N	f	0	\N
10364	74	14	\N	0	\N	\N	f	0	\N
10365	74	13	\N	0	\N	\N	f	0	\N
10366	74	12	\N	0	\N	\N	f	0	\N
10367	74	11	\N	0	\N	\N	f	0	\N
10368	74	10	\N	0	\N	\N	f	0	\N
10369	74	9	\N	0	\N	\N	f	0	\N
10370	74	8	\N	0	\N	\N	f	0	\N
10371	74	7	\N	0	\N	\N	f	0	\N
10372	74	6	\N	0	\N	\N	f	0	\N
10373	74	5	\N	0	\N	\N	f	0	\N
10374	74	4	\N	0	\N	\N	f	0	\N
10375	74	3	\N	0	\N	\N	f	0	\N
10376	74	2	\N	0	\N	\N	f	0	\N
10377	74	1	\N	0	\N	\N	f	0	\N
10378	74	109	\N	0	\N	\N	f	0	\N
10379	74	108	\N	0	\N	\N	f	0	\N
10380	74	107	\N	0	\N	\N	f	0	\N
10381	74	106	\N	0	\N	\N	f	0	\N
10382	74	105	\N	0	\N	\N	f	0	\N
10383	74	104	\N	0	\N	\N	f	0	\N
10384	74	103	\N	0	\N	\N	f	0	\N
10385	74	102	\N	0	\N	\N	f	0	\N
10386	74	101	\N	0	\N	\N	f	0	\N
10387	74	100	\N	0	\N	\N	f	0	\N
10388	74	99	\N	0	\N	\N	f	0	\N
10389	74	98	\N	0	\N	\N	f	0	\N
10390	74	97	\N	0	\N	\N	f	0	\N
10391	74	96	\N	0	\N	\N	f	0	\N
10392	74	95	\N	0	\N	\N	f	0	\N
10393	74	94	\N	0	\N	\N	f	0	\N
10394	74	93	\N	0	\N	\N	f	0	\N
10395	74	92	\N	0	\N	\N	f	0	\N
10396	74	91	\N	0	\N	\N	f	0	\N
10397	74	90	\N	0	\N	\N	f	0	\N
10398	74	89	\N	0	\N	\N	f	0	\N
10399	74	88	\N	0	\N	\N	f	0	\N
10400	74	87	\N	0	\N	\N	f	0	\N
10401	74	86	\N	0	\N	\N	f	0	\N
10402	74	85	\N	0	\N	\N	f	0	\N
10403	74	84	\N	0	\N	\N	f	0	\N
10404	74	83	\N	0	\N	\N	f	0	\N
10405	74	82	\N	0	\N	\N	f	0	\N
10406	74	81	\N	0	\N	\N	f	0	\N
10407	74	80	\N	0	\N	\N	f	0	\N
10408	74	79	\N	0	\N	\N	f	0	\N
10409	74	78	\N	0	\N	\N	f	0	\N
10410	74	77	\N	0	\N	\N	f	0	\N
10411	74	76	\N	0	\N	\N	f	0	\N
10412	74	75	\N	0	\N	\N	f	0	\N
10413	74	74	\N	0	\N	\N	f	0	\N
10414	74	73	\N	0	\N	\N	f	0	\N
10415	74	72	\N	0	\N	\N	f	0	\N
10416	74	71	\N	0	\N	\N	f	0	\N
10417	74	70	\N	0	\N	\N	f	0	\N
10418	74	69	\N	0	\N	\N	f	0	\N
10419	74	68	\N	0	\N	\N	f	0	\N
10420	74	67	\N	0	\N	\N	f	0	\N
10421	74	66	\N	0	\N	\N	f	0	\N
10422	74	65	\N	0	\N	\N	f	0	\N
10423	74	64	\N	0	\N	\N	f	0	\N
10424	74	63	\N	0	\N	\N	f	0	\N
10425	74	62	\N	0	\N	\N	f	0	\N
10426	74	61	\N	0	\N	\N	f	0	\N
10427	74	60	\N	0	\N	\N	f	0	\N
10428	74	59	\N	0	\N	\N	f	0	\N
10429	74	58	\N	0	\N	\N	f	0	\N
10430	74	57	\N	0	\N	\N	f	0	\N
10431	74	56	\N	0	\N	\N	f	0	\N
10432	74	55	\N	0	\N	\N	f	0	\N
10433	74	54	\N	0	\N	\N	f	0	\N
10434	74	53	\N	0	\N	\N	f	0	\N
10435	74	52	\N	0	\N	\N	f	0	\N
10436	74	51	\N	0	\N	\N	f	0	\N
10437	74	50	\N	0	\N	\N	f	0	\N
10438	74	49	\N	0	\N	\N	f	0	\N
10439	74	48	\N	0	\N	\N	f	0	\N
10440	74	47	\N	0	\N	\N	f	0	\N
10441	74	46	\N	0	\N	\N	f	0	\N
10442	74	45	\N	0	\N	\N	f	0	\N
10443	74	44	\N	0	\N	\N	f	0	\N
10444	74	43	\N	0	\N	\N	f	0	\N
10445	74	42	\N	0	\N	\N	f	0	\N
10446	74	41	\N	0	\N	\N	f	0	\N
10447	74	40	\N	0	\N	\N	f	0	\N
10448	74	145	\N	0	\N	\N	f	0	\N
10449	74	144	\N	0	\N	\N	f	0	\N
10450	74	143	\N	0	\N	\N	f	0	\N
10451	74	142	\N	0	\N	\N	f	0	\N
10452	74	141	\N	0	\N	\N	f	0	\N
10453	74	140	\N	0	\N	\N	f	0	\N
10454	74	139	\N	0	\N	\N	f	0	\N
10455	74	138	\N	0	\N	\N	f	0	\N
10456	74	137	\N	0	\N	\N	f	0	\N
10457	74	136	\N	0	\N	\N	f	0	\N
10458	74	135	\N	0	\N	\N	f	0	\N
10459	74	134	\N	0	\N	\N	f	0	\N
10460	74	133	\N	0	\N	\N	f	0	\N
10461	74	132	\N	0	\N	\N	f	0	\N
10462	74	131	\N	0	\N	\N	f	0	\N
10463	74	130	\N	0	\N	\N	f	0	\N
10464	74	129	\N	0	\N	\N	f	0	\N
10465	74	128	\N	0	\N	\N	f	0	\N
10466	74	127	\N	0	\N	\N	f	0	\N
10467	74	126	\N	0	\N	\N	f	0	\N
10468	74	125	\N	0	\N	\N	f	0	\N
10469	74	124	\N	0	\N	\N	f	0	\N
10470	74	123	\N	0	\N	\N	f	0	\N
10471	74	122	\N	0	\N	\N	f	0	\N
10472	74	121	\N	0	\N	\N	f	0	\N
10473	74	120	\N	0	\N	\N	f	0	\N
10474	74	119	\N	0	\N	\N	f	0	\N
10475	74	118	\N	0	\N	\N	f	0	\N
10476	74	117	\N	0	\N	\N	f	0	\N
10477	74	116	\N	0	\N	\N	f	0	\N
10478	74	115	\N	0	\N	\N	f	0	\N
10479	74	114	\N	0	\N	\N	f	0	\N
10480	74	113	\N	0	\N	\N	f	0	\N
10481	74	112	\N	0	\N	\N	f	0	\N
10482	74	111	\N	0	\N	\N	f	0	\N
10483	74	110	\N	0	\N	\N	f	0	\N
10484	74	180	\N	0	\N	\N	f	0	\N
10485	74	179	\N	0	\N	\N	f	0	\N
10486	74	178	\N	0	\N	\N	f	0	\N
10487	74	177	\N	0	\N	\N	f	0	\N
10488	74	176	\N	0	\N	\N	f	0	\N
10489	74	175	\N	0	\N	\N	f	0	\N
10490	74	174	\N	0	\N	\N	f	0	\N
10491	74	173	\N	0	\N	\N	f	0	\N
10492	74	172	\N	0	\N	\N	f	0	\N
10493	74	171	\N	0	\N	\N	f	0	\N
10494	74	170	\N	0	\N	\N	f	0	\N
10495	74	169	\N	0	\N	\N	f	0	\N
10496	74	168	\N	0	\N	\N	f	0	\N
10497	74	167	\N	0	\N	\N	f	0	\N
10498	74	166	\N	0	\N	\N	f	0	\N
10499	74	165	\N	0	\N	\N	f	0	\N
10500	74	164	\N	0	\N	\N	f	0	\N
10501	74	163	\N	0	\N	\N	f	0	\N
10502	74	162	\N	0	\N	\N	f	0	\N
10503	74	161	\N	0	\N	\N	f	0	\N
10504	74	160	\N	0	\N	\N	f	0	\N
10505	74	159	\N	0	\N	\N	f	0	\N
10506	74	158	\N	0	\N	\N	f	0	\N
10507	74	157	\N	0	\N	\N	f	0	\N
10508	74	156	\N	0	\N	\N	f	0	\N
10509	74	155	\N	0	\N	\N	f	0	\N
10510	74	154	\N	0	\N	\N	f	0	\N
10511	74	153	\N	0	\N	\N	f	0	\N
10512	74	152	\N	0	\N	\N	f	0	\N
10513	74	151	\N	0	\N	\N	f	0	\N
10514	74	150	\N	0	\N	\N	f	0	\N
10515	74	149	\N	0	\N	\N	f	0	\N
10516	74	148	\N	0	\N	\N	f	0	\N
10517	74	147	\N	0	\N	\N	f	0	\N
10518	74	146	\N	0	\N	\N	f	0	\N
10519	74	323	\N	0	\N	\N	f	0	\N
10520	74	322	\N	0	\N	\N	f	0	\N
10521	74	321	\N	0	\N	\N	f	0	\N
10522	74	320	\N	0	\N	\N	f	0	\N
10523	74	319	\N	0	\N	\N	f	0	\N
10524	74	318	\N	0	\N	\N	f	0	\N
10525	74	317	\N	0	\N	\N	f	0	\N
10526	74	316	\N	0	\N	\N	f	0	\N
10527	74	315	\N	0	\N	\N	f	0	\N
10528	74	314	\N	0	\N	\N	f	0	\N
10529	74	313	\N	0	\N	\N	f	0	\N
10530	74	312	\N	0	\N	\N	f	0	\N
10531	74	311	\N	0	\N	\N	f	0	\N
10532	74	310	\N	0	\N	\N	f	0	\N
10533	74	309	\N	0	\N	\N	f	0	\N
10534	74	308	\N	0	\N	\N	f	0	\N
10535	74	307	\N	0	\N	\N	f	0	\N
10536	74	306	\N	0	\N	\N	f	0	\N
10537	74	305	\N	0	\N	\N	f	0	\N
10538	74	304	\N	0	\N	\N	f	0	\N
10539	74	303	\N	0	\N	\N	f	0	\N
10540	74	302	\N	0	\N	\N	f	0	\N
10541	74	301	\N	0	\N	\N	f	0	\N
10542	74	300	\N	0	\N	\N	f	0	\N
10543	74	299	\N	0	\N	\N	f	0	\N
10544	74	298	\N	0	\N	\N	f	0	\N
10545	74	297	\N	0	\N	\N	f	0	\N
10546	74	296	\N	0	\N	\N	f	0	\N
10547	74	295	\N	0	\N	\N	f	0	\N
10548	74	294	\N	0	\N	\N	f	0	\N
10549	74	293	\N	0	\N	\N	f	0	\N
10550	74	292	\N	0	\N	\N	f	0	\N
10551	74	291	\N	0	\N	\N	f	0	\N
10552	74	254	\N	0	\N	\N	f	0	\N
10553	74	253	\N	0	\N	\N	f	0	\N
10554	74	252	\N	0	\N	\N	f	0	\N
10555	74	251	\N	0	\N	\N	f	0	\N
10556	74	250	\N	0	\N	\N	f	0	\N
10557	74	249	\N	0	\N	\N	f	0	\N
10558	74	248	\N	0	\N	\N	f	0	\N
10559	74	247	\N	0	\N	\N	f	0	\N
10560	74	246	\N	0	\N	\N	f	0	\N
10561	74	245	\N	0	\N	\N	f	0	\N
10562	74	244	\N	0	\N	\N	f	0	\N
10563	74	243	\N	0	\N	\N	f	0	\N
10564	74	242	\N	0	\N	\N	f	0	\N
10565	74	241	\N	0	\N	\N	f	0	\N
10566	74	240	\N	0	\N	\N	f	0	\N
10567	74	239	\N	0	\N	\N	f	0	\N
10568	74	238	\N	0	\N	\N	f	0	\N
10569	74	237	\N	0	\N	\N	f	0	\N
10570	74	236	\N	0	\N	\N	f	0	\N
10571	74	235	\N	0	\N	\N	f	0	\N
10572	74	234	\N	0	\N	\N	f	0	\N
10573	74	233	\N	0	\N	\N	f	0	\N
10574	74	232	\N	0	\N	\N	f	0	\N
10575	74	231	\N	0	\N	\N	f	0	\N
10576	74	230	\N	0	\N	\N	f	0	\N
10577	74	229	\N	0	\N	\N	f	0	\N
10578	74	228	\N	0	\N	\N	f	0	\N
10579	74	227	\N	0	\N	\N	f	0	\N
10580	74	226	\N	0	\N	\N	f	0	\N
10581	74	225	\N	0	\N	\N	f	0	\N
10582	74	224	\N	0	\N	\N	f	0	\N
10583	74	223	\N	0	\N	\N	f	0	\N
10584	74	222	\N	0	\N	\N	f	0	\N
10585	74	221	\N	0	\N	\N	f	0	\N
10586	74	220	\N	0	\N	\N	f	0	\N
10587	74	219	\N	0	\N	\N	f	0	\N
10588	74	432	\N	0	\N	\N	f	0	\N
10589	74	431	\N	0	\N	\N	f	0	\N
10590	74	430	\N	0	\N	\N	f	0	\N
10591	74	429	\N	0	\N	\N	f	0	\N
10592	74	428	\N	0	\N	\N	f	0	\N
10593	74	427	\N	0	\N	\N	f	0	\N
10594	74	426	\N	0	\N	\N	f	0	\N
10595	74	425	\N	0	\N	\N	f	0	\N
10596	74	424	\N	0	\N	\N	f	0	\N
10597	74	423	\N	0	\N	\N	f	0	\N
10598	74	422	\N	0	\N	\N	f	0	\N
10599	74	421	\N	0	\N	\N	f	0	\N
10600	74	420	\N	0	\N	\N	f	0	\N
10601	74	419	\N	0	\N	\N	f	0	\N
10602	74	418	\N	0	\N	\N	f	0	\N
10603	74	417	\N	0	\N	\N	f	0	\N
10604	74	416	\N	0	\N	\N	f	0	\N
10605	74	415	\N	0	\N	\N	f	0	\N
10606	74	414	\N	0	\N	\N	f	0	\N
10607	74	413	\N	0	\N	\N	f	0	\N
10608	74	412	\N	0	\N	\N	f	0	\N
10609	74	411	\N	0	\N	\N	f	0	\N
10610	74	410	\N	0	\N	\N	f	0	\N
10611	74	409	\N	0	\N	\N	f	0	\N
10612	74	408	\N	0	\N	\N	f	0	\N
10613	74	407	\N	0	\N	\N	f	0	\N
10614	74	406	\N	0	\N	\N	f	0	\N
10615	74	405	\N	0	\N	\N	f	0	\N
10616	74	404	\N	0	\N	\N	f	0	\N
10617	74	403	\N	0	\N	\N	f	0	\N
10618	74	402	\N	0	\N	\N	f	0	\N
10619	74	401	\N	0	\N	\N	f	0	\N
10620	74	400	\N	0	\N	\N	f	0	\N
10621	74	399	\N	0	\N	\N	f	0	\N
10622	74	398	\N	0	\N	\N	f	0	\N
10623	74	397	\N	0	\N	\N	f	0	\N
10624	74	396	\N	0	\N	\N	f	0	\N
10625	74	395	\N	0	\N	\N	f	0	\N
10626	74	394	\N	0	\N	\N	f	0	\N
10627	74	393	\N	0	\N	\N	f	0	\N
10628	74	392	\N	0	\N	\N	f	0	\N
10629	74	391	\N	0	\N	\N	f	0	\N
10630	74	390	\N	0	\N	\N	f	0	\N
10631	74	389	\N	0	\N	\N	f	0	\N
10632	74	388	\N	0	\N	\N	f	0	\N
10633	74	387	\N	0	\N	\N	f	0	\N
10634	74	386	\N	0	\N	\N	f	0	\N
10635	74	385	\N	0	\N	\N	f	0	\N
10636	74	384	\N	0	\N	\N	f	0	\N
10637	74	383	\N	0	\N	\N	f	0	\N
10638	74	382	\N	0	\N	\N	f	0	\N
10639	74	381	\N	0	\N	\N	f	0	\N
10640	74	380	\N	0	\N	\N	f	0	\N
10641	74	379	\N	0	\N	\N	f	0	\N
10642	74	378	\N	0	\N	\N	f	0	\N
10643	74	377	\N	0	\N	\N	f	0	\N
10644	74	376	\N	0	\N	\N	f	0	\N
10645	74	375	\N	0	\N	\N	f	0	\N
10646	74	374	\N	0	\N	\N	f	0	\N
10647	74	373	\N	0	\N	\N	f	0	\N
10648	74	372	\N	0	\N	\N	f	0	\N
10649	74	371	\N	0	\N	\N	f	0	\N
10650	74	370	\N	0	\N	\N	f	0	\N
10651	74	369	\N	0	\N	\N	f	0	\N
10652	74	368	\N	0	\N	\N	f	0	\N
10653	74	367	\N	0	\N	\N	f	0	\N
10654	74	366	\N	0	\N	\N	f	0	\N
10655	74	365	\N	0	\N	\N	f	0	\N
10656	74	364	\N	0	\N	\N	f	0	\N
10657	74	363	\N	0	\N	\N	f	0	\N
10658	74	362	\N	0	\N	\N	f	0	\N
10659	74	361	\N	0	\N	\N	f	0	\N
10660	74	360	\N	0	\N	\N	f	0	\N
10661	74	359	\N	0	\N	\N	f	0	\N
10662	74	358	\N	0	\N	\N	f	0	\N
10663	74	357	\N	0	\N	\N	f	0	\N
10664	74	356	\N	0	\N	\N	f	0	\N
10665	74	355	\N	0	\N	\N	f	0	\N
10666	74	354	\N	0	\N	\N	f	0	\N
10667	74	353	\N	0	\N	\N	f	0	\N
10668	74	352	\N	0	\N	\N	f	0	\N
10669	74	351	\N	0	\N	\N	f	0	\N
10670	74	350	\N	0	\N	\N	f	0	\N
10671	74	349	\N	0	\N	\N	f	0	\N
10672	74	348	\N	0	\N	\N	f	0	\N
10673	74	347	\N	0	\N	\N	f	0	\N
10674	74	346	\N	0	\N	\N	f	0	\N
10675	74	345	\N	0	\N	\N	f	0	\N
10676	74	344	\N	0	\N	\N	f	0	\N
10677	74	343	\N	0	\N	\N	f	0	\N
10678	74	342	\N	0	\N	\N	f	0	\N
10679	74	341	\N	0	\N	\N	f	0	\N
10680	74	340	\N	0	\N	\N	f	0	\N
10681	74	339	\N	0	\N	\N	f	0	\N
10682	74	338	\N	0	\N	\N	f	0	\N
10683	74	337	\N	0	\N	\N	f	0	\N
10684	74	336	\N	0	\N	\N	f	0	\N
10685	74	335	\N	0	\N	\N	f	0	\N
10686	74	334	\N	0	\N	\N	f	0	\N
10687	74	333	\N	0	\N	\N	f	0	\N
10688	74	332	\N	0	\N	\N	f	0	\N
10689	74	331	\N	0	\N	\N	f	0	\N
10690	74	330	\N	0	\N	\N	f	0	\N
10691	74	329	\N	0	\N	\N	f	0	\N
10692	74	328	\N	0	\N	\N	f	0	\N
10693	74	327	\N	0	\N	\N	f	0	\N
10694	74	326	\N	0	\N	\N	f	0	\N
10695	74	325	\N	0	\N	\N	f	0	\N
10696	74	324	\N	0	\N	\N	f	0	\N
10697	74	218	\N	0	\N	\N	f	0	\N
10698	74	217	\N	0	\N	\N	f	0	\N
10699	74	216	\N	0	\N	\N	f	0	\N
10700	74	215	\N	0	\N	\N	f	0	\N
10701	74	214	\N	0	\N	\N	f	0	\N
10702	74	213	\N	0	\N	\N	f	0	\N
10703	74	212	\N	0	\N	\N	f	0	\N
10704	74	211	\N	0	\N	\N	f	0	\N
10705	74	210	\N	0	\N	\N	f	0	\N
10706	74	209	\N	0	\N	\N	f	0	\N
10707	74	208	\N	0	\N	\N	f	0	\N
10708	74	207	\N	0	\N	\N	f	0	\N
10709	74	206	\N	0	\N	\N	f	0	\N
10710	74	205	\N	0	\N	\N	f	0	\N
10711	74	204	\N	0	\N	\N	f	0	\N
10712	74	203	\N	0	\N	\N	f	0	\N
10713	74	202	\N	0	\N	\N	f	0	\N
10714	74	201	\N	0	\N	\N	f	0	\N
10715	74	200	\N	0	\N	\N	f	0	\N
10716	74	199	\N	0	\N	\N	f	0	\N
10717	74	198	\N	0	\N	\N	f	0	\N
10718	74	197	\N	0	\N	\N	f	0	\N
10719	74	196	\N	0	\N	\N	f	0	\N
10720	74	195	\N	0	\N	\N	f	0	\N
10721	74	194	\N	0	\N	\N	f	0	\N
10722	74	193	\N	0	\N	\N	f	0	\N
10723	74	192	\N	0	\N	\N	f	0	\N
10724	74	191	\N	0	\N	\N	f	0	\N
10725	74	190	\N	0	\N	\N	f	0	\N
10726	74	189	\N	0	\N	\N	f	0	\N
10727	74	188	\N	0	\N	\N	f	0	\N
10728	74	187	\N	0	\N	\N	f	0	\N
10729	74	186	\N	0	\N	\N	f	0	\N
10730	74	185	\N	0	\N	\N	f	0	\N
10731	74	184	\N	0	\N	\N	f	0	\N
10732	74	183	\N	0	\N	\N	f	0	\N
10733	74	182	\N	0	\N	\N	f	0	\N
10734	74	181	\N	0	\N	\N	f	0	\N
10735	75	323	\N	0	\N	\N	f	0	\N
10736	75	322	\N	0	\N	\N	f	0	\N
10737	75	321	\N	0	\N	\N	f	0	\N
10738	75	320	\N	0	\N	\N	f	0	\N
10739	75	319	\N	0	\N	\N	f	0	\N
10740	75	318	\N	0	\N	\N	f	0	\N
10741	75	317	\N	0	\N	\N	f	0	\N
10742	75	316	\N	0	\N	\N	f	0	\N
10743	75	315	\N	0	\N	\N	f	0	\N
10744	75	314	\N	0	\N	\N	f	0	\N
10745	75	313	\N	0	\N	\N	f	0	\N
10746	75	312	\N	0	\N	\N	f	0	\N
10747	75	311	\N	0	\N	\N	f	0	\N
10748	75	310	\N	0	\N	\N	f	0	\N
10749	75	309	\N	0	\N	\N	f	0	\N
10750	75	308	\N	0	\N	\N	f	0	\N
10751	75	307	\N	0	\N	\N	f	0	\N
10752	75	306	\N	0	\N	\N	f	0	\N
10753	75	305	\N	0	\N	\N	f	0	\N
10754	75	304	\N	0	\N	\N	f	0	\N
10755	75	303	\N	0	\N	\N	f	0	\N
10756	75	302	\N	0	\N	\N	f	0	\N
10757	75	301	\N	0	\N	\N	f	0	\N
10758	75	300	\N	0	\N	\N	f	0	\N
10759	75	299	\N	0	\N	\N	f	0	\N
10760	75	298	\N	0	\N	\N	f	0	\N
10761	75	297	\N	0	\N	\N	f	0	\N
10762	75	296	\N	0	\N	\N	f	0	\N
10763	75	295	\N	0	\N	\N	f	0	\N
10764	75	294	\N	0	\N	\N	f	0	\N
10765	75	293	\N	0	\N	\N	f	0	\N
10766	75	292	\N	0	\N	\N	f	0	\N
10767	75	291	\N	0	\N	\N	f	0	\N
10768	75	401	\N	0	\N	\N	f	0	\N
10769	75	400	\N	0	\N	\N	f	0	\N
10770	75	399	\N	0	\N	\N	f	0	\N
10771	75	398	\N	0	\N	\N	f	0	\N
10772	75	397	\N	0	\N	\N	f	0	\N
10773	75	396	\N	0	\N	\N	f	0	\N
10774	75	395	\N	0	\N	\N	f	0	\N
10775	75	394	\N	0	\N	\N	f	0	\N
10776	75	393	\N	0	\N	\N	f	0	\N
10777	75	392	\N	0	\N	\N	f	0	\N
10778	75	391	\N	0	\N	\N	f	0	\N
10779	75	390	\N	0	\N	\N	f	0	\N
10780	75	389	\N	0	\N	\N	f	0	\N
10781	75	388	\N	0	\N	\N	f	0	\N
10782	75	387	\N	0	\N	\N	f	0	\N
10783	75	386	\N	0	\N	\N	f	0	\N
10784	75	385	\N	0	\N	\N	f	0	\N
10785	75	384	\N	0	\N	\N	f	0	\N
10786	75	383	\N	0	\N	\N	f	0	\N
10787	75	382	\N	0	\N	\N	f	0	\N
10788	75	381	\N	0	\N	\N	f	0	\N
10789	75	380	\N	0	\N	\N	f	0	\N
10790	75	379	\N	0	\N	\N	f	0	\N
10791	75	378	\N	0	\N	\N	f	0	\N
10792	75	377	\N	0	\N	\N	f	0	\N
10793	75	376	\N	0	\N	\N	f	0	\N
10794	75	375	\N	0	\N	\N	f	0	\N
10795	75	374	\N	0	\N	\N	f	0	\N
10796	75	373	\N	0	\N	\N	f	0	\N
10797	75	372	\N	0	\N	\N	f	0	\N
10798	75	371	\N	0	\N	\N	f	0	\N
10799	75	370	\N	0	\N	\N	f	0	\N
10800	75	369	\N	0	\N	\N	f	0	\N
10801	75	368	\N	0	\N	\N	f	0	\N
10802	75	367	\N	0	\N	\N	f	0	\N
10803	75	366	\N	0	\N	\N	f	0	\N
10804	75	365	\N	0	\N	\N	f	0	\N
10805	75	364	\N	0	\N	\N	f	0	\N
10806	75	363	\N	0	\N	\N	f	0	\N
10807	75	362	\N	0	\N	\N	f	0	\N
10808	75	361	\N	0	\N	\N	f	0	\N
10809	75	180	\N	0	\N	\N	f	0	\N
10810	75	179	\N	0	\N	\N	f	0	\N
10811	75	178	\N	0	\N	\N	f	0	\N
10812	75	177	\N	0	\N	\N	f	0	\N
10813	75	176	\N	0	\N	\N	f	0	\N
10814	75	175	\N	0	\N	\N	f	0	\N
10815	75	174	\N	0	\N	\N	f	0	\N
10816	75	173	\N	0	\N	\N	f	0	\N
10817	75	172	\N	0	\N	\N	f	0	\N
10818	75	171	\N	0	\N	\N	f	0	\N
10819	75	170	\N	0	\N	\N	f	0	\N
10820	75	169	\N	0	\N	\N	f	0	\N
10821	75	168	\N	0	\N	\N	f	0	\N
10822	75	167	\N	0	\N	\N	f	0	\N
10823	75	166	\N	0	\N	\N	f	0	\N
10824	75	165	\N	0	\N	\N	f	0	\N
10825	75	164	\N	0	\N	\N	f	0	\N
10826	75	163	\N	0	\N	\N	f	0	\N
10827	75	162	\N	0	\N	\N	f	0	\N
10828	75	161	\N	0	\N	\N	f	0	\N
10829	75	160	\N	0	\N	\N	f	0	\N
10830	75	159	\N	0	\N	\N	f	0	\N
10831	75	158	\N	0	\N	\N	f	0	\N
10832	75	157	\N	0	\N	\N	f	0	\N
10833	75	156	\N	0	\N	\N	f	0	\N
10834	75	155	\N	0	\N	\N	f	0	\N
10835	75	154	\N	0	\N	\N	f	0	\N
10836	75	153	\N	0	\N	\N	f	0	\N
10837	75	152	\N	0	\N	\N	f	0	\N
10838	75	151	\N	0	\N	\N	f	0	\N
10839	75	150	\N	0	\N	\N	f	0	\N
10840	75	149	\N	0	\N	\N	f	0	\N
10841	75	148	\N	0	\N	\N	f	0	\N
10842	75	147	\N	0	\N	\N	f	0	\N
10843	75	146	\N	0	\N	\N	f	0	\N
10844	75	254	\N	0	\N	\N	f	0	\N
10845	75	253	\N	0	\N	\N	f	0	\N
10846	75	252	\N	0	\N	\N	f	0	\N
10847	75	251	\N	0	\N	\N	f	0	\N
10848	75	250	\N	0	\N	\N	f	0	\N
10849	75	249	\N	0	\N	\N	f	0	\N
10850	75	248	\N	0	\N	\N	f	0	\N
10851	75	247	\N	0	\N	\N	f	0	\N
10852	75	246	\N	0	\N	\N	f	0	\N
10853	75	245	\N	0	\N	\N	f	0	\N
10854	75	244	\N	0	\N	\N	f	0	\N
10855	75	243	\N	0	\N	\N	f	0	\N
10856	75	242	\N	0	\N	\N	f	0	\N
10857	75	241	\N	0	\N	\N	f	0	\N
10858	75	240	\N	0	\N	\N	f	0	\N
10859	75	239	\N	0	\N	\N	f	0	\N
10860	75	238	\N	0	\N	\N	f	0	\N
10861	75	237	\N	0	\N	\N	f	0	\N
10862	75	236	\N	0	\N	\N	f	0	\N
10863	75	235	\N	0	\N	\N	f	0	\N
10864	75	234	\N	0	\N	\N	f	0	\N
10865	75	233	\N	0	\N	\N	f	0	\N
10866	75	232	\N	0	\N	\N	f	0	\N
10867	75	231	\N	0	\N	\N	f	0	\N
10868	75	230	\N	0	\N	\N	f	0	\N
10869	75	229	\N	0	\N	\N	f	0	\N
10870	75	228	\N	0	\N	\N	f	0	\N
10871	75	227	\N	0	\N	\N	f	0	\N
10872	75	226	\N	0	\N	\N	f	0	\N
10873	75	225	\N	0	\N	\N	f	0	\N
10874	75	224	\N	0	\N	\N	f	0	\N
10875	75	223	\N	0	\N	\N	f	0	\N
10876	75	222	\N	0	\N	\N	f	0	\N
10877	75	221	\N	0	\N	\N	f	0	\N
10878	75	220	\N	0	\N	\N	f	0	\N
10879	75	219	\N	0	\N	\N	f	0	\N
10880	75	109	\N	0	\N	\N	f	0	\N
10881	75	108	\N	0	\N	\N	f	0	\N
10882	75	107	\N	0	\N	\N	f	0	\N
10883	75	106	\N	0	\N	\N	f	0	\N
10884	75	105	\N	0	\N	\N	f	0	\N
10885	75	104	\N	0	\N	\N	f	0	\N
10886	75	103	\N	0	\N	\N	f	0	\N
10887	75	102	\N	0	\N	\N	f	0	\N
10888	75	101	\N	0	\N	\N	f	0	\N
10889	75	100	\N	0	\N	\N	f	0	\N
10890	75	99	\N	0	\N	\N	f	0	\N
10891	75	98	\N	0	\N	\N	f	0	\N
10892	75	97	\N	0	\N	\N	f	0	\N
10893	75	96	\N	0	\N	\N	f	0	\N
10894	75	95	\N	0	\N	\N	f	0	\N
10895	75	94	\N	0	\N	\N	f	0	\N
10896	75	93	\N	0	\N	\N	f	0	\N
10897	75	92	\N	0	\N	\N	f	0	\N
10898	75	91	\N	0	\N	\N	f	0	\N
10899	75	90	\N	0	\N	\N	f	0	\N
10900	75	89	\N	0	\N	\N	f	0	\N
10901	75	88	\N	0	\N	\N	f	0	\N
10902	75	87	\N	0	\N	\N	f	0	\N
10903	75	86	\N	0	\N	\N	f	0	\N
10904	75	85	\N	0	\N	\N	f	0	\N
10905	75	84	\N	0	\N	\N	f	0	\N
10906	75	83	\N	0	\N	\N	f	0	\N
10907	75	82	\N	0	\N	\N	f	0	\N
10908	75	81	\N	0	\N	\N	f	0	\N
10909	75	80	\N	0	\N	\N	f	0	\N
10910	75	79	\N	0	\N	\N	f	0	\N
10911	75	78	\N	0	\N	\N	f	0	\N
10912	75	77	\N	0	\N	\N	f	0	\N
10913	75	76	\N	0	\N	\N	f	0	\N
10914	75	75	\N	0	\N	\N	f	0	\N
10915	75	360	\N	0	\N	\N	f	0	\N
10916	75	359	\N	0	\N	\N	f	0	\N
10917	75	358	\N	0	\N	\N	f	0	\N
10918	75	357	\N	0	\N	\N	f	0	\N
10919	75	356	\N	0	\N	\N	f	0	\N
10920	75	355	\N	0	\N	\N	f	0	\N
10921	75	354	\N	0	\N	\N	f	0	\N
10922	75	353	\N	0	\N	\N	f	0	\N
10923	75	352	\N	0	\N	\N	f	0	\N
10924	75	351	\N	0	\N	\N	f	0	\N
10925	75	350	\N	0	\N	\N	f	0	\N
10926	75	349	\N	0	\N	\N	f	0	\N
10927	75	348	\N	0	\N	\N	f	0	\N
10928	75	347	\N	0	\N	\N	f	0	\N
10929	75	346	\N	0	\N	\N	f	0	\N
10930	75	345	\N	0	\N	\N	f	0	\N
10931	75	344	\N	0	\N	\N	f	0	\N
10932	75	343	\N	0	\N	\N	f	0	\N
10933	75	342	\N	0	\N	\N	f	0	\N
10934	75	341	\N	0	\N	\N	f	0	\N
10935	75	340	\N	0	\N	\N	f	0	\N
10936	75	339	\N	0	\N	\N	f	0	\N
10937	75	338	\N	0	\N	\N	f	0	\N
10938	75	337	\N	0	\N	\N	f	0	\N
10939	75	336	\N	0	\N	\N	f	0	\N
10940	75	335	\N	0	\N	\N	f	0	\N
10941	75	334	\N	0	\N	\N	f	0	\N
10942	75	333	\N	0	\N	\N	f	0	\N
10943	75	332	\N	0	\N	\N	f	0	\N
10944	75	331	\N	0	\N	\N	f	0	\N
10945	75	330	\N	0	\N	\N	f	0	\N
10946	75	329	\N	0	\N	\N	f	0	\N
10947	75	328	\N	0	\N	\N	f	0	\N
10948	75	327	\N	0	\N	\N	f	0	\N
10949	75	326	\N	0	\N	\N	f	0	\N
10950	75	325	\N	0	\N	\N	f	0	\N
10951	75	324	\N	0	\N	\N	f	0	\N
10952	75	218	\N	0	\N	\N	f	0	\N
10953	75	217	\N	0	\N	\N	f	0	\N
10954	75	216	\N	0	\N	\N	f	0	\N
10955	75	215	\N	0	\N	\N	f	0	\N
10956	75	214	\N	0	\N	\N	f	0	\N
10957	75	213	\N	0	\N	\N	f	0	\N
10958	75	212	\N	0	\N	\N	f	0	\N
10959	75	211	\N	0	\N	\N	f	0	\N
10960	75	210	\N	0	\N	\N	f	0	\N
10961	75	209	\N	0	\N	\N	f	0	\N
10962	75	208	\N	0	\N	\N	f	0	\N
10963	75	207	\N	0	\N	\N	f	0	\N
10964	75	206	\N	0	\N	\N	f	0	\N
10965	75	205	\N	0	\N	\N	f	0	\N
10966	75	204	\N	0	\N	\N	f	0	\N
10967	75	203	\N	0	\N	\N	f	0	\N
10968	75	202	\N	0	\N	\N	f	0	\N
10969	75	201	\N	0	\N	\N	f	0	\N
10970	75	200	\N	0	\N	\N	f	0	\N
10971	75	199	\N	0	\N	\N	f	0	\N
10972	75	198	\N	0	\N	\N	f	0	\N
10973	75	197	\N	0	\N	\N	f	0	\N
10974	75	196	\N	0	\N	\N	f	0	\N
10975	75	195	\N	0	\N	\N	f	0	\N
10976	75	194	\N	0	\N	\N	f	0	\N
10977	75	193	\N	0	\N	\N	f	0	\N
10978	75	192	\N	0	\N	\N	f	0	\N
10979	75	191	\N	0	\N	\N	f	0	\N
10980	75	190	\N	0	\N	\N	f	0	\N
10981	75	189	\N	0	\N	\N	f	0	\N
10982	75	188	\N	0	\N	\N	f	0	\N
10983	75	187	\N	0	\N	\N	f	0	\N
10984	75	186	\N	0	\N	\N	f	0	\N
10985	75	185	\N	0	\N	\N	f	0	\N
10986	75	184	\N	0	\N	\N	f	0	\N
10987	75	183	\N	0	\N	\N	f	0	\N
10988	75	182	\N	0	\N	\N	f	0	\N
10989	75	181	\N	0	\N	\N	f	0	\N
10990	75	145	\N	0	\N	\N	f	0	\N
10991	75	144	\N	0	\N	\N	f	0	\N
10992	75	143	\N	0	\N	\N	f	0	\N
10993	75	142	\N	0	\N	\N	f	0	\N
10994	75	141	\N	0	\N	\N	f	0	\N
10995	75	140	\N	0	\N	\N	f	0	\N
10996	75	139	\N	0	\N	\N	f	0	\N
10997	75	138	\N	0	\N	\N	f	0	\N
10998	75	137	\N	0	\N	\N	f	0	\N
10999	75	136	\N	0	\N	\N	f	0	\N
11000	75	135	\N	0	\N	\N	f	0	\N
11001	75	134	\N	0	\N	\N	f	0	\N
11002	75	133	\N	0	\N	\N	f	0	\N
11003	75	132	\N	0	\N	\N	f	0	\N
11004	75	131	\N	0	\N	\N	f	0	\N
11005	75	130	\N	0	\N	\N	f	0	\N
11006	75	129	\N	0	\N	\N	f	0	\N
11007	75	128	\N	0	\N	\N	f	0	\N
11008	75	127	\N	0	\N	\N	f	0	\N
11009	75	126	\N	0	\N	\N	f	0	\N
11010	75	125	\N	0	\N	\N	f	0	\N
11011	75	124	\N	0	\N	\N	f	0	\N
11012	75	123	\N	0	\N	\N	f	0	\N
11013	75	122	\N	0	\N	\N	f	0	\N
11014	75	121	\N	0	\N	\N	f	0	\N
11015	75	120	\N	0	\N	\N	f	0	\N
11016	75	119	\N	0	\N	\N	f	0	\N
11017	75	118	\N	0	\N	\N	f	0	\N
11018	75	117	\N	0	\N	\N	f	0	\N
11019	75	116	\N	0	\N	\N	f	0	\N
11020	75	115	\N	0	\N	\N	f	0	\N
11021	75	114	\N	0	\N	\N	f	0	\N
11022	75	113	\N	0	\N	\N	f	0	\N
11023	75	112	\N	0	\N	\N	f	0	\N
11024	75	111	\N	0	\N	\N	f	0	\N
11025	75	110	\N	0	\N	\N	f	0	\N
11026	75	74	\N	0	\N	\N	f	0	\N
11027	75	73	\N	0	\N	\N	f	0	\N
11028	75	72	\N	0	\N	\N	f	0	\N
11029	75	71	\N	0	\N	\N	f	0	\N
11030	75	70	\N	0	\N	\N	f	0	\N
11031	75	69	\N	0	\N	\N	f	0	\N
11032	75	68	\N	0	\N	\N	f	0	\N
11033	75	67	\N	0	\N	\N	f	0	\N
11034	75	66	\N	0	\N	\N	f	0	\N
11035	75	65	\N	0	\N	\N	f	0	\N
11036	75	64	\N	0	\N	\N	f	0	\N
11037	75	63	\N	0	\N	\N	f	0	\N
11038	75	62	\N	0	\N	\N	f	0	\N
11039	75	61	\N	0	\N	\N	f	0	\N
11040	75	60	\N	0	\N	\N	f	0	\N
11041	75	59	\N	0	\N	\N	f	0	\N
11042	75	58	\N	0	\N	\N	f	0	\N
11043	75	57	\N	0	\N	\N	f	0	\N
11044	75	56	\N	0	\N	\N	f	0	\N
11045	75	55	\N	0	\N	\N	f	0	\N
11046	75	54	\N	0	\N	\N	f	0	\N
11047	75	53	\N	0	\N	\N	f	0	\N
11048	75	52	\N	0	\N	\N	f	0	\N
11049	75	51	\N	0	\N	\N	f	0	\N
11050	75	50	\N	0	\N	\N	f	0	\N
11051	75	49	\N	0	\N	\N	f	0	\N
11052	75	48	\N	0	\N	\N	f	0	\N
11053	75	47	\N	0	\N	\N	f	0	\N
11054	75	46	\N	0	\N	\N	f	0	\N
11055	75	45	\N	0	\N	\N	f	0	\N
11056	75	44	\N	0	\N	\N	f	0	\N
11057	75	43	\N	0	\N	\N	f	0	\N
11058	75	42	\N	0	\N	\N	f	0	\N
11059	75	41	\N	0	\N	\N	f	0	\N
11060	75	40	\N	0	\N	\N	f	0	\N
11061	75	39	\N	0	\N	\N	f	0	\N
11062	75	38	\N	0	\N	\N	f	0	\N
11063	75	37	\N	0	\N	\N	f	0	\N
11064	75	36	\N	0	\N	\N	f	0	\N
11065	75	35	\N	0	\N	\N	f	0	\N
11066	75	34	\N	0	\N	\N	f	0	\N
11067	75	33	\N	0	\N	\N	f	0	\N
11068	75	32	\N	0	\N	\N	f	0	\N
11069	75	31	\N	0	\N	\N	f	0	\N
11070	75	30	\N	0	\N	\N	f	0	\N
11071	75	29	\N	0	\N	\N	f	0	\N
11072	75	28	\N	0	\N	\N	f	0	\N
11073	75	27	\N	0	\N	\N	f	0	\N
11074	75	26	\N	0	\N	\N	f	0	\N
11075	75	25	\N	0	\N	\N	f	0	\N
11076	75	24	\N	0	\N	\N	f	0	\N
11077	75	23	\N	0	\N	\N	f	0	\N
11078	75	22	\N	0	\N	\N	f	0	\N
11079	75	21	\N	0	\N	\N	f	0	\N
11080	75	20	\N	0	\N	\N	f	0	\N
11081	75	19	\N	0	\N	\N	f	0	\N
11082	75	18	\N	0	\N	\N	f	0	\N
11083	75	17	\N	0	\N	\N	f	0	\N
11084	75	16	\N	0	\N	\N	f	0	\N
11085	75	15	\N	0	\N	\N	f	0	\N
11086	75	14	\N	0	\N	\N	f	0	\N
11087	75	13	\N	0	\N	\N	f	0	\N
11088	75	12	\N	0	\N	\N	f	0	\N
11089	75	11	\N	0	\N	\N	f	0	\N
11090	75	10	\N	0	\N	\N	f	0	\N
11091	75	9	\N	0	\N	\N	f	0	\N
11092	75	8	\N	0	\N	\N	f	0	\N
11093	75	7	\N	0	\N	\N	f	0	\N
11094	75	6	\N	0	\N	\N	f	0	\N
11095	75	5	\N	0	\N	\N	f	0	\N
11096	75	4	\N	0	\N	\N	f	0	\N
11097	75	3	\N	0	\N	\N	f	0	\N
11098	75	2	\N	0	\N	\N	f	0	\N
11099	75	1	\N	0	\N	\N	f	0	\N
11100	75	432	\N	0	\N	\N	f	0	\N
11101	75	431	\N	0	\N	\N	f	0	\N
11102	75	430	\N	0	\N	\N	f	0	\N
11103	75	429	\N	0	\N	\N	f	0	\N
11104	75	428	\N	0	\N	\N	f	0	\N
11105	75	427	\N	0	\N	\N	f	0	\N
11106	75	426	\N	0	\N	\N	f	0	\N
11107	75	425	\N	0	\N	\N	f	0	\N
11108	75	424	\N	0	\N	\N	f	0	\N
11109	75	423	\N	0	\N	\N	f	0	\N
11110	75	422	\N	0	\N	\N	f	0	\N
11111	75	421	\N	0	\N	\N	f	0	\N
11112	75	420	\N	0	\N	\N	f	0	\N
11113	75	419	\N	0	\N	\N	f	0	\N
11114	75	418	\N	0	\N	\N	f	0	\N
11115	75	417	\N	0	\N	\N	f	0	\N
11116	75	416	\N	0	\N	\N	f	0	\N
11117	75	415	\N	0	\N	\N	f	0	\N
11118	75	414	\N	0	\N	\N	f	0	\N
11119	75	413	\N	0	\N	\N	f	0	\N
11120	75	412	\N	0	\N	\N	f	0	\N
11121	75	411	\N	0	\N	\N	f	0	\N
11122	75	410	\N	0	\N	\N	f	0	\N
11123	75	409	\N	0	\N	\N	f	0	\N
11124	75	408	\N	0	\N	\N	f	0	\N
11125	75	407	\N	0	\N	\N	f	0	\N
11126	75	406	\N	0	\N	\N	f	0	\N
11127	75	405	\N	0	\N	\N	f	0	\N
11128	75	404	\N	0	\N	\N	f	0	\N
11129	75	403	\N	0	\N	\N	f	0	\N
11130	75	402	\N	0	\N	\N	f	0	\N
11131	75	290	\N	0	\N	\N	f	0	\N
11132	75	289	\N	0	\N	\N	f	0	\N
11133	75	288	\N	0	\N	\N	f	0	\N
11134	75	287	\N	0	\N	\N	f	0	\N
11135	75	286	\N	0	\N	\N	f	0	\N
11136	75	285	\N	0	\N	\N	f	0	\N
11137	75	284	\N	0	\N	\N	f	0	\N
11138	75	283	\N	0	\N	\N	f	0	\N
11139	75	282	\N	0	\N	\N	f	0	\N
11140	75	281	\N	0	\N	\N	f	0	\N
11141	75	280	\N	0	\N	\N	f	0	\N
11142	75	279	\N	0	\N	\N	f	0	\N
11143	75	278	\N	0	\N	\N	f	0	\N
11144	75	277	\N	0	\N	\N	f	0	\N
11145	75	276	\N	0	\N	\N	f	0	\N
11146	75	275	\N	0	\N	\N	f	0	\N
11147	75	274	\N	0	\N	\N	f	0	\N
11148	75	273	\N	0	\N	\N	f	0	\N
11149	75	272	\N	0	\N	\N	f	0	\N
11150	75	271	\N	0	\N	\N	f	0	\N
11151	75	270	\N	0	\N	\N	f	0	\N
11152	75	269	\N	0	\N	\N	f	0	\N
11153	75	268	\N	0	\N	\N	f	0	\N
11154	75	267	\N	0	\N	\N	f	0	\N
11155	75	266	\N	0	\N	\N	f	0	\N
11156	75	265	\N	0	\N	\N	f	0	\N
11157	75	264	\N	0	\N	\N	f	0	\N
11158	75	263	\N	0	\N	\N	f	0	\N
11159	75	262	\N	0	\N	\N	f	0	\N
11160	75	261	\N	0	\N	\N	f	0	\N
11161	75	260	\N	0	\N	\N	f	0	\N
11162	75	259	\N	0	\N	\N	f	0	\N
11163	75	258	\N	0	\N	\N	f	0	\N
11164	75	257	\N	0	\N	\N	f	0	\N
11165	75	256	\N	0	\N	\N	f	0	\N
11166	75	255	\N	0	\N	\N	f	0	\N
11167	76	180	\N	0	\N	\N	f	0	\N
11168	76	179	\N	0	\N	\N	f	0	\N
11169	76	178	\N	0	\N	\N	f	0	\N
11170	76	177	\N	0	\N	\N	f	0	\N
11171	76	176	\N	0	\N	\N	f	0	\N
11172	76	175	\N	0	\N	\N	f	0	\N
11173	76	174	\N	0	\N	\N	f	0	\N
11174	76	173	\N	0	\N	\N	f	0	\N
11175	76	172	\N	0	\N	\N	f	0	\N
11176	76	171	\N	0	\N	\N	f	0	\N
11177	76	170	\N	0	\N	\N	f	0	\N
11178	76	169	\N	0	\N	\N	f	0	\N
11179	76	168	\N	0	\N	\N	f	0	\N
11180	76	167	\N	0	\N	\N	f	0	\N
11181	76	166	\N	0	\N	\N	f	0	\N
11182	76	165	\N	0	\N	\N	f	0	\N
11183	76	164	\N	0	\N	\N	f	0	\N
11184	76	163	\N	0	\N	\N	f	0	\N
11185	76	162	\N	0	\N	\N	f	0	\N
11186	76	161	\N	0	\N	\N	f	0	\N
11187	76	160	\N	0	\N	\N	f	0	\N
11188	76	159	\N	0	\N	\N	f	0	\N
11189	76	158	\N	0	\N	\N	f	0	\N
11190	76	157	\N	0	\N	\N	f	0	\N
11191	76	156	\N	0	\N	\N	f	0	\N
11192	76	155	\N	0	\N	\N	f	0	\N
11193	76	154	\N	0	\N	\N	f	0	\N
11194	76	153	\N	0	\N	\N	f	0	\N
11195	76	152	\N	0	\N	\N	f	0	\N
11196	76	151	\N	0	\N	\N	f	0	\N
11197	76	150	\N	0	\N	\N	f	0	\N
11198	76	149	\N	0	\N	\N	f	0	\N
11199	76	148	\N	0	\N	\N	f	0	\N
11200	76	147	\N	0	\N	\N	f	0	\N
11201	76	146	\N	0	\N	\N	f	0	\N
11202	76	74	\N	0	\N	\N	f	0	\N
11203	76	73	\N	0	\N	\N	f	0	\N
11204	76	72	\N	0	\N	\N	f	0	\N
11205	76	71	\N	0	\N	\N	f	0	\N
11206	76	70	\N	0	\N	\N	f	0	\N
11207	76	69	\N	0	\N	\N	f	0	\N
11208	76	68	\N	0	\N	\N	f	0	\N
11209	76	67	\N	0	\N	\N	f	0	\N
11210	76	66	\N	0	\N	\N	f	0	\N
11211	76	65	\N	0	\N	\N	f	0	\N
11212	76	64	\N	0	\N	\N	f	0	\N
11213	76	63	\N	0	\N	\N	f	0	\N
11214	76	62	\N	0	\N	\N	f	0	\N
11215	76	61	\N	0	\N	\N	f	0	\N
11216	76	60	\N	0	\N	\N	f	0	\N
11217	76	59	\N	0	\N	\N	f	0	\N
11218	76	58	\N	0	\N	\N	f	0	\N
11219	76	57	\N	0	\N	\N	f	0	\N
11220	76	56	\N	0	\N	\N	f	0	\N
11221	76	55	\N	0	\N	\N	f	0	\N
11222	76	54	\N	0	\N	\N	f	0	\N
11223	76	53	\N	0	\N	\N	f	0	\N
11224	76	52	\N	0	\N	\N	f	0	\N
11225	76	51	\N	0	\N	\N	f	0	\N
11226	76	50	\N	0	\N	\N	f	0	\N
11227	76	49	\N	0	\N	\N	f	0	\N
11228	76	48	\N	0	\N	\N	f	0	\N
11229	76	47	\N	0	\N	\N	f	0	\N
11230	76	46	\N	0	\N	\N	f	0	\N
11231	76	45	\N	0	\N	\N	f	0	\N
11232	76	44	\N	0	\N	\N	f	0	\N
11233	76	43	\N	0	\N	\N	f	0	\N
11234	76	42	\N	0	\N	\N	f	0	\N
11235	76	41	\N	0	\N	\N	f	0	\N
11236	76	40	\N	0	\N	\N	f	0	\N
11237	76	109	\N	0	\N	\N	f	0	\N
11238	76	108	\N	0	\N	\N	f	0	\N
11239	76	107	\N	0	\N	\N	f	0	\N
11240	76	106	\N	0	\N	\N	f	0	\N
11241	76	105	\N	0	\N	\N	f	0	\N
11242	76	104	\N	0	\N	\N	f	0	\N
11243	76	103	\N	0	\N	\N	f	0	\N
11244	76	102	\N	0	\N	\N	f	0	\N
11245	76	101	\N	0	\N	\N	f	0	\N
11246	76	100	\N	0	\N	\N	f	0	\N
11247	76	99	\N	0	\N	\N	f	0	\N
11248	76	98	\N	0	\N	\N	f	0	\N
11249	76	97	\N	0	\N	\N	f	0	\N
11250	76	96	\N	0	\N	\N	f	0	\N
11251	76	95	\N	0	\N	\N	f	0	\N
11252	76	94	\N	0	\N	\N	f	0	\N
11253	76	93	\N	0	\N	\N	f	0	\N
11254	76	92	\N	0	\N	\N	f	0	\N
11255	76	91	\N	0	\N	\N	f	0	\N
11256	76	90	\N	0	\N	\N	f	0	\N
11257	76	89	\N	0	\N	\N	f	0	\N
11258	76	88	\N	0	\N	\N	f	0	\N
11259	76	87	\N	0	\N	\N	f	0	\N
11260	76	86	\N	0	\N	\N	f	0	\N
11261	76	85	\N	0	\N	\N	f	0	\N
11262	76	84	\N	0	\N	\N	f	0	\N
11263	76	83	\N	0	\N	\N	f	0	\N
11264	76	82	\N	0	\N	\N	f	0	\N
11265	76	81	\N	0	\N	\N	f	0	\N
11266	76	80	\N	0	\N	\N	f	0	\N
11267	76	79	\N	0	\N	\N	f	0	\N
11268	76	78	\N	0	\N	\N	f	0	\N
11269	76	77	\N	0	\N	\N	f	0	\N
11270	76	76	\N	0	\N	\N	f	0	\N
11271	76	75	\N	0	\N	\N	f	0	\N
11272	76	360	\N	0	\N	\N	f	0	\N
11273	76	359	\N	0	\N	\N	f	0	\N
11274	76	358	\N	0	\N	\N	f	0	\N
11275	76	357	\N	0	\N	\N	f	0	\N
11276	76	356	\N	0	\N	\N	f	0	\N
11277	76	355	\N	0	\N	\N	f	0	\N
11278	76	354	\N	0	\N	\N	f	0	\N
11279	76	353	\N	0	\N	\N	f	0	\N
11280	76	352	\N	0	\N	\N	f	0	\N
11281	76	351	\N	0	\N	\N	f	0	\N
11282	76	350	\N	0	\N	\N	f	0	\N
11283	76	349	\N	0	\N	\N	f	0	\N
11284	76	348	\N	0	\N	\N	f	0	\N
11285	76	347	\N	0	\N	\N	f	0	\N
11286	76	346	\N	0	\N	\N	f	0	\N
11287	76	345	\N	0	\N	\N	f	0	\N
11288	76	344	\N	0	\N	\N	f	0	\N
11289	76	343	\N	0	\N	\N	f	0	\N
11290	76	342	\N	0	\N	\N	f	0	\N
11291	76	341	\N	0	\N	\N	f	0	\N
11292	76	340	\N	0	\N	\N	f	0	\N
11293	76	339	\N	0	\N	\N	f	0	\N
11294	76	338	\N	0	\N	\N	f	0	\N
11295	76	337	\N	0	\N	\N	f	0	\N
11296	76	336	\N	0	\N	\N	f	0	\N
11297	76	335	\N	0	\N	\N	f	0	\N
11298	76	334	\N	0	\N	\N	f	0	\N
11299	76	333	\N	0	\N	\N	f	0	\N
11300	76	332	\N	0	\N	\N	f	0	\N
11301	76	331	\N	0	\N	\N	f	0	\N
11302	76	330	\N	0	\N	\N	f	0	\N
11303	76	329	\N	0	\N	\N	f	0	\N
11304	76	328	\N	0	\N	\N	f	0	\N
11305	76	327	\N	0	\N	\N	f	0	\N
11306	76	326	\N	0	\N	\N	f	0	\N
11307	76	325	\N	0	\N	\N	f	0	\N
11308	76	324	\N	0	\N	\N	f	0	\N
11309	76	432	\N	0	\N	\N	f	0	\N
11310	76	431	\N	0	\N	\N	f	0	\N
11311	76	430	\N	0	\N	\N	f	0	\N
11312	76	429	\N	0	\N	\N	f	0	\N
11313	76	428	\N	0	\N	\N	f	0	\N
11314	76	427	\N	0	\N	\N	f	0	\N
11315	76	426	\N	0	\N	\N	f	0	\N
11316	76	425	\N	0	\N	\N	f	0	\N
11317	76	424	\N	0	\N	\N	f	0	\N
11318	76	423	\N	0	\N	\N	f	0	\N
11319	76	422	\N	0	\N	\N	f	0	\N
11320	76	421	\N	0	\N	\N	f	0	\N
11321	76	420	\N	0	\N	\N	f	0	\N
11322	76	419	\N	0	\N	\N	f	0	\N
11323	76	418	\N	0	\N	\N	f	0	\N
11324	76	417	\N	0	\N	\N	f	0	\N
11325	76	416	\N	0	\N	\N	f	0	\N
11326	76	415	\N	0	\N	\N	f	0	\N
11327	76	414	\N	0	\N	\N	f	0	\N
11328	76	413	\N	0	\N	\N	f	0	\N
11329	76	412	\N	0	\N	\N	f	0	\N
11330	76	411	\N	0	\N	\N	f	0	\N
11331	76	410	\N	0	\N	\N	f	0	\N
11332	76	409	\N	0	\N	\N	f	0	\N
11333	76	408	\N	0	\N	\N	f	0	\N
11334	76	407	\N	0	\N	\N	f	0	\N
11335	76	406	\N	0	\N	\N	f	0	\N
11336	76	405	\N	0	\N	\N	f	0	\N
11337	76	404	\N	0	\N	\N	f	0	\N
11338	76	403	\N	0	\N	\N	f	0	\N
11339	76	402	\N	0	\N	\N	f	0	\N
11340	76	39	\N	0	\N	\N	f	0	\N
11341	76	38	\N	0	\N	\N	f	0	\N
11342	76	37	\N	0	\N	\N	f	0	\N
11343	76	36	\N	0	\N	\N	f	0	\N
11344	76	35	\N	0	\N	\N	f	0	\N
11345	76	34	\N	0	\N	\N	f	0	\N
11346	76	33	\N	0	\N	\N	f	0	\N
11347	76	32	\N	0	\N	\N	f	0	\N
11348	76	31	\N	0	\N	\N	f	0	\N
11349	76	30	\N	0	\N	\N	f	0	\N
11350	76	29	\N	0	\N	\N	f	0	\N
11351	76	28	\N	0	\N	\N	f	0	\N
11352	76	27	\N	0	\N	\N	f	0	\N
11353	76	26	\N	0	\N	\N	f	0	\N
11354	76	25	\N	0	\N	\N	f	0	\N
11355	76	24	\N	0	\N	\N	f	0	\N
11356	76	23	\N	0	\N	\N	f	0	\N
11357	76	22	\N	0	\N	\N	f	0	\N
11358	76	21	\N	0	\N	\N	f	0	\N
11359	76	20	\N	0	\N	\N	f	0	\N
11360	76	19	\N	0	\N	\N	f	0	\N
11361	76	18	\N	0	\N	\N	f	0	\N
11362	76	17	\N	0	\N	\N	f	0	\N
11363	76	16	\N	0	\N	\N	f	0	\N
11364	76	15	\N	0	\N	\N	f	0	\N
11365	76	14	\N	0	\N	\N	f	0	\N
11366	76	13	\N	0	\N	\N	f	0	\N
11367	76	12	\N	0	\N	\N	f	0	\N
11368	76	11	\N	0	\N	\N	f	0	\N
11369	76	10	\N	0	\N	\N	f	0	\N
11370	76	9	\N	0	\N	\N	f	0	\N
11371	76	8	\N	0	\N	\N	f	0	\N
11372	76	7	\N	0	\N	\N	f	0	\N
11373	76	6	\N	0	\N	\N	f	0	\N
11374	76	5	\N	0	\N	\N	f	0	\N
11375	76	4	\N	0	\N	\N	f	0	\N
11376	76	3	\N	0	\N	\N	f	0	\N
11377	76	2	\N	0	\N	\N	f	0	\N
11378	76	1	\N	0	\N	\N	f	0	\N
11379	76	401	\N	0	\N	\N	f	0	\N
11380	76	400	\N	0	\N	\N	f	0	\N
11381	76	399	\N	0	\N	\N	f	0	\N
11382	76	398	\N	0	\N	\N	f	0	\N
11383	76	397	\N	0	\N	\N	f	0	\N
11384	76	396	\N	0	\N	\N	f	0	\N
11385	76	395	\N	0	\N	\N	f	0	\N
11386	76	394	\N	0	\N	\N	f	0	\N
11387	76	393	\N	0	\N	\N	f	0	\N
11388	76	392	\N	0	\N	\N	f	0	\N
11389	76	391	\N	0	\N	\N	f	0	\N
11390	76	390	\N	0	\N	\N	f	0	\N
11391	76	389	\N	0	\N	\N	f	0	\N
11392	76	388	\N	0	\N	\N	f	0	\N
11393	76	387	\N	0	\N	\N	f	0	\N
11394	76	386	\N	0	\N	\N	f	0	\N
11395	76	385	\N	0	\N	\N	f	0	\N
11396	76	384	\N	0	\N	\N	f	0	\N
11397	76	383	\N	0	\N	\N	f	0	\N
11398	76	382	\N	0	\N	\N	f	0	\N
11399	76	381	\N	0	\N	\N	f	0	\N
11400	76	380	\N	0	\N	\N	f	0	\N
11401	76	379	\N	0	\N	\N	f	0	\N
11402	76	378	\N	0	\N	\N	f	0	\N
11403	76	377	\N	0	\N	\N	f	0	\N
11404	76	376	\N	0	\N	\N	f	0	\N
11405	76	375	\N	0	\N	\N	f	0	\N
11406	76	374	\N	0	\N	\N	f	0	\N
11407	76	373	\N	0	\N	\N	f	0	\N
11408	76	372	\N	0	\N	\N	f	0	\N
11409	76	371	\N	0	\N	\N	f	0	\N
11410	76	370	\N	0	\N	\N	f	0	\N
11411	76	369	\N	0	\N	\N	f	0	\N
11412	76	368	\N	0	\N	\N	f	0	\N
11413	76	367	\N	0	\N	\N	f	0	\N
11414	76	366	\N	0	\N	\N	f	0	\N
11415	76	365	\N	0	\N	\N	f	0	\N
11416	76	364	\N	0	\N	\N	f	0	\N
11417	76	363	\N	0	\N	\N	f	0	\N
11418	76	362	\N	0	\N	\N	f	0	\N
11419	76	361	\N	0	\N	\N	f	0	\N
11420	76	254	\N	0	\N	\N	f	0	\N
11421	76	253	\N	0	\N	\N	f	0	\N
11422	76	252	\N	0	\N	\N	f	0	\N
11423	76	251	\N	0	\N	\N	f	0	\N
11424	76	250	\N	0	\N	\N	f	0	\N
11425	76	249	\N	0	\N	\N	f	0	\N
11426	76	248	\N	0	\N	\N	f	0	\N
11427	76	247	\N	0	\N	\N	f	0	\N
11428	76	246	\N	0	\N	\N	f	0	\N
11429	76	245	\N	0	\N	\N	f	0	\N
11430	76	244	\N	0	\N	\N	f	0	\N
11431	76	243	\N	0	\N	\N	f	0	\N
11432	76	242	\N	0	\N	\N	f	0	\N
11433	76	241	\N	0	\N	\N	f	0	\N
11434	76	240	\N	0	\N	\N	f	0	\N
11435	76	239	\N	0	\N	\N	f	0	\N
11436	76	238	\N	0	\N	\N	f	0	\N
11437	76	237	\N	0	\N	\N	f	0	\N
11438	76	236	\N	0	\N	\N	f	0	\N
11439	76	235	\N	0	\N	\N	f	0	\N
11440	76	234	\N	0	\N	\N	f	0	\N
11441	76	233	\N	0	\N	\N	f	0	\N
11442	76	232	\N	0	\N	\N	f	0	\N
11443	76	231	\N	0	\N	\N	f	0	\N
11444	76	230	\N	0	\N	\N	f	0	\N
11445	76	229	\N	0	\N	\N	f	0	\N
11446	76	228	\N	0	\N	\N	f	0	\N
11447	76	227	\N	0	\N	\N	f	0	\N
11448	76	226	\N	0	\N	\N	f	0	\N
11449	76	225	\N	0	\N	\N	f	0	\N
11450	76	224	\N	0	\N	\N	f	0	\N
11451	76	223	\N	0	\N	\N	f	0	\N
11452	76	222	\N	0	\N	\N	f	0	\N
11453	76	221	\N	0	\N	\N	f	0	\N
11454	76	220	\N	0	\N	\N	f	0	\N
11455	76	219	\N	0	\N	\N	f	0	\N
11456	76	323	\N	0	\N	\N	f	0	\N
11457	76	322	\N	0	\N	\N	f	0	\N
11458	76	321	\N	0	\N	\N	f	0	\N
11459	76	320	\N	0	\N	\N	f	0	\N
11460	76	319	\N	0	\N	\N	f	0	\N
11461	76	318	\N	0	\N	\N	f	0	\N
11462	76	317	\N	0	\N	\N	f	0	\N
11463	76	316	\N	0	\N	\N	f	0	\N
11464	76	315	\N	0	\N	\N	f	0	\N
11465	76	314	\N	0	\N	\N	f	0	\N
11466	76	313	\N	0	\N	\N	f	0	\N
11467	76	312	\N	0	\N	\N	f	0	\N
11468	76	311	\N	0	\N	\N	f	0	\N
11469	76	310	\N	0	\N	\N	f	0	\N
11470	76	309	\N	0	\N	\N	f	0	\N
11471	76	308	\N	0	\N	\N	f	0	\N
11472	76	307	\N	0	\N	\N	f	0	\N
11473	76	306	\N	0	\N	\N	f	0	\N
11474	76	305	\N	0	\N	\N	f	0	\N
11475	76	304	\N	0	\N	\N	f	0	\N
11476	76	303	\N	0	\N	\N	f	0	\N
11477	76	302	\N	0	\N	\N	f	0	\N
11478	76	301	\N	0	\N	\N	f	0	\N
11479	76	300	\N	0	\N	\N	f	0	\N
11480	76	299	\N	0	\N	\N	f	0	\N
11481	76	298	\N	0	\N	\N	f	0	\N
11482	76	297	\N	0	\N	\N	f	0	\N
11483	76	296	\N	0	\N	\N	f	0	\N
11484	76	295	\N	0	\N	\N	f	0	\N
11485	76	294	\N	0	\N	\N	f	0	\N
11486	76	293	\N	0	\N	\N	f	0	\N
11487	76	292	\N	0	\N	\N	f	0	\N
11488	76	291	\N	0	\N	\N	f	0	\N
11489	76	145	\N	0	\N	\N	f	0	\N
11490	76	144	\N	0	\N	\N	f	0	\N
11491	76	143	\N	0	\N	\N	f	0	\N
11492	76	142	\N	0	\N	\N	f	0	\N
11493	76	141	\N	0	\N	\N	f	0	\N
11494	76	140	\N	0	\N	\N	f	0	\N
11495	76	139	\N	0	\N	\N	f	0	\N
11496	76	138	\N	0	\N	\N	f	0	\N
11497	76	137	\N	0	\N	\N	f	0	\N
11498	76	136	\N	0	\N	\N	f	0	\N
11499	76	135	\N	0	\N	\N	f	0	\N
11500	76	134	\N	0	\N	\N	f	0	\N
11501	76	133	\N	0	\N	\N	f	0	\N
11502	76	132	\N	0	\N	\N	f	0	\N
11503	76	131	\N	0	\N	\N	f	0	\N
11504	76	130	\N	0	\N	\N	f	0	\N
11505	76	129	\N	0	\N	\N	f	0	\N
11506	76	128	\N	0	\N	\N	f	0	\N
11507	76	127	\N	0	\N	\N	f	0	\N
11508	76	126	\N	0	\N	\N	f	0	\N
11509	76	125	\N	0	\N	\N	f	0	\N
11510	76	124	\N	0	\N	\N	f	0	\N
11511	76	123	\N	0	\N	\N	f	0	\N
11512	76	122	\N	0	\N	\N	f	0	\N
11513	76	121	\N	0	\N	\N	f	0	\N
11514	76	120	\N	0	\N	\N	f	0	\N
11515	76	119	\N	0	\N	\N	f	0	\N
11516	76	118	\N	0	\N	\N	f	0	\N
11517	76	117	\N	0	\N	\N	f	0	\N
11518	76	116	\N	0	\N	\N	f	0	\N
11519	76	115	\N	0	\N	\N	f	0	\N
11520	76	114	\N	0	\N	\N	f	0	\N
11521	76	113	\N	0	\N	\N	f	0	\N
11522	76	112	\N	0	\N	\N	f	0	\N
11523	76	111	\N	0	\N	\N	f	0	\N
11524	76	110	\N	0	\N	\N	f	0	\N
11525	76	290	\N	0	\N	\N	f	0	\N
11526	76	289	\N	0	\N	\N	f	0	\N
11527	76	288	\N	0	\N	\N	f	0	\N
11528	76	287	\N	0	\N	\N	f	0	\N
11529	76	286	\N	0	\N	\N	f	0	\N
11530	76	285	\N	0	\N	\N	f	0	\N
11531	76	284	\N	0	\N	\N	f	0	\N
11532	76	283	\N	0	\N	\N	f	0	\N
11533	76	282	\N	0	\N	\N	f	0	\N
11534	76	281	\N	0	\N	\N	f	0	\N
11535	76	280	\N	0	\N	\N	f	0	\N
11536	76	279	\N	0	\N	\N	f	0	\N
11537	76	278	\N	0	\N	\N	f	0	\N
11538	76	277	\N	0	\N	\N	f	0	\N
11539	76	276	\N	0	\N	\N	f	0	\N
11540	76	275	\N	0	\N	\N	f	0	\N
11541	76	274	\N	0	\N	\N	f	0	\N
11542	76	273	\N	0	\N	\N	f	0	\N
11543	76	272	\N	0	\N	\N	f	0	\N
11544	76	271	\N	0	\N	\N	f	0	\N
11545	76	270	\N	0	\N	\N	f	0	\N
11546	76	269	\N	0	\N	\N	f	0	\N
11547	76	268	\N	0	\N	\N	f	0	\N
11548	76	267	\N	0	\N	\N	f	0	\N
11549	76	266	\N	0	\N	\N	f	0	\N
11550	76	265	\N	0	\N	\N	f	0	\N
11551	76	264	\N	0	\N	\N	f	0	\N
11552	76	263	\N	0	\N	\N	f	0	\N
11553	76	262	\N	0	\N	\N	f	0	\N
11554	76	261	\N	0	\N	\N	f	0	\N
11555	76	260	\N	0	\N	\N	f	0	\N
11556	76	259	\N	0	\N	\N	f	0	\N
11557	76	258	\N	0	\N	\N	f	0	\N
11558	76	257	\N	0	\N	\N	f	0	\N
11559	76	256	\N	0	\N	\N	f	0	\N
11560	76	255	\N	0	\N	\N	f	0	\N
11561	76	218	\N	0	\N	\N	f	0	\N
11562	76	217	\N	0	\N	\N	f	0	\N
11563	76	216	\N	0	\N	\N	f	0	\N
11564	76	215	\N	0	\N	\N	f	0	\N
11565	76	214	\N	0	\N	\N	f	0	\N
11566	76	213	\N	0	\N	\N	f	0	\N
11567	76	212	\N	0	\N	\N	f	0	\N
11568	76	211	\N	0	\N	\N	f	0	\N
11569	76	210	\N	0	\N	\N	f	0	\N
11570	76	209	\N	0	\N	\N	f	0	\N
11571	76	208	\N	0	\N	\N	f	0	\N
11572	76	207	\N	0	\N	\N	f	0	\N
11573	76	206	\N	0	\N	\N	f	0	\N
11574	76	205	\N	0	\N	\N	f	0	\N
11575	76	204	\N	0	\N	\N	f	0	\N
11576	76	203	\N	0	\N	\N	f	0	\N
11577	76	202	\N	0	\N	\N	f	0	\N
11578	76	201	\N	0	\N	\N	f	0	\N
11579	76	200	\N	0	\N	\N	f	0	\N
11580	76	199	\N	0	\N	\N	f	0	\N
11581	76	198	\N	0	\N	\N	f	0	\N
11582	76	197	\N	0	\N	\N	f	0	\N
11583	76	196	\N	0	\N	\N	f	0	\N
11584	76	195	\N	0	\N	\N	f	0	\N
11585	76	194	\N	0	\N	\N	f	0	\N
11586	76	193	\N	0	\N	\N	f	0	\N
11587	76	192	\N	0	\N	\N	f	0	\N
11588	76	191	\N	0	\N	\N	f	0	\N
11589	76	190	\N	0	\N	\N	f	0	\N
11590	76	189	\N	0	\N	\N	f	0	\N
11591	76	188	\N	0	\N	\N	f	0	\N
11592	76	187	\N	0	\N	\N	f	0	\N
11593	76	186	\N	0	\N	\N	f	0	\N
11594	76	185	\N	0	\N	\N	f	0	\N
11595	76	184	\N	0	\N	\N	f	0	\N
11596	76	183	\N	0	\N	\N	f	0	\N
11597	76	182	\N	0	\N	\N	f	0	\N
11598	76	181	\N	0	\N	\N	f	0	\N
11599	77	180	\N	0	\N	\N	f	0	\N
11600	77	179	\N	0	\N	\N	f	0	\N
11601	77	178	\N	0	\N	\N	f	0	\N
11602	77	177	\N	0	\N	\N	f	0	\N
11603	77	176	\N	0	\N	\N	f	0	\N
11604	77	175	\N	0	\N	\N	f	0	\N
11605	77	174	\N	0	\N	\N	f	0	\N
11606	77	173	\N	0	\N	\N	f	0	\N
11607	77	172	\N	0	\N	\N	f	0	\N
11608	77	171	\N	0	\N	\N	f	0	\N
11609	77	170	\N	0	\N	\N	f	0	\N
11610	77	169	\N	0	\N	\N	f	0	\N
11611	77	168	\N	0	\N	\N	f	0	\N
11612	77	167	\N	0	\N	\N	f	0	\N
11613	77	166	\N	0	\N	\N	f	0	\N
11614	77	165	\N	0	\N	\N	f	0	\N
11615	77	164	\N	0	\N	\N	f	0	\N
11616	77	163	\N	0	\N	\N	f	0	\N
11617	77	162	\N	0	\N	\N	f	0	\N
11618	77	161	\N	0	\N	\N	f	0	\N
11619	77	160	\N	0	\N	\N	f	0	\N
11620	77	159	\N	0	\N	\N	f	0	\N
11621	77	158	\N	0	\N	\N	f	0	\N
11622	77	157	\N	0	\N	\N	f	0	\N
11623	77	156	\N	0	\N	\N	f	0	\N
11624	77	155	\N	0	\N	\N	f	0	\N
11625	77	154	\N	0	\N	\N	f	0	\N
11626	77	153	\N	0	\N	\N	f	0	\N
11627	77	152	\N	0	\N	\N	f	0	\N
11628	77	151	\N	0	\N	\N	f	0	\N
11629	77	150	\N	0	\N	\N	f	0	\N
11630	77	149	\N	0	\N	\N	f	0	\N
11631	77	148	\N	0	\N	\N	f	0	\N
11632	77	147	\N	0	\N	\N	f	0	\N
11633	77	146	\N	0	\N	\N	f	0	\N
11634	77	218	\N	0	\N	\N	f	0	\N
11635	77	217	\N	0	\N	\N	f	0	\N
11636	77	216	\N	0	\N	\N	f	0	\N
11637	77	215	\N	0	\N	\N	f	0	\N
11638	77	214	\N	0	\N	\N	f	0	\N
11639	77	213	\N	0	\N	\N	f	0	\N
11640	77	212	\N	0	\N	\N	f	0	\N
11641	77	211	\N	0	\N	\N	f	0	\N
11642	77	210	\N	0	\N	\N	f	0	\N
11643	77	209	\N	0	\N	\N	f	0	\N
11644	77	208	\N	0	\N	\N	f	0	\N
11645	77	207	\N	0	\N	\N	f	0	\N
11646	77	206	\N	0	\N	\N	f	0	\N
11647	77	205	\N	0	\N	\N	f	0	\N
11648	77	204	\N	0	\N	\N	f	0	\N
11649	77	203	\N	0	\N	\N	f	0	\N
11650	77	202	\N	0	\N	\N	f	0	\N
11651	77	201	\N	0	\N	\N	f	0	\N
11652	77	200	\N	0	\N	\N	f	0	\N
11653	77	199	\N	0	\N	\N	f	0	\N
11654	77	198	\N	0	\N	\N	f	0	\N
11655	77	197	\N	0	\N	\N	f	0	\N
11656	77	196	\N	0	\N	\N	f	0	\N
11657	77	195	\N	0	\N	\N	f	0	\N
11658	77	194	\N	0	\N	\N	f	0	\N
11659	77	193	\N	0	\N	\N	f	0	\N
11660	77	192	\N	0	\N	\N	f	0	\N
11661	77	191	\N	0	\N	\N	f	0	\N
11662	77	190	\N	0	\N	\N	f	0	\N
11663	77	189	\N	0	\N	\N	f	0	\N
11664	77	188	\N	0	\N	\N	f	0	\N
11665	77	187	\N	0	\N	\N	f	0	\N
11666	77	186	\N	0	\N	\N	f	0	\N
11667	77	185	\N	0	\N	\N	f	0	\N
11668	77	184	\N	0	\N	\N	f	0	\N
11669	77	183	\N	0	\N	\N	f	0	\N
11670	77	182	\N	0	\N	\N	f	0	\N
11671	77	181	\N	0	\N	\N	f	0	\N
11672	77	323	\N	0	\N	\N	f	0	\N
11673	77	322	\N	0	\N	\N	f	0	\N
11674	77	321	\N	0	\N	\N	f	0	\N
11675	77	320	\N	0	\N	\N	f	0	\N
11676	77	319	\N	0	\N	\N	f	0	\N
11677	77	318	\N	0	\N	\N	f	0	\N
11678	77	317	\N	0	\N	\N	f	0	\N
11679	77	316	\N	0	\N	\N	f	0	\N
11680	77	315	\N	0	\N	\N	f	0	\N
11681	77	314	\N	0	\N	\N	f	0	\N
11682	77	313	\N	0	\N	\N	f	0	\N
11683	77	312	\N	0	\N	\N	f	0	\N
11684	77	311	\N	0	\N	\N	f	0	\N
11685	77	310	\N	0	\N	\N	f	0	\N
11686	77	309	\N	0	\N	\N	f	0	\N
11687	77	308	\N	0	\N	\N	f	0	\N
11688	77	307	\N	0	\N	\N	f	0	\N
11689	77	306	\N	0	\N	\N	f	0	\N
11690	77	305	\N	0	\N	\N	f	0	\N
11691	77	304	\N	0	\N	\N	f	0	\N
11692	77	303	\N	0	\N	\N	f	0	\N
11693	77	302	\N	0	\N	\N	f	0	\N
11694	77	301	\N	0	\N	\N	f	0	\N
11695	77	300	\N	0	\N	\N	f	0	\N
11696	77	299	\N	0	\N	\N	f	0	\N
11697	77	298	\N	0	\N	\N	f	0	\N
11698	77	297	\N	0	\N	\N	f	0	\N
11699	77	296	\N	0	\N	\N	f	0	\N
11700	77	295	\N	0	\N	\N	f	0	\N
11701	77	294	\N	0	\N	\N	f	0	\N
11702	77	293	\N	0	\N	\N	f	0	\N
11703	77	292	\N	0	\N	\N	f	0	\N
11704	77	291	\N	0	\N	\N	f	0	\N
11705	77	109	\N	0	\N	\N	f	0	\N
11706	77	108	\N	0	\N	\N	f	0	\N
11707	77	107	\N	0	\N	\N	f	0	\N
11708	77	106	\N	0	\N	\N	f	0	\N
11709	77	105	\N	0	\N	\N	f	0	\N
11710	77	104	\N	0	\N	\N	f	0	\N
11711	77	103	\N	0	\N	\N	f	0	\N
11712	77	102	\N	0	\N	\N	f	0	\N
11713	77	101	\N	0	\N	\N	f	0	\N
11714	77	100	\N	0	\N	\N	f	0	\N
11715	77	99	\N	0	\N	\N	f	0	\N
11716	77	98	\N	0	\N	\N	f	0	\N
11717	77	97	\N	0	\N	\N	f	0	\N
11718	77	96	\N	0	\N	\N	f	0	\N
11719	77	95	\N	0	\N	\N	f	0	\N
11720	77	94	\N	0	\N	\N	f	0	\N
11721	77	93	\N	0	\N	\N	f	0	\N
11722	77	92	\N	0	\N	\N	f	0	\N
11723	77	91	\N	0	\N	\N	f	0	\N
11724	77	90	\N	0	\N	\N	f	0	\N
11725	77	89	\N	0	\N	\N	f	0	\N
11726	77	88	\N	0	\N	\N	f	0	\N
11727	77	87	\N	0	\N	\N	f	0	\N
11728	77	86	\N	0	\N	\N	f	0	\N
11729	77	85	\N	0	\N	\N	f	0	\N
11730	77	84	\N	0	\N	\N	f	0	\N
11731	77	83	\N	0	\N	\N	f	0	\N
11732	77	82	\N	0	\N	\N	f	0	\N
11733	77	81	\N	0	\N	\N	f	0	\N
11734	77	80	\N	0	\N	\N	f	0	\N
11735	77	79	\N	0	\N	\N	f	0	\N
11736	77	78	\N	0	\N	\N	f	0	\N
11737	77	77	\N	0	\N	\N	f	0	\N
11738	77	76	\N	0	\N	\N	f	0	\N
11739	77	75	\N	0	\N	\N	f	0	\N
11740	77	360	\N	0	\N	\N	f	0	\N
11741	77	359	\N	0	\N	\N	f	0	\N
11742	77	358	\N	0	\N	\N	f	0	\N
11743	77	357	\N	0	\N	\N	f	0	\N
11744	77	356	\N	0	\N	\N	f	0	\N
11745	77	355	\N	0	\N	\N	f	0	\N
11746	77	354	\N	0	\N	\N	f	0	\N
11747	77	353	\N	0	\N	\N	f	0	\N
11748	77	352	\N	0	\N	\N	f	0	\N
11749	77	351	\N	0	\N	\N	f	0	\N
11750	77	350	\N	0	\N	\N	f	0	\N
11751	77	349	\N	0	\N	\N	f	0	\N
11752	77	348	\N	0	\N	\N	f	0	\N
11753	77	347	\N	0	\N	\N	f	0	\N
11754	77	346	\N	0	\N	\N	f	0	\N
11755	77	345	\N	0	\N	\N	f	0	\N
11756	77	344	\N	0	\N	\N	f	0	\N
11757	77	343	\N	0	\N	\N	f	0	\N
11758	77	342	\N	0	\N	\N	f	0	\N
11759	77	341	\N	0	\N	\N	f	0	\N
11760	77	340	\N	0	\N	\N	f	0	\N
11761	77	339	\N	0	\N	\N	f	0	\N
11762	77	338	\N	0	\N	\N	f	0	\N
11763	77	337	\N	0	\N	\N	f	0	\N
11764	77	336	\N	0	\N	\N	f	0	\N
11765	77	335	\N	0	\N	\N	f	0	\N
11766	77	334	\N	0	\N	\N	f	0	\N
11767	77	333	\N	0	\N	\N	f	0	\N
11768	77	332	\N	0	\N	\N	f	0	\N
11769	77	331	\N	0	\N	\N	f	0	\N
11770	77	330	\N	0	\N	\N	f	0	\N
11771	77	329	\N	0	\N	\N	f	0	\N
11772	77	328	\N	0	\N	\N	f	0	\N
11773	77	327	\N	0	\N	\N	f	0	\N
11774	77	326	\N	0	\N	\N	f	0	\N
11775	77	325	\N	0	\N	\N	f	0	\N
11776	77	324	\N	0	\N	\N	f	0	\N
11777	77	74	\N	0	\N	\N	f	0	\N
11778	77	73	\N	0	\N	\N	f	0	\N
11779	77	72	\N	0	\N	\N	f	0	\N
11780	77	71	\N	0	\N	\N	f	0	\N
11781	77	70	\N	0	\N	\N	f	0	\N
11782	77	69	\N	0	\N	\N	f	0	\N
11783	77	68	\N	0	\N	\N	f	0	\N
11784	77	67	\N	0	\N	\N	f	0	\N
11785	77	66	\N	0	\N	\N	f	0	\N
11786	77	65	\N	0	\N	\N	f	0	\N
11787	77	64	\N	0	\N	\N	f	0	\N
11788	77	63	\N	0	\N	\N	f	0	\N
11789	77	62	\N	0	\N	\N	f	0	\N
11790	77	61	\N	0	\N	\N	f	0	\N
11791	77	60	\N	0	\N	\N	f	0	\N
11792	77	59	\N	0	\N	\N	f	0	\N
11793	77	58	\N	0	\N	\N	f	0	\N
11794	77	57	\N	0	\N	\N	f	0	\N
11795	77	56	\N	0	\N	\N	f	0	\N
11796	77	55	\N	0	\N	\N	f	0	\N
11797	77	54	\N	0	\N	\N	f	0	\N
11798	77	53	\N	0	\N	\N	f	0	\N
11799	77	52	\N	0	\N	\N	f	0	\N
11800	77	51	\N	0	\N	\N	f	0	\N
11801	77	50	\N	0	\N	\N	f	0	\N
11802	77	49	\N	0	\N	\N	f	0	\N
11803	77	48	\N	0	\N	\N	f	0	\N
11804	77	47	\N	0	\N	\N	f	0	\N
11805	77	46	\N	0	\N	\N	f	0	\N
11806	77	45	\N	0	\N	\N	f	0	\N
11807	77	44	\N	0	\N	\N	f	0	\N
11808	77	43	\N	0	\N	\N	f	0	\N
11809	77	42	\N	0	\N	\N	f	0	\N
11810	77	41	\N	0	\N	\N	f	0	\N
11811	77	40	\N	0	\N	\N	f	0	\N
11812	77	39	\N	0	\N	\N	f	0	\N
11813	77	38	\N	0	\N	\N	f	0	\N
11814	77	37	\N	0	\N	\N	f	0	\N
11815	77	36	\N	0	\N	\N	f	0	\N
11816	77	35	\N	0	\N	\N	f	0	\N
11817	77	34	\N	0	\N	\N	f	0	\N
11818	77	33	\N	0	\N	\N	f	0	\N
11819	77	32	\N	0	\N	\N	f	0	\N
11820	77	31	\N	0	\N	\N	f	0	\N
11821	77	30	\N	0	\N	\N	f	0	\N
11822	77	29	\N	0	\N	\N	f	0	\N
11823	77	28	\N	0	\N	\N	f	0	\N
11824	77	27	\N	0	\N	\N	f	0	\N
11825	77	26	\N	0	\N	\N	f	0	\N
11826	77	25	\N	0	\N	\N	f	0	\N
11827	77	24	\N	0	\N	\N	f	0	\N
11828	77	23	\N	0	\N	\N	f	0	\N
11829	77	22	\N	0	\N	\N	f	0	\N
11830	77	21	\N	0	\N	\N	f	0	\N
11831	77	20	\N	0	\N	\N	f	0	\N
11832	77	19	\N	0	\N	\N	f	0	\N
11833	77	18	\N	0	\N	\N	f	0	\N
11834	77	17	\N	0	\N	\N	f	0	\N
11835	77	16	\N	0	\N	\N	f	0	\N
11836	77	15	\N	0	\N	\N	f	0	\N
11837	77	14	\N	0	\N	\N	f	0	\N
11838	77	13	\N	0	\N	\N	f	0	\N
11839	77	12	\N	0	\N	\N	f	0	\N
11840	77	11	\N	0	\N	\N	f	0	\N
11841	77	10	\N	0	\N	\N	f	0	\N
11842	77	9	\N	0	\N	\N	f	0	\N
11843	77	8	\N	0	\N	\N	f	0	\N
11844	77	7	\N	0	\N	\N	f	0	\N
11845	77	6	\N	0	\N	\N	f	0	\N
11846	77	5	\N	0	\N	\N	f	0	\N
11847	77	4	\N	0	\N	\N	f	0	\N
11848	77	3	\N	0	\N	\N	f	0	\N
11849	77	2	\N	0	\N	\N	f	0	\N
11850	77	1	\N	0	\N	\N	f	0	\N
11851	77	432	\N	0	\N	\N	f	0	\N
11852	77	431	\N	0	\N	\N	f	0	\N
11853	77	430	\N	0	\N	\N	f	0	\N
11854	77	429	\N	0	\N	\N	f	0	\N
11855	77	428	\N	0	\N	\N	f	0	\N
11856	77	427	\N	0	\N	\N	f	0	\N
11857	77	426	\N	0	\N	\N	f	0	\N
11858	77	425	\N	0	\N	\N	f	0	\N
11859	77	424	\N	0	\N	\N	f	0	\N
11860	77	423	\N	0	\N	\N	f	0	\N
11861	77	422	\N	0	\N	\N	f	0	\N
11862	77	421	\N	0	\N	\N	f	0	\N
11863	77	420	\N	0	\N	\N	f	0	\N
11864	77	419	\N	0	\N	\N	f	0	\N
11865	77	418	\N	0	\N	\N	f	0	\N
11866	77	417	\N	0	\N	\N	f	0	\N
11867	77	416	\N	0	\N	\N	f	0	\N
11868	77	415	\N	0	\N	\N	f	0	\N
11869	77	414	\N	0	\N	\N	f	0	\N
11870	77	413	\N	0	\N	\N	f	0	\N
11871	77	412	\N	0	\N	\N	f	0	\N
11872	77	411	\N	0	\N	\N	f	0	\N
11873	77	410	\N	0	\N	\N	f	0	\N
11874	77	409	\N	0	\N	\N	f	0	\N
11875	77	408	\N	0	\N	\N	f	0	\N
11876	77	407	\N	0	\N	\N	f	0	\N
11877	77	406	\N	0	\N	\N	f	0	\N
11878	77	405	\N	0	\N	\N	f	0	\N
11879	77	404	\N	0	\N	\N	f	0	\N
11880	77	403	\N	0	\N	\N	f	0	\N
11881	77	402	\N	0	\N	\N	f	0	\N
11882	77	401	\N	0	\N	\N	f	0	\N
11883	77	400	\N	0	\N	\N	f	0	\N
11884	77	399	\N	0	\N	\N	f	0	\N
11885	77	398	\N	0	\N	\N	f	0	\N
11886	77	397	\N	0	\N	\N	f	0	\N
11887	77	396	\N	0	\N	\N	f	0	\N
11888	77	395	\N	0	\N	\N	f	0	\N
11889	77	394	\N	0	\N	\N	f	0	\N
11890	77	393	\N	0	\N	\N	f	0	\N
11891	77	392	\N	0	\N	\N	f	0	\N
11892	77	391	\N	0	\N	\N	f	0	\N
11893	77	390	\N	0	\N	\N	f	0	\N
11894	77	389	\N	0	\N	\N	f	0	\N
11895	77	388	\N	0	\N	\N	f	0	\N
11896	77	387	\N	0	\N	\N	f	0	\N
11897	77	386	\N	0	\N	\N	f	0	\N
11898	77	385	\N	0	\N	\N	f	0	\N
11899	77	384	\N	0	\N	\N	f	0	\N
11900	77	383	\N	0	\N	\N	f	0	\N
11901	77	382	\N	0	\N	\N	f	0	\N
11902	77	381	\N	0	\N	\N	f	0	\N
11903	77	380	\N	0	\N	\N	f	0	\N
11904	77	379	\N	0	\N	\N	f	0	\N
11905	77	378	\N	0	\N	\N	f	0	\N
11906	77	377	\N	0	\N	\N	f	0	\N
11907	77	376	\N	0	\N	\N	f	0	\N
11908	77	375	\N	0	\N	\N	f	0	\N
11909	77	374	\N	0	\N	\N	f	0	\N
11910	77	373	\N	0	\N	\N	f	0	\N
11911	77	372	\N	0	\N	\N	f	0	\N
11912	77	371	\N	0	\N	\N	f	0	\N
11913	77	370	\N	0	\N	\N	f	0	\N
11914	77	369	\N	0	\N	\N	f	0	\N
11915	77	368	\N	0	\N	\N	f	0	\N
11916	77	367	\N	0	\N	\N	f	0	\N
11917	77	366	\N	0	\N	\N	f	0	\N
11918	77	365	\N	0	\N	\N	f	0	\N
11919	77	364	\N	0	\N	\N	f	0	\N
11920	77	363	\N	0	\N	\N	f	0	\N
11921	77	362	\N	0	\N	\N	f	0	\N
11922	77	361	\N	0	\N	\N	f	0	\N
11923	77	145	\N	0	\N	\N	f	0	\N
11924	77	144	\N	0	\N	\N	f	0	\N
11925	77	143	\N	0	\N	\N	f	0	\N
11926	77	142	\N	0	\N	\N	f	0	\N
11927	77	141	\N	0	\N	\N	f	0	\N
11928	77	140	\N	0	\N	\N	f	0	\N
11929	77	139	\N	0	\N	\N	f	0	\N
11930	77	138	\N	0	\N	\N	f	0	\N
11931	77	137	\N	0	\N	\N	f	0	\N
11932	77	136	\N	0	\N	\N	f	0	\N
11933	77	135	\N	0	\N	\N	f	0	\N
11934	77	134	\N	0	\N	\N	f	0	\N
11935	77	133	\N	0	\N	\N	f	0	\N
11936	77	132	\N	0	\N	\N	f	0	\N
11937	77	131	\N	0	\N	\N	f	0	\N
11938	77	130	\N	0	\N	\N	f	0	\N
11939	77	129	\N	0	\N	\N	f	0	\N
11940	77	128	\N	0	\N	\N	f	0	\N
11941	77	127	\N	0	\N	\N	f	0	\N
11942	77	126	\N	0	\N	\N	f	0	\N
11943	77	125	\N	0	\N	\N	f	0	\N
11944	77	124	\N	0	\N	\N	f	0	\N
11945	77	123	\N	0	\N	\N	f	0	\N
11946	77	122	\N	0	\N	\N	f	0	\N
11947	77	121	\N	0	\N	\N	f	0	\N
11948	77	120	\N	0	\N	\N	f	0	\N
11949	77	119	\N	0	\N	\N	f	0	\N
11950	77	118	\N	0	\N	\N	f	0	\N
11951	77	117	\N	0	\N	\N	f	0	\N
11952	77	116	\N	0	\N	\N	f	0	\N
11953	77	115	\N	0	\N	\N	f	0	\N
11954	77	114	\N	0	\N	\N	f	0	\N
11955	77	113	\N	0	\N	\N	f	0	\N
11956	77	112	\N	0	\N	\N	f	0	\N
11957	77	111	\N	0	\N	\N	f	0	\N
11958	77	110	\N	0	\N	\N	f	0	\N
11959	78	145	\N	0	\N	\N	f	0	\N
11960	78	144	\N	0	\N	\N	f	0	\N
11961	78	143	\N	0	\N	\N	f	0	\N
11962	78	142	\N	0	\N	\N	f	0	\N
11963	78	141	\N	0	\N	\N	f	0	\N
11964	78	140	\N	0	\N	\N	f	0	\N
11965	78	139	\N	0	\N	\N	f	0	\N
11966	78	138	\N	0	\N	\N	f	0	\N
11967	78	137	\N	0	\N	\N	f	0	\N
11968	78	136	\N	0	\N	\N	f	0	\N
11969	78	135	\N	0	\N	\N	f	0	\N
11970	78	134	\N	0	\N	\N	f	0	\N
11971	78	133	\N	0	\N	\N	f	0	\N
11972	78	132	\N	0	\N	\N	f	0	\N
11973	78	131	\N	0	\N	\N	f	0	\N
11974	78	130	\N	0	\N	\N	f	0	\N
11975	78	129	\N	0	\N	\N	f	0	\N
11976	78	128	\N	0	\N	\N	f	0	\N
11977	78	127	\N	0	\N	\N	f	0	\N
11978	78	126	\N	0	\N	\N	f	0	\N
11979	78	125	\N	0	\N	\N	f	0	\N
11980	78	124	\N	0	\N	\N	f	0	\N
11981	78	123	\N	0	\N	\N	f	0	\N
11982	78	122	\N	0	\N	\N	f	0	\N
11983	78	121	\N	0	\N	\N	f	0	\N
11984	78	120	\N	0	\N	\N	f	0	\N
11985	78	119	\N	0	\N	\N	f	0	\N
11986	78	118	\N	0	\N	\N	f	0	\N
11987	78	117	\N	0	\N	\N	f	0	\N
11988	78	116	\N	0	\N	\N	f	0	\N
11989	78	115	\N	0	\N	\N	f	0	\N
11990	78	114	\N	0	\N	\N	f	0	\N
11991	78	113	\N	0	\N	\N	f	0	\N
11992	78	112	\N	0	\N	\N	f	0	\N
11993	78	111	\N	0	\N	\N	f	0	\N
11994	78	110	\N	0	\N	\N	f	0	\N
11995	78	109	\N	0	\N	\N	f	0	\N
11996	78	108	\N	0	\N	\N	f	0	\N
11997	78	107	\N	0	\N	\N	f	0	\N
11998	78	106	\N	0	\N	\N	f	0	\N
11999	78	105	\N	0	\N	\N	f	0	\N
12000	78	104	\N	0	\N	\N	f	0	\N
12001	78	103	\N	0	\N	\N	f	0	\N
12002	78	102	\N	0	\N	\N	f	0	\N
12003	78	101	\N	0	\N	\N	f	0	\N
12004	78	100	\N	0	\N	\N	f	0	\N
12005	78	99	\N	0	\N	\N	f	0	\N
12006	78	98	\N	0	\N	\N	f	0	\N
12007	78	97	\N	0	\N	\N	f	0	\N
12008	78	96	\N	0	\N	\N	f	0	\N
12009	78	95	\N	0	\N	\N	f	0	\N
12010	78	94	\N	0	\N	\N	f	0	\N
12011	78	93	\N	0	\N	\N	f	0	\N
12012	78	92	\N	0	\N	\N	f	0	\N
12013	78	91	\N	0	\N	\N	f	0	\N
12014	78	90	\N	0	\N	\N	f	0	\N
12015	78	89	\N	0	\N	\N	f	0	\N
12016	78	88	\N	0	\N	\N	f	0	\N
12017	78	87	\N	0	\N	\N	f	0	\N
12018	78	86	\N	0	\N	\N	f	0	\N
12019	78	85	\N	0	\N	\N	f	0	\N
12020	78	84	\N	0	\N	\N	f	0	\N
12021	78	83	\N	0	\N	\N	f	0	\N
12022	78	82	\N	0	\N	\N	f	0	\N
12023	78	81	\N	0	\N	\N	f	0	\N
12024	78	80	\N	0	\N	\N	f	0	\N
12025	78	79	\N	0	\N	\N	f	0	\N
12026	78	78	\N	0	\N	\N	f	0	\N
12027	78	77	\N	0	\N	\N	f	0	\N
12028	78	76	\N	0	\N	\N	f	0	\N
12029	78	75	\N	0	\N	\N	f	0	\N
12030	78	290	\N	0	\N	\N	f	0	\N
12031	78	289	\N	0	\N	\N	f	0	\N
12032	78	288	\N	0	\N	\N	f	0	\N
12033	78	287	\N	0	\N	\N	f	0	\N
12034	78	286	\N	0	\N	\N	f	0	\N
12035	78	285	\N	0	\N	\N	f	0	\N
12036	78	284	\N	0	\N	\N	f	0	\N
12037	78	283	\N	0	\N	\N	f	0	\N
12038	78	282	\N	0	\N	\N	f	0	\N
12039	78	281	\N	0	\N	\N	f	0	\N
12040	78	280	\N	0	\N	\N	f	0	\N
12041	78	279	\N	0	\N	\N	f	0	\N
12042	78	278	\N	0	\N	\N	f	0	\N
12043	78	277	\N	0	\N	\N	f	0	\N
12044	78	276	\N	0	\N	\N	f	0	\N
12045	78	275	\N	0	\N	\N	f	0	\N
12046	78	274	\N	0	\N	\N	f	0	\N
12047	78	273	\N	0	\N	\N	f	0	\N
12048	78	272	\N	0	\N	\N	f	0	\N
12049	78	271	\N	0	\N	\N	f	0	\N
12050	78	270	\N	0	\N	\N	f	0	\N
12051	78	269	\N	0	\N	\N	f	0	\N
12052	78	268	\N	0	\N	\N	f	0	\N
12053	78	267	\N	0	\N	\N	f	0	\N
12054	78	266	\N	0	\N	\N	f	0	\N
12055	78	265	\N	0	\N	\N	f	0	\N
12056	78	264	\N	0	\N	\N	f	0	\N
12057	78	263	\N	0	\N	\N	f	0	\N
12058	78	262	\N	0	\N	\N	f	0	\N
12059	78	261	\N	0	\N	\N	f	0	\N
12060	78	260	\N	0	\N	\N	f	0	\N
12061	78	259	\N	0	\N	\N	f	0	\N
12062	78	258	\N	0	\N	\N	f	0	\N
12063	78	257	\N	0	\N	\N	f	0	\N
12064	78	256	\N	0	\N	\N	f	0	\N
12065	78	255	\N	0	\N	\N	f	0	\N
12066	78	323	\N	0	\N	\N	f	0	\N
12067	78	322	\N	0	\N	\N	f	0	\N
12068	78	321	\N	0	\N	\N	f	0	\N
12069	78	320	\N	0	\N	\N	f	0	\N
12070	78	319	\N	0	\N	\N	f	0	\N
12071	78	318	\N	0	\N	\N	f	0	\N
12072	78	317	\N	0	\N	\N	f	0	\N
12073	78	316	\N	0	\N	\N	f	0	\N
12074	78	315	\N	0	\N	\N	f	0	\N
12075	78	314	\N	0	\N	\N	f	0	\N
12076	78	313	\N	0	\N	\N	f	0	\N
12077	78	312	\N	0	\N	\N	f	0	\N
12078	78	311	\N	0	\N	\N	f	0	\N
12079	78	310	\N	0	\N	\N	f	0	\N
12080	78	309	\N	0	\N	\N	f	0	\N
12081	78	308	\N	0	\N	\N	f	0	\N
12082	78	307	\N	0	\N	\N	f	0	\N
12083	78	306	\N	0	\N	\N	f	0	\N
12084	78	305	\N	0	\N	\N	f	0	\N
12085	78	304	\N	0	\N	\N	f	0	\N
12086	78	303	\N	0	\N	\N	f	0	\N
12087	78	302	\N	0	\N	\N	f	0	\N
12088	78	301	\N	0	\N	\N	f	0	\N
12089	78	300	\N	0	\N	\N	f	0	\N
12090	78	299	\N	0	\N	\N	f	0	\N
12091	78	298	\N	0	\N	\N	f	0	\N
12092	78	297	\N	0	\N	\N	f	0	\N
12093	78	296	\N	0	\N	\N	f	0	\N
12094	78	295	\N	0	\N	\N	f	0	\N
12095	78	294	\N	0	\N	\N	f	0	\N
12096	78	293	\N	0	\N	\N	f	0	\N
12097	78	292	\N	0	\N	\N	f	0	\N
12098	78	291	\N	0	\N	\N	f	0	\N
12099	78	74	\N	0	\N	\N	f	0	\N
12100	78	73	\N	0	\N	\N	f	0	\N
12101	78	72	\N	0	\N	\N	f	0	\N
12102	78	71	\N	0	\N	\N	f	0	\N
12103	78	70	\N	0	\N	\N	f	0	\N
12104	78	69	\N	0	\N	\N	f	0	\N
12105	78	68	\N	0	\N	\N	f	0	\N
12106	78	67	\N	0	\N	\N	f	0	\N
12107	78	66	\N	0	\N	\N	f	0	\N
12108	78	65	\N	0	\N	\N	f	0	\N
12109	78	64	\N	0	\N	\N	f	0	\N
12110	78	63	\N	0	\N	\N	f	0	\N
12111	78	62	\N	0	\N	\N	f	0	\N
12112	78	61	\N	0	\N	\N	f	0	\N
12113	78	60	\N	0	\N	\N	f	0	\N
12114	78	59	\N	0	\N	\N	f	0	\N
12115	78	58	\N	0	\N	\N	f	0	\N
12116	78	57	\N	0	\N	\N	f	0	\N
12117	78	56	\N	0	\N	\N	f	0	\N
12118	78	55	\N	0	\N	\N	f	0	\N
12119	78	54	\N	0	\N	\N	f	0	\N
12120	78	53	\N	0	\N	\N	f	0	\N
12121	78	52	\N	0	\N	\N	f	0	\N
12122	78	51	\N	0	\N	\N	f	0	\N
12123	78	50	\N	0	\N	\N	f	0	\N
12124	78	49	\N	0	\N	\N	f	0	\N
12125	78	48	\N	0	\N	\N	f	0	\N
12126	78	47	\N	0	\N	\N	f	0	\N
12127	78	46	\N	0	\N	\N	f	0	\N
12128	78	45	\N	0	\N	\N	f	0	\N
12129	78	44	\N	0	\N	\N	f	0	\N
12130	78	43	\N	0	\N	\N	f	0	\N
12131	78	42	\N	0	\N	\N	f	0	\N
12132	78	41	\N	0	\N	\N	f	0	\N
12133	78	40	\N	0	\N	\N	f	0	\N
12134	78	180	\N	0	\N	\N	f	0	\N
12135	78	179	\N	0	\N	\N	f	0	\N
12136	78	178	\N	0	\N	\N	f	0	\N
12137	78	177	\N	0	\N	\N	f	0	\N
12138	78	176	\N	0	\N	\N	f	0	\N
12139	78	175	\N	0	\N	\N	f	0	\N
12140	78	174	\N	0	\N	\N	f	0	\N
12141	78	173	\N	0	\N	\N	f	0	\N
12142	78	172	\N	0	\N	\N	f	0	\N
12143	78	171	\N	0	\N	\N	f	0	\N
12144	78	170	\N	0	\N	\N	f	0	\N
12145	78	169	\N	0	\N	\N	f	0	\N
12146	78	168	\N	0	\N	\N	f	0	\N
12147	78	167	\N	0	\N	\N	f	0	\N
12148	78	166	\N	0	\N	\N	f	0	\N
12149	78	165	\N	0	\N	\N	f	0	\N
12150	78	164	\N	0	\N	\N	f	0	\N
12151	78	163	\N	0	\N	\N	f	0	\N
12152	78	162	\N	0	\N	\N	f	0	\N
12153	78	161	\N	0	\N	\N	f	0	\N
12154	78	160	\N	0	\N	\N	f	0	\N
12155	78	159	\N	0	\N	\N	f	0	\N
12156	78	158	\N	0	\N	\N	f	0	\N
12157	78	157	\N	0	\N	\N	f	0	\N
12158	78	156	\N	0	\N	\N	f	0	\N
12159	78	155	\N	0	\N	\N	f	0	\N
12160	78	154	\N	0	\N	\N	f	0	\N
12161	78	153	\N	0	\N	\N	f	0	\N
12162	78	152	\N	0	\N	\N	f	0	\N
12163	78	151	\N	0	\N	\N	f	0	\N
12164	78	150	\N	0	\N	\N	f	0	\N
12165	78	149	\N	0	\N	\N	f	0	\N
12166	78	148	\N	0	\N	\N	f	0	\N
12167	78	147	\N	0	\N	\N	f	0	\N
12168	78	146	\N	0	\N	\N	f	0	\N
12169	78	254	\N	0	\N	\N	f	0	\N
12170	78	253	\N	0	\N	\N	f	0	\N
12171	78	252	\N	0	\N	\N	f	0	\N
12172	78	251	\N	0	\N	\N	f	0	\N
12173	78	250	\N	0	\N	\N	f	0	\N
12174	78	249	\N	0	\N	\N	f	0	\N
12175	78	248	\N	0	\N	\N	f	0	\N
12176	78	247	\N	0	\N	\N	f	0	\N
12177	78	246	\N	0	\N	\N	f	0	\N
12178	78	245	\N	0	\N	\N	f	0	\N
12179	78	244	\N	0	\N	\N	f	0	\N
12180	78	243	\N	0	\N	\N	f	0	\N
12181	78	242	\N	0	\N	\N	f	0	\N
12182	78	241	\N	0	\N	\N	f	0	\N
12183	78	240	\N	0	\N	\N	f	0	\N
12184	78	239	\N	0	\N	\N	f	0	\N
12185	78	238	\N	0	\N	\N	f	0	\N
12186	78	237	\N	0	\N	\N	f	0	\N
12187	78	236	\N	0	\N	\N	f	0	\N
12188	78	235	\N	0	\N	\N	f	0	\N
12189	78	234	\N	0	\N	\N	f	0	\N
12190	78	233	\N	0	\N	\N	f	0	\N
12191	78	232	\N	0	\N	\N	f	0	\N
12192	78	231	\N	0	\N	\N	f	0	\N
12193	78	230	\N	0	\N	\N	f	0	\N
12194	78	229	\N	0	\N	\N	f	0	\N
12195	78	228	\N	0	\N	\N	f	0	\N
12196	78	227	\N	0	\N	\N	f	0	\N
12197	78	226	\N	0	\N	\N	f	0	\N
12198	78	225	\N	0	\N	\N	f	0	\N
12199	78	224	\N	0	\N	\N	f	0	\N
12200	78	223	\N	0	\N	\N	f	0	\N
12201	78	222	\N	0	\N	\N	f	0	\N
12202	78	221	\N	0	\N	\N	f	0	\N
12203	78	220	\N	0	\N	\N	f	0	\N
12204	78	219	\N	0	\N	\N	f	0	\N
12205	78	432	\N	0	\N	\N	f	0	\N
12206	78	431	\N	0	\N	\N	f	0	\N
12207	78	430	\N	0	\N	\N	f	0	\N
12208	78	429	\N	0	\N	\N	f	0	\N
12209	78	428	\N	0	\N	\N	f	0	\N
12210	78	427	\N	0	\N	\N	f	0	\N
12211	78	426	\N	0	\N	\N	f	0	\N
12212	78	425	\N	0	\N	\N	f	0	\N
12213	78	424	\N	0	\N	\N	f	0	\N
12214	78	423	\N	0	\N	\N	f	0	\N
12215	78	422	\N	0	\N	\N	f	0	\N
12216	78	421	\N	0	\N	\N	f	0	\N
12217	78	420	\N	0	\N	\N	f	0	\N
12218	78	419	\N	0	\N	\N	f	0	\N
12219	78	418	\N	0	\N	\N	f	0	\N
12220	78	417	\N	0	\N	\N	f	0	\N
12221	78	416	\N	0	\N	\N	f	0	\N
12222	78	415	\N	0	\N	\N	f	0	\N
12223	78	414	\N	0	\N	\N	f	0	\N
12224	78	413	\N	0	\N	\N	f	0	\N
12225	78	412	\N	0	\N	\N	f	0	\N
12226	78	411	\N	0	\N	\N	f	0	\N
12227	78	410	\N	0	\N	\N	f	0	\N
12228	78	409	\N	0	\N	\N	f	0	\N
12229	78	408	\N	0	\N	\N	f	0	\N
12230	78	407	\N	0	\N	\N	f	0	\N
12231	78	406	\N	0	\N	\N	f	0	\N
12232	78	405	\N	0	\N	\N	f	0	\N
12233	78	404	\N	0	\N	\N	f	0	\N
12234	78	403	\N	0	\N	\N	f	0	\N
12235	78	402	\N	0	\N	\N	f	0	\N
12236	79	218	\N	0	\N	\N	f	0	\N
12237	79	217	\N	0	\N	\N	f	0	\N
12238	79	216	\N	0	\N	\N	f	0	\N
12239	79	215	\N	0	\N	\N	f	0	\N
12240	79	214	\N	0	\N	\N	f	0	\N
12241	79	213	\N	0	\N	\N	f	0	\N
12242	79	212	\N	0	\N	\N	f	0	\N
12243	79	211	\N	0	\N	\N	f	0	\N
12244	79	210	\N	0	\N	\N	f	0	\N
12245	79	209	\N	0	\N	\N	f	0	\N
12246	79	208	\N	0	\N	\N	f	0	\N
12247	79	207	\N	0	\N	\N	f	0	\N
12248	79	206	\N	0	\N	\N	f	0	\N
12249	79	205	\N	0	\N	\N	f	0	\N
12250	79	204	\N	0	\N	\N	f	0	\N
12251	79	203	\N	0	\N	\N	f	0	\N
12252	79	202	\N	0	\N	\N	f	0	\N
12253	79	201	\N	0	\N	\N	f	0	\N
12254	79	200	\N	0	\N	\N	f	0	\N
12255	79	199	\N	0	\N	\N	f	0	\N
12256	79	198	\N	0	\N	\N	f	0	\N
12257	79	197	\N	0	\N	\N	f	0	\N
12258	79	196	\N	0	\N	\N	f	0	\N
12259	79	195	\N	0	\N	\N	f	0	\N
12260	79	194	\N	0	\N	\N	f	0	\N
12261	79	193	\N	0	\N	\N	f	0	\N
12262	79	192	\N	0	\N	\N	f	0	\N
12263	79	191	\N	0	\N	\N	f	0	\N
12264	79	190	\N	0	\N	\N	f	0	\N
12265	79	189	\N	0	\N	\N	f	0	\N
12266	79	188	\N	0	\N	\N	f	0	\N
12267	79	187	\N	0	\N	\N	f	0	\N
12268	79	186	\N	0	\N	\N	f	0	\N
12269	79	185	\N	0	\N	\N	f	0	\N
12270	79	184	\N	0	\N	\N	f	0	\N
12271	79	183	\N	0	\N	\N	f	0	\N
12272	79	182	\N	0	\N	\N	f	0	\N
12273	79	181	\N	0	\N	\N	f	0	\N
12274	79	74	\N	0	\N	\N	f	0	\N
12275	79	73	\N	0	\N	\N	f	0	\N
12276	79	72	\N	0	\N	\N	f	0	\N
12277	79	71	\N	0	\N	\N	f	0	\N
12278	79	70	\N	0	\N	\N	f	0	\N
12279	79	69	\N	0	\N	\N	f	0	\N
12280	79	68	\N	0	\N	\N	f	0	\N
12281	79	67	\N	0	\N	\N	f	0	\N
12282	79	66	\N	0	\N	\N	f	0	\N
12283	79	65	\N	0	\N	\N	f	0	\N
12284	79	64	\N	0	\N	\N	f	0	\N
12285	79	63	\N	0	\N	\N	f	0	\N
12286	79	62	\N	0	\N	\N	f	0	\N
12287	79	61	\N	0	\N	\N	f	0	\N
12288	79	60	\N	0	\N	\N	f	0	\N
12289	79	59	\N	0	\N	\N	f	0	\N
12290	79	58	\N	0	\N	\N	f	0	\N
12291	79	57	\N	0	\N	\N	f	0	\N
12292	79	56	\N	0	\N	\N	f	0	\N
12293	79	55	\N	0	\N	\N	f	0	\N
12294	79	54	\N	0	\N	\N	f	0	\N
12295	79	53	\N	0	\N	\N	f	0	\N
12296	79	52	\N	0	\N	\N	f	0	\N
12297	79	51	\N	0	\N	\N	f	0	\N
12298	79	50	\N	0	\N	\N	f	0	\N
12299	79	49	\N	0	\N	\N	f	0	\N
12300	79	48	\N	0	\N	\N	f	0	\N
12301	79	47	\N	0	\N	\N	f	0	\N
12302	79	46	\N	0	\N	\N	f	0	\N
12303	79	45	\N	0	\N	\N	f	0	\N
12304	79	44	\N	0	\N	\N	f	0	\N
12305	79	43	\N	0	\N	\N	f	0	\N
12306	79	42	\N	0	\N	\N	f	0	\N
12307	79	41	\N	0	\N	\N	f	0	\N
12308	79	40	\N	0	\N	\N	f	0	\N
12309	79	401	\N	0	\N	\N	f	0	\N
12310	79	400	\N	0	\N	\N	f	0	\N
12311	79	399	\N	0	\N	\N	f	0	\N
12312	79	398	\N	0	\N	\N	f	0	\N
12313	79	397	\N	0	\N	\N	f	0	\N
12314	79	396	\N	0	\N	\N	f	0	\N
12315	79	395	\N	0	\N	\N	f	0	\N
12316	79	394	\N	0	\N	\N	f	0	\N
12317	79	393	\N	0	\N	\N	f	0	\N
12318	79	392	\N	0	\N	\N	f	0	\N
12319	79	391	\N	0	\N	\N	f	0	\N
12320	79	390	\N	0	\N	\N	f	0	\N
12321	79	389	\N	0	\N	\N	f	0	\N
12322	79	388	\N	0	\N	\N	f	0	\N
12323	79	387	\N	0	\N	\N	f	0	\N
12324	79	386	\N	0	\N	\N	f	0	\N
12325	79	385	\N	0	\N	\N	f	0	\N
12326	79	384	\N	0	\N	\N	f	0	\N
12327	79	383	\N	0	\N	\N	f	0	\N
12328	79	382	\N	0	\N	\N	f	0	\N
12329	79	381	\N	0	\N	\N	f	0	\N
12330	79	380	\N	0	\N	\N	f	0	\N
12331	79	379	\N	0	\N	\N	f	0	\N
12332	79	378	\N	0	\N	\N	f	0	\N
12333	79	377	\N	0	\N	\N	f	0	\N
12334	79	376	\N	0	\N	\N	f	0	\N
12335	79	375	\N	0	\N	\N	f	0	\N
12336	79	374	\N	0	\N	\N	f	0	\N
12337	79	373	\N	0	\N	\N	f	0	\N
12338	79	372	\N	0	\N	\N	f	0	\N
12339	79	371	\N	0	\N	\N	f	0	\N
12340	79	370	\N	0	\N	\N	f	0	\N
12341	79	369	\N	0	\N	\N	f	0	\N
12342	79	368	\N	0	\N	\N	f	0	\N
12343	79	367	\N	0	\N	\N	f	0	\N
12344	79	366	\N	0	\N	\N	f	0	\N
12345	79	365	\N	0	\N	\N	f	0	\N
12346	79	364	\N	0	\N	\N	f	0	\N
12347	79	363	\N	0	\N	\N	f	0	\N
12348	79	362	\N	0	\N	\N	f	0	\N
12349	79	361	\N	0	\N	\N	f	0	\N
12350	79	290	\N	0	\N	\N	f	0	\N
12351	79	289	\N	0	\N	\N	f	0	\N
12352	79	288	\N	0	\N	\N	f	0	\N
12353	79	287	\N	0	\N	\N	f	0	\N
12354	79	286	\N	0	\N	\N	f	0	\N
12355	79	285	\N	0	\N	\N	f	0	\N
12356	79	284	\N	0	\N	\N	f	0	\N
12357	79	283	\N	0	\N	\N	f	0	\N
12358	79	282	\N	0	\N	\N	f	0	\N
12359	79	281	\N	0	\N	\N	f	0	\N
12360	79	280	\N	0	\N	\N	f	0	\N
12361	79	279	\N	0	\N	\N	f	0	\N
12362	79	278	\N	0	\N	\N	f	0	\N
12363	79	277	\N	0	\N	\N	f	0	\N
12364	79	276	\N	0	\N	\N	f	0	\N
12365	79	275	\N	0	\N	\N	f	0	\N
12366	79	274	\N	0	\N	\N	f	0	\N
12367	79	273	\N	0	\N	\N	f	0	\N
12368	79	272	\N	0	\N	\N	f	0	\N
12369	79	271	\N	0	\N	\N	f	0	\N
12370	79	270	\N	0	\N	\N	f	0	\N
12371	79	269	\N	0	\N	\N	f	0	\N
12372	79	268	\N	0	\N	\N	f	0	\N
12373	79	267	\N	0	\N	\N	f	0	\N
12374	79	266	\N	0	\N	\N	f	0	\N
12375	79	265	\N	0	\N	\N	f	0	\N
12376	79	264	\N	0	\N	\N	f	0	\N
12377	79	263	\N	0	\N	\N	f	0	\N
12378	79	262	\N	0	\N	\N	f	0	\N
12379	79	261	\N	0	\N	\N	f	0	\N
12380	79	260	\N	0	\N	\N	f	0	\N
12381	79	259	\N	0	\N	\N	f	0	\N
12382	79	258	\N	0	\N	\N	f	0	\N
12383	79	257	\N	0	\N	\N	f	0	\N
12384	79	256	\N	0	\N	\N	f	0	\N
12385	79	255	\N	0	\N	\N	f	0	\N
12386	79	360	\N	0	\N	\N	f	0	\N
12387	79	359	\N	0	\N	\N	f	0	\N
12388	79	358	\N	0	\N	\N	f	0	\N
12389	79	357	\N	0	\N	\N	f	0	\N
12390	79	356	\N	0	\N	\N	f	0	\N
12391	79	355	\N	0	\N	\N	f	0	\N
12392	79	354	\N	0	\N	\N	f	0	\N
12393	79	353	\N	0	\N	\N	f	0	\N
12394	79	352	\N	0	\N	\N	f	0	\N
12395	79	351	\N	0	\N	\N	f	0	\N
12396	79	350	\N	0	\N	\N	f	0	\N
12397	79	349	\N	0	\N	\N	f	0	\N
12398	79	348	\N	0	\N	\N	f	0	\N
12399	79	347	\N	0	\N	\N	f	0	\N
12400	79	346	\N	0	\N	\N	f	0	\N
12401	79	345	\N	0	\N	\N	f	0	\N
12402	79	344	\N	0	\N	\N	f	0	\N
12403	79	343	\N	0	\N	\N	f	0	\N
12404	79	342	\N	0	\N	\N	f	0	\N
12405	79	341	\N	0	\N	\N	f	0	\N
12406	79	340	\N	0	\N	\N	f	0	\N
12407	79	339	\N	0	\N	\N	f	0	\N
12408	79	338	\N	0	\N	\N	f	0	\N
12409	79	337	\N	0	\N	\N	f	0	\N
12410	79	336	\N	0	\N	\N	f	0	\N
12411	79	335	\N	0	\N	\N	f	0	\N
12412	79	334	\N	0	\N	\N	f	0	\N
12413	79	333	\N	0	\N	\N	f	0	\N
12414	79	332	\N	0	\N	\N	f	0	\N
12415	79	331	\N	0	\N	\N	f	0	\N
12416	79	330	\N	0	\N	\N	f	0	\N
12417	79	329	\N	0	\N	\N	f	0	\N
12418	79	328	\N	0	\N	\N	f	0	\N
12419	79	327	\N	0	\N	\N	f	0	\N
12420	79	326	\N	0	\N	\N	f	0	\N
12421	79	325	\N	0	\N	\N	f	0	\N
12422	79	324	\N	0	\N	\N	f	0	\N
12423	79	432	\N	0	\N	\N	f	0	\N
12424	79	431	\N	0	\N	\N	f	0	\N
12425	79	430	\N	0	\N	\N	f	0	\N
12426	79	429	\N	0	\N	\N	f	0	\N
12427	79	428	\N	0	\N	\N	f	0	\N
12428	79	427	\N	0	\N	\N	f	0	\N
12429	79	426	\N	0	\N	\N	f	0	\N
12430	79	425	\N	0	\N	\N	f	0	\N
12431	79	424	\N	0	\N	\N	f	0	\N
12432	79	423	\N	0	\N	\N	f	0	\N
12433	79	422	\N	0	\N	\N	f	0	\N
12434	79	421	\N	0	\N	\N	f	0	\N
12435	79	420	\N	0	\N	\N	f	0	\N
12436	79	419	\N	0	\N	\N	f	0	\N
12437	79	418	\N	0	\N	\N	f	0	\N
12438	79	417	\N	0	\N	\N	f	0	\N
12439	79	416	\N	0	\N	\N	f	0	\N
12440	79	415	\N	0	\N	\N	f	0	\N
12441	79	414	\N	0	\N	\N	f	0	\N
12442	79	413	\N	0	\N	\N	f	0	\N
12443	79	412	\N	0	\N	\N	f	0	\N
12444	79	411	\N	0	\N	\N	f	0	\N
12445	79	410	\N	0	\N	\N	f	0	\N
12446	79	409	\N	0	\N	\N	f	0	\N
12447	79	408	\N	0	\N	\N	f	0	\N
12448	79	407	\N	0	\N	\N	f	0	\N
12449	79	406	\N	0	\N	\N	f	0	\N
12450	79	405	\N	0	\N	\N	f	0	\N
12451	79	404	\N	0	\N	\N	f	0	\N
12452	79	403	\N	0	\N	\N	f	0	\N
12453	79	402	\N	0	\N	\N	f	0	\N
12454	79	39	\N	0	\N	\N	f	0	\N
12455	79	38	\N	0	\N	\N	f	0	\N
12456	79	37	\N	0	\N	\N	f	0	\N
12457	79	36	\N	0	\N	\N	f	0	\N
12458	79	35	\N	0	\N	\N	f	0	\N
12459	79	34	\N	0	\N	\N	f	0	\N
12460	79	33	\N	0	\N	\N	f	0	\N
12461	79	32	\N	0	\N	\N	f	0	\N
12462	79	31	\N	0	\N	\N	f	0	\N
12463	79	30	\N	0	\N	\N	f	0	\N
12464	79	29	\N	0	\N	\N	f	0	\N
12465	79	28	\N	0	\N	\N	f	0	\N
12466	79	27	\N	0	\N	\N	f	0	\N
12467	79	26	\N	0	\N	\N	f	0	\N
12468	79	25	\N	0	\N	\N	f	0	\N
12469	79	24	\N	0	\N	\N	f	0	\N
12470	79	23	\N	0	\N	\N	f	0	\N
12471	79	22	\N	0	\N	\N	f	0	\N
12472	79	21	\N	0	\N	\N	f	0	\N
12473	79	20	\N	0	\N	\N	f	0	\N
12474	79	19	\N	0	\N	\N	f	0	\N
12475	79	18	\N	0	\N	\N	f	0	\N
12476	79	17	\N	0	\N	\N	f	0	\N
12477	79	16	\N	0	\N	\N	f	0	\N
12478	79	15	\N	0	\N	\N	f	0	\N
12479	79	14	\N	0	\N	\N	f	0	\N
12480	79	13	\N	0	\N	\N	f	0	\N
12481	79	12	\N	0	\N	\N	f	0	\N
12482	79	11	\N	0	\N	\N	f	0	\N
12483	79	10	\N	0	\N	\N	f	0	\N
12484	79	9	\N	0	\N	\N	f	0	\N
12485	79	8	\N	0	\N	\N	f	0	\N
12486	79	7	\N	0	\N	\N	f	0	\N
12487	79	6	\N	0	\N	\N	f	0	\N
12488	79	5	\N	0	\N	\N	f	0	\N
12489	79	4	\N	0	\N	\N	f	0	\N
12490	79	3	\N	0	\N	\N	f	0	\N
12491	79	2	\N	0	\N	\N	f	0	\N
12492	79	1	\N	0	\N	\N	f	0	\N
12493	79	145	\N	0	\N	\N	f	0	\N
12494	79	144	\N	0	\N	\N	f	0	\N
12495	79	143	\N	0	\N	\N	f	0	\N
12496	79	142	\N	0	\N	\N	f	0	\N
12497	79	141	\N	0	\N	\N	f	0	\N
12498	79	140	\N	0	\N	\N	f	0	\N
12499	79	139	\N	0	\N	\N	f	0	\N
12500	79	138	\N	0	\N	\N	f	0	\N
12501	79	137	\N	0	\N	\N	f	0	\N
12502	79	136	\N	0	\N	\N	f	0	\N
12503	79	135	\N	0	\N	\N	f	0	\N
12504	79	134	\N	0	\N	\N	f	0	\N
12505	79	133	\N	0	\N	\N	f	0	\N
12506	79	132	\N	0	\N	\N	f	0	\N
12507	79	131	\N	0	\N	\N	f	0	\N
12508	79	130	\N	0	\N	\N	f	0	\N
12509	79	129	\N	0	\N	\N	f	0	\N
12510	79	128	\N	0	\N	\N	f	0	\N
12511	79	127	\N	0	\N	\N	f	0	\N
12512	79	126	\N	0	\N	\N	f	0	\N
12513	79	125	\N	0	\N	\N	f	0	\N
12514	79	124	\N	0	\N	\N	f	0	\N
12515	79	123	\N	0	\N	\N	f	0	\N
12516	79	122	\N	0	\N	\N	f	0	\N
12517	79	121	\N	0	\N	\N	f	0	\N
12518	79	120	\N	0	\N	\N	f	0	\N
12519	79	119	\N	0	\N	\N	f	0	\N
12520	79	118	\N	0	\N	\N	f	0	\N
12521	79	117	\N	0	\N	\N	f	0	\N
12522	79	116	\N	0	\N	\N	f	0	\N
12523	79	115	\N	0	\N	\N	f	0	\N
12524	79	114	\N	0	\N	\N	f	0	\N
12525	79	113	\N	0	\N	\N	f	0	\N
12526	79	112	\N	0	\N	\N	f	0	\N
12527	79	111	\N	0	\N	\N	f	0	\N
12528	79	110	\N	0	\N	\N	f	0	\N
12529	80	290	\N	0	\N	\N	f	0	\N
12530	80	289	\N	0	\N	\N	f	0	\N
12531	80	288	\N	0	\N	\N	f	0	\N
12532	80	287	\N	0	\N	\N	f	0	\N
12533	80	286	\N	0	\N	\N	f	0	\N
12534	80	285	\N	0	\N	\N	f	0	\N
12535	80	284	\N	0	\N	\N	f	0	\N
12536	80	283	\N	0	\N	\N	f	0	\N
12537	80	282	\N	0	\N	\N	f	0	\N
12538	80	281	\N	0	\N	\N	f	0	\N
12539	80	280	\N	0	\N	\N	f	0	\N
12540	80	279	\N	0	\N	\N	f	0	\N
12541	80	278	\N	0	\N	\N	f	0	\N
12542	80	277	\N	0	\N	\N	f	0	\N
12543	80	276	\N	0	\N	\N	f	0	\N
12544	80	275	\N	0	\N	\N	f	0	\N
12545	80	274	\N	0	\N	\N	f	0	\N
12546	80	273	\N	0	\N	\N	f	0	\N
12547	80	272	\N	0	\N	\N	f	0	\N
12548	80	271	\N	0	\N	\N	f	0	\N
12549	80	270	\N	0	\N	\N	f	0	\N
12550	80	269	\N	0	\N	\N	f	0	\N
12551	80	268	\N	0	\N	\N	f	0	\N
12552	80	267	\N	0	\N	\N	f	0	\N
12553	80	266	\N	0	\N	\N	f	0	\N
12554	80	265	\N	0	\N	\N	f	0	\N
12555	80	264	\N	0	\N	\N	f	0	\N
12556	80	263	\N	0	\N	\N	f	0	\N
12557	80	262	\N	0	\N	\N	f	0	\N
12558	80	261	\N	0	\N	\N	f	0	\N
12559	80	260	\N	0	\N	\N	f	0	\N
12560	80	259	\N	0	\N	\N	f	0	\N
12561	80	258	\N	0	\N	\N	f	0	\N
12562	80	257	\N	0	\N	\N	f	0	\N
12563	80	256	\N	0	\N	\N	f	0	\N
12564	80	255	\N	0	\N	\N	f	0	\N
12565	80	360	\N	0	\N	\N	f	0	\N
12566	80	359	\N	0	\N	\N	f	0	\N
12567	80	358	\N	0	\N	\N	f	0	\N
12568	80	357	\N	0	\N	\N	f	0	\N
12569	80	356	\N	0	\N	\N	f	0	\N
12570	80	355	\N	0	\N	\N	f	0	\N
12571	80	354	\N	0	\N	\N	f	0	\N
12572	80	353	\N	0	\N	\N	f	0	\N
12573	80	352	\N	0	\N	\N	f	0	\N
12574	80	351	\N	0	\N	\N	f	0	\N
12575	80	350	\N	0	\N	\N	f	0	\N
12576	80	349	\N	0	\N	\N	f	0	\N
12577	80	348	\N	0	\N	\N	f	0	\N
12578	80	347	\N	0	\N	\N	f	0	\N
12579	80	346	\N	0	\N	\N	f	0	\N
12580	80	345	\N	0	\N	\N	f	0	\N
12581	80	344	\N	0	\N	\N	f	0	\N
12582	80	343	\N	0	\N	\N	f	0	\N
12583	80	342	\N	0	\N	\N	f	0	\N
12584	80	341	\N	0	\N	\N	f	0	\N
12585	80	340	\N	0	\N	\N	f	0	\N
12586	80	339	\N	0	\N	\N	f	0	\N
12587	80	338	\N	0	\N	\N	f	0	\N
12588	80	337	\N	0	\N	\N	f	0	\N
12589	80	336	\N	0	\N	\N	f	0	\N
12590	80	335	\N	0	\N	\N	f	0	\N
12591	80	334	\N	0	\N	\N	f	0	\N
12592	80	333	\N	0	\N	\N	f	0	\N
12593	80	332	\N	0	\N	\N	f	0	\N
12594	80	331	\N	0	\N	\N	f	0	\N
12595	80	330	\N	0	\N	\N	f	0	\N
12596	80	329	\N	0	\N	\N	f	0	\N
12597	80	328	\N	0	\N	\N	f	0	\N
12598	80	327	\N	0	\N	\N	f	0	\N
12599	80	326	\N	0	\N	\N	f	0	\N
12600	80	325	\N	0	\N	\N	f	0	\N
12601	80	324	\N	0	\N	\N	f	0	\N
12602	80	109	\N	0	\N	\N	f	0	\N
12603	80	108	\N	0	\N	\N	f	0	\N
12604	80	107	\N	0	\N	\N	f	0	\N
12605	80	106	\N	0	\N	\N	f	0	\N
12606	80	105	\N	0	\N	\N	f	0	\N
12607	80	104	\N	0	\N	\N	f	0	\N
12608	80	103	\N	0	\N	\N	f	0	\N
12609	80	102	\N	0	\N	\N	f	0	\N
12610	80	101	\N	0	\N	\N	f	0	\N
12611	80	100	\N	0	\N	\N	f	0	\N
12612	80	99	\N	0	\N	\N	f	0	\N
12613	80	98	\N	0	\N	\N	f	0	\N
12614	80	97	\N	0	\N	\N	f	0	\N
12615	80	96	\N	0	\N	\N	f	0	\N
12616	80	95	\N	0	\N	\N	f	0	\N
12617	80	94	\N	0	\N	\N	f	0	\N
12618	80	93	\N	0	\N	\N	f	0	\N
12619	80	92	\N	0	\N	\N	f	0	\N
12620	80	91	\N	0	\N	\N	f	0	\N
12621	80	90	\N	0	\N	\N	f	0	\N
12622	80	89	\N	0	\N	\N	f	0	\N
12623	80	88	\N	0	\N	\N	f	0	\N
12624	80	87	\N	0	\N	\N	f	0	\N
12625	80	86	\N	0	\N	\N	f	0	\N
12626	80	85	\N	0	\N	\N	f	0	\N
12627	80	84	\N	0	\N	\N	f	0	\N
12628	80	83	\N	0	\N	\N	f	0	\N
12629	80	82	\N	0	\N	\N	f	0	\N
12630	80	81	\N	0	\N	\N	f	0	\N
12631	80	80	\N	0	\N	\N	f	0	\N
12632	80	79	\N	0	\N	\N	f	0	\N
12633	80	78	\N	0	\N	\N	f	0	\N
12634	80	77	\N	0	\N	\N	f	0	\N
12635	80	76	\N	0	\N	\N	f	0	\N
12636	80	75	\N	0	\N	\N	f	0	\N
12637	80	74	\N	0	\N	\N	f	0	\N
12638	80	73	\N	0	\N	\N	f	0	\N
12639	80	72	\N	0	\N	\N	f	0	\N
12640	80	71	\N	0	\N	\N	f	0	\N
12641	80	70	\N	0	\N	\N	f	0	\N
12642	80	69	\N	0	\N	\N	f	0	\N
12643	80	68	\N	0	\N	\N	f	0	\N
12644	80	67	\N	0	\N	\N	f	0	\N
12645	80	66	\N	0	\N	\N	f	0	\N
12646	80	65	\N	0	\N	\N	f	0	\N
12647	80	64	\N	0	\N	\N	f	0	\N
12648	80	63	\N	0	\N	\N	f	0	\N
12649	80	62	\N	0	\N	\N	f	0	\N
12650	80	61	\N	0	\N	\N	f	0	\N
12651	80	60	\N	0	\N	\N	f	0	\N
12652	80	59	\N	0	\N	\N	f	0	\N
12653	80	58	\N	0	\N	\N	f	0	\N
12654	80	57	\N	0	\N	\N	f	0	\N
12655	80	56	\N	0	\N	\N	f	0	\N
12656	80	55	\N	0	\N	\N	f	0	\N
12657	80	54	\N	0	\N	\N	f	0	\N
12658	80	53	\N	0	\N	\N	f	0	\N
12659	80	52	\N	0	\N	\N	f	0	\N
12660	80	51	\N	0	\N	\N	f	0	\N
12661	80	50	\N	0	\N	\N	f	0	\N
12662	80	49	\N	0	\N	\N	f	0	\N
12663	80	48	\N	0	\N	\N	f	0	\N
12664	80	47	\N	0	\N	\N	f	0	\N
12665	80	46	\N	0	\N	\N	f	0	\N
12666	80	45	\N	0	\N	\N	f	0	\N
12667	80	44	\N	0	\N	\N	f	0	\N
12668	80	43	\N	0	\N	\N	f	0	\N
12669	80	42	\N	0	\N	\N	f	0	\N
12670	80	41	\N	0	\N	\N	f	0	\N
12671	80	40	\N	0	\N	\N	f	0	\N
12672	80	323	\N	0	\N	\N	f	0	\N
12673	80	322	\N	0	\N	\N	f	0	\N
12674	80	321	\N	0	\N	\N	f	0	\N
12675	80	320	\N	0	\N	\N	f	0	\N
12676	80	319	\N	0	\N	\N	f	0	\N
12677	80	318	\N	0	\N	\N	f	0	\N
12678	80	317	\N	0	\N	\N	f	0	\N
12679	80	316	\N	0	\N	\N	f	0	\N
12680	80	315	\N	0	\N	\N	f	0	\N
12681	80	314	\N	0	\N	\N	f	0	\N
12682	80	313	\N	0	\N	\N	f	0	\N
12683	80	312	\N	0	\N	\N	f	0	\N
12684	80	311	\N	0	\N	\N	f	0	\N
12685	80	310	\N	0	\N	\N	f	0	\N
12686	80	309	\N	0	\N	\N	f	0	\N
12687	80	308	\N	0	\N	\N	f	0	\N
12688	80	307	\N	0	\N	\N	f	0	\N
12689	80	306	\N	0	\N	\N	f	0	\N
12690	80	305	\N	0	\N	\N	f	0	\N
12691	80	304	\N	0	\N	\N	f	0	\N
12692	80	303	\N	0	\N	\N	f	0	\N
12693	80	302	\N	0	\N	\N	f	0	\N
12694	80	301	\N	0	\N	\N	f	0	\N
12695	80	300	\N	0	\N	\N	f	0	\N
12696	80	299	\N	0	\N	\N	f	0	\N
12697	80	298	\N	0	\N	\N	f	0	\N
12698	80	297	\N	0	\N	\N	f	0	\N
12699	80	296	\N	0	\N	\N	f	0	\N
12700	80	295	\N	0	\N	\N	f	0	\N
12701	80	294	\N	0	\N	\N	f	0	\N
12702	80	293	\N	0	\N	\N	f	0	\N
12703	80	292	\N	0	\N	\N	f	0	\N
12704	80	291	\N	0	\N	\N	f	0	\N
12705	80	145	\N	0	\N	\N	f	0	\N
12706	80	144	\N	0	\N	\N	f	0	\N
12707	80	143	\N	0	\N	\N	f	0	\N
12708	80	142	\N	0	\N	\N	f	0	\N
12709	80	141	\N	0	\N	\N	f	0	\N
12710	80	140	\N	0	\N	\N	f	0	\N
12711	80	139	\N	0	\N	\N	f	0	\N
12712	80	138	\N	0	\N	\N	f	0	\N
12713	80	137	\N	0	\N	\N	f	0	\N
12714	80	136	\N	0	\N	\N	f	0	\N
12715	80	135	\N	0	\N	\N	f	0	\N
12716	80	134	\N	0	\N	\N	f	0	\N
12717	80	133	\N	0	\N	\N	f	0	\N
12718	80	132	\N	0	\N	\N	f	0	\N
12719	80	131	\N	0	\N	\N	f	0	\N
12720	80	130	\N	0	\N	\N	f	0	\N
12721	80	129	\N	0	\N	\N	f	0	\N
12722	80	128	\N	0	\N	\N	f	0	\N
12723	80	127	\N	0	\N	\N	f	0	\N
12724	80	126	\N	0	\N	\N	f	0	\N
12725	80	125	\N	0	\N	\N	f	0	\N
12726	80	124	\N	0	\N	\N	f	0	\N
12727	80	123	\N	0	\N	\N	f	0	\N
12728	80	122	\N	0	\N	\N	f	0	\N
12729	80	121	\N	0	\N	\N	f	0	\N
12730	80	120	\N	0	\N	\N	f	0	\N
12731	80	119	\N	0	\N	\N	f	0	\N
12732	80	118	\N	0	\N	\N	f	0	\N
12733	80	117	\N	0	\N	\N	f	0	\N
12734	80	116	\N	0	\N	\N	f	0	\N
12735	80	115	\N	0	\N	\N	f	0	\N
12736	80	114	\N	0	\N	\N	f	0	\N
12737	80	113	\N	0	\N	\N	f	0	\N
12738	80	112	\N	0	\N	\N	f	0	\N
12739	80	111	\N	0	\N	\N	f	0	\N
12740	80	110	\N	0	\N	\N	f	0	\N
12741	80	401	\N	0	\N	\N	f	0	\N
12742	80	400	\N	0	\N	\N	f	0	\N
12743	80	399	\N	0	\N	\N	f	0	\N
12744	80	398	\N	0	\N	\N	f	0	\N
12745	80	397	\N	0	\N	\N	f	0	\N
12746	80	396	\N	0	\N	\N	f	0	\N
12747	80	395	\N	0	\N	\N	f	0	\N
12748	80	394	\N	0	\N	\N	f	0	\N
12749	80	393	\N	0	\N	\N	f	0	\N
12750	80	392	\N	0	\N	\N	f	0	\N
12751	80	391	\N	0	\N	\N	f	0	\N
12752	80	390	\N	0	\N	\N	f	0	\N
12753	80	389	\N	0	\N	\N	f	0	\N
12754	80	388	\N	0	\N	\N	f	0	\N
12755	80	387	\N	0	\N	\N	f	0	\N
12756	80	386	\N	0	\N	\N	f	0	\N
12757	80	385	\N	0	\N	\N	f	0	\N
12758	80	384	\N	0	\N	\N	f	0	\N
12759	80	383	\N	0	\N	\N	f	0	\N
12760	80	382	\N	0	\N	\N	f	0	\N
12761	80	381	\N	0	\N	\N	f	0	\N
12762	80	380	\N	0	\N	\N	f	0	\N
12763	80	379	\N	0	\N	\N	f	0	\N
12764	80	378	\N	0	\N	\N	f	0	\N
12765	80	377	\N	0	\N	\N	f	0	\N
12766	80	376	\N	0	\N	\N	f	0	\N
12767	80	375	\N	0	\N	\N	f	0	\N
12768	80	374	\N	0	\N	\N	f	0	\N
12769	80	373	\N	0	\N	\N	f	0	\N
12770	80	372	\N	0	\N	\N	f	0	\N
12771	80	371	\N	0	\N	\N	f	0	\N
12772	80	370	\N	0	\N	\N	f	0	\N
12773	80	369	\N	0	\N	\N	f	0	\N
12774	80	368	\N	0	\N	\N	f	0	\N
12775	80	367	\N	0	\N	\N	f	0	\N
12776	80	366	\N	0	\N	\N	f	0	\N
12777	80	365	\N	0	\N	\N	f	0	\N
12778	80	364	\N	0	\N	\N	f	0	\N
12779	80	363	\N	0	\N	\N	f	0	\N
12780	80	362	\N	0	\N	\N	f	0	\N
12781	80	361	\N	0	\N	\N	f	0	\N
12782	80	254	\N	0	\N	\N	f	0	\N
12783	80	253	\N	0	\N	\N	f	0	\N
12784	80	252	\N	0	\N	\N	f	0	\N
12785	80	251	\N	0	\N	\N	f	0	\N
12786	80	250	\N	0	\N	\N	f	0	\N
12787	80	249	\N	0	\N	\N	f	0	\N
12788	80	248	\N	0	\N	\N	f	0	\N
12789	80	247	\N	0	\N	\N	f	0	\N
12790	80	246	\N	0	\N	\N	f	0	\N
12791	80	245	\N	0	\N	\N	f	0	\N
12792	80	244	\N	0	\N	\N	f	0	\N
12793	80	243	\N	0	\N	\N	f	0	\N
12794	80	242	\N	0	\N	\N	f	0	\N
12795	80	241	\N	0	\N	\N	f	0	\N
12796	80	240	\N	0	\N	\N	f	0	\N
12797	80	239	\N	0	\N	\N	f	0	\N
12798	80	238	\N	0	\N	\N	f	0	\N
12799	80	237	\N	0	\N	\N	f	0	\N
12800	80	236	\N	0	\N	\N	f	0	\N
12801	80	235	\N	0	\N	\N	f	0	\N
12802	80	234	\N	0	\N	\N	f	0	\N
12803	80	233	\N	0	\N	\N	f	0	\N
12804	80	232	\N	0	\N	\N	f	0	\N
12805	80	231	\N	0	\N	\N	f	0	\N
12806	80	230	\N	0	\N	\N	f	0	\N
12807	80	229	\N	0	\N	\N	f	0	\N
12808	80	228	\N	0	\N	\N	f	0	\N
12809	80	227	\N	0	\N	\N	f	0	\N
12810	80	226	\N	0	\N	\N	f	0	\N
12811	80	225	\N	0	\N	\N	f	0	\N
12812	80	224	\N	0	\N	\N	f	0	\N
12813	80	223	\N	0	\N	\N	f	0	\N
12814	80	222	\N	0	\N	\N	f	0	\N
12815	80	221	\N	0	\N	\N	f	0	\N
12816	80	220	\N	0	\N	\N	f	0	\N
12817	80	219	\N	0	\N	\N	f	0	\N
12818	80	218	\N	0	\N	\N	f	0	\N
12819	80	217	\N	0	\N	\N	f	0	\N
12820	80	216	\N	0	\N	\N	f	0	\N
12821	80	215	\N	0	\N	\N	f	0	\N
12822	80	214	\N	0	\N	\N	f	0	\N
12823	80	213	\N	0	\N	\N	f	0	\N
12824	80	212	\N	0	\N	\N	f	0	\N
12825	80	211	\N	0	\N	\N	f	0	\N
12826	80	210	\N	0	\N	\N	f	0	\N
12827	80	209	\N	0	\N	\N	f	0	\N
12828	80	208	\N	0	\N	\N	f	0	\N
12829	80	207	\N	0	\N	\N	f	0	\N
12830	80	206	\N	0	\N	\N	f	0	\N
12831	80	205	\N	0	\N	\N	f	0	\N
12832	80	204	\N	0	\N	\N	f	0	\N
12833	80	203	\N	0	\N	\N	f	0	\N
12834	80	202	\N	0	\N	\N	f	0	\N
12835	80	201	\N	0	\N	\N	f	0	\N
12836	80	200	\N	0	\N	\N	f	0	\N
12837	80	199	\N	0	\N	\N	f	0	\N
12838	80	198	\N	0	\N	\N	f	0	\N
12839	80	197	\N	0	\N	\N	f	0	\N
12840	80	196	\N	0	\N	\N	f	0	\N
12841	80	195	\N	0	\N	\N	f	0	\N
12842	80	194	\N	0	\N	\N	f	0	\N
12843	80	193	\N	0	\N	\N	f	0	\N
12844	80	192	\N	0	\N	\N	f	0	\N
12845	80	191	\N	0	\N	\N	f	0	\N
12846	80	190	\N	0	\N	\N	f	0	\N
12847	80	189	\N	0	\N	\N	f	0	\N
12848	80	188	\N	0	\N	\N	f	0	\N
12849	80	187	\N	0	\N	\N	f	0	\N
12850	80	186	\N	0	\N	\N	f	0	\N
12851	80	185	\N	0	\N	\N	f	0	\N
12852	80	184	\N	0	\N	\N	f	0	\N
12853	80	183	\N	0	\N	\N	f	0	\N
12854	80	182	\N	0	\N	\N	f	0	\N
12855	80	181	\N	0	\N	\N	f	0	\N
12856	80	432	\N	0	\N	\N	f	0	\N
12857	80	431	\N	0	\N	\N	f	0	\N
12858	80	430	\N	0	\N	\N	f	0	\N
12859	80	429	\N	0	\N	\N	f	0	\N
12860	80	428	\N	0	\N	\N	f	0	\N
12861	80	427	\N	0	\N	\N	f	0	\N
12862	80	426	\N	0	\N	\N	f	0	\N
12863	80	425	\N	0	\N	\N	f	0	\N
12864	80	424	\N	0	\N	\N	f	0	\N
12865	80	423	\N	0	\N	\N	f	0	\N
12866	80	422	\N	0	\N	\N	f	0	\N
12867	80	421	\N	0	\N	\N	f	0	\N
12868	80	420	\N	0	\N	\N	f	0	\N
12869	80	419	\N	0	\N	\N	f	0	\N
12870	80	418	\N	0	\N	\N	f	0	\N
12871	80	417	\N	0	\N	\N	f	0	\N
12872	80	416	\N	0	\N	\N	f	0	\N
12873	80	415	\N	0	\N	\N	f	0	\N
12874	80	414	\N	0	\N	\N	f	0	\N
12875	80	413	\N	0	\N	\N	f	0	\N
12876	80	412	\N	0	\N	\N	f	0	\N
12877	80	411	\N	0	\N	\N	f	0	\N
12878	80	410	\N	0	\N	\N	f	0	\N
12879	80	409	\N	0	\N	\N	f	0	\N
12880	80	408	\N	0	\N	\N	f	0	\N
12881	80	407	\N	0	\N	\N	f	0	\N
12882	80	406	\N	0	\N	\N	f	0	\N
12883	80	405	\N	0	\N	\N	f	0	\N
12884	80	404	\N	0	\N	\N	f	0	\N
12885	80	403	\N	0	\N	\N	f	0	\N
12886	80	402	\N	0	\N	\N	f	0	\N
12887	80	180	\N	0	\N	\N	f	0	\N
12888	80	179	\N	0	\N	\N	f	0	\N
12889	80	178	\N	0	\N	\N	f	0	\N
12890	80	177	\N	0	\N	\N	f	0	\N
12891	80	176	\N	0	\N	\N	f	0	\N
12892	80	175	\N	0	\N	\N	f	0	\N
12893	80	174	\N	0	\N	\N	f	0	\N
12894	80	173	\N	0	\N	\N	f	0	\N
12895	80	172	\N	0	\N	\N	f	0	\N
12896	80	171	\N	0	\N	\N	f	0	\N
12897	80	170	\N	0	\N	\N	f	0	\N
12898	80	169	\N	0	\N	\N	f	0	\N
12899	80	168	\N	0	\N	\N	f	0	\N
12900	80	167	\N	0	\N	\N	f	0	\N
12901	80	166	\N	0	\N	\N	f	0	\N
12902	80	165	\N	0	\N	\N	f	0	\N
12903	80	164	\N	0	\N	\N	f	0	\N
12904	80	163	\N	0	\N	\N	f	0	\N
12905	80	162	\N	0	\N	\N	f	0	\N
12906	80	161	\N	0	\N	\N	f	0	\N
12907	80	160	\N	0	\N	\N	f	0	\N
12908	80	159	\N	0	\N	\N	f	0	\N
12909	80	158	\N	0	\N	\N	f	0	\N
12910	80	157	\N	0	\N	\N	f	0	\N
12911	80	156	\N	0	\N	\N	f	0	\N
12912	80	155	\N	0	\N	\N	f	0	\N
12913	80	154	\N	0	\N	\N	f	0	\N
12914	80	153	\N	0	\N	\N	f	0	\N
12915	80	152	\N	0	\N	\N	f	0	\N
12916	80	151	\N	0	\N	\N	f	0	\N
12917	80	150	\N	0	\N	\N	f	0	\N
12918	80	149	\N	0	\N	\N	f	0	\N
12919	80	148	\N	0	\N	\N	f	0	\N
12920	80	147	\N	0	\N	\N	f	0	\N
12921	80	146	\N	0	\N	\N	f	0	\N
12922	80	39	\N	0	\N	\N	f	0	\N
12923	80	38	\N	0	\N	\N	f	0	\N
12924	80	37	\N	0	\N	\N	f	0	\N
12925	80	36	\N	0	\N	\N	f	0	\N
12926	80	35	\N	0	\N	\N	f	0	\N
12927	80	34	\N	0	\N	\N	f	0	\N
12928	80	33	\N	0	\N	\N	f	0	\N
12929	80	32	\N	0	\N	\N	f	0	\N
12930	80	31	\N	0	\N	\N	f	0	\N
12931	80	30	\N	0	\N	\N	f	0	\N
12932	80	29	\N	0	\N	\N	f	0	\N
12933	80	28	\N	0	\N	\N	f	0	\N
12934	80	27	\N	0	\N	\N	f	0	\N
12935	80	26	\N	0	\N	\N	f	0	\N
12936	80	25	\N	0	\N	\N	f	0	\N
12937	80	24	\N	0	\N	\N	f	0	\N
12938	80	23	\N	0	\N	\N	f	0	\N
12939	80	22	\N	0	\N	\N	f	0	\N
12940	80	21	\N	0	\N	\N	f	0	\N
12941	80	20	\N	0	\N	\N	f	0	\N
12942	80	19	\N	0	\N	\N	f	0	\N
12943	80	18	\N	0	\N	\N	f	0	\N
12944	80	17	\N	0	\N	\N	f	0	\N
12945	80	16	\N	0	\N	\N	f	0	\N
12946	80	15	\N	0	\N	\N	f	0	\N
12947	80	14	\N	0	\N	\N	f	0	\N
12948	80	13	\N	0	\N	\N	f	0	\N
12949	80	12	\N	0	\N	\N	f	0	\N
12950	80	11	\N	0	\N	\N	f	0	\N
12951	80	10	\N	0	\N	\N	f	0	\N
12952	80	9	\N	0	\N	\N	f	0	\N
12953	80	8	\N	0	\N	\N	f	0	\N
12954	80	7	\N	0	\N	\N	f	0	\N
12955	80	6	\N	0	\N	\N	f	0	\N
12956	80	5	\N	0	\N	\N	f	0	\N
12957	80	4	\N	0	\N	\N	f	0	\N
12958	80	3	\N	0	\N	\N	f	0	\N
12959	80	2	\N	0	\N	\N	f	0	\N
12960	80	1	\N	0	\N	\N	f	0	\N
12961	81	254	\N	0	\N	\N	f	0	\N
12962	81	253	\N	0	\N	\N	f	0	\N
12963	81	252	\N	0	\N	\N	f	0	\N
12964	81	251	\N	0	\N	\N	f	0	\N
12965	81	250	\N	0	\N	\N	f	0	\N
12966	81	249	\N	0	\N	\N	f	0	\N
12967	81	248	\N	0	\N	\N	f	0	\N
12968	81	247	\N	0	\N	\N	f	0	\N
12969	81	246	\N	0	\N	\N	f	0	\N
12970	81	245	\N	0	\N	\N	f	0	\N
12971	81	244	\N	0	\N	\N	f	0	\N
12972	81	243	\N	0	\N	\N	f	0	\N
12973	81	242	\N	0	\N	\N	f	0	\N
12974	81	241	\N	0	\N	\N	f	0	\N
12975	81	240	\N	0	\N	\N	f	0	\N
12976	81	239	\N	0	\N	\N	f	0	\N
12977	81	238	\N	0	\N	\N	f	0	\N
12978	81	237	\N	0	\N	\N	f	0	\N
12979	81	236	\N	0	\N	\N	f	0	\N
12980	81	235	\N	0	\N	\N	f	0	\N
12981	81	234	\N	0	\N	\N	f	0	\N
12982	81	233	\N	0	\N	\N	f	0	\N
12983	81	232	\N	0	\N	\N	f	0	\N
12984	81	231	\N	0	\N	\N	f	0	\N
12985	81	230	\N	0	\N	\N	f	0	\N
12986	81	229	\N	0	\N	\N	f	0	\N
12987	81	228	\N	0	\N	\N	f	0	\N
12988	81	227	\N	0	\N	\N	f	0	\N
12989	81	226	\N	0	\N	\N	f	0	\N
12990	81	225	\N	0	\N	\N	f	0	\N
12991	81	224	\N	0	\N	\N	f	0	\N
12992	81	223	\N	0	\N	\N	f	0	\N
12993	81	222	\N	0	\N	\N	f	0	\N
12994	81	221	\N	0	\N	\N	f	0	\N
12995	81	220	\N	0	\N	\N	f	0	\N
12996	81	219	\N	0	\N	\N	f	0	\N
12997	81	39	\N	0	\N	\N	f	0	\N
12998	81	38	\N	0	\N	\N	f	0	\N
12999	81	37	\N	0	\N	\N	f	0	\N
13000	81	36	\N	0	\N	\N	f	0	\N
13001	81	35	\N	0	\N	\N	f	0	\N
13002	81	34	\N	0	\N	\N	f	0	\N
13003	81	33	\N	0	\N	\N	f	0	\N
13004	81	32	\N	0	\N	\N	f	0	\N
13005	81	31	\N	0	\N	\N	f	0	\N
13006	81	30	\N	0	\N	\N	f	0	\N
13007	81	29	\N	0	\N	\N	f	0	\N
13008	81	28	\N	0	\N	\N	f	0	\N
13009	81	27	\N	0	\N	\N	f	0	\N
13010	81	26	\N	0	\N	\N	f	0	\N
13011	81	25	\N	0	\N	\N	f	0	\N
13012	81	24	\N	0	\N	\N	f	0	\N
13013	81	23	\N	0	\N	\N	f	0	\N
13014	81	22	\N	0	\N	\N	f	0	\N
13015	81	21	\N	0	\N	\N	f	0	\N
13016	81	20	\N	0	\N	\N	f	0	\N
13017	81	19	\N	0	\N	\N	f	0	\N
13018	81	18	\N	0	\N	\N	f	0	\N
13019	81	17	\N	0	\N	\N	f	0	\N
13020	81	16	\N	0	\N	\N	f	0	\N
13021	81	15	\N	0	\N	\N	f	0	\N
13022	81	14	\N	0	\N	\N	f	0	\N
13023	81	13	\N	0	\N	\N	f	0	\N
13024	81	12	\N	0	\N	\N	f	0	\N
13025	81	11	\N	0	\N	\N	f	0	\N
13026	81	10	\N	0	\N	\N	f	0	\N
13027	81	9	\N	0	\N	\N	f	0	\N
13028	81	8	\N	0	\N	\N	f	0	\N
13029	81	7	\N	0	\N	\N	f	0	\N
13030	81	6	\N	0	\N	\N	f	0	\N
13031	81	5	\N	0	\N	\N	f	0	\N
13032	81	4	\N	0	\N	\N	f	0	\N
13033	81	3	\N	0	\N	\N	f	0	\N
13034	81	2	\N	0	\N	\N	f	0	\N
13035	81	1	\N	0	\N	\N	f	0	\N
13036	81	360	\N	0	\N	\N	f	0	\N
13037	81	359	\N	0	\N	\N	f	0	\N
13038	81	358	\N	0	\N	\N	f	0	\N
13039	81	357	\N	0	\N	\N	f	0	\N
13040	81	356	\N	0	\N	\N	f	0	\N
13041	81	355	\N	0	\N	\N	f	0	\N
13042	81	354	\N	0	\N	\N	f	0	\N
13043	81	353	\N	0	\N	\N	f	0	\N
13044	81	352	\N	0	\N	\N	f	0	\N
13045	81	351	\N	0	\N	\N	f	0	\N
13046	81	350	\N	0	\N	\N	f	0	\N
13047	81	349	\N	0	\N	\N	f	0	\N
13048	81	348	\N	0	\N	\N	f	0	\N
13049	81	347	\N	0	\N	\N	f	0	\N
13050	81	346	\N	0	\N	\N	f	0	\N
13051	81	345	\N	0	\N	\N	f	0	\N
13052	81	344	\N	0	\N	\N	f	0	\N
13053	81	343	\N	0	\N	\N	f	0	\N
13054	81	342	\N	0	\N	\N	f	0	\N
13055	81	341	\N	0	\N	\N	f	0	\N
13056	81	340	\N	0	\N	\N	f	0	\N
13057	81	339	\N	0	\N	\N	f	0	\N
13058	81	338	\N	0	\N	\N	f	0	\N
13059	81	337	\N	0	\N	\N	f	0	\N
13060	81	336	\N	0	\N	\N	f	0	\N
13061	81	335	\N	0	\N	\N	f	0	\N
13062	81	334	\N	0	\N	\N	f	0	\N
13063	81	333	\N	0	\N	\N	f	0	\N
13064	81	332	\N	0	\N	\N	f	0	\N
13065	81	331	\N	0	\N	\N	f	0	\N
13066	81	330	\N	0	\N	\N	f	0	\N
13067	81	329	\N	0	\N	\N	f	0	\N
13068	81	328	\N	0	\N	\N	f	0	\N
13069	81	327	\N	0	\N	\N	f	0	\N
13070	81	326	\N	0	\N	\N	f	0	\N
13071	81	325	\N	0	\N	\N	f	0	\N
13072	81	324	\N	0	\N	\N	f	0	\N
13073	81	74	\N	0	\N	\N	f	0	\N
13074	81	73	\N	0	\N	\N	f	0	\N
13075	81	72	\N	0	\N	\N	f	0	\N
13076	81	71	\N	0	\N	\N	f	0	\N
13077	81	70	\N	0	\N	\N	f	0	\N
13078	81	69	\N	0	\N	\N	f	0	\N
13079	81	68	\N	0	\N	\N	f	0	\N
13080	81	67	\N	0	\N	\N	f	0	\N
13081	81	66	\N	0	\N	\N	f	0	\N
13082	81	65	\N	0	\N	\N	f	0	\N
13083	81	64	\N	0	\N	\N	f	0	\N
13084	81	63	\N	0	\N	\N	f	0	\N
13085	81	62	\N	0	\N	\N	f	0	\N
13086	81	61	\N	0	\N	\N	f	0	\N
13087	81	60	\N	0	\N	\N	f	0	\N
13088	81	59	\N	0	\N	\N	f	0	\N
13089	81	58	\N	0	\N	\N	f	0	\N
13090	81	57	\N	0	\N	\N	f	0	\N
13091	81	56	\N	0	\N	\N	f	0	\N
13092	81	55	\N	0	\N	\N	f	0	\N
13093	81	54	\N	0	\N	\N	f	0	\N
13094	81	53	\N	0	\N	\N	f	0	\N
13095	81	52	\N	0	\N	\N	f	0	\N
13096	81	51	\N	0	\N	\N	f	0	\N
13097	81	50	\N	0	\N	\N	f	0	\N
13098	81	49	\N	0	\N	\N	f	0	\N
13099	81	48	\N	0	\N	\N	f	0	\N
13100	81	47	\N	0	\N	\N	f	0	\N
13101	81	46	\N	0	\N	\N	f	0	\N
13102	81	45	\N	0	\N	\N	f	0	\N
13103	81	44	\N	0	\N	\N	f	0	\N
13104	81	43	\N	0	\N	\N	f	0	\N
13105	81	42	\N	0	\N	\N	f	0	\N
13106	81	41	\N	0	\N	\N	f	0	\N
13107	81	40	\N	0	\N	\N	f	0	\N
13108	81	290	\N	0	\N	\N	f	0	\N
13109	81	289	\N	0	\N	\N	f	0	\N
13110	81	288	\N	0	\N	\N	f	0	\N
13111	81	287	\N	0	\N	\N	f	0	\N
13112	81	286	\N	0	\N	\N	f	0	\N
13113	81	285	\N	0	\N	\N	f	0	\N
13114	81	284	\N	0	\N	\N	f	0	\N
13115	81	283	\N	0	\N	\N	f	0	\N
13116	81	282	\N	0	\N	\N	f	0	\N
13117	81	281	\N	0	\N	\N	f	0	\N
13118	81	280	\N	0	\N	\N	f	0	\N
13119	81	279	\N	0	\N	\N	f	0	\N
13120	81	278	\N	0	\N	\N	f	0	\N
13121	81	277	\N	0	\N	\N	f	0	\N
13122	81	276	\N	0	\N	\N	f	0	\N
13123	81	275	\N	0	\N	\N	f	0	\N
13124	81	274	\N	0	\N	\N	f	0	\N
13125	81	273	\N	0	\N	\N	f	0	\N
13126	81	272	\N	0	\N	\N	f	0	\N
13127	81	271	\N	0	\N	\N	f	0	\N
13128	81	270	\N	0	\N	\N	f	0	\N
13129	81	269	\N	0	\N	\N	f	0	\N
13130	81	268	\N	0	\N	\N	f	0	\N
13131	81	267	\N	0	\N	\N	f	0	\N
13132	81	266	\N	0	\N	\N	f	0	\N
13133	81	265	\N	0	\N	\N	f	0	\N
13134	81	264	\N	0	\N	\N	f	0	\N
13135	81	263	\N	0	\N	\N	f	0	\N
13136	81	262	\N	0	\N	\N	f	0	\N
13137	81	261	\N	0	\N	\N	f	0	\N
13138	81	260	\N	0	\N	\N	f	0	\N
13139	81	259	\N	0	\N	\N	f	0	\N
13140	81	258	\N	0	\N	\N	f	0	\N
13141	81	257	\N	0	\N	\N	f	0	\N
13142	81	256	\N	0	\N	\N	f	0	\N
13143	81	255	\N	0	\N	\N	f	0	\N
13144	81	180	\N	0	\N	\N	f	0	\N
13145	81	179	\N	0	\N	\N	f	0	\N
13146	81	178	\N	0	\N	\N	f	0	\N
13147	81	177	\N	0	\N	\N	f	0	\N
13148	81	176	\N	0	\N	\N	f	0	\N
13149	81	175	\N	0	\N	\N	f	0	\N
13150	81	174	\N	0	\N	\N	f	0	\N
13151	81	173	\N	0	\N	\N	f	0	\N
13152	81	172	\N	0	\N	\N	f	0	\N
13153	81	171	\N	0	\N	\N	f	0	\N
13154	81	170	\N	0	\N	\N	f	0	\N
13155	81	169	\N	0	\N	\N	f	0	\N
13156	81	168	\N	0	\N	\N	f	0	\N
13157	81	167	\N	0	\N	\N	f	0	\N
13158	81	166	\N	0	\N	\N	f	0	\N
13159	81	165	\N	0	\N	\N	f	0	\N
13160	81	164	\N	0	\N	\N	f	0	\N
13161	81	163	\N	0	\N	\N	f	0	\N
13162	81	162	\N	0	\N	\N	f	0	\N
13163	81	161	\N	0	\N	\N	f	0	\N
13164	81	160	\N	0	\N	\N	f	0	\N
13165	81	159	\N	0	\N	\N	f	0	\N
13166	81	158	\N	0	\N	\N	f	0	\N
13167	81	157	\N	0	\N	\N	f	0	\N
13168	81	156	\N	0	\N	\N	f	0	\N
13169	81	155	\N	0	\N	\N	f	0	\N
13170	81	154	\N	0	\N	\N	f	0	\N
13171	81	153	\N	0	\N	\N	f	0	\N
13172	81	152	\N	0	\N	\N	f	0	\N
13173	81	151	\N	0	\N	\N	f	0	\N
13174	81	150	\N	0	\N	\N	f	0	\N
13175	81	149	\N	0	\N	\N	f	0	\N
13176	81	148	\N	0	\N	\N	f	0	\N
13177	81	147	\N	0	\N	\N	f	0	\N
13178	81	146	\N	0	\N	\N	f	0	\N
13179	81	109	\N	0	\N	\N	f	0	\N
13180	81	108	\N	0	\N	\N	f	0	\N
13181	81	107	\N	0	\N	\N	f	0	\N
13182	81	106	\N	0	\N	\N	f	0	\N
13183	81	105	\N	0	\N	\N	f	0	\N
13184	81	104	\N	0	\N	\N	f	0	\N
13185	81	103	\N	0	\N	\N	f	0	\N
13186	81	102	\N	0	\N	\N	f	0	\N
13187	81	101	\N	0	\N	\N	f	0	\N
13188	81	100	\N	0	\N	\N	f	0	\N
13189	81	99	\N	0	\N	\N	f	0	\N
13190	81	98	\N	0	\N	\N	f	0	\N
13191	81	97	\N	0	\N	\N	f	0	\N
13192	81	96	\N	0	\N	\N	f	0	\N
13193	81	95	\N	0	\N	\N	f	0	\N
13194	81	94	\N	0	\N	\N	f	0	\N
13195	81	93	\N	0	\N	\N	f	0	\N
13196	81	92	\N	0	\N	\N	f	0	\N
13197	81	91	\N	0	\N	\N	f	0	\N
13198	81	90	\N	0	\N	\N	f	0	\N
13199	81	89	\N	0	\N	\N	f	0	\N
13200	81	88	\N	0	\N	\N	f	0	\N
13201	81	87	\N	0	\N	\N	f	0	\N
13202	81	86	\N	0	\N	\N	f	0	\N
13203	81	85	\N	0	\N	\N	f	0	\N
13204	81	84	\N	0	\N	\N	f	0	\N
13205	81	83	\N	0	\N	\N	f	0	\N
13206	81	82	\N	0	\N	\N	f	0	\N
13207	81	81	\N	0	\N	\N	f	0	\N
13208	81	80	\N	0	\N	\N	f	0	\N
13209	81	79	\N	0	\N	\N	f	0	\N
13210	81	78	\N	0	\N	\N	f	0	\N
13211	81	77	\N	0	\N	\N	f	0	\N
13212	81	76	\N	0	\N	\N	f	0	\N
13213	81	75	\N	0	\N	\N	f	0	\N
13214	81	145	\N	0	\N	\N	f	0	\N
13215	81	144	\N	0	\N	\N	f	0	\N
13216	81	143	\N	0	\N	\N	f	0	\N
13217	81	142	\N	0	\N	\N	f	0	\N
13218	81	141	\N	0	\N	\N	f	0	\N
13219	81	140	\N	0	\N	\N	f	0	\N
13220	81	139	\N	0	\N	\N	f	0	\N
13221	81	138	\N	0	\N	\N	f	0	\N
13222	81	137	\N	0	\N	\N	f	0	\N
13223	81	136	\N	0	\N	\N	f	0	\N
13224	81	135	\N	0	\N	\N	f	0	\N
13225	81	134	\N	0	\N	\N	f	0	\N
13226	81	133	\N	0	\N	\N	f	0	\N
13227	81	132	\N	0	\N	\N	f	0	\N
13228	81	131	\N	0	\N	\N	f	0	\N
13229	81	130	\N	0	\N	\N	f	0	\N
13230	81	129	\N	0	\N	\N	f	0	\N
13231	81	128	\N	0	\N	\N	f	0	\N
13232	81	127	\N	0	\N	\N	f	0	\N
13233	81	126	\N	0	\N	\N	f	0	\N
13234	81	125	\N	0	\N	\N	f	0	\N
13235	81	124	\N	0	\N	\N	f	0	\N
13236	81	123	\N	0	\N	\N	f	0	\N
13237	81	122	\N	0	\N	\N	f	0	\N
13238	81	121	\N	0	\N	\N	f	0	\N
13239	81	120	\N	0	\N	\N	f	0	\N
13240	81	119	\N	0	\N	\N	f	0	\N
13241	81	118	\N	0	\N	\N	f	0	\N
13242	81	117	\N	0	\N	\N	f	0	\N
13243	81	116	\N	0	\N	\N	f	0	\N
13244	81	115	\N	0	\N	\N	f	0	\N
13245	81	114	\N	0	\N	\N	f	0	\N
13246	81	113	\N	0	\N	\N	f	0	\N
13247	81	112	\N	0	\N	\N	f	0	\N
13248	81	111	\N	0	\N	\N	f	0	\N
13249	81	110	\N	0	\N	\N	f	0	\N
13250	81	323	\N	0	\N	\N	f	0	\N
13251	81	322	\N	0	\N	\N	f	0	\N
13252	81	321	\N	0	\N	\N	f	0	\N
13253	81	320	\N	0	\N	\N	f	0	\N
13254	81	319	\N	0	\N	\N	f	0	\N
13255	81	318	\N	0	\N	\N	f	0	\N
13256	81	317	\N	0	\N	\N	f	0	\N
13257	81	316	\N	0	\N	\N	f	0	\N
13258	81	315	\N	0	\N	\N	f	0	\N
13259	81	314	\N	0	\N	\N	f	0	\N
13260	81	313	\N	0	\N	\N	f	0	\N
13261	81	312	\N	0	\N	\N	f	0	\N
13262	81	311	\N	0	\N	\N	f	0	\N
13263	81	310	\N	0	\N	\N	f	0	\N
13264	81	309	\N	0	\N	\N	f	0	\N
13265	81	308	\N	0	\N	\N	f	0	\N
13266	81	307	\N	0	\N	\N	f	0	\N
13267	81	306	\N	0	\N	\N	f	0	\N
13268	81	305	\N	0	\N	\N	f	0	\N
13269	81	304	\N	0	\N	\N	f	0	\N
13270	81	303	\N	0	\N	\N	f	0	\N
13271	81	302	\N	0	\N	\N	f	0	\N
13272	81	301	\N	0	\N	\N	f	0	\N
13273	81	300	\N	0	\N	\N	f	0	\N
13274	81	299	\N	0	\N	\N	f	0	\N
13275	81	298	\N	0	\N	\N	f	0	\N
13276	81	297	\N	0	\N	\N	f	0	\N
13277	81	296	\N	0	\N	\N	f	0	\N
13278	81	295	\N	0	\N	\N	f	0	\N
13279	81	294	\N	0	\N	\N	f	0	\N
13280	81	293	\N	0	\N	\N	f	0	\N
13281	81	292	\N	0	\N	\N	f	0	\N
13282	81	291	\N	0	\N	\N	f	0	\N
13283	81	432	\N	0	\N	\N	f	0	\N
13284	81	431	\N	0	\N	\N	f	0	\N
13285	81	430	\N	0	\N	\N	f	0	\N
13286	81	429	\N	0	\N	\N	f	0	\N
13287	81	428	\N	0	\N	\N	f	0	\N
13288	81	427	\N	0	\N	\N	f	0	\N
13289	81	426	\N	0	\N	\N	f	0	\N
13290	81	425	\N	0	\N	\N	f	0	\N
13291	81	424	\N	0	\N	\N	f	0	\N
13292	81	423	\N	0	\N	\N	f	0	\N
13293	81	422	\N	0	\N	\N	f	0	\N
13294	81	421	\N	0	\N	\N	f	0	\N
13295	81	420	\N	0	\N	\N	f	0	\N
13296	81	419	\N	0	\N	\N	f	0	\N
13297	81	418	\N	0	\N	\N	f	0	\N
13298	81	417	\N	0	\N	\N	f	0	\N
13299	81	416	\N	0	\N	\N	f	0	\N
13300	81	415	\N	0	\N	\N	f	0	\N
13301	81	414	\N	0	\N	\N	f	0	\N
13302	81	413	\N	0	\N	\N	f	0	\N
13303	81	412	\N	0	\N	\N	f	0	\N
13304	81	411	\N	0	\N	\N	f	0	\N
13305	81	410	\N	0	\N	\N	f	0	\N
13306	81	409	\N	0	\N	\N	f	0	\N
13307	81	408	\N	0	\N	\N	f	0	\N
13308	81	407	\N	0	\N	\N	f	0	\N
13309	81	406	\N	0	\N	\N	f	0	\N
13310	81	405	\N	0	\N	\N	f	0	\N
13311	81	404	\N	0	\N	\N	f	0	\N
13312	81	403	\N	0	\N	\N	f	0	\N
13313	81	402	\N	0	\N	\N	f	0	\N
13314	81	401	\N	0	\N	\N	f	0	\N
13315	81	400	\N	0	\N	\N	f	0	\N
13316	81	399	\N	0	\N	\N	f	0	\N
13317	81	398	\N	0	\N	\N	f	0	\N
13318	81	397	\N	0	\N	\N	f	0	\N
13319	81	396	\N	0	\N	\N	f	0	\N
13320	81	395	\N	0	\N	\N	f	0	\N
13321	81	394	\N	0	\N	\N	f	0	\N
13322	81	393	\N	0	\N	\N	f	0	\N
13323	81	392	\N	0	\N	\N	f	0	\N
13324	81	391	\N	0	\N	\N	f	0	\N
13325	81	390	\N	0	\N	\N	f	0	\N
13326	81	389	\N	0	\N	\N	f	0	\N
13327	81	388	\N	0	\N	\N	f	0	\N
13328	81	387	\N	0	\N	\N	f	0	\N
13329	81	386	\N	0	\N	\N	f	0	\N
13330	81	385	\N	0	\N	\N	f	0	\N
13331	81	384	\N	0	\N	\N	f	0	\N
13332	81	383	\N	0	\N	\N	f	0	\N
13333	81	382	\N	0	\N	\N	f	0	\N
13334	81	381	\N	0	\N	\N	f	0	\N
13335	81	380	\N	0	\N	\N	f	0	\N
13336	81	379	\N	0	\N	\N	f	0	\N
13337	81	378	\N	0	\N	\N	f	0	\N
13338	81	377	\N	0	\N	\N	f	0	\N
13339	81	376	\N	0	\N	\N	f	0	\N
13340	81	375	\N	0	\N	\N	f	0	\N
13341	81	374	\N	0	\N	\N	f	0	\N
13342	81	373	\N	0	\N	\N	f	0	\N
13343	81	372	\N	0	\N	\N	f	0	\N
13344	81	371	\N	0	\N	\N	f	0	\N
13345	81	370	\N	0	\N	\N	f	0	\N
13346	81	369	\N	0	\N	\N	f	0	\N
13347	81	368	\N	0	\N	\N	f	0	\N
13348	81	367	\N	0	\N	\N	f	0	\N
13349	81	366	\N	0	\N	\N	f	0	\N
13350	81	365	\N	0	\N	\N	f	0	\N
13351	81	364	\N	0	\N	\N	f	0	\N
13352	81	363	\N	0	\N	\N	f	0	\N
13353	81	362	\N	0	\N	\N	f	0	\N
13354	81	361	\N	0	\N	\N	f	0	\N
13355	81	218	\N	0	\N	\N	f	0	\N
13356	81	217	\N	0	\N	\N	f	0	\N
13357	81	216	\N	0	\N	\N	f	0	\N
13358	81	215	\N	0	\N	\N	f	0	\N
13359	81	214	\N	0	\N	\N	f	0	\N
13360	81	213	\N	0	\N	\N	f	0	\N
13361	81	212	\N	0	\N	\N	f	0	\N
13362	81	211	\N	0	\N	\N	f	0	\N
13363	81	210	\N	0	\N	\N	f	0	\N
13364	81	209	\N	0	\N	\N	f	0	\N
13365	81	208	\N	0	\N	\N	f	0	\N
13366	81	207	\N	0	\N	\N	f	0	\N
13367	81	206	\N	0	\N	\N	f	0	\N
13368	81	205	\N	0	\N	\N	f	0	\N
13369	81	204	\N	0	\N	\N	f	0	\N
13370	81	203	\N	0	\N	\N	f	0	\N
13371	81	202	\N	0	\N	\N	f	0	\N
13372	81	201	\N	0	\N	\N	f	0	\N
13373	81	200	\N	0	\N	\N	f	0	\N
13374	81	199	\N	0	\N	\N	f	0	\N
13375	81	198	\N	0	\N	\N	f	0	\N
13376	81	197	\N	0	\N	\N	f	0	\N
13377	81	196	\N	0	\N	\N	f	0	\N
13378	81	195	\N	0	\N	\N	f	0	\N
13379	81	194	\N	0	\N	\N	f	0	\N
13380	81	193	\N	0	\N	\N	f	0	\N
13381	81	192	\N	0	\N	\N	f	0	\N
13382	81	191	\N	0	\N	\N	f	0	\N
13383	81	190	\N	0	\N	\N	f	0	\N
13384	81	189	\N	0	\N	\N	f	0	\N
13385	81	188	\N	0	\N	\N	f	0	\N
13386	81	187	\N	0	\N	\N	f	0	\N
13387	81	186	\N	0	\N	\N	f	0	\N
13388	81	185	\N	0	\N	\N	f	0	\N
13389	81	184	\N	0	\N	\N	f	0	\N
13390	81	183	\N	0	\N	\N	f	0	\N
13391	81	182	\N	0	\N	\N	f	0	\N
13392	81	181	\N	0	\N	\N	f	0	\N
13393	82	401	\N	0	\N	\N	f	0	\N
13394	82	400	\N	0	\N	\N	f	0	\N
13395	82	399	\N	0	\N	\N	f	0	\N
13396	82	398	\N	0	\N	\N	f	0	\N
13397	82	397	\N	0	\N	\N	f	0	\N
13398	82	396	\N	0	\N	\N	f	0	\N
13399	82	395	\N	0	\N	\N	f	0	\N
13400	82	394	\N	0	\N	\N	f	0	\N
13401	82	393	\N	0	\N	\N	f	0	\N
13402	82	392	\N	0	\N	\N	f	0	\N
13403	82	391	\N	0	\N	\N	f	0	\N
13404	82	390	\N	0	\N	\N	f	0	\N
13405	82	389	\N	0	\N	\N	f	0	\N
13406	82	388	\N	0	\N	\N	f	0	\N
13407	82	387	\N	0	\N	\N	f	0	\N
13408	82	386	\N	0	\N	\N	f	0	\N
13409	82	385	\N	0	\N	\N	f	0	\N
13410	82	384	\N	0	\N	\N	f	0	\N
13411	82	383	\N	0	\N	\N	f	0	\N
13412	82	382	\N	0	\N	\N	f	0	\N
13413	82	381	\N	0	\N	\N	f	0	\N
13414	82	380	\N	0	\N	\N	f	0	\N
13415	82	379	\N	0	\N	\N	f	0	\N
13416	82	378	\N	0	\N	\N	f	0	\N
13417	82	377	\N	0	\N	\N	f	0	\N
13418	82	376	\N	0	\N	\N	f	0	\N
13419	82	375	\N	0	\N	\N	f	0	\N
13420	82	374	\N	0	\N	\N	f	0	\N
13421	82	373	\N	0	\N	\N	f	0	\N
13422	82	372	\N	0	\N	\N	f	0	\N
13423	82	371	\N	0	\N	\N	f	0	\N
13424	82	370	\N	0	\N	\N	f	0	\N
13425	82	369	\N	0	\N	\N	f	0	\N
13426	82	368	\N	0	\N	\N	f	0	\N
13427	82	367	\N	0	\N	\N	f	0	\N
13428	82	366	\N	0	\N	\N	f	0	\N
13429	82	365	\N	0	\N	\N	f	0	\N
13430	82	364	\N	0	\N	\N	f	0	\N
13431	82	363	\N	0	\N	\N	f	0	\N
13432	82	362	\N	0	\N	\N	f	0	\N
13433	82	361	\N	0	\N	\N	f	0	\N
13434	82	432	\N	0	\N	\N	f	0	\N
13435	82	431	\N	0	\N	\N	f	0	\N
13436	82	430	\N	0	\N	\N	f	0	\N
13437	82	429	\N	0	\N	\N	f	0	\N
13438	82	428	\N	0	\N	\N	f	0	\N
13439	82	427	\N	0	\N	\N	f	0	\N
13440	82	426	\N	0	\N	\N	f	0	\N
13441	82	425	\N	0	\N	\N	f	0	\N
13442	82	424	\N	0	\N	\N	f	0	\N
13443	82	423	\N	0	\N	\N	f	0	\N
13444	82	422	\N	0	\N	\N	f	0	\N
13445	82	421	\N	0	\N	\N	f	0	\N
13446	82	420	\N	0	\N	\N	f	0	\N
13447	82	419	\N	0	\N	\N	f	0	\N
13448	82	418	\N	0	\N	\N	f	0	\N
13449	82	417	\N	0	\N	\N	f	0	\N
13450	82	416	\N	0	\N	\N	f	0	\N
13451	82	415	\N	0	\N	\N	f	0	\N
13452	82	414	\N	0	\N	\N	f	0	\N
13453	82	413	\N	0	\N	\N	f	0	\N
13454	82	412	\N	0	\N	\N	f	0	\N
13455	82	411	\N	0	\N	\N	f	0	\N
13456	82	410	\N	0	\N	\N	f	0	\N
13457	82	409	\N	0	\N	\N	f	0	\N
13458	82	408	\N	0	\N	\N	f	0	\N
13459	82	407	\N	0	\N	\N	f	0	\N
13460	82	406	\N	0	\N	\N	f	0	\N
13461	82	405	\N	0	\N	\N	f	0	\N
13462	82	404	\N	0	\N	\N	f	0	\N
13463	82	403	\N	0	\N	\N	f	0	\N
13464	82	402	\N	0	\N	\N	f	0	\N
13465	82	290	\N	0	\N	\N	f	0	\N
13466	82	289	\N	0	\N	\N	f	0	\N
13467	82	288	\N	0	\N	\N	f	0	\N
13468	82	287	\N	0	\N	\N	f	0	\N
13469	82	286	\N	0	\N	\N	f	0	\N
13470	82	285	\N	0	\N	\N	f	0	\N
13471	82	284	\N	0	\N	\N	f	0	\N
13472	82	283	\N	0	\N	\N	f	0	\N
13473	82	282	\N	0	\N	\N	f	0	\N
13474	82	281	\N	0	\N	\N	f	0	\N
13475	82	280	\N	0	\N	\N	f	0	\N
13476	82	279	\N	0	\N	\N	f	0	\N
13477	82	278	\N	0	\N	\N	f	0	\N
13478	82	277	\N	0	\N	\N	f	0	\N
13479	82	276	\N	0	\N	\N	f	0	\N
13480	82	275	\N	0	\N	\N	f	0	\N
13481	82	274	\N	0	\N	\N	f	0	\N
13482	82	273	\N	0	\N	\N	f	0	\N
13483	82	272	\N	0	\N	\N	f	0	\N
13484	82	271	\N	0	\N	\N	f	0	\N
13485	82	270	\N	0	\N	\N	f	0	\N
13486	82	269	\N	0	\N	\N	f	0	\N
13487	82	268	\N	0	\N	\N	f	0	\N
13488	82	267	\N	0	\N	\N	f	0	\N
13489	82	266	\N	0	\N	\N	f	0	\N
13490	82	265	\N	0	\N	\N	f	0	\N
13491	82	264	\N	0	\N	\N	f	0	\N
13492	82	263	\N	0	\N	\N	f	0	\N
13493	82	262	\N	0	\N	\N	f	0	\N
13494	82	261	\N	0	\N	\N	f	0	\N
13495	82	260	\N	0	\N	\N	f	0	\N
13496	82	259	\N	0	\N	\N	f	0	\N
13497	82	258	\N	0	\N	\N	f	0	\N
13498	82	257	\N	0	\N	\N	f	0	\N
13499	82	256	\N	0	\N	\N	f	0	\N
13500	82	255	\N	0	\N	\N	f	0	\N
13501	82	180	\N	0	\N	\N	f	0	\N
13502	82	179	\N	0	\N	\N	f	0	\N
13503	82	178	\N	0	\N	\N	f	0	\N
13504	82	177	\N	0	\N	\N	f	0	\N
13505	82	176	\N	0	\N	\N	f	0	\N
13506	82	175	\N	0	\N	\N	f	0	\N
13507	82	174	\N	0	\N	\N	f	0	\N
13508	82	173	\N	0	\N	\N	f	0	\N
13509	82	172	\N	0	\N	\N	f	0	\N
13510	82	171	\N	0	\N	\N	f	0	\N
13511	82	170	\N	0	\N	\N	f	0	\N
13512	82	169	\N	0	\N	\N	f	0	\N
13513	82	168	\N	0	\N	\N	f	0	\N
13514	82	167	\N	0	\N	\N	f	0	\N
13515	82	166	\N	0	\N	\N	f	0	\N
13516	82	165	\N	0	\N	\N	f	0	\N
13517	82	164	\N	0	\N	\N	f	0	\N
13518	82	163	\N	0	\N	\N	f	0	\N
13519	82	162	\N	0	\N	\N	f	0	\N
13520	82	161	\N	0	\N	\N	f	0	\N
13521	82	160	\N	0	\N	\N	f	0	\N
13522	82	159	\N	0	\N	\N	f	0	\N
13523	82	158	\N	0	\N	\N	f	0	\N
13524	82	157	\N	0	\N	\N	f	0	\N
13525	82	156	\N	0	\N	\N	f	0	\N
13526	82	155	\N	0	\N	\N	f	0	\N
13527	82	154	\N	0	\N	\N	f	0	\N
13528	82	153	\N	0	\N	\N	f	0	\N
13529	82	152	\N	0	\N	\N	f	0	\N
13530	82	151	\N	0	\N	\N	f	0	\N
13531	82	150	\N	0	\N	\N	f	0	\N
13532	82	149	\N	0	\N	\N	f	0	\N
13533	82	148	\N	0	\N	\N	f	0	\N
13534	82	147	\N	0	\N	\N	f	0	\N
13535	82	146	\N	0	\N	\N	f	0	\N
13536	82	145	\N	0	\N	\N	f	0	\N
13537	82	144	\N	0	\N	\N	f	0	\N
13538	82	143	\N	0	\N	\N	f	0	\N
13539	82	142	\N	0	\N	\N	f	0	\N
13540	82	141	\N	0	\N	\N	f	0	\N
13541	82	140	\N	0	\N	\N	f	0	\N
13542	82	139	\N	0	\N	\N	f	0	\N
13543	82	138	\N	0	\N	\N	f	0	\N
13544	82	137	\N	0	\N	\N	f	0	\N
13545	82	136	\N	0	\N	\N	f	0	\N
13546	82	135	\N	0	\N	\N	f	0	\N
13547	82	134	\N	0	\N	\N	f	0	\N
13548	82	133	\N	0	\N	\N	f	0	\N
13549	82	132	\N	0	\N	\N	f	0	\N
13550	82	131	\N	0	\N	\N	f	0	\N
13551	82	130	\N	0	\N	\N	f	0	\N
13552	82	129	\N	0	\N	\N	f	0	\N
13553	82	128	\N	0	\N	\N	f	0	\N
13554	82	127	\N	0	\N	\N	f	0	\N
13555	82	126	\N	0	\N	\N	f	0	\N
13556	82	125	\N	0	\N	\N	f	0	\N
13557	82	124	\N	0	\N	\N	f	0	\N
13558	82	123	\N	0	\N	\N	f	0	\N
13559	82	122	\N	0	\N	\N	f	0	\N
13560	82	121	\N	0	\N	\N	f	0	\N
13561	82	120	\N	0	\N	\N	f	0	\N
13562	82	119	\N	0	\N	\N	f	0	\N
13563	82	118	\N	0	\N	\N	f	0	\N
13564	82	117	\N	0	\N	\N	f	0	\N
13565	82	116	\N	0	\N	\N	f	0	\N
13566	82	115	\N	0	\N	\N	f	0	\N
13567	82	114	\N	0	\N	\N	f	0	\N
13568	82	113	\N	0	\N	\N	f	0	\N
13569	82	112	\N	0	\N	\N	f	0	\N
13570	82	111	\N	0	\N	\N	f	0	\N
13571	82	110	\N	0	\N	\N	f	0	\N
13572	82	74	\N	0	\N	\N	f	0	\N
13573	82	73	\N	0	\N	\N	f	0	\N
13574	82	72	\N	0	\N	\N	f	0	\N
13575	82	71	\N	0	\N	\N	f	0	\N
13576	82	70	\N	0	\N	\N	f	0	\N
13577	82	69	\N	0	\N	\N	f	0	\N
13578	82	68	\N	0	\N	\N	f	0	\N
13579	82	67	\N	0	\N	\N	f	0	\N
13580	82	66	\N	0	\N	\N	f	0	\N
13581	82	65	\N	0	\N	\N	f	0	\N
13582	82	64	\N	0	\N	\N	f	0	\N
13583	82	63	\N	0	\N	\N	f	0	\N
13584	82	62	\N	0	\N	\N	f	0	\N
13585	82	61	\N	0	\N	\N	f	0	\N
13586	82	60	\N	0	\N	\N	f	0	\N
13587	82	59	\N	0	\N	\N	f	0	\N
13588	82	58	\N	0	\N	\N	f	0	\N
13589	82	57	\N	0	\N	\N	f	0	\N
13590	82	56	\N	0	\N	\N	f	0	\N
13591	82	55	\N	0	\N	\N	f	0	\N
13592	82	54	\N	0	\N	\N	f	0	\N
13593	82	53	\N	0	\N	\N	f	0	\N
13594	82	52	\N	0	\N	\N	f	0	\N
13595	82	51	\N	0	\N	\N	f	0	\N
13596	82	50	\N	0	\N	\N	f	0	\N
13597	82	49	\N	0	\N	\N	f	0	\N
13598	82	48	\N	0	\N	\N	f	0	\N
13599	82	47	\N	0	\N	\N	f	0	\N
13600	82	46	\N	0	\N	\N	f	0	\N
13601	82	45	\N	0	\N	\N	f	0	\N
13602	82	44	\N	0	\N	\N	f	0	\N
13603	82	43	\N	0	\N	\N	f	0	\N
13604	82	42	\N	0	\N	\N	f	0	\N
13605	82	41	\N	0	\N	\N	f	0	\N
13606	82	40	\N	0	\N	\N	f	0	\N
13607	82	323	\N	0	\N	\N	f	0	\N
13608	82	322	\N	0	\N	\N	f	0	\N
13609	82	321	\N	0	\N	\N	f	0	\N
13610	82	320	\N	0	\N	\N	f	0	\N
13611	82	319	\N	0	\N	\N	f	0	\N
13612	82	318	\N	0	\N	\N	f	0	\N
13613	82	317	\N	0	\N	\N	f	0	\N
13614	82	316	\N	0	\N	\N	f	0	\N
13615	82	315	\N	0	\N	\N	f	0	\N
13616	82	314	\N	0	\N	\N	f	0	\N
13617	82	313	\N	0	\N	\N	f	0	\N
13618	82	312	\N	0	\N	\N	f	0	\N
13619	82	311	\N	0	\N	\N	f	0	\N
13620	82	310	\N	0	\N	\N	f	0	\N
13621	82	309	\N	0	\N	\N	f	0	\N
13622	82	308	\N	0	\N	\N	f	0	\N
13623	82	307	\N	0	\N	\N	f	0	\N
13624	82	306	\N	0	\N	\N	f	0	\N
13625	82	305	\N	0	\N	\N	f	0	\N
13626	82	304	\N	0	\N	\N	f	0	\N
13627	82	303	\N	0	\N	\N	f	0	\N
13628	82	302	\N	0	\N	\N	f	0	\N
13629	82	301	\N	0	\N	\N	f	0	\N
13630	82	300	\N	0	\N	\N	f	0	\N
13631	82	299	\N	0	\N	\N	f	0	\N
13632	82	298	\N	0	\N	\N	f	0	\N
13633	82	297	\N	0	\N	\N	f	0	\N
13634	82	296	\N	0	\N	\N	f	0	\N
13635	82	295	\N	0	\N	\N	f	0	\N
13636	82	294	\N	0	\N	\N	f	0	\N
13637	82	293	\N	0	\N	\N	f	0	\N
13638	82	292	\N	0	\N	\N	f	0	\N
13639	82	291	\N	0	\N	\N	f	0	\N
13640	82	254	\N	0	\N	\N	f	0	\N
13641	82	253	\N	0	\N	\N	f	0	\N
13642	82	252	\N	0	\N	\N	f	0	\N
13643	82	251	\N	0	\N	\N	f	0	\N
13644	82	250	\N	0	\N	\N	f	0	\N
13645	82	249	\N	0	\N	\N	f	0	\N
13646	82	248	\N	0	\N	\N	f	0	\N
13647	82	247	\N	0	\N	\N	f	0	\N
13648	82	246	\N	0	\N	\N	f	0	\N
13649	82	245	\N	0	\N	\N	f	0	\N
13650	82	244	\N	0	\N	\N	f	0	\N
13651	82	243	\N	0	\N	\N	f	0	\N
13652	82	242	\N	0	\N	\N	f	0	\N
13653	82	241	\N	0	\N	\N	f	0	\N
13654	82	240	\N	0	\N	\N	f	0	\N
13655	82	239	\N	0	\N	\N	f	0	\N
13656	82	238	\N	0	\N	\N	f	0	\N
13657	82	237	\N	0	\N	\N	f	0	\N
13658	82	236	\N	0	\N	\N	f	0	\N
13659	82	235	\N	0	\N	\N	f	0	\N
13660	82	234	\N	0	\N	\N	f	0	\N
13661	82	233	\N	0	\N	\N	f	0	\N
13662	82	232	\N	0	\N	\N	f	0	\N
13663	82	231	\N	0	\N	\N	f	0	\N
13664	82	230	\N	0	\N	\N	f	0	\N
13665	82	229	\N	0	\N	\N	f	0	\N
13666	82	228	\N	0	\N	\N	f	0	\N
13667	82	227	\N	0	\N	\N	f	0	\N
13668	82	226	\N	0	\N	\N	f	0	\N
13669	82	225	\N	0	\N	\N	f	0	\N
13670	82	224	\N	0	\N	\N	f	0	\N
13671	82	223	\N	0	\N	\N	f	0	\N
13672	82	222	\N	0	\N	\N	f	0	\N
13673	82	221	\N	0	\N	\N	f	0	\N
13674	82	220	\N	0	\N	\N	f	0	\N
13675	82	219	\N	0	\N	\N	f	0	\N
13676	82	39	\N	0	\N	\N	f	0	\N
13677	82	38	\N	0	\N	\N	f	0	\N
13678	82	37	\N	0	\N	\N	f	0	\N
13679	82	36	\N	0	\N	\N	f	0	\N
13680	82	35	\N	0	\N	\N	f	0	\N
13681	82	34	\N	0	\N	\N	f	0	\N
13682	82	33	\N	0	\N	\N	f	0	\N
13683	82	32	\N	0	\N	\N	f	0	\N
13684	82	31	\N	0	\N	\N	f	0	\N
13685	82	30	\N	0	\N	\N	f	0	\N
13686	82	29	\N	0	\N	\N	f	0	\N
13687	82	28	\N	0	\N	\N	f	0	\N
13688	82	27	\N	0	\N	\N	f	0	\N
13689	82	26	\N	0	\N	\N	f	0	\N
13690	82	25	\N	0	\N	\N	f	0	\N
13691	82	24	\N	0	\N	\N	f	0	\N
13692	82	23	\N	0	\N	\N	f	0	\N
13693	82	22	\N	0	\N	\N	f	0	\N
13694	82	21	\N	0	\N	\N	f	0	\N
13695	82	20	\N	0	\N	\N	f	0	\N
13696	82	19	\N	0	\N	\N	f	0	\N
13697	82	18	\N	0	\N	\N	f	0	\N
13698	82	17	\N	0	\N	\N	f	0	\N
13699	82	16	\N	0	\N	\N	f	0	\N
13700	82	15	\N	0	\N	\N	f	0	\N
13701	82	14	\N	0	\N	\N	f	0	\N
13702	82	13	\N	0	\N	\N	f	0	\N
13703	82	12	\N	0	\N	\N	f	0	\N
13704	82	11	\N	0	\N	\N	f	0	\N
13705	82	10	\N	0	\N	\N	f	0	\N
13706	82	9	\N	0	\N	\N	f	0	\N
13707	82	8	\N	0	\N	\N	f	0	\N
13708	82	7	\N	0	\N	\N	f	0	\N
13709	82	6	\N	0	\N	\N	f	0	\N
13710	82	5	\N	0	\N	\N	f	0	\N
13711	82	4	\N	0	\N	\N	f	0	\N
13712	82	3	\N	0	\N	\N	f	0	\N
13713	82	2	\N	0	\N	\N	f	0	\N
13714	82	1	\N	0	\N	\N	f	0	\N
13715	82	109	\N	0	\N	\N	f	0	\N
13716	82	108	\N	0	\N	\N	f	0	\N
13717	82	107	\N	0	\N	\N	f	0	\N
13718	82	106	\N	0	\N	\N	f	0	\N
13719	82	105	\N	0	\N	\N	f	0	\N
13720	82	104	\N	0	\N	\N	f	0	\N
13721	82	103	\N	0	\N	\N	f	0	\N
13722	82	102	\N	0	\N	\N	f	0	\N
13723	82	101	\N	0	\N	\N	f	0	\N
13724	82	100	\N	0	\N	\N	f	0	\N
13725	82	99	\N	0	\N	\N	f	0	\N
13726	82	98	\N	0	\N	\N	f	0	\N
13727	82	97	\N	0	\N	\N	f	0	\N
13728	82	96	\N	0	\N	\N	f	0	\N
13729	82	95	\N	0	\N	\N	f	0	\N
13730	82	94	\N	0	\N	\N	f	0	\N
13731	82	93	\N	0	\N	\N	f	0	\N
13732	82	92	\N	0	\N	\N	f	0	\N
13733	82	91	\N	0	\N	\N	f	0	\N
13734	82	90	\N	0	\N	\N	f	0	\N
13735	82	89	\N	0	\N	\N	f	0	\N
13736	82	88	\N	0	\N	\N	f	0	\N
13737	82	87	\N	0	\N	\N	f	0	\N
13738	82	86	\N	0	\N	\N	f	0	\N
13739	82	85	\N	0	\N	\N	f	0	\N
13740	82	84	\N	0	\N	\N	f	0	\N
13741	82	83	\N	0	\N	\N	f	0	\N
13742	82	82	\N	0	\N	\N	f	0	\N
13743	82	81	\N	0	\N	\N	f	0	\N
13744	82	80	\N	0	\N	\N	f	0	\N
13745	82	79	\N	0	\N	\N	f	0	\N
13746	82	78	\N	0	\N	\N	f	0	\N
13747	82	77	\N	0	\N	\N	f	0	\N
13748	82	76	\N	0	\N	\N	f	0	\N
13749	82	75	\N	0	\N	\N	f	0	\N
13750	83	360	\N	0	\N	\N	f	0	\N
13751	83	359	\N	0	\N	\N	f	0	\N
13752	83	358	\N	0	\N	\N	f	0	\N
13753	83	357	\N	0	\N	\N	f	0	\N
13754	83	356	\N	0	\N	\N	f	0	\N
13755	83	355	\N	0	\N	\N	f	0	\N
13756	83	354	\N	0	\N	\N	f	0	\N
13757	83	353	\N	0	\N	\N	f	0	\N
13758	83	352	\N	0	\N	\N	f	0	\N
13759	83	351	\N	0	\N	\N	f	0	\N
13760	83	350	\N	0	\N	\N	f	0	\N
13761	83	349	\N	0	\N	\N	f	0	\N
13762	83	348	\N	0	\N	\N	f	0	\N
13763	83	347	\N	0	\N	\N	f	0	\N
13764	83	346	\N	0	\N	\N	f	0	\N
13765	83	345	\N	0	\N	\N	f	0	\N
13766	83	344	\N	0	\N	\N	f	0	\N
13767	83	343	\N	0	\N	\N	f	0	\N
13768	83	342	\N	0	\N	\N	f	0	\N
13769	83	341	\N	0	\N	\N	f	0	\N
13770	83	340	\N	0	\N	\N	f	0	\N
13771	83	339	\N	0	\N	\N	f	0	\N
13772	83	338	\N	0	\N	\N	f	0	\N
13773	83	337	\N	0	\N	\N	f	0	\N
13774	83	336	\N	0	\N	\N	f	0	\N
13775	83	335	\N	0	\N	\N	f	0	\N
13776	83	334	\N	0	\N	\N	f	0	\N
13777	83	333	\N	0	\N	\N	f	0	\N
13778	83	332	\N	0	\N	\N	f	0	\N
13779	83	331	\N	0	\N	\N	f	0	\N
13780	83	330	\N	0	\N	\N	f	0	\N
13781	83	329	\N	0	\N	\N	f	0	\N
13782	83	328	\N	0	\N	\N	f	0	\N
13783	83	327	\N	0	\N	\N	f	0	\N
13784	83	326	\N	0	\N	\N	f	0	\N
13785	83	325	\N	0	\N	\N	f	0	\N
13786	83	324	\N	0	\N	\N	f	0	\N
13787	83	39	\N	0	\N	\N	f	0	\N
13788	83	38	\N	0	\N	\N	f	0	\N
13789	83	37	\N	0	\N	\N	f	0	\N
13790	83	36	\N	0	\N	\N	f	0	\N
13791	83	35	\N	0	\N	\N	f	0	\N
13792	83	34	\N	0	\N	\N	f	0	\N
13793	83	33	\N	0	\N	\N	f	0	\N
13794	83	32	\N	0	\N	\N	f	0	\N
13795	83	31	\N	0	\N	\N	f	0	\N
13796	83	30	\N	0	\N	\N	f	0	\N
13797	83	29	\N	0	\N	\N	f	0	\N
13798	83	28	\N	0	\N	\N	f	0	\N
13799	83	27	\N	0	\N	\N	f	0	\N
13800	83	26	\N	0	\N	\N	f	0	\N
13801	83	25	\N	0	\N	\N	f	0	\N
13802	83	24	\N	0	\N	\N	f	0	\N
13803	83	23	\N	0	\N	\N	f	0	\N
13804	83	22	\N	0	\N	\N	f	0	\N
13805	83	21	\N	0	\N	\N	f	0	\N
13806	83	20	\N	0	\N	\N	f	0	\N
13807	83	19	\N	0	\N	\N	f	0	\N
13808	83	18	\N	0	\N	\N	f	0	\N
13809	83	17	\N	0	\N	\N	f	0	\N
13810	83	16	\N	0	\N	\N	f	0	\N
13811	83	15	\N	0	\N	\N	f	0	\N
13812	83	14	\N	0	\N	\N	f	0	\N
13813	83	13	\N	0	\N	\N	f	0	\N
13814	83	12	\N	0	\N	\N	f	0	\N
13815	83	11	\N	0	\N	\N	f	0	\N
13816	83	10	\N	0	\N	\N	f	0	\N
13817	83	9	\N	0	\N	\N	f	0	\N
13818	83	8	\N	0	\N	\N	f	0	\N
13819	83	7	\N	0	\N	\N	f	0	\N
13820	83	6	\N	0	\N	\N	f	0	\N
13821	83	5	\N	0	\N	\N	f	0	\N
13822	83	4	\N	0	\N	\N	f	0	\N
13823	83	3	\N	0	\N	\N	f	0	\N
13824	83	2	\N	0	\N	\N	f	0	\N
13825	83	1	\N	0	\N	\N	f	0	\N
13826	83	432	\N	0	\N	\N	f	0	\N
13827	83	431	\N	0	\N	\N	f	0	\N
13828	83	430	\N	0	\N	\N	f	0	\N
13829	83	429	\N	0	\N	\N	f	0	\N
13830	83	428	\N	0	\N	\N	f	0	\N
13831	83	427	\N	0	\N	\N	f	0	\N
13832	83	426	\N	0	\N	\N	f	0	\N
13833	83	425	\N	0	\N	\N	f	0	\N
13834	83	424	\N	0	\N	\N	f	0	\N
13835	83	423	\N	0	\N	\N	f	0	\N
13836	83	422	\N	0	\N	\N	f	0	\N
13837	83	421	\N	0	\N	\N	f	0	\N
13838	83	420	\N	0	\N	\N	f	0	\N
13839	83	419	\N	0	\N	\N	f	0	\N
13840	83	418	\N	0	\N	\N	f	0	\N
13841	83	417	\N	0	\N	\N	f	0	\N
13842	83	416	\N	0	\N	\N	f	0	\N
13843	83	415	\N	0	\N	\N	f	0	\N
13844	83	414	\N	0	\N	\N	f	0	\N
13845	83	413	\N	0	\N	\N	f	0	\N
13846	83	412	\N	0	\N	\N	f	0	\N
13847	83	411	\N	0	\N	\N	f	0	\N
13848	83	410	\N	0	\N	\N	f	0	\N
13849	83	409	\N	0	\N	\N	f	0	\N
13850	83	408	\N	0	\N	\N	f	0	\N
13851	83	407	\N	0	\N	\N	f	0	\N
13852	83	406	\N	0	\N	\N	f	0	\N
13853	83	405	\N	0	\N	\N	f	0	\N
13854	83	404	\N	0	\N	\N	f	0	\N
13855	83	403	\N	0	\N	\N	f	0	\N
13856	83	402	\N	0	\N	\N	f	0	\N
13857	83	290	\N	0	\N	\N	f	0	\N
13858	83	289	\N	0	\N	\N	f	0	\N
13859	83	288	\N	0	\N	\N	f	0	\N
13860	83	287	\N	0	\N	\N	f	0	\N
13861	83	286	\N	0	\N	\N	f	0	\N
13862	83	285	\N	0	\N	\N	f	0	\N
13863	83	284	\N	0	\N	\N	f	0	\N
13864	83	283	\N	0	\N	\N	f	0	\N
13865	83	282	\N	0	\N	\N	f	0	\N
13866	83	281	\N	0	\N	\N	f	0	\N
13867	83	280	\N	0	\N	\N	f	0	\N
13868	83	279	\N	0	\N	\N	f	0	\N
13869	83	278	\N	0	\N	\N	f	0	\N
13870	83	277	\N	0	\N	\N	f	0	\N
13871	83	276	\N	0	\N	\N	f	0	\N
13872	83	275	\N	0	\N	\N	f	0	\N
13873	83	274	\N	0	\N	\N	f	0	\N
13874	83	273	\N	0	\N	\N	f	0	\N
13875	83	272	\N	0	\N	\N	f	0	\N
13876	83	271	\N	0	\N	\N	f	0	\N
13877	83	270	\N	0	\N	\N	f	0	\N
13878	83	269	\N	0	\N	\N	f	0	\N
13879	83	268	\N	0	\N	\N	f	0	\N
13880	83	267	\N	0	\N	\N	f	0	\N
13881	83	266	\N	0	\N	\N	f	0	\N
13882	83	265	\N	0	\N	\N	f	0	\N
13883	83	264	\N	0	\N	\N	f	0	\N
13884	83	263	\N	0	\N	\N	f	0	\N
13885	83	262	\N	0	\N	\N	f	0	\N
13886	83	261	\N	0	\N	\N	f	0	\N
13887	83	260	\N	0	\N	\N	f	0	\N
13888	83	259	\N	0	\N	\N	f	0	\N
13889	83	258	\N	0	\N	\N	f	0	\N
13890	83	257	\N	0	\N	\N	f	0	\N
13891	83	256	\N	0	\N	\N	f	0	\N
13892	83	255	\N	0	\N	\N	f	0	\N
13893	83	323	\N	0	\N	\N	f	0	\N
13894	83	322	\N	0	\N	\N	f	0	\N
13895	83	321	\N	0	\N	\N	f	0	\N
13896	83	320	\N	0	\N	\N	f	0	\N
13897	83	319	\N	0	\N	\N	f	0	\N
13898	83	318	\N	0	\N	\N	f	0	\N
13899	83	317	\N	0	\N	\N	f	0	\N
13900	83	316	\N	0	\N	\N	f	0	\N
13901	83	315	\N	0	\N	\N	f	0	\N
13902	83	314	\N	0	\N	\N	f	0	\N
13903	83	313	\N	0	\N	\N	f	0	\N
13904	83	312	\N	0	\N	\N	f	0	\N
13905	83	311	\N	0	\N	\N	f	0	\N
13906	83	310	\N	0	\N	\N	f	0	\N
13907	83	309	\N	0	\N	\N	f	0	\N
13908	83	308	\N	0	\N	\N	f	0	\N
13909	83	307	\N	0	\N	\N	f	0	\N
13910	83	306	\N	0	\N	\N	f	0	\N
13911	83	305	\N	0	\N	\N	f	0	\N
13912	83	304	\N	0	\N	\N	f	0	\N
13913	83	303	\N	0	\N	\N	f	0	\N
13914	83	302	\N	0	\N	\N	f	0	\N
13915	83	301	\N	0	\N	\N	f	0	\N
13916	83	300	\N	0	\N	\N	f	0	\N
13917	83	299	\N	0	\N	\N	f	0	\N
13918	83	298	\N	0	\N	\N	f	0	\N
13919	83	297	\N	0	\N	\N	f	0	\N
13920	83	296	\N	0	\N	\N	f	0	\N
13921	83	295	\N	0	\N	\N	f	0	\N
13922	83	294	\N	0	\N	\N	f	0	\N
13923	83	293	\N	0	\N	\N	f	0	\N
13924	83	292	\N	0	\N	\N	f	0	\N
13925	83	291	\N	0	\N	\N	f	0	\N
13926	83	401	\N	0	\N	\N	f	0	\N
13927	83	400	\N	0	\N	\N	f	0	\N
13928	83	399	\N	0	\N	\N	f	0	\N
13929	83	398	\N	0	\N	\N	f	0	\N
13930	83	397	\N	0	\N	\N	f	0	\N
13931	83	396	\N	0	\N	\N	f	0	\N
13932	83	395	\N	0	\N	\N	f	0	\N
13933	83	394	\N	0	\N	\N	f	0	\N
13934	83	393	\N	0	\N	\N	f	0	\N
13935	83	392	\N	0	\N	\N	f	0	\N
13936	83	391	\N	0	\N	\N	f	0	\N
13937	83	390	\N	0	\N	\N	f	0	\N
13938	83	389	\N	0	\N	\N	f	0	\N
13939	83	388	\N	0	\N	\N	f	0	\N
13940	83	387	\N	0	\N	\N	f	0	\N
13941	83	386	\N	0	\N	\N	f	0	\N
13942	83	385	\N	0	\N	\N	f	0	\N
13943	83	384	\N	0	\N	\N	f	0	\N
13944	83	383	\N	0	\N	\N	f	0	\N
13945	83	382	\N	0	\N	\N	f	0	\N
13946	83	381	\N	0	\N	\N	f	0	\N
13947	83	380	\N	0	\N	\N	f	0	\N
13948	83	379	\N	0	\N	\N	f	0	\N
13949	83	378	\N	0	\N	\N	f	0	\N
13950	83	377	\N	0	\N	\N	f	0	\N
13951	83	376	\N	0	\N	\N	f	0	\N
13952	83	375	\N	0	\N	\N	f	0	\N
13953	83	374	\N	0	\N	\N	f	0	\N
13954	83	373	\N	0	\N	\N	f	0	\N
13955	83	372	\N	0	\N	\N	f	0	\N
13956	83	371	\N	0	\N	\N	f	0	\N
13957	83	370	\N	0	\N	\N	f	0	\N
13958	83	369	\N	0	\N	\N	f	0	\N
13959	83	368	\N	0	\N	\N	f	0	\N
13960	83	367	\N	0	\N	\N	f	0	\N
13961	83	366	\N	0	\N	\N	f	0	\N
13962	83	365	\N	0	\N	\N	f	0	\N
13963	83	364	\N	0	\N	\N	f	0	\N
13964	83	363	\N	0	\N	\N	f	0	\N
13965	83	362	\N	0	\N	\N	f	0	\N
13966	83	361	\N	0	\N	\N	f	0	\N
13967	83	145	\N	0	\N	\N	f	0	\N
13968	83	144	\N	0	\N	\N	f	0	\N
13969	83	143	\N	0	\N	\N	f	0	\N
13970	83	142	\N	0	\N	\N	f	0	\N
13971	83	141	\N	0	\N	\N	f	0	\N
13972	83	140	\N	0	\N	\N	f	0	\N
13973	83	139	\N	0	\N	\N	f	0	\N
13974	83	138	\N	0	\N	\N	f	0	\N
13975	83	137	\N	0	\N	\N	f	0	\N
13976	83	136	\N	0	\N	\N	f	0	\N
13977	83	135	\N	0	\N	\N	f	0	\N
13978	83	134	\N	0	\N	\N	f	0	\N
13979	83	133	\N	0	\N	\N	f	0	\N
13980	83	132	\N	0	\N	\N	f	0	\N
13981	83	131	\N	0	\N	\N	f	0	\N
13982	83	130	\N	0	\N	\N	f	0	\N
13983	83	129	\N	0	\N	\N	f	0	\N
13984	83	128	\N	0	\N	\N	f	0	\N
13985	83	127	\N	0	\N	\N	f	0	\N
13986	83	126	\N	0	\N	\N	f	0	\N
13987	83	125	\N	0	\N	\N	f	0	\N
13988	83	124	\N	0	\N	\N	f	0	\N
13989	83	123	\N	0	\N	\N	f	0	\N
13990	83	122	\N	0	\N	\N	f	0	\N
13991	83	121	\N	0	\N	\N	f	0	\N
13992	83	120	\N	0	\N	\N	f	0	\N
13993	83	119	\N	0	\N	\N	f	0	\N
13994	83	118	\N	0	\N	\N	f	0	\N
13995	83	117	\N	0	\N	\N	f	0	\N
13996	83	116	\N	0	\N	\N	f	0	\N
13997	83	115	\N	0	\N	\N	f	0	\N
13998	83	114	\N	0	\N	\N	f	0	\N
13999	83	113	\N	0	\N	\N	f	0	\N
14000	83	112	\N	0	\N	\N	f	0	\N
14001	83	111	\N	0	\N	\N	f	0	\N
14002	83	110	\N	0	\N	\N	f	0	\N
14003	83	180	\N	0	\N	\N	f	0	\N
14004	83	179	\N	0	\N	\N	f	0	\N
14005	83	178	\N	0	\N	\N	f	0	\N
14006	83	177	\N	0	\N	\N	f	0	\N
14007	83	176	\N	0	\N	\N	f	0	\N
14008	83	175	\N	0	\N	\N	f	0	\N
14009	83	174	\N	0	\N	\N	f	0	\N
14010	83	173	\N	0	\N	\N	f	0	\N
14011	83	172	\N	0	\N	\N	f	0	\N
14012	83	171	\N	0	\N	\N	f	0	\N
14013	83	170	\N	0	\N	\N	f	0	\N
14014	83	169	\N	0	\N	\N	f	0	\N
14015	83	168	\N	0	\N	\N	f	0	\N
14016	83	167	\N	0	\N	\N	f	0	\N
14017	83	166	\N	0	\N	\N	f	0	\N
14018	83	165	\N	0	\N	\N	f	0	\N
14019	83	164	\N	0	\N	\N	f	0	\N
14020	83	163	\N	0	\N	\N	f	0	\N
14021	83	162	\N	0	\N	\N	f	0	\N
14022	83	161	\N	0	\N	\N	f	0	\N
14023	83	160	\N	0	\N	\N	f	0	\N
14024	83	159	\N	0	\N	\N	f	0	\N
14025	83	158	\N	0	\N	\N	f	0	\N
14026	83	157	\N	0	\N	\N	f	0	\N
14027	83	156	\N	0	\N	\N	f	0	\N
14028	83	155	\N	0	\N	\N	f	0	\N
14029	83	154	\N	0	\N	\N	f	0	\N
14030	83	153	\N	0	\N	\N	f	0	\N
14031	83	152	\N	0	\N	\N	f	0	\N
14032	83	151	\N	0	\N	\N	f	0	\N
14033	83	150	\N	0	\N	\N	f	0	\N
14034	83	149	\N	0	\N	\N	f	0	\N
14035	83	148	\N	0	\N	\N	f	0	\N
14036	83	147	\N	0	\N	\N	f	0	\N
14037	83	146	\N	0	\N	\N	f	0	\N
14038	83	218	\N	0	\N	\N	f	0	\N
14039	83	217	\N	0	\N	\N	f	0	\N
14040	83	216	\N	0	\N	\N	f	0	\N
14041	83	215	\N	0	\N	\N	f	0	\N
14042	83	214	\N	0	\N	\N	f	0	\N
14043	83	213	\N	0	\N	\N	f	0	\N
14044	83	212	\N	0	\N	\N	f	0	\N
14045	83	211	\N	0	\N	\N	f	0	\N
14046	83	210	\N	0	\N	\N	f	0	\N
14047	83	209	\N	0	\N	\N	f	0	\N
14048	83	208	\N	0	\N	\N	f	0	\N
14049	83	207	\N	0	\N	\N	f	0	\N
14050	83	206	\N	0	\N	\N	f	0	\N
14051	83	205	\N	0	\N	\N	f	0	\N
14052	83	204	\N	0	\N	\N	f	0	\N
14053	83	203	\N	0	\N	\N	f	0	\N
14054	83	202	\N	0	\N	\N	f	0	\N
14055	83	201	\N	0	\N	\N	f	0	\N
14056	83	200	\N	0	\N	\N	f	0	\N
14057	83	199	\N	0	\N	\N	f	0	\N
14058	83	198	\N	0	\N	\N	f	0	\N
14059	83	197	\N	0	\N	\N	f	0	\N
14060	83	196	\N	0	\N	\N	f	0	\N
14061	83	195	\N	0	\N	\N	f	0	\N
14062	83	194	\N	0	\N	\N	f	0	\N
14063	83	193	\N	0	\N	\N	f	0	\N
14064	83	192	\N	0	\N	\N	f	0	\N
14065	83	191	\N	0	\N	\N	f	0	\N
14066	83	190	\N	0	\N	\N	f	0	\N
14067	83	189	\N	0	\N	\N	f	0	\N
14068	83	188	\N	0	\N	\N	f	0	\N
14069	83	187	\N	0	\N	\N	f	0	\N
14070	83	186	\N	0	\N	\N	f	0	\N
14071	83	185	\N	0	\N	\N	f	0	\N
14072	83	184	\N	0	\N	\N	f	0	\N
14073	83	183	\N	0	\N	\N	f	0	\N
14074	83	182	\N	0	\N	\N	f	0	\N
14075	83	181	\N	0	\N	\N	f	0	\N
14076	83	74	\N	0	\N	\N	f	0	\N
14077	83	73	\N	0	\N	\N	f	0	\N
14078	83	72	\N	0	\N	\N	f	0	\N
14079	83	71	\N	0	\N	\N	f	0	\N
14080	83	70	\N	0	\N	\N	f	0	\N
14081	83	69	\N	0	\N	\N	f	0	\N
14082	83	68	\N	0	\N	\N	f	0	\N
14083	83	67	\N	0	\N	\N	f	0	\N
14084	83	66	\N	0	\N	\N	f	0	\N
14085	83	65	\N	0	\N	\N	f	0	\N
14086	83	64	\N	0	\N	\N	f	0	\N
14087	83	63	\N	0	\N	\N	f	0	\N
14088	83	62	\N	0	\N	\N	f	0	\N
14089	83	61	\N	0	\N	\N	f	0	\N
14090	83	60	\N	0	\N	\N	f	0	\N
14091	83	59	\N	0	\N	\N	f	0	\N
14092	83	58	\N	0	\N	\N	f	0	\N
14093	83	57	\N	0	\N	\N	f	0	\N
14094	83	56	\N	0	\N	\N	f	0	\N
14095	83	55	\N	0	\N	\N	f	0	\N
14096	83	54	\N	0	\N	\N	f	0	\N
14097	83	53	\N	0	\N	\N	f	0	\N
14098	83	52	\N	0	\N	\N	f	0	\N
14099	83	51	\N	0	\N	\N	f	0	\N
14100	83	50	\N	0	\N	\N	f	0	\N
14101	83	49	\N	0	\N	\N	f	0	\N
14102	83	48	\N	0	\N	\N	f	0	\N
14103	83	47	\N	0	\N	\N	f	0	\N
14104	83	46	\N	0	\N	\N	f	0	\N
14105	83	45	\N	0	\N	\N	f	0	\N
14106	83	44	\N	0	\N	\N	f	0	\N
14107	83	43	\N	0	\N	\N	f	0	\N
14108	83	42	\N	0	\N	\N	f	0	\N
14109	83	41	\N	0	\N	\N	f	0	\N
14110	83	40	\N	0	\N	\N	f	0	\N
14111	83	109	\N	0	\N	\N	f	0	\N
14112	83	108	\N	0	\N	\N	f	0	\N
14113	83	107	\N	0	\N	\N	f	0	\N
14114	83	106	\N	0	\N	\N	f	0	\N
14115	83	105	\N	0	\N	\N	f	0	\N
14116	83	104	\N	0	\N	\N	f	0	\N
14117	83	103	\N	0	\N	\N	f	0	\N
14118	83	102	\N	0	\N	\N	f	0	\N
14119	83	101	\N	0	\N	\N	f	0	\N
14120	83	100	\N	0	\N	\N	f	0	\N
14121	83	99	\N	0	\N	\N	f	0	\N
14122	83	98	\N	0	\N	\N	f	0	\N
14123	83	97	\N	0	\N	\N	f	0	\N
14124	83	96	\N	0	\N	\N	f	0	\N
14125	83	95	\N	0	\N	\N	f	0	\N
14126	83	94	\N	0	\N	\N	f	0	\N
14127	83	93	\N	0	\N	\N	f	0	\N
14128	83	92	\N	0	\N	\N	f	0	\N
14129	83	91	\N	0	\N	\N	f	0	\N
14130	83	90	\N	0	\N	\N	f	0	\N
14131	83	89	\N	0	\N	\N	f	0	\N
14132	83	88	\N	0	\N	\N	f	0	\N
14133	83	87	\N	0	\N	\N	f	0	\N
14134	83	86	\N	0	\N	\N	f	0	\N
14135	83	85	\N	0	\N	\N	f	0	\N
14136	83	84	\N	0	\N	\N	f	0	\N
14137	83	83	\N	0	\N	\N	f	0	\N
14138	83	82	\N	0	\N	\N	f	0	\N
14139	83	81	\N	0	\N	\N	f	0	\N
14140	83	80	\N	0	\N	\N	f	0	\N
14141	83	79	\N	0	\N	\N	f	0	\N
14142	83	78	\N	0	\N	\N	f	0	\N
14143	83	77	\N	0	\N	\N	f	0	\N
14144	83	76	\N	0	\N	\N	f	0	\N
14145	83	75	\N	0	\N	\N	f	0	\N
14146	83	254	\N	0	\N	\N	f	0	\N
14147	83	253	\N	0	\N	\N	f	0	\N
14148	83	252	\N	0	\N	\N	f	0	\N
14149	83	251	\N	0	\N	\N	f	0	\N
14150	83	250	\N	0	\N	\N	f	0	\N
14151	83	249	\N	0	\N	\N	f	0	\N
14152	83	248	\N	0	\N	\N	f	0	\N
14153	83	247	\N	0	\N	\N	f	0	\N
14154	83	246	\N	0	\N	\N	f	0	\N
14155	83	245	\N	0	\N	\N	f	0	\N
14156	83	244	\N	0	\N	\N	f	0	\N
14157	83	243	\N	0	\N	\N	f	0	\N
14158	83	242	\N	0	\N	\N	f	0	\N
14159	83	241	\N	0	\N	\N	f	0	\N
14160	83	240	\N	0	\N	\N	f	0	\N
14161	83	239	\N	0	\N	\N	f	0	\N
14162	83	238	\N	0	\N	\N	f	0	\N
14163	83	237	\N	0	\N	\N	f	0	\N
14164	83	236	\N	0	\N	\N	f	0	\N
14165	83	235	\N	0	\N	\N	f	0	\N
14166	83	234	\N	0	\N	\N	f	0	\N
14167	83	233	\N	0	\N	\N	f	0	\N
14168	83	232	\N	0	\N	\N	f	0	\N
14169	83	231	\N	0	\N	\N	f	0	\N
14170	83	230	\N	0	\N	\N	f	0	\N
14171	83	229	\N	0	\N	\N	f	0	\N
14172	83	228	\N	0	\N	\N	f	0	\N
14173	83	227	\N	0	\N	\N	f	0	\N
14174	83	226	\N	0	\N	\N	f	0	\N
14175	83	225	\N	0	\N	\N	f	0	\N
14176	83	224	\N	0	\N	\N	f	0	\N
14177	83	223	\N	0	\N	\N	f	0	\N
14178	83	222	\N	0	\N	\N	f	0	\N
14179	83	221	\N	0	\N	\N	f	0	\N
14180	83	220	\N	0	\N	\N	f	0	\N
14181	83	219	\N	0	\N	\N	f	0	\N
14182	84	109	\N	0	\N	\N	f	0	\N
14183	84	108	\N	0	\N	\N	f	0	\N
14184	84	107	\N	0	\N	\N	f	0	\N
14185	84	106	\N	0	\N	\N	f	0	\N
14186	84	105	\N	0	\N	\N	f	0	\N
14187	84	104	\N	0	\N	\N	f	0	\N
14188	84	103	\N	0	\N	\N	f	0	\N
14189	84	102	\N	0	\N	\N	f	0	\N
14190	84	101	\N	0	\N	\N	f	0	\N
14191	84	100	\N	0	\N	\N	f	0	\N
14192	84	99	\N	0	\N	\N	f	0	\N
14193	84	98	\N	0	\N	\N	f	0	\N
14194	84	97	\N	0	\N	\N	f	0	\N
14195	84	96	\N	0	\N	\N	f	0	\N
14196	84	95	\N	0	\N	\N	f	0	\N
14197	84	94	\N	0	\N	\N	f	0	\N
14198	84	93	\N	0	\N	\N	f	0	\N
14199	84	92	\N	0	\N	\N	f	0	\N
14200	84	91	\N	0	\N	\N	f	0	\N
14201	84	90	\N	0	\N	\N	f	0	\N
14202	84	89	\N	0	\N	\N	f	0	\N
14203	84	88	\N	0	\N	\N	f	0	\N
14204	84	87	\N	0	\N	\N	f	0	\N
14205	84	86	\N	0	\N	\N	f	0	\N
14206	84	85	\N	0	\N	\N	f	0	\N
14207	84	84	\N	0	\N	\N	f	0	\N
14208	84	83	\N	0	\N	\N	f	0	\N
14209	84	82	\N	0	\N	\N	f	0	\N
14210	84	81	\N	0	\N	\N	f	0	\N
14211	84	80	\N	0	\N	\N	f	0	\N
14212	84	79	\N	0	\N	\N	f	0	\N
14213	84	78	\N	0	\N	\N	f	0	\N
14214	84	77	\N	0	\N	\N	f	0	\N
14215	84	76	\N	0	\N	\N	f	0	\N
14216	84	75	\N	0	\N	\N	f	0	\N
14217	84	290	\N	0	\N	\N	f	0	\N
14218	84	289	\N	0	\N	\N	f	0	\N
14219	84	288	\N	0	\N	\N	f	0	\N
14220	84	287	\N	0	\N	\N	f	0	\N
14221	84	286	\N	0	\N	\N	f	0	\N
14222	84	285	\N	0	\N	\N	f	0	\N
14223	84	284	\N	0	\N	\N	f	0	\N
14224	84	283	\N	0	\N	\N	f	0	\N
14225	84	282	\N	0	\N	\N	f	0	\N
14226	84	281	\N	0	\N	\N	f	0	\N
14227	84	280	\N	0	\N	\N	f	0	\N
14228	84	279	\N	0	\N	\N	f	0	\N
14229	84	278	\N	0	\N	\N	f	0	\N
14230	84	277	\N	0	\N	\N	f	0	\N
14231	84	276	\N	0	\N	\N	f	0	\N
14232	84	275	\N	0	\N	\N	f	0	\N
14233	84	274	\N	0	\N	\N	f	0	\N
14234	84	273	\N	0	\N	\N	f	0	\N
14235	84	272	\N	0	\N	\N	f	0	\N
14236	84	271	\N	0	\N	\N	f	0	\N
14237	84	270	\N	0	\N	\N	f	0	\N
14238	84	269	\N	0	\N	\N	f	0	\N
14239	84	268	\N	0	\N	\N	f	0	\N
14240	84	267	\N	0	\N	\N	f	0	\N
14241	84	266	\N	0	\N	\N	f	0	\N
14242	84	265	\N	0	\N	\N	f	0	\N
14243	84	264	\N	0	\N	\N	f	0	\N
14244	84	263	\N	0	\N	\N	f	0	\N
14245	84	262	\N	0	\N	\N	f	0	\N
14246	84	261	\N	0	\N	\N	f	0	\N
14247	84	260	\N	0	\N	\N	f	0	\N
14248	84	259	\N	0	\N	\N	f	0	\N
14249	84	258	\N	0	\N	\N	f	0	\N
14250	84	257	\N	0	\N	\N	f	0	\N
14251	84	256	\N	0	\N	\N	f	0	\N
14252	84	255	\N	0	\N	\N	f	0	\N
14253	84	360	\N	0	\N	\N	f	0	\N
14254	84	359	\N	0	\N	\N	f	0	\N
14255	84	358	\N	0	\N	\N	f	0	\N
14256	84	357	\N	0	\N	\N	f	0	\N
14257	84	356	\N	0	\N	\N	f	0	\N
14258	84	355	\N	0	\N	\N	f	0	\N
14259	84	354	\N	0	\N	\N	f	0	\N
14260	84	353	\N	0	\N	\N	f	0	\N
14261	84	352	\N	0	\N	\N	f	0	\N
14262	84	351	\N	0	\N	\N	f	0	\N
14263	84	350	\N	0	\N	\N	f	0	\N
14264	84	349	\N	0	\N	\N	f	0	\N
14265	84	348	\N	0	\N	\N	f	0	\N
14266	84	347	\N	0	\N	\N	f	0	\N
14267	84	346	\N	0	\N	\N	f	0	\N
14268	84	345	\N	0	\N	\N	f	0	\N
14269	84	344	\N	0	\N	\N	f	0	\N
14270	84	343	\N	0	\N	\N	f	0	\N
14271	84	342	\N	0	\N	\N	f	0	\N
14272	84	341	\N	0	\N	\N	f	0	\N
14273	84	340	\N	0	\N	\N	f	0	\N
14274	84	339	\N	0	\N	\N	f	0	\N
14275	84	338	\N	0	\N	\N	f	0	\N
14276	84	337	\N	0	\N	\N	f	0	\N
14277	84	336	\N	0	\N	\N	f	0	\N
14278	84	335	\N	0	\N	\N	f	0	\N
14279	84	334	\N	0	\N	\N	f	0	\N
14280	84	333	\N	0	\N	\N	f	0	\N
14281	84	332	\N	0	\N	\N	f	0	\N
14282	84	331	\N	0	\N	\N	f	0	\N
14283	84	330	\N	0	\N	\N	f	0	\N
14284	84	329	\N	0	\N	\N	f	0	\N
14285	84	328	\N	0	\N	\N	f	0	\N
14286	84	327	\N	0	\N	\N	f	0	\N
14287	84	326	\N	0	\N	\N	f	0	\N
14288	84	325	\N	0	\N	\N	f	0	\N
14289	84	324	\N	0	\N	\N	f	0	\N
14290	84	74	\N	0	\N	\N	f	0	\N
14291	84	73	\N	0	\N	\N	f	0	\N
14292	84	72	\N	0	\N	\N	f	0	\N
14293	84	71	\N	0	\N	\N	f	0	\N
14294	84	70	\N	0	\N	\N	f	0	\N
14295	84	69	\N	0	\N	\N	f	0	\N
14296	84	68	\N	0	\N	\N	f	0	\N
14297	84	67	\N	0	\N	\N	f	0	\N
14298	84	66	\N	0	\N	\N	f	0	\N
14299	84	65	\N	0	\N	\N	f	0	\N
14300	84	64	\N	0	\N	\N	f	0	\N
14301	84	63	\N	0	\N	\N	f	0	\N
14302	84	62	\N	0	\N	\N	f	0	\N
14303	84	61	\N	0	\N	\N	f	0	\N
14304	84	60	\N	0	\N	\N	f	0	\N
14305	84	59	\N	0	\N	\N	f	0	\N
14306	84	58	\N	0	\N	\N	f	0	\N
14307	84	57	\N	0	\N	\N	f	0	\N
14308	84	56	\N	0	\N	\N	f	0	\N
14309	84	55	\N	0	\N	\N	f	0	\N
14310	84	54	\N	0	\N	\N	f	0	\N
14311	84	53	\N	0	\N	\N	f	0	\N
14312	84	52	\N	0	\N	\N	f	0	\N
14313	84	51	\N	0	\N	\N	f	0	\N
14314	84	50	\N	0	\N	\N	f	0	\N
14315	84	49	\N	0	\N	\N	f	0	\N
14316	84	48	\N	0	\N	\N	f	0	\N
14317	84	47	\N	0	\N	\N	f	0	\N
14318	84	46	\N	0	\N	\N	f	0	\N
14319	84	45	\N	0	\N	\N	f	0	\N
14320	84	44	\N	0	\N	\N	f	0	\N
14321	84	43	\N	0	\N	\N	f	0	\N
14322	84	42	\N	0	\N	\N	f	0	\N
14323	84	41	\N	0	\N	\N	f	0	\N
14324	84	40	\N	0	\N	\N	f	0	\N
14325	84	218	\N	0	\N	\N	f	0	\N
14326	84	217	\N	0	\N	\N	f	0	\N
14327	84	216	\N	0	\N	\N	f	0	\N
14328	84	215	\N	0	\N	\N	f	0	\N
14329	84	214	\N	0	\N	\N	f	0	\N
14330	84	213	\N	0	\N	\N	f	0	\N
14331	84	212	\N	0	\N	\N	f	0	\N
14332	84	211	\N	0	\N	\N	f	0	\N
14333	84	210	\N	0	\N	\N	f	0	\N
14334	84	209	\N	0	\N	\N	f	0	\N
14335	84	208	\N	0	\N	\N	f	0	\N
14336	84	207	\N	0	\N	\N	f	0	\N
14337	84	206	\N	0	\N	\N	f	0	\N
14338	84	205	\N	0	\N	\N	f	0	\N
14339	84	204	\N	0	\N	\N	f	0	\N
14340	84	203	\N	0	\N	\N	f	0	\N
14341	84	202	\N	0	\N	\N	f	0	\N
14342	84	201	\N	0	\N	\N	f	0	\N
14343	84	200	\N	0	\N	\N	f	0	\N
14344	84	199	\N	0	\N	\N	f	0	\N
14345	84	198	\N	0	\N	\N	f	0	\N
14346	84	197	\N	0	\N	\N	f	0	\N
14347	84	196	\N	0	\N	\N	f	0	\N
14348	84	195	\N	0	\N	\N	f	0	\N
14349	84	194	\N	0	\N	\N	f	0	\N
14350	84	193	\N	0	\N	\N	f	0	\N
14351	84	192	\N	0	\N	\N	f	0	\N
14352	84	191	\N	0	\N	\N	f	0	\N
14353	84	190	\N	0	\N	\N	f	0	\N
14354	84	189	\N	0	\N	\N	f	0	\N
14355	84	188	\N	0	\N	\N	f	0	\N
14356	84	187	\N	0	\N	\N	f	0	\N
14357	84	186	\N	0	\N	\N	f	0	\N
14358	84	185	\N	0	\N	\N	f	0	\N
14359	84	184	\N	0	\N	\N	f	0	\N
14360	84	183	\N	0	\N	\N	f	0	\N
14361	84	182	\N	0	\N	\N	f	0	\N
14362	84	181	\N	0	\N	\N	f	0	\N
14363	84	323	\N	0	\N	\N	f	0	\N
14364	84	322	\N	0	\N	\N	f	0	\N
14365	84	321	\N	0	\N	\N	f	0	\N
14366	84	320	\N	0	\N	\N	f	0	\N
14367	84	319	\N	0	\N	\N	f	0	\N
14368	84	318	\N	0	\N	\N	f	0	\N
14369	84	317	\N	0	\N	\N	f	0	\N
14370	84	316	\N	0	\N	\N	f	0	\N
14371	84	315	\N	0	\N	\N	f	0	\N
14372	84	314	\N	0	\N	\N	f	0	\N
14373	84	313	\N	0	\N	\N	f	0	\N
14374	84	312	\N	0	\N	\N	f	0	\N
14375	84	311	\N	0	\N	\N	f	0	\N
14376	84	310	\N	0	\N	\N	f	0	\N
14377	84	309	\N	0	\N	\N	f	0	\N
14378	84	308	\N	0	\N	\N	f	0	\N
14379	84	307	\N	0	\N	\N	f	0	\N
14380	84	306	\N	0	\N	\N	f	0	\N
14381	84	305	\N	0	\N	\N	f	0	\N
14382	84	304	\N	0	\N	\N	f	0	\N
14383	84	303	\N	0	\N	\N	f	0	\N
14384	84	302	\N	0	\N	\N	f	0	\N
14385	84	301	\N	0	\N	\N	f	0	\N
14386	84	300	\N	0	\N	\N	f	0	\N
14387	84	299	\N	0	\N	\N	f	0	\N
14388	84	298	\N	0	\N	\N	f	0	\N
14389	84	297	\N	0	\N	\N	f	0	\N
14390	84	296	\N	0	\N	\N	f	0	\N
14391	84	295	\N	0	\N	\N	f	0	\N
14392	84	294	\N	0	\N	\N	f	0	\N
14393	84	293	\N	0	\N	\N	f	0	\N
14394	84	292	\N	0	\N	\N	f	0	\N
14395	84	291	\N	0	\N	\N	f	0	\N
14396	84	145	\N	0	\N	\N	f	0	\N
14397	84	144	\N	0	\N	\N	f	0	\N
14398	84	143	\N	0	\N	\N	f	0	\N
14399	84	142	\N	0	\N	\N	f	0	\N
14400	84	141	\N	0	\N	\N	f	0	\N
14401	84	140	\N	0	\N	\N	f	0	\N
14402	84	139	\N	0	\N	\N	f	0	\N
14403	84	138	\N	0	\N	\N	f	0	\N
14404	84	137	\N	0	\N	\N	f	0	\N
14405	84	136	\N	0	\N	\N	f	0	\N
14406	84	135	\N	0	\N	\N	f	0	\N
14407	84	134	\N	0	\N	\N	f	0	\N
14408	84	133	\N	0	\N	\N	f	0	\N
14409	84	132	\N	0	\N	\N	f	0	\N
14410	84	131	\N	0	\N	\N	f	0	\N
14411	84	130	\N	0	\N	\N	f	0	\N
14412	84	129	\N	0	\N	\N	f	0	\N
14413	84	128	\N	0	\N	\N	f	0	\N
14414	84	127	\N	0	\N	\N	f	0	\N
14415	84	126	\N	0	\N	\N	f	0	\N
14416	84	125	\N	0	\N	\N	f	0	\N
14417	84	124	\N	0	\N	\N	f	0	\N
14418	84	123	\N	0	\N	\N	f	0	\N
14419	84	122	\N	0	\N	\N	f	0	\N
14420	84	121	\N	0	\N	\N	f	0	\N
14421	84	120	\N	0	\N	\N	f	0	\N
14422	84	119	\N	0	\N	\N	f	0	\N
14423	84	118	\N	0	\N	\N	f	0	\N
14424	84	117	\N	0	\N	\N	f	0	\N
14425	84	116	\N	0	\N	\N	f	0	\N
14426	84	115	\N	0	\N	\N	f	0	\N
14427	84	114	\N	0	\N	\N	f	0	\N
14428	84	113	\N	0	\N	\N	f	0	\N
14429	84	112	\N	0	\N	\N	f	0	\N
14430	84	111	\N	0	\N	\N	f	0	\N
14431	84	110	\N	0	\N	\N	f	0	\N
14432	84	180	\N	0	\N	\N	f	0	\N
14433	84	179	\N	0	\N	\N	f	0	\N
14434	84	178	\N	0	\N	\N	f	0	\N
14435	84	177	\N	0	\N	\N	f	0	\N
14436	84	176	\N	0	\N	\N	f	0	\N
14437	84	175	\N	0	\N	\N	f	0	\N
14438	84	174	\N	0	\N	\N	f	0	\N
14439	84	173	\N	0	\N	\N	f	0	\N
14440	84	172	\N	0	\N	\N	f	0	\N
14441	84	171	\N	0	\N	\N	f	0	\N
14442	84	170	\N	0	\N	\N	f	0	\N
14443	84	169	\N	0	\N	\N	f	0	\N
14444	84	168	\N	0	\N	\N	f	0	\N
14445	84	167	\N	0	\N	\N	f	0	\N
14446	84	166	\N	0	\N	\N	f	0	\N
14447	84	165	\N	0	\N	\N	f	0	\N
14448	84	164	\N	0	\N	\N	f	0	\N
14449	84	163	\N	0	\N	\N	f	0	\N
14450	84	162	\N	0	\N	\N	f	0	\N
14451	84	161	\N	0	\N	\N	f	0	\N
14452	84	160	\N	0	\N	\N	f	0	\N
14453	84	159	\N	0	\N	\N	f	0	\N
14454	84	158	\N	0	\N	\N	f	0	\N
14455	84	157	\N	0	\N	\N	f	0	\N
14456	84	156	\N	0	\N	\N	f	0	\N
14457	84	155	\N	0	\N	\N	f	0	\N
14458	84	154	\N	0	\N	\N	f	0	\N
14459	84	153	\N	0	\N	\N	f	0	\N
14460	84	152	\N	0	\N	\N	f	0	\N
14461	84	151	\N	0	\N	\N	f	0	\N
14462	84	150	\N	0	\N	\N	f	0	\N
14463	84	149	\N	0	\N	\N	f	0	\N
14464	84	148	\N	0	\N	\N	f	0	\N
14465	84	147	\N	0	\N	\N	f	0	\N
14466	84	146	\N	0	\N	\N	f	0	\N
14467	84	254	\N	0	\N	\N	f	0	\N
14468	84	253	\N	0	\N	\N	f	0	\N
14469	84	252	\N	0	\N	\N	f	0	\N
14470	84	251	\N	0	\N	\N	f	0	\N
14471	84	250	\N	0	\N	\N	f	0	\N
14472	84	249	\N	0	\N	\N	f	0	\N
14473	84	248	\N	0	\N	\N	f	0	\N
14474	84	247	\N	0	\N	\N	f	0	\N
14475	84	246	\N	0	\N	\N	f	0	\N
14476	84	245	\N	0	\N	\N	f	0	\N
14477	84	244	\N	0	\N	\N	f	0	\N
14478	84	243	\N	0	\N	\N	f	0	\N
14479	84	242	\N	0	\N	\N	f	0	\N
14480	84	241	\N	0	\N	\N	f	0	\N
14481	84	240	\N	0	\N	\N	f	0	\N
14482	84	239	\N	0	\N	\N	f	0	\N
14483	84	238	\N	0	\N	\N	f	0	\N
14484	84	237	\N	0	\N	\N	f	0	\N
14485	84	236	\N	0	\N	\N	f	0	\N
14486	84	235	\N	0	\N	\N	f	0	\N
14487	84	234	\N	0	\N	\N	f	0	\N
14488	84	233	\N	0	\N	\N	f	0	\N
14489	84	232	\N	0	\N	\N	f	0	\N
14490	84	231	\N	0	\N	\N	f	0	\N
14491	84	230	\N	0	\N	\N	f	0	\N
14492	84	229	\N	0	\N	\N	f	0	\N
14493	84	228	\N	0	\N	\N	f	0	\N
14494	84	227	\N	0	\N	\N	f	0	\N
14495	84	226	\N	0	\N	\N	f	0	\N
14496	84	225	\N	0	\N	\N	f	0	\N
14497	84	224	\N	0	\N	\N	f	0	\N
14498	84	223	\N	0	\N	\N	f	0	\N
14499	84	222	\N	0	\N	\N	f	0	\N
14500	84	221	\N	0	\N	\N	f	0	\N
14501	84	220	\N	0	\N	\N	f	0	\N
14502	84	219	\N	0	\N	\N	f	0	\N
14503	84	432	\N	0	\N	\N	f	0	\N
14504	84	431	\N	0	\N	\N	f	0	\N
14505	84	430	\N	0	\N	\N	f	0	\N
14506	84	429	\N	0	\N	\N	f	0	\N
14507	84	428	\N	0	\N	\N	f	0	\N
14508	84	427	\N	0	\N	\N	f	0	\N
14509	84	426	\N	0	\N	\N	f	0	\N
14510	84	425	\N	0	\N	\N	f	0	\N
14511	84	424	\N	0	\N	\N	f	0	\N
14512	84	423	\N	0	\N	\N	f	0	\N
14513	84	422	\N	0	\N	\N	f	0	\N
14514	84	421	\N	0	\N	\N	f	0	\N
14515	84	420	\N	0	\N	\N	f	0	\N
14516	84	419	\N	0	\N	\N	f	0	\N
14517	84	418	\N	0	\N	\N	f	0	\N
14518	84	417	\N	0	\N	\N	f	0	\N
14519	84	416	\N	0	\N	\N	f	0	\N
14520	84	415	\N	0	\N	\N	f	0	\N
14521	84	414	\N	0	\N	\N	f	0	\N
14522	84	413	\N	0	\N	\N	f	0	\N
14523	84	412	\N	0	\N	\N	f	0	\N
14524	84	411	\N	0	\N	\N	f	0	\N
14525	84	410	\N	0	\N	\N	f	0	\N
14526	84	409	\N	0	\N	\N	f	0	\N
14527	84	408	\N	0	\N	\N	f	0	\N
14528	84	407	\N	0	\N	\N	f	0	\N
14529	84	406	\N	0	\N	\N	f	0	\N
14530	84	405	\N	0	\N	\N	f	0	\N
14531	84	404	\N	0	\N	\N	f	0	\N
14532	84	403	\N	0	\N	\N	f	0	\N
14533	84	402	\N	0	\N	\N	f	0	\N
14534	84	39	\N	0	\N	\N	f	0	\N
14535	84	38	\N	0	\N	\N	f	0	\N
14536	84	37	\N	0	\N	\N	f	0	\N
14537	84	36	\N	0	\N	\N	f	0	\N
14538	84	35	\N	0	\N	\N	f	0	\N
14539	84	34	\N	0	\N	\N	f	0	\N
14540	84	33	\N	0	\N	\N	f	0	\N
14541	84	32	\N	0	\N	\N	f	0	\N
14542	84	31	\N	0	\N	\N	f	0	\N
14543	84	30	\N	0	\N	\N	f	0	\N
14544	84	29	\N	0	\N	\N	f	0	\N
14545	84	28	\N	0	\N	\N	f	0	\N
14546	84	27	\N	0	\N	\N	f	0	\N
14547	84	26	\N	0	\N	\N	f	0	\N
14548	84	25	\N	0	\N	\N	f	0	\N
14549	84	24	\N	0	\N	\N	f	0	\N
14550	84	23	\N	0	\N	\N	f	0	\N
14551	84	22	\N	0	\N	\N	f	0	\N
14552	84	21	\N	0	\N	\N	f	0	\N
14553	84	20	\N	0	\N	\N	f	0	\N
14554	84	19	\N	0	\N	\N	f	0	\N
14555	84	18	\N	0	\N	\N	f	0	\N
14556	84	17	\N	0	\N	\N	f	0	\N
14557	84	16	\N	0	\N	\N	f	0	\N
14558	84	15	\N	0	\N	\N	f	0	\N
14559	84	14	\N	0	\N	\N	f	0	\N
14560	84	13	\N	0	\N	\N	f	0	\N
14561	84	12	\N	0	\N	\N	f	0	\N
14562	84	11	\N	0	\N	\N	f	0	\N
14563	84	10	\N	0	\N	\N	f	0	\N
14564	84	9	\N	0	\N	\N	f	0	\N
14565	84	8	\N	0	\N	\N	f	0	\N
14566	84	7	\N	0	\N	\N	f	0	\N
14567	84	6	\N	0	\N	\N	f	0	\N
14568	84	5	\N	0	\N	\N	f	0	\N
14569	84	4	\N	0	\N	\N	f	0	\N
14570	84	3	\N	0	\N	\N	f	0	\N
14571	84	2	\N	0	\N	\N	f	0	\N
14572	84	1	\N	0	\N	\N	f	0	\N
14573	84	401	\N	0	\N	\N	f	0	\N
14574	84	400	\N	0	\N	\N	f	0	\N
14575	84	399	\N	0	\N	\N	f	0	\N
14576	84	398	\N	0	\N	\N	f	0	\N
14577	84	397	\N	0	\N	\N	f	0	\N
14578	84	396	\N	0	\N	\N	f	0	\N
14579	84	395	\N	0	\N	\N	f	0	\N
14580	84	394	\N	0	\N	\N	f	0	\N
14581	84	393	\N	0	\N	\N	f	0	\N
14582	84	392	\N	0	\N	\N	f	0	\N
14583	84	391	\N	0	\N	\N	f	0	\N
14584	84	390	\N	0	\N	\N	f	0	\N
14585	84	389	\N	0	\N	\N	f	0	\N
14586	84	388	\N	0	\N	\N	f	0	\N
14587	84	387	\N	0	\N	\N	f	0	\N
14588	84	386	\N	0	\N	\N	f	0	\N
14589	84	385	\N	0	\N	\N	f	0	\N
14590	84	384	\N	0	\N	\N	f	0	\N
14591	84	383	\N	0	\N	\N	f	0	\N
14592	84	382	\N	0	\N	\N	f	0	\N
14593	84	381	\N	0	\N	\N	f	0	\N
14594	84	380	\N	0	\N	\N	f	0	\N
14595	84	379	\N	0	\N	\N	f	0	\N
14596	84	378	\N	0	\N	\N	f	0	\N
14597	84	377	\N	0	\N	\N	f	0	\N
14598	84	376	\N	0	\N	\N	f	0	\N
14599	84	375	\N	0	\N	\N	f	0	\N
14600	84	374	\N	0	\N	\N	f	0	\N
14601	84	373	\N	0	\N	\N	f	0	\N
14602	84	372	\N	0	\N	\N	f	0	\N
14603	84	371	\N	0	\N	\N	f	0	\N
14604	84	370	\N	0	\N	\N	f	0	\N
14605	84	369	\N	0	\N	\N	f	0	\N
14606	84	368	\N	0	\N	\N	f	0	\N
14607	84	367	\N	0	\N	\N	f	0	\N
14608	84	366	\N	0	\N	\N	f	0	\N
14609	84	365	\N	0	\N	\N	f	0	\N
14610	84	364	\N	0	\N	\N	f	0	\N
14611	84	363	\N	0	\N	\N	f	0	\N
14612	84	362	\N	0	\N	\N	f	0	\N
14613	84	361	\N	0	\N	\N	f	0	\N
14614	85	360	\N	0	\N	\N	f	0	\N
14615	85	359	\N	0	\N	\N	f	0	\N
14616	85	358	\N	0	\N	\N	f	0	\N
14617	85	357	\N	0	\N	\N	f	0	\N
14618	85	356	\N	0	\N	\N	f	0	\N
14619	85	355	\N	0	\N	\N	f	0	\N
14620	85	354	\N	0	\N	\N	f	0	\N
14621	85	353	\N	0	\N	\N	f	0	\N
14622	85	352	\N	0	\N	\N	f	0	\N
14623	85	351	\N	0	\N	\N	f	0	\N
14624	85	350	\N	0	\N	\N	f	0	\N
14625	85	349	\N	0	\N	\N	f	0	\N
14626	85	348	\N	0	\N	\N	f	0	\N
14627	85	347	\N	0	\N	\N	f	0	\N
14628	85	346	\N	0	\N	\N	f	0	\N
14629	85	345	\N	0	\N	\N	f	0	\N
14630	85	344	\N	0	\N	\N	f	0	\N
14631	85	343	\N	0	\N	\N	f	0	\N
14632	85	342	\N	0	\N	\N	f	0	\N
14633	85	341	\N	0	\N	\N	f	0	\N
14634	85	340	\N	0	\N	\N	f	0	\N
14635	85	339	\N	0	\N	\N	f	0	\N
14636	85	338	\N	0	\N	\N	f	0	\N
14637	85	337	\N	0	\N	\N	f	0	\N
14638	85	336	\N	0	\N	\N	f	0	\N
14639	85	335	\N	0	\N	\N	f	0	\N
14640	85	334	\N	0	\N	\N	f	0	\N
14641	85	333	\N	0	\N	\N	f	0	\N
14642	85	332	\N	0	\N	\N	f	0	\N
14643	85	331	\N	0	\N	\N	f	0	\N
14644	85	330	\N	0	\N	\N	f	0	\N
14645	85	329	\N	0	\N	\N	f	0	\N
14646	85	328	\N	0	\N	\N	f	0	\N
14647	85	327	\N	0	\N	\N	f	0	\N
14648	85	326	\N	0	\N	\N	f	0	\N
14649	85	325	\N	0	\N	\N	f	0	\N
14650	85	324	\N	0	\N	\N	f	0	\N
14651	85	39	\N	0	\N	\N	f	0	\N
14652	85	38	\N	0	\N	\N	f	0	\N
14653	85	37	\N	0	\N	\N	f	0	\N
14654	85	36	\N	0	\N	\N	f	0	\N
14655	85	35	\N	0	\N	\N	f	0	\N
14656	85	34	\N	0	\N	\N	f	0	\N
14657	85	33	\N	0	\N	\N	f	0	\N
14658	85	32	\N	0	\N	\N	f	0	\N
14659	85	31	\N	0	\N	\N	f	0	\N
14660	85	30	\N	0	\N	\N	f	0	\N
14661	85	29	\N	0	\N	\N	f	0	\N
14662	85	28	\N	0	\N	\N	f	0	\N
14663	85	27	\N	0	\N	\N	f	0	\N
14664	85	26	\N	0	\N	\N	f	0	\N
14665	85	25	\N	0	\N	\N	f	0	\N
14666	85	24	\N	0	\N	\N	f	0	\N
14667	85	23	\N	0	\N	\N	f	0	\N
14668	85	22	\N	0	\N	\N	f	0	\N
14669	85	21	\N	0	\N	\N	f	0	\N
14670	85	20	\N	0	\N	\N	f	0	\N
14671	85	19	\N	0	\N	\N	f	0	\N
14672	85	18	\N	0	\N	\N	f	0	\N
14673	85	17	\N	0	\N	\N	f	0	\N
14674	85	16	\N	0	\N	\N	f	0	\N
14675	85	15	\N	0	\N	\N	f	0	\N
14676	85	14	\N	0	\N	\N	f	0	\N
14677	85	13	\N	0	\N	\N	f	0	\N
14678	85	12	\N	0	\N	\N	f	0	\N
14679	85	11	\N	0	\N	\N	f	0	\N
14680	85	10	\N	0	\N	\N	f	0	\N
14681	85	9	\N	0	\N	\N	f	0	\N
14682	85	8	\N	0	\N	\N	f	0	\N
14683	85	7	\N	0	\N	\N	f	0	\N
14684	85	6	\N	0	\N	\N	f	0	\N
14685	85	5	\N	0	\N	\N	f	0	\N
14686	85	4	\N	0	\N	\N	f	0	\N
14687	85	3	\N	0	\N	\N	f	0	\N
14688	85	2	\N	0	\N	\N	f	0	\N
14689	85	1	\N	0	\N	\N	f	0	\N
14690	85	290	\N	0	\N	\N	f	0	\N
14691	85	289	\N	0	\N	\N	f	0	\N
14692	85	288	\N	0	\N	\N	f	0	\N
14693	85	287	\N	0	\N	\N	f	0	\N
14694	85	286	\N	0	\N	\N	f	0	\N
14695	85	285	\N	0	\N	\N	f	0	\N
14696	85	284	\N	0	\N	\N	f	0	\N
14697	85	283	\N	0	\N	\N	f	0	\N
14698	85	282	\N	0	\N	\N	f	0	\N
14699	85	281	\N	0	\N	\N	f	0	\N
14700	85	280	\N	0	\N	\N	f	0	\N
14701	85	279	\N	0	\N	\N	f	0	\N
14702	85	278	\N	0	\N	\N	f	0	\N
14703	85	277	\N	0	\N	\N	f	0	\N
14704	85	276	\N	0	\N	\N	f	0	\N
14705	85	275	\N	0	\N	\N	f	0	\N
14706	85	274	\N	0	\N	\N	f	0	\N
14707	85	273	\N	0	\N	\N	f	0	\N
14708	85	272	\N	0	\N	\N	f	0	\N
14709	85	271	\N	0	\N	\N	f	0	\N
14710	85	270	\N	0	\N	\N	f	0	\N
14711	85	269	\N	0	\N	\N	f	0	\N
14712	85	268	\N	0	\N	\N	f	0	\N
14713	85	267	\N	0	\N	\N	f	0	\N
14714	85	266	\N	0	\N	\N	f	0	\N
14715	85	265	\N	0	\N	\N	f	0	\N
14716	85	264	\N	0	\N	\N	f	0	\N
14717	85	263	\N	0	\N	\N	f	0	\N
14718	85	262	\N	0	\N	\N	f	0	\N
14719	85	261	\N	0	\N	\N	f	0	\N
14720	85	260	\N	0	\N	\N	f	0	\N
14721	85	259	\N	0	\N	\N	f	0	\N
14722	85	258	\N	0	\N	\N	f	0	\N
14723	85	257	\N	0	\N	\N	f	0	\N
14724	85	256	\N	0	\N	\N	f	0	\N
14725	85	255	\N	0	\N	\N	f	0	\N
14726	85	254	\N	0	\N	\N	f	0	\N
14727	85	253	\N	0	\N	\N	f	0	\N
14728	85	252	\N	0	\N	\N	f	0	\N
14729	85	251	\N	0	\N	\N	f	0	\N
14730	85	250	\N	0	\N	\N	f	0	\N
14731	85	249	\N	0	\N	\N	f	0	\N
14732	85	248	\N	0	\N	\N	f	0	\N
14733	85	247	\N	0	\N	\N	f	0	\N
14734	85	246	\N	0	\N	\N	f	0	\N
14735	85	245	\N	0	\N	\N	f	0	\N
14736	85	244	\N	0	\N	\N	f	0	\N
14737	85	243	\N	0	\N	\N	f	0	\N
14738	85	242	\N	0	\N	\N	f	0	\N
14739	85	241	\N	0	\N	\N	f	0	\N
14740	85	240	\N	0	\N	\N	f	0	\N
14741	85	239	\N	0	\N	\N	f	0	\N
14742	85	238	\N	0	\N	\N	f	0	\N
14743	85	237	\N	0	\N	\N	f	0	\N
14744	85	236	\N	0	\N	\N	f	0	\N
14745	85	235	\N	0	\N	\N	f	0	\N
14746	85	234	\N	0	\N	\N	f	0	\N
14747	85	233	\N	0	\N	\N	f	0	\N
14748	85	232	\N	0	\N	\N	f	0	\N
14749	85	231	\N	0	\N	\N	f	0	\N
14750	85	230	\N	0	\N	\N	f	0	\N
14751	85	229	\N	0	\N	\N	f	0	\N
14752	85	228	\N	0	\N	\N	f	0	\N
14753	85	227	\N	0	\N	\N	f	0	\N
14754	85	226	\N	0	\N	\N	f	0	\N
14755	85	225	\N	0	\N	\N	f	0	\N
14756	85	224	\N	0	\N	\N	f	0	\N
14757	85	223	\N	0	\N	\N	f	0	\N
14758	85	222	\N	0	\N	\N	f	0	\N
14759	85	221	\N	0	\N	\N	f	0	\N
14760	85	220	\N	0	\N	\N	f	0	\N
14761	85	219	\N	0	\N	\N	f	0	\N
14762	85	145	\N	0	\N	\N	f	0	\N
14763	85	144	\N	0	\N	\N	f	0	\N
14764	85	143	\N	0	\N	\N	f	0	\N
14765	85	142	\N	0	\N	\N	f	0	\N
14766	85	141	\N	0	\N	\N	f	0	\N
14767	85	140	\N	0	\N	\N	f	0	\N
14768	85	139	\N	0	\N	\N	f	0	\N
14769	85	138	\N	0	\N	\N	f	0	\N
14770	85	137	\N	0	\N	\N	f	0	\N
14771	85	136	\N	0	\N	\N	f	0	\N
14772	85	135	\N	0	\N	\N	f	0	\N
14773	85	134	\N	0	\N	\N	f	0	\N
14774	85	133	\N	0	\N	\N	f	0	\N
14775	85	132	\N	0	\N	\N	f	0	\N
14776	85	131	\N	0	\N	\N	f	0	\N
14777	85	130	\N	0	\N	\N	f	0	\N
14778	85	129	\N	0	\N	\N	f	0	\N
14779	85	128	\N	0	\N	\N	f	0	\N
14780	85	127	\N	0	\N	\N	f	0	\N
14781	85	126	\N	0	\N	\N	f	0	\N
14782	85	125	\N	0	\N	\N	f	0	\N
14783	85	124	\N	0	\N	\N	f	0	\N
14784	85	123	\N	0	\N	\N	f	0	\N
14785	85	122	\N	0	\N	\N	f	0	\N
14786	85	121	\N	0	\N	\N	f	0	\N
14787	85	120	\N	0	\N	\N	f	0	\N
14788	85	119	\N	0	\N	\N	f	0	\N
14789	85	118	\N	0	\N	\N	f	0	\N
14790	85	117	\N	0	\N	\N	f	0	\N
14791	85	116	\N	0	\N	\N	f	0	\N
14792	85	115	\N	0	\N	\N	f	0	\N
14793	85	114	\N	0	\N	\N	f	0	\N
14794	85	113	\N	0	\N	\N	f	0	\N
14795	85	112	\N	0	\N	\N	f	0	\N
14796	85	111	\N	0	\N	\N	f	0	\N
14797	85	110	\N	0	\N	\N	f	0	\N
14798	85	323	\N	0	\N	\N	f	0	\N
14799	85	322	\N	0	\N	\N	f	0	\N
14800	85	321	\N	0	\N	\N	f	0	\N
14801	85	320	\N	0	\N	\N	f	0	\N
14802	85	319	\N	0	\N	\N	f	0	\N
14803	85	318	\N	0	\N	\N	f	0	\N
14804	85	317	\N	0	\N	\N	f	0	\N
14805	85	316	\N	0	\N	\N	f	0	\N
14806	85	315	\N	0	\N	\N	f	0	\N
14807	85	314	\N	0	\N	\N	f	0	\N
14808	85	313	\N	0	\N	\N	f	0	\N
14809	85	312	\N	0	\N	\N	f	0	\N
14810	85	311	\N	0	\N	\N	f	0	\N
14811	85	310	\N	0	\N	\N	f	0	\N
14812	85	309	\N	0	\N	\N	f	0	\N
14813	85	308	\N	0	\N	\N	f	0	\N
14814	85	307	\N	0	\N	\N	f	0	\N
14815	85	306	\N	0	\N	\N	f	0	\N
14816	85	305	\N	0	\N	\N	f	0	\N
14817	85	304	\N	0	\N	\N	f	0	\N
14818	85	303	\N	0	\N	\N	f	0	\N
14819	85	302	\N	0	\N	\N	f	0	\N
14820	85	301	\N	0	\N	\N	f	0	\N
14821	85	300	\N	0	\N	\N	f	0	\N
14822	85	299	\N	0	\N	\N	f	0	\N
14823	85	298	\N	0	\N	\N	f	0	\N
14824	85	297	\N	0	\N	\N	f	0	\N
14825	85	296	\N	0	\N	\N	f	0	\N
14826	85	295	\N	0	\N	\N	f	0	\N
14827	85	294	\N	0	\N	\N	f	0	\N
14828	85	293	\N	0	\N	\N	f	0	\N
14829	85	292	\N	0	\N	\N	f	0	\N
14830	85	291	\N	0	\N	\N	f	0	\N
14831	85	109	\N	0	\N	\N	f	0	\N
14832	85	108	\N	0	\N	\N	f	0	\N
14833	85	107	\N	0	\N	\N	f	0	\N
14834	85	106	\N	0	\N	\N	f	0	\N
14835	85	105	\N	0	\N	\N	f	0	\N
14836	85	104	\N	0	\N	\N	f	0	\N
14837	85	103	\N	0	\N	\N	f	0	\N
14838	85	102	\N	0	\N	\N	f	0	\N
14839	85	101	\N	0	\N	\N	f	0	\N
14840	85	100	\N	0	\N	\N	f	0	\N
14841	85	99	\N	0	\N	\N	f	0	\N
14842	85	98	\N	0	\N	\N	f	0	\N
14843	85	97	\N	0	\N	\N	f	0	\N
14844	85	96	\N	0	\N	\N	f	0	\N
14845	85	95	\N	0	\N	\N	f	0	\N
14846	85	94	\N	0	\N	\N	f	0	\N
14847	85	93	\N	0	\N	\N	f	0	\N
14848	85	92	\N	0	\N	\N	f	0	\N
14849	85	91	\N	0	\N	\N	f	0	\N
14850	85	90	\N	0	\N	\N	f	0	\N
14851	85	89	\N	0	\N	\N	f	0	\N
14852	85	88	\N	0	\N	\N	f	0	\N
14853	85	87	\N	0	\N	\N	f	0	\N
14854	85	86	\N	0	\N	\N	f	0	\N
14855	85	85	\N	0	\N	\N	f	0	\N
14856	85	84	\N	0	\N	\N	f	0	\N
14857	85	83	\N	0	\N	\N	f	0	\N
14858	85	82	\N	0	\N	\N	f	0	\N
14859	85	81	\N	0	\N	\N	f	0	\N
14860	85	80	\N	0	\N	\N	f	0	\N
14861	85	79	\N	0	\N	\N	f	0	\N
14862	85	78	\N	0	\N	\N	f	0	\N
14863	85	77	\N	0	\N	\N	f	0	\N
14864	85	76	\N	0	\N	\N	f	0	\N
14865	85	75	\N	0	\N	\N	f	0	\N
14866	85	180	\N	0	\N	\N	f	0	\N
14867	85	179	\N	0	\N	\N	f	0	\N
14868	85	178	\N	0	\N	\N	f	0	\N
14869	85	177	\N	0	\N	\N	f	0	\N
14870	85	176	\N	0	\N	\N	f	0	\N
14871	85	175	\N	0	\N	\N	f	0	\N
14872	85	174	\N	0	\N	\N	f	0	\N
14873	85	173	\N	0	\N	\N	f	0	\N
14874	85	172	\N	0	\N	\N	f	0	\N
14875	85	171	\N	0	\N	\N	f	0	\N
14876	85	170	\N	0	\N	\N	f	0	\N
14877	85	169	\N	0	\N	\N	f	0	\N
14878	85	168	\N	0	\N	\N	f	0	\N
14879	85	167	\N	0	\N	\N	f	0	\N
14880	85	166	\N	0	\N	\N	f	0	\N
14881	85	165	\N	0	\N	\N	f	0	\N
14882	85	164	\N	0	\N	\N	f	0	\N
14883	85	163	\N	0	\N	\N	f	0	\N
14884	85	162	\N	0	\N	\N	f	0	\N
14885	85	161	\N	0	\N	\N	f	0	\N
14886	85	160	\N	0	\N	\N	f	0	\N
14887	85	159	\N	0	\N	\N	f	0	\N
14888	85	158	\N	0	\N	\N	f	0	\N
14889	85	157	\N	0	\N	\N	f	0	\N
14890	85	156	\N	0	\N	\N	f	0	\N
14891	85	155	\N	0	\N	\N	f	0	\N
14892	85	154	\N	0	\N	\N	f	0	\N
14893	85	153	\N	0	\N	\N	f	0	\N
14894	85	152	\N	0	\N	\N	f	0	\N
14895	85	151	\N	0	\N	\N	f	0	\N
14896	85	150	\N	0	\N	\N	f	0	\N
14897	85	149	\N	0	\N	\N	f	0	\N
14898	85	148	\N	0	\N	\N	f	0	\N
14899	85	147	\N	0	\N	\N	f	0	\N
14900	85	146	\N	0	\N	\N	f	0	\N
14901	85	218	\N	0	\N	\N	f	0	\N
14902	85	217	\N	0	\N	\N	f	0	\N
14903	85	216	\N	0	\N	\N	f	0	\N
14904	85	215	\N	0	\N	\N	f	0	\N
14905	85	214	\N	0	\N	\N	f	0	\N
14906	85	213	\N	0	\N	\N	f	0	\N
14907	85	212	\N	0	\N	\N	f	0	\N
14908	85	211	\N	0	\N	\N	f	0	\N
14909	85	210	\N	0	\N	\N	f	0	\N
14910	85	209	\N	0	\N	\N	f	0	\N
14911	85	208	\N	0	\N	\N	f	0	\N
14912	85	207	\N	0	\N	\N	f	0	\N
14913	85	206	\N	0	\N	\N	f	0	\N
14914	85	205	\N	0	\N	\N	f	0	\N
14915	85	204	\N	0	\N	\N	f	0	\N
14916	85	203	\N	0	\N	\N	f	0	\N
14917	85	202	\N	0	\N	\N	f	0	\N
14918	85	201	\N	0	\N	\N	f	0	\N
14919	85	200	\N	0	\N	\N	f	0	\N
14920	85	199	\N	0	\N	\N	f	0	\N
14921	85	198	\N	0	\N	\N	f	0	\N
14922	85	197	\N	0	\N	\N	f	0	\N
14923	85	196	\N	0	\N	\N	f	0	\N
14924	85	195	\N	0	\N	\N	f	0	\N
14925	85	194	\N	0	\N	\N	f	0	\N
14926	85	193	\N	0	\N	\N	f	0	\N
14927	85	192	\N	0	\N	\N	f	0	\N
14928	85	191	\N	0	\N	\N	f	0	\N
14929	85	190	\N	0	\N	\N	f	0	\N
14930	85	189	\N	0	\N	\N	f	0	\N
14931	85	188	\N	0	\N	\N	f	0	\N
14932	85	187	\N	0	\N	\N	f	0	\N
14933	85	186	\N	0	\N	\N	f	0	\N
14934	85	185	\N	0	\N	\N	f	0	\N
14935	85	184	\N	0	\N	\N	f	0	\N
14936	85	183	\N	0	\N	\N	f	0	\N
14937	85	182	\N	0	\N	\N	f	0	\N
14938	85	181	\N	0	\N	\N	f	0	\N
14939	85	74	\N	0	\N	\N	f	0	\N
14940	85	73	\N	0	\N	\N	f	0	\N
14941	85	72	\N	0	\N	\N	f	0	\N
14942	85	71	\N	0	\N	\N	f	0	\N
14943	85	70	\N	0	\N	\N	f	0	\N
14944	85	69	\N	0	\N	\N	f	0	\N
14945	85	68	\N	0	\N	\N	f	0	\N
14946	85	67	\N	0	\N	\N	f	0	\N
14947	85	66	\N	0	\N	\N	f	0	\N
14948	85	65	\N	0	\N	\N	f	0	\N
14949	85	64	\N	0	\N	\N	f	0	\N
14950	85	63	\N	0	\N	\N	f	0	\N
14951	85	62	\N	0	\N	\N	f	0	\N
14952	85	61	\N	0	\N	\N	f	0	\N
14953	85	60	\N	0	\N	\N	f	0	\N
14954	85	59	\N	0	\N	\N	f	0	\N
14955	85	58	\N	0	\N	\N	f	0	\N
14956	85	57	\N	0	\N	\N	f	0	\N
14957	85	56	\N	0	\N	\N	f	0	\N
14958	85	55	\N	0	\N	\N	f	0	\N
14959	85	54	\N	0	\N	\N	f	0	\N
14960	85	53	\N	0	\N	\N	f	0	\N
14961	85	52	\N	0	\N	\N	f	0	\N
14962	85	51	\N	0	\N	\N	f	0	\N
14963	85	50	\N	0	\N	\N	f	0	\N
14964	85	49	\N	0	\N	\N	f	0	\N
14965	85	48	\N	0	\N	\N	f	0	\N
14966	85	47	\N	0	\N	\N	f	0	\N
14967	85	46	\N	0	\N	\N	f	0	\N
14968	85	45	\N	0	\N	\N	f	0	\N
14969	85	44	\N	0	\N	\N	f	0	\N
14970	85	43	\N	0	\N	\N	f	0	\N
14971	85	42	\N	0	\N	\N	f	0	\N
14972	85	41	\N	0	\N	\N	f	0	\N
14973	85	40	\N	0	\N	\N	f	0	\N
14974	85	432	\N	0	\N	\N	f	0	\N
14975	85	431	\N	0	\N	\N	f	0	\N
14976	85	430	\N	0	\N	\N	f	0	\N
14977	85	429	\N	0	\N	\N	f	0	\N
14978	85	428	\N	0	\N	\N	f	0	\N
14979	85	427	\N	0	\N	\N	f	0	\N
14980	85	426	\N	0	\N	\N	f	0	\N
14981	85	425	\N	0	\N	\N	f	0	\N
14982	85	424	\N	0	\N	\N	f	0	\N
14983	85	423	\N	0	\N	\N	f	0	\N
14984	85	422	\N	0	\N	\N	f	0	\N
14985	85	421	\N	0	\N	\N	f	0	\N
14986	85	420	\N	0	\N	\N	f	0	\N
14987	85	419	\N	0	\N	\N	f	0	\N
14988	85	418	\N	0	\N	\N	f	0	\N
14989	85	417	\N	0	\N	\N	f	0	\N
14990	85	416	\N	0	\N	\N	f	0	\N
14991	85	415	\N	0	\N	\N	f	0	\N
14992	85	414	\N	0	\N	\N	f	0	\N
14993	85	413	\N	0	\N	\N	f	0	\N
14994	85	412	\N	0	\N	\N	f	0	\N
14995	85	411	\N	0	\N	\N	f	0	\N
14996	85	410	\N	0	\N	\N	f	0	\N
14997	85	409	\N	0	\N	\N	f	0	\N
14998	85	408	\N	0	\N	\N	f	0	\N
14999	85	407	\N	0	\N	\N	f	0	\N
15000	85	406	\N	0	\N	\N	f	0	\N
15001	85	405	\N	0	\N	\N	f	0	\N
15002	85	404	\N	0	\N	\N	f	0	\N
15003	85	403	\N	0	\N	\N	f	0	\N
15004	85	402	\N	0	\N	\N	f	0	\N
15005	85	401	\N	0	\N	\N	f	0	\N
15006	85	400	\N	0	\N	\N	f	0	\N
15007	85	399	\N	0	\N	\N	f	0	\N
15008	85	398	\N	0	\N	\N	f	0	\N
15009	85	397	\N	0	\N	\N	f	0	\N
15010	85	396	\N	0	\N	\N	f	0	\N
15011	85	395	\N	0	\N	\N	f	0	\N
15012	85	394	\N	0	\N	\N	f	0	\N
15013	85	393	\N	0	\N	\N	f	0	\N
15014	85	392	\N	0	\N	\N	f	0	\N
15015	85	391	\N	0	\N	\N	f	0	\N
15016	85	390	\N	0	\N	\N	f	0	\N
15017	85	389	\N	0	\N	\N	f	0	\N
15018	85	388	\N	0	\N	\N	f	0	\N
15019	85	387	\N	0	\N	\N	f	0	\N
15020	85	386	\N	0	\N	\N	f	0	\N
15021	85	385	\N	0	\N	\N	f	0	\N
15022	85	384	\N	0	\N	\N	f	0	\N
15023	85	383	\N	0	\N	\N	f	0	\N
15024	85	382	\N	0	\N	\N	f	0	\N
15025	85	381	\N	0	\N	\N	f	0	\N
15026	85	380	\N	0	\N	\N	f	0	\N
15027	85	379	\N	0	\N	\N	f	0	\N
15028	85	378	\N	0	\N	\N	f	0	\N
15029	85	377	\N	0	\N	\N	f	0	\N
15030	85	376	\N	0	\N	\N	f	0	\N
15031	85	375	\N	0	\N	\N	f	0	\N
15032	85	374	\N	0	\N	\N	f	0	\N
15033	85	373	\N	0	\N	\N	f	0	\N
15034	85	372	\N	0	\N	\N	f	0	\N
15035	85	371	\N	0	\N	\N	f	0	\N
15036	85	370	\N	0	\N	\N	f	0	\N
15037	85	369	\N	0	\N	\N	f	0	\N
15038	85	368	\N	0	\N	\N	f	0	\N
15039	85	367	\N	0	\N	\N	f	0	\N
15040	85	366	\N	0	\N	\N	f	0	\N
15041	85	365	\N	0	\N	\N	f	0	\N
15042	85	364	\N	0	\N	\N	f	0	\N
15043	85	363	\N	0	\N	\N	f	0	\N
15044	85	362	\N	0	\N	\N	f	0	\N
15045	85	361	\N	0	\N	\N	f	0	\N
15478	86	74	\N	0	\N	\N	f	0	\N
15479	86	73	\N	0	\N	\N	f	0	\N
15480	86	72	\N	0	\N	\N	f	0	\N
15481	86	71	\N	0	\N	\N	f	0	\N
15482	86	70	\N	0	\N	\N	f	0	\N
15483	86	69	\N	0	\N	\N	f	0	\N
15484	86	68	\N	0	\N	\N	f	0	\N
15485	86	67	\N	0	\N	\N	f	0	\N
15486	86	66	\N	0	\N	\N	f	0	\N
15487	86	65	\N	0	\N	\N	f	0	\N
15488	86	64	\N	0	\N	\N	f	0	\N
15489	86	63	\N	0	\N	\N	f	0	\N
15490	86	62	\N	0	\N	\N	f	0	\N
15491	86	61	\N	0	\N	\N	f	0	\N
15492	86	60	\N	0	\N	\N	f	0	\N
15493	86	59	\N	0	\N	\N	f	0	\N
15494	86	58	\N	0	\N	\N	f	0	\N
15495	86	57	\N	0	\N	\N	f	0	\N
15496	86	56	\N	0	\N	\N	f	0	\N
15497	86	55	\N	0	\N	\N	f	0	\N
15498	86	54	\N	0	\N	\N	f	0	\N
15499	86	53	\N	0	\N	\N	f	0	\N
15500	86	52	\N	0	\N	\N	f	0	\N
15501	86	51	\N	0	\N	\N	f	0	\N
15502	86	50	\N	0	\N	\N	f	0	\N
15503	86	49	\N	0	\N	\N	f	0	\N
15504	86	48	\N	0	\N	\N	f	0	\N
15505	86	47	\N	0	\N	\N	f	0	\N
15506	86	46	\N	0	\N	\N	f	0	\N
15507	86	45	\N	0	\N	\N	f	0	\N
15508	86	44	\N	0	\N	\N	f	0	\N
15509	86	43	\N	0	\N	\N	f	0	\N
15510	86	42	\N	0	\N	\N	f	0	\N
15511	86	41	\N	0	\N	\N	f	0	\N
15512	86	40	\N	0	\N	\N	f	0	\N
15513	86	145	\N	0	\N	\N	f	0	\N
15514	86	144	\N	0	\N	\N	f	0	\N
15515	86	143	\N	0	\N	\N	f	0	\N
15516	86	142	\N	0	\N	\N	f	0	\N
15517	86	141	\N	0	\N	\N	f	0	\N
15518	86	140	\N	0	\N	\N	f	0	\N
15519	86	139	\N	0	\N	\N	f	0	\N
15520	86	138	\N	0	\N	\N	f	0	\N
15521	86	137	\N	0	\N	\N	f	0	\N
15522	86	136	\N	0	\N	\N	f	0	\N
15523	86	135	\N	0	\N	\N	f	0	\N
15524	86	134	\N	0	\N	\N	f	0	\N
15525	86	133	\N	0	\N	\N	f	0	\N
15526	86	132	\N	0	\N	\N	f	0	\N
15527	86	131	\N	0	\N	\N	f	0	\N
15528	86	130	\N	0	\N	\N	f	0	\N
15529	86	129	\N	0	\N	\N	f	0	\N
15530	86	128	\N	0	\N	\N	f	0	\N
15531	86	127	\N	0	\N	\N	f	0	\N
15532	86	126	\N	0	\N	\N	f	0	\N
15533	86	125	\N	0	\N	\N	f	0	\N
15534	86	124	\N	0	\N	\N	f	0	\N
15535	86	123	\N	0	\N	\N	f	0	\N
15536	86	122	\N	0	\N	\N	f	0	\N
15537	86	121	\N	0	\N	\N	f	0	\N
15538	86	120	\N	0	\N	\N	f	0	\N
15539	86	119	\N	0	\N	\N	f	0	\N
15540	86	118	\N	0	\N	\N	f	0	\N
15541	86	117	\N	0	\N	\N	f	0	\N
15542	86	116	\N	0	\N	\N	f	0	\N
15543	86	115	\N	0	\N	\N	f	0	\N
15544	86	114	\N	0	\N	\N	f	0	\N
15545	86	113	\N	0	\N	\N	f	0	\N
15546	86	112	\N	0	\N	\N	f	0	\N
15547	86	111	\N	0	\N	\N	f	0	\N
15548	86	110	\N	0	\N	\N	f	0	\N
15549	86	432	\N	0	\N	\N	f	0	\N
15550	86	431	\N	0	\N	\N	f	0	\N
15551	86	430	\N	0	\N	\N	f	0	\N
15552	86	429	\N	0	\N	\N	f	0	\N
15553	86	428	\N	0	\N	\N	f	0	\N
15554	86	427	\N	0	\N	\N	f	0	\N
15555	86	426	\N	0	\N	\N	f	0	\N
15556	86	425	\N	0	\N	\N	f	0	\N
15557	86	424	\N	0	\N	\N	f	0	\N
15558	86	423	\N	0	\N	\N	f	0	\N
15559	86	422	\N	0	\N	\N	f	0	\N
15560	86	421	\N	0	\N	\N	f	0	\N
15561	86	420	\N	0	\N	\N	f	0	\N
15562	86	419	\N	0	\N	\N	f	0	\N
15563	86	418	\N	0	\N	\N	f	0	\N
15564	86	417	\N	0	\N	\N	f	0	\N
15565	86	416	\N	0	\N	\N	f	0	\N
15566	86	415	\N	0	\N	\N	f	0	\N
15567	86	414	\N	0	\N	\N	f	0	\N
15568	86	413	\N	0	\N	\N	f	0	\N
15569	86	412	\N	0	\N	\N	f	0	\N
15570	86	411	\N	0	\N	\N	f	0	\N
15571	86	410	\N	0	\N	\N	f	0	\N
15572	86	409	\N	0	\N	\N	f	0	\N
15573	86	408	\N	0	\N	\N	f	0	\N
15574	86	407	\N	0	\N	\N	f	0	\N
15575	86	406	\N	0	\N	\N	f	0	\N
15576	86	405	\N	0	\N	\N	f	0	\N
15577	86	404	\N	0	\N	\N	f	0	\N
15578	86	403	\N	0	\N	\N	f	0	\N
15579	86	402	\N	0	\N	\N	f	0	\N
15580	86	360	\N	0	\N	\N	f	0	\N
15581	86	359	\N	0	\N	\N	f	0	\N
15582	86	358	\N	0	\N	\N	f	0	\N
15583	86	357	\N	0	\N	\N	f	0	\N
15584	86	356	\N	0	\N	\N	f	0	\N
15585	86	355	\N	0	\N	\N	f	0	\N
15586	86	354	\N	0	\N	\N	f	0	\N
15587	86	353	\N	0	\N	\N	f	0	\N
15588	86	352	\N	0	\N	\N	f	0	\N
15589	86	351	\N	0	\N	\N	f	0	\N
15590	86	350	\N	0	\N	\N	f	0	\N
15591	86	349	\N	0	\N	\N	f	0	\N
15592	86	348	\N	0	\N	\N	f	0	\N
15593	86	347	\N	0	\N	\N	f	0	\N
15594	86	346	\N	0	\N	\N	f	0	\N
15595	86	345	\N	0	\N	\N	f	0	\N
15596	86	344	\N	0	\N	\N	f	0	\N
15597	86	343	\N	0	\N	\N	f	0	\N
15598	86	342	\N	0	\N	\N	f	0	\N
15599	86	341	\N	0	\N	\N	f	0	\N
15600	86	340	\N	0	\N	\N	f	0	\N
15601	86	339	\N	0	\N	\N	f	0	\N
15602	86	338	\N	0	\N	\N	f	0	\N
15603	86	337	\N	0	\N	\N	f	0	\N
15604	86	336	\N	0	\N	\N	f	0	\N
15605	86	335	\N	0	\N	\N	f	0	\N
15606	86	334	\N	0	\N	\N	f	0	\N
15607	86	333	\N	0	\N	\N	f	0	\N
15608	86	332	\N	0	\N	\N	f	0	\N
15609	86	331	\N	0	\N	\N	f	0	\N
15610	86	330	\N	0	\N	\N	f	0	\N
15611	86	329	\N	0	\N	\N	f	0	\N
15612	86	328	\N	0	\N	\N	f	0	\N
15613	86	327	\N	0	\N	\N	f	0	\N
15614	86	326	\N	0	\N	\N	f	0	\N
15615	86	325	\N	0	\N	\N	f	0	\N
15616	86	324	\N	0	\N	\N	f	0	\N
15617	86	401	\N	0	\N	\N	f	0	\N
15618	86	400	\N	0	\N	\N	f	0	\N
15619	86	399	\N	0	\N	\N	f	0	\N
15620	86	398	\N	0	\N	\N	f	0	\N
15621	86	397	\N	0	\N	\N	f	0	\N
15622	86	396	\N	0	\N	\N	f	0	\N
15623	86	395	\N	0	\N	\N	f	0	\N
15624	86	394	\N	0	\N	\N	f	0	\N
15625	86	393	\N	0	\N	\N	f	0	\N
15626	86	392	\N	0	\N	\N	f	0	\N
15627	86	391	\N	0	\N	\N	f	0	\N
15628	86	390	\N	0	\N	\N	f	0	\N
15629	86	389	\N	0	\N	\N	f	0	\N
15630	86	388	\N	0	\N	\N	f	0	\N
15631	86	387	\N	0	\N	\N	f	0	\N
15632	86	386	\N	0	\N	\N	f	0	\N
15633	86	385	\N	0	\N	\N	f	0	\N
15634	86	384	\N	0	\N	\N	f	0	\N
15635	86	383	\N	0	\N	\N	f	0	\N
15636	86	382	\N	0	\N	\N	f	0	\N
15637	86	381	\N	0	\N	\N	f	0	\N
15638	86	380	\N	0	\N	\N	f	0	\N
15639	86	379	\N	0	\N	\N	f	0	\N
15640	86	378	\N	0	\N	\N	f	0	\N
15641	86	377	\N	0	\N	\N	f	0	\N
15642	86	376	\N	0	\N	\N	f	0	\N
15643	86	375	\N	0	\N	\N	f	0	\N
15644	86	374	\N	0	\N	\N	f	0	\N
15645	86	373	\N	0	\N	\N	f	0	\N
15646	86	372	\N	0	\N	\N	f	0	\N
15647	86	371	\N	0	\N	\N	f	0	\N
15648	86	370	\N	0	\N	\N	f	0	\N
15649	86	369	\N	0	\N	\N	f	0	\N
15650	86	368	\N	0	\N	\N	f	0	\N
15651	86	367	\N	0	\N	\N	f	0	\N
15652	86	366	\N	0	\N	\N	f	0	\N
15653	86	365	\N	0	\N	\N	f	0	\N
15654	86	364	\N	0	\N	\N	f	0	\N
15655	86	363	\N	0	\N	\N	f	0	\N
15656	86	362	\N	0	\N	\N	f	0	\N
15657	86	361	\N	0	\N	\N	f	0	\N
15658	86	39	\N	0	\N	\N	f	0	\N
15659	86	38	\N	0	\N	\N	f	0	\N
15660	86	37	\N	0	\N	\N	f	0	\N
15661	86	36	\N	0	\N	\N	f	0	\N
15662	86	35	\N	0	\N	\N	f	0	\N
15663	86	34	\N	0	\N	\N	f	0	\N
15664	86	33	\N	0	\N	\N	f	0	\N
15665	86	32	\N	0	\N	\N	f	0	\N
15666	86	31	\N	0	\N	\N	f	0	\N
15667	86	30	\N	0	\N	\N	f	0	\N
15668	86	29	\N	0	\N	\N	f	0	\N
15669	86	28	\N	0	\N	\N	f	0	\N
15670	86	27	\N	0	\N	\N	f	0	\N
15671	86	26	\N	0	\N	\N	f	0	\N
15672	86	25	\N	0	\N	\N	f	0	\N
15673	86	24	\N	0	\N	\N	f	0	\N
15674	86	23	\N	0	\N	\N	f	0	\N
15675	86	22	\N	0	\N	\N	f	0	\N
15676	86	21	\N	0	\N	\N	f	0	\N
15677	86	20	\N	0	\N	\N	f	0	\N
15678	86	19	\N	0	\N	\N	f	0	\N
15679	86	18	\N	0	\N	\N	f	0	\N
15680	86	17	\N	0	\N	\N	f	0	\N
15681	86	16	\N	0	\N	\N	f	0	\N
15682	86	15	\N	0	\N	\N	f	0	\N
15683	86	14	\N	0	\N	\N	f	0	\N
15684	86	13	\N	0	\N	\N	f	0	\N
15685	86	12	\N	0	\N	\N	f	0	\N
15686	86	11	\N	0	\N	\N	f	0	\N
15687	86	10	\N	0	\N	\N	f	0	\N
15688	86	9	\N	0	\N	\N	f	0	\N
15689	86	8	\N	0	\N	\N	f	0	\N
15690	86	7	\N	0	\N	\N	f	0	\N
15691	86	6	\N	0	\N	\N	f	0	\N
15692	86	5	\N	0	\N	\N	f	0	\N
15693	86	4	\N	0	\N	\N	f	0	\N
15694	86	3	\N	0	\N	\N	f	0	\N
15695	86	2	\N	0	\N	\N	f	0	\N
15696	86	1	\N	0	\N	\N	f	0	\N
15697	86	323	\N	0	\N	\N	f	0	\N
15698	86	322	\N	0	\N	\N	f	0	\N
15699	86	321	\N	0	\N	\N	f	0	\N
15700	86	320	\N	0	\N	\N	f	0	\N
15701	86	319	\N	0	\N	\N	f	0	\N
15702	86	318	\N	0	\N	\N	f	0	\N
15703	86	317	\N	0	\N	\N	f	0	\N
15704	86	316	\N	0	\N	\N	f	0	\N
15705	86	315	\N	0	\N	\N	f	0	\N
15706	86	314	\N	0	\N	\N	f	0	\N
15707	86	313	\N	0	\N	\N	f	0	\N
15708	86	312	\N	0	\N	\N	f	0	\N
15709	86	311	\N	0	\N	\N	f	0	\N
15710	86	310	\N	0	\N	\N	f	0	\N
15711	86	309	\N	0	\N	\N	f	0	\N
15712	86	308	\N	0	\N	\N	f	0	\N
15713	86	307	\N	0	\N	\N	f	0	\N
15714	86	306	\N	0	\N	\N	f	0	\N
15715	86	305	\N	0	\N	\N	f	0	\N
15716	86	304	\N	0	\N	\N	f	0	\N
15717	86	303	\N	0	\N	\N	f	0	\N
15718	86	302	\N	0	\N	\N	f	0	\N
15719	86	301	\N	0	\N	\N	f	0	\N
15720	86	300	\N	0	\N	\N	f	0	\N
15721	86	299	\N	0	\N	\N	f	0	\N
15722	86	298	\N	0	\N	\N	f	0	\N
15723	86	297	\N	0	\N	\N	f	0	\N
15724	86	296	\N	0	\N	\N	f	0	\N
15725	86	295	\N	0	\N	\N	f	0	\N
15726	86	294	\N	0	\N	\N	f	0	\N
15727	86	293	\N	0	\N	\N	f	0	\N
15728	86	292	\N	0	\N	\N	f	0	\N
15729	86	291	\N	0	\N	\N	f	0	\N
15730	86	218	\N	0	\N	\N	f	0	\N
15731	86	217	\N	0	\N	\N	f	0	\N
15732	86	216	\N	0	\N	\N	f	0	\N
15733	86	215	\N	0	\N	\N	f	0	\N
15734	86	214	\N	0	\N	\N	f	0	\N
15735	86	213	\N	0	\N	\N	f	0	\N
15736	86	212	\N	0	\N	\N	f	0	\N
15737	86	211	\N	0	\N	\N	f	0	\N
15738	86	210	\N	0	\N	\N	f	0	\N
15739	86	209	\N	0	\N	\N	f	0	\N
15740	86	208	\N	0	\N	\N	f	0	\N
15741	86	207	\N	0	\N	\N	f	0	\N
15742	86	206	\N	0	\N	\N	f	0	\N
15743	86	205	\N	0	\N	\N	f	0	\N
15744	86	204	\N	0	\N	\N	f	0	\N
15745	86	203	\N	0	\N	\N	f	0	\N
15746	86	202	\N	0	\N	\N	f	0	\N
15747	86	201	\N	0	\N	\N	f	0	\N
15748	86	200	\N	0	\N	\N	f	0	\N
15749	86	199	\N	0	\N	\N	f	0	\N
15750	86	198	\N	0	\N	\N	f	0	\N
15751	86	197	\N	0	\N	\N	f	0	\N
15752	86	196	\N	0	\N	\N	f	0	\N
15753	86	195	\N	0	\N	\N	f	0	\N
15754	86	194	\N	0	\N	\N	f	0	\N
15755	86	193	\N	0	\N	\N	f	0	\N
15756	86	192	\N	0	\N	\N	f	0	\N
15757	86	191	\N	0	\N	\N	f	0	\N
15758	86	190	\N	0	\N	\N	f	0	\N
15759	86	189	\N	0	\N	\N	f	0	\N
15760	86	188	\N	0	\N	\N	f	0	\N
15761	86	187	\N	0	\N	\N	f	0	\N
15762	86	186	\N	0	\N	\N	f	0	\N
15763	86	185	\N	0	\N	\N	f	0	\N
15764	86	184	\N	0	\N	\N	f	0	\N
15765	86	183	\N	0	\N	\N	f	0	\N
15766	86	182	\N	0	\N	\N	f	0	\N
15767	86	181	\N	0	\N	\N	f	0	\N
15768	86	109	\N	0	\N	\N	f	0	\N
15769	86	108	\N	0	\N	\N	f	0	\N
15770	86	107	\N	0	\N	\N	f	0	\N
15771	86	106	\N	0	\N	\N	f	0	\N
15772	86	105	\N	0	\N	\N	f	0	\N
15773	86	104	\N	0	\N	\N	f	0	\N
15774	86	103	\N	0	\N	\N	f	0	\N
15775	86	102	\N	0	\N	\N	f	0	\N
15776	86	101	\N	0	\N	\N	f	0	\N
15777	86	100	\N	0	\N	\N	f	0	\N
15778	86	99	\N	0	\N	\N	f	0	\N
15779	86	98	\N	0	\N	\N	f	0	\N
15780	86	97	\N	0	\N	\N	f	0	\N
15781	86	96	\N	0	\N	\N	f	0	\N
15782	86	95	\N	0	\N	\N	f	0	\N
15783	86	94	\N	0	\N	\N	f	0	\N
15784	86	93	\N	0	\N	\N	f	0	\N
15785	86	92	\N	0	\N	\N	f	0	\N
15786	86	91	\N	0	\N	\N	f	0	\N
15787	86	90	\N	0	\N	\N	f	0	\N
15788	86	89	\N	0	\N	\N	f	0	\N
15789	86	88	\N	0	\N	\N	f	0	\N
15790	86	87	\N	0	\N	\N	f	0	\N
15791	86	86	\N	0	\N	\N	f	0	\N
15792	86	85	\N	0	\N	\N	f	0	\N
15793	86	84	\N	0	\N	\N	f	0	\N
15794	86	83	\N	0	\N	\N	f	0	\N
15795	86	82	\N	0	\N	\N	f	0	\N
15796	86	81	\N	0	\N	\N	f	0	\N
15797	86	80	\N	0	\N	\N	f	0	\N
15798	86	79	\N	0	\N	\N	f	0	\N
15799	86	78	\N	0	\N	\N	f	0	\N
15800	86	77	\N	0	\N	\N	f	0	\N
15801	86	76	\N	0	\N	\N	f	0	\N
15802	86	75	\N	0	\N	\N	f	0	\N
15803	86	290	\N	0	\N	\N	f	0	\N
15804	86	289	\N	0	\N	\N	f	0	\N
15805	86	288	\N	0	\N	\N	f	0	\N
15806	86	287	\N	0	\N	\N	f	0	\N
15807	86	286	\N	0	\N	\N	f	0	\N
15808	86	285	\N	0	\N	\N	f	0	\N
15809	86	284	\N	0	\N	\N	f	0	\N
15810	86	283	\N	0	\N	\N	f	0	\N
15811	86	282	\N	0	\N	\N	f	0	\N
15812	86	281	\N	0	\N	\N	f	0	\N
15813	86	280	\N	0	\N	\N	f	0	\N
15814	86	279	\N	0	\N	\N	f	0	\N
15815	86	278	\N	0	\N	\N	f	0	\N
15816	86	277	\N	0	\N	\N	f	0	\N
15817	86	276	\N	0	\N	\N	f	0	\N
15818	86	275	\N	0	\N	\N	f	0	\N
15819	86	274	\N	0	\N	\N	f	0	\N
15820	86	273	\N	0	\N	\N	f	0	\N
15821	86	272	\N	0	\N	\N	f	0	\N
15822	86	271	\N	0	\N	\N	f	0	\N
15823	86	270	\N	0	\N	\N	f	0	\N
15824	86	269	\N	0	\N	\N	f	0	\N
15825	86	268	\N	0	\N	\N	f	0	\N
15826	86	267	\N	0	\N	\N	f	0	\N
15827	86	266	\N	0	\N	\N	f	0	\N
15828	86	265	\N	0	\N	\N	f	0	\N
15829	86	264	\N	0	\N	\N	f	0	\N
15830	86	263	\N	0	\N	\N	f	0	\N
15831	86	262	\N	0	\N	\N	f	0	\N
15832	86	261	\N	0	\N	\N	f	0	\N
15833	86	260	\N	0	\N	\N	f	0	\N
15834	86	259	\N	0	\N	\N	f	0	\N
15835	86	258	\N	0	\N	\N	f	0	\N
15836	86	257	\N	0	\N	\N	f	0	\N
15837	86	256	\N	0	\N	\N	f	0	\N
15838	86	255	\N	0	\N	\N	f	0	\N
15839	86	254	\N	0	\N	\N	f	0	\N
15840	86	253	\N	0	\N	\N	f	0	\N
15841	86	252	\N	0	\N	\N	f	0	\N
15842	86	251	\N	0	\N	\N	f	0	\N
15843	86	250	\N	0	\N	\N	f	0	\N
15844	86	249	\N	0	\N	\N	f	0	\N
15845	86	248	\N	0	\N	\N	f	0	\N
15846	86	247	\N	0	\N	\N	f	0	\N
15847	86	246	\N	0	\N	\N	f	0	\N
15848	86	245	\N	0	\N	\N	f	0	\N
15849	86	244	\N	0	\N	\N	f	0	\N
15850	86	243	\N	0	\N	\N	f	0	\N
15851	86	242	\N	0	\N	\N	f	0	\N
15852	86	241	\N	0	\N	\N	f	0	\N
15853	86	240	\N	0	\N	\N	f	0	\N
15854	86	239	\N	0	\N	\N	f	0	\N
15855	86	238	\N	0	\N	\N	f	0	\N
15856	86	237	\N	0	\N	\N	f	0	\N
15857	86	236	\N	0	\N	\N	f	0	\N
15858	86	235	\N	0	\N	\N	f	0	\N
15859	86	234	\N	0	\N	\N	f	0	\N
15860	86	233	\N	0	\N	\N	f	0	\N
15861	86	232	\N	0	\N	\N	f	0	\N
15862	86	231	\N	0	\N	\N	f	0	\N
15863	86	230	\N	0	\N	\N	f	0	\N
15864	86	229	\N	0	\N	\N	f	0	\N
15865	86	228	\N	0	\N	\N	f	0	\N
15866	86	227	\N	0	\N	\N	f	0	\N
15867	86	226	\N	0	\N	\N	f	0	\N
15868	86	225	\N	0	\N	\N	f	0	\N
15869	86	224	\N	0	\N	\N	f	0	\N
15870	86	223	\N	0	\N	\N	f	0	\N
15871	86	222	\N	0	\N	\N	f	0	\N
15872	86	221	\N	0	\N	\N	f	0	\N
15873	86	220	\N	0	\N	\N	f	0	\N
15874	86	219	\N	0	\N	\N	f	0	\N
15875	87	145	\N	0	\N	\N	f	0	\N
15876	87	144	\N	0	\N	\N	f	0	\N
15877	87	143	\N	0	\N	\N	f	0	\N
15878	87	142	\N	0	\N	\N	f	0	\N
15879	87	141	\N	0	\N	\N	f	0	\N
15880	87	140	\N	0	\N	\N	f	0	\N
15881	87	139	\N	0	\N	\N	f	0	\N
15882	87	138	\N	0	\N	\N	f	0	\N
15883	87	137	\N	0	\N	\N	f	0	\N
15884	87	136	\N	0	\N	\N	f	0	\N
15885	87	135	\N	0	\N	\N	f	0	\N
15886	87	134	\N	0	\N	\N	f	0	\N
15887	87	133	\N	0	\N	\N	f	0	\N
15888	87	132	\N	0	\N	\N	f	0	\N
15889	87	131	\N	0	\N	\N	f	0	\N
15890	87	130	\N	0	\N	\N	f	0	\N
15891	87	129	\N	0	\N	\N	f	0	\N
15892	87	128	\N	0	\N	\N	f	0	\N
15893	87	127	\N	0	\N	\N	f	0	\N
15894	87	126	\N	0	\N	\N	f	0	\N
15895	87	125	\N	0	\N	\N	f	0	\N
15896	87	124	\N	0	\N	\N	f	0	\N
15897	87	123	\N	0	\N	\N	f	0	\N
15898	87	122	\N	0	\N	\N	f	0	\N
15899	87	121	\N	0	\N	\N	f	0	\N
15900	87	120	\N	0	\N	\N	f	0	\N
15901	87	119	\N	0	\N	\N	f	0	\N
15902	87	118	\N	0	\N	\N	f	0	\N
15903	87	117	\N	0	\N	\N	f	0	\N
15904	87	116	\N	0	\N	\N	f	0	\N
15905	87	115	\N	0	\N	\N	f	0	\N
15906	87	114	\N	0	\N	\N	f	0	\N
15907	87	113	\N	0	\N	\N	f	0	\N
15908	87	112	\N	0	\N	\N	f	0	\N
15909	87	111	\N	0	\N	\N	f	0	\N
15910	87	110	\N	0	\N	\N	f	0	\N
15911	87	109	\N	0	\N	\N	f	0	\N
15912	87	108	\N	0	\N	\N	f	0	\N
15913	87	107	\N	0	\N	\N	f	0	\N
15914	87	106	\N	0	\N	\N	f	0	\N
15915	87	105	\N	0	\N	\N	f	0	\N
15916	87	104	\N	0	\N	\N	f	0	\N
15917	87	103	\N	0	\N	\N	f	0	\N
15918	87	102	\N	0	\N	\N	f	0	\N
15919	87	101	\N	0	\N	\N	f	0	\N
15920	87	100	\N	0	\N	\N	f	0	\N
15921	87	99	\N	0	\N	\N	f	0	\N
15922	87	98	\N	0	\N	\N	f	0	\N
15923	87	97	\N	0	\N	\N	f	0	\N
15924	87	96	\N	0	\N	\N	f	0	\N
15925	87	95	\N	0	\N	\N	f	0	\N
15926	87	94	\N	0	\N	\N	f	0	\N
15927	87	93	\N	0	\N	\N	f	0	\N
15928	87	92	\N	0	\N	\N	f	0	\N
15929	87	91	\N	0	\N	\N	f	0	\N
15930	87	90	\N	0	\N	\N	f	0	\N
15931	87	89	\N	0	\N	\N	f	0	\N
15932	87	88	\N	0	\N	\N	f	0	\N
15933	87	87	\N	0	\N	\N	f	0	\N
15934	87	86	\N	0	\N	\N	f	0	\N
15935	87	85	\N	0	\N	\N	f	0	\N
15936	87	84	\N	0	\N	\N	f	0	\N
15937	87	83	\N	0	\N	\N	f	0	\N
15938	87	82	\N	0	\N	\N	f	0	\N
15939	87	81	\N	0	\N	\N	f	0	\N
15940	87	80	\N	0	\N	\N	f	0	\N
15941	87	79	\N	0	\N	\N	f	0	\N
15942	87	78	\N	0	\N	\N	f	0	\N
15943	87	77	\N	0	\N	\N	f	0	\N
15944	87	76	\N	0	\N	\N	f	0	\N
15945	87	75	\N	0	\N	\N	f	0	\N
15946	87	254	\N	0	\N	\N	f	0	\N
15947	87	253	\N	0	\N	\N	f	0	\N
15948	87	252	\N	0	\N	\N	f	0	\N
15949	87	251	\N	0	\N	\N	f	0	\N
15950	87	250	\N	0	\N	\N	f	0	\N
15951	87	249	\N	0	\N	\N	f	0	\N
15952	87	248	\N	0	\N	\N	f	0	\N
15953	87	247	\N	0	\N	\N	f	0	\N
15954	87	246	\N	0	\N	\N	f	0	\N
15955	87	245	\N	0	\N	\N	f	0	\N
15956	87	244	\N	0	\N	\N	f	0	\N
15957	87	243	\N	0	\N	\N	f	0	\N
15958	87	242	\N	0	\N	\N	f	0	\N
15959	87	241	\N	0	\N	\N	f	0	\N
15960	87	240	\N	0	\N	\N	f	0	\N
15961	87	239	\N	0	\N	\N	f	0	\N
15962	87	238	\N	0	\N	\N	f	0	\N
15963	87	237	\N	0	\N	\N	f	0	\N
15964	87	236	\N	0	\N	\N	f	0	\N
15965	87	235	\N	0	\N	\N	f	0	\N
15966	87	234	\N	0	\N	\N	f	0	\N
15967	87	233	\N	0	\N	\N	f	0	\N
15968	87	232	\N	0	\N	\N	f	0	\N
15969	87	231	\N	0	\N	\N	f	0	\N
15970	87	230	\N	0	\N	\N	f	0	\N
15971	87	229	\N	0	\N	\N	f	0	\N
15972	87	228	\N	0	\N	\N	f	0	\N
15973	87	227	\N	0	\N	\N	f	0	\N
15974	87	226	\N	0	\N	\N	f	0	\N
15975	87	225	\N	0	\N	\N	f	0	\N
15976	87	224	\N	0	\N	\N	f	0	\N
15977	87	223	\N	0	\N	\N	f	0	\N
15978	87	222	\N	0	\N	\N	f	0	\N
15979	87	221	\N	0	\N	\N	f	0	\N
15980	87	220	\N	0	\N	\N	f	0	\N
15981	87	219	\N	0	\N	\N	f	0	\N
15982	87	360	\N	0	\N	\N	f	0	\N
15983	87	359	\N	0	\N	\N	f	0	\N
15984	87	358	\N	0	\N	\N	f	0	\N
15985	87	357	\N	0	\N	\N	f	0	\N
15986	87	356	\N	0	\N	\N	f	0	\N
15987	87	355	\N	0	\N	\N	f	0	\N
15988	87	354	\N	0	\N	\N	f	0	\N
15989	87	353	\N	0	\N	\N	f	0	\N
15990	87	352	\N	0	\N	\N	f	0	\N
15991	87	351	\N	0	\N	\N	f	0	\N
15992	87	350	\N	0	\N	\N	f	0	\N
15993	87	349	\N	0	\N	\N	f	0	\N
15994	87	348	\N	0	\N	\N	f	0	\N
15995	87	347	\N	0	\N	\N	f	0	\N
15996	87	346	\N	0	\N	\N	f	0	\N
15997	87	345	\N	0	\N	\N	f	0	\N
15998	87	344	\N	0	\N	\N	f	0	\N
15999	87	343	\N	0	\N	\N	f	0	\N
16000	87	342	\N	0	\N	\N	f	0	\N
16001	87	341	\N	0	\N	\N	f	0	\N
16002	87	340	\N	0	\N	\N	f	0	\N
16003	87	339	\N	0	\N	\N	f	0	\N
16004	87	338	\N	0	\N	\N	f	0	\N
16005	87	337	\N	0	\N	\N	f	0	\N
16006	87	336	\N	0	\N	\N	f	0	\N
16007	87	335	\N	0	\N	\N	f	0	\N
16008	87	334	\N	0	\N	\N	f	0	\N
16009	87	333	\N	0	\N	\N	f	0	\N
16010	87	332	\N	0	\N	\N	f	0	\N
16011	87	331	\N	0	\N	\N	f	0	\N
16012	87	330	\N	0	\N	\N	f	0	\N
16013	87	329	\N	0	\N	\N	f	0	\N
16014	87	328	\N	0	\N	\N	f	0	\N
16015	87	327	\N	0	\N	\N	f	0	\N
16016	87	326	\N	0	\N	\N	f	0	\N
16017	87	325	\N	0	\N	\N	f	0	\N
16018	87	324	\N	0	\N	\N	f	0	\N
16019	87	290	\N	0	\N	\N	f	0	\N
16020	87	289	\N	0	\N	\N	f	0	\N
16021	87	288	\N	0	\N	\N	f	0	\N
16022	87	287	\N	0	\N	\N	f	0	\N
16023	87	286	\N	0	\N	\N	f	0	\N
16024	87	285	\N	0	\N	\N	f	0	\N
16025	87	284	\N	0	\N	\N	f	0	\N
16026	87	283	\N	0	\N	\N	f	0	\N
16027	87	282	\N	0	\N	\N	f	0	\N
16028	87	281	\N	0	\N	\N	f	0	\N
16029	87	280	\N	0	\N	\N	f	0	\N
16030	87	279	\N	0	\N	\N	f	0	\N
16031	87	278	\N	0	\N	\N	f	0	\N
16032	87	277	\N	0	\N	\N	f	0	\N
16033	87	276	\N	0	\N	\N	f	0	\N
16034	87	275	\N	0	\N	\N	f	0	\N
16035	87	274	\N	0	\N	\N	f	0	\N
16036	87	273	\N	0	\N	\N	f	0	\N
16037	87	272	\N	0	\N	\N	f	0	\N
16038	87	271	\N	0	\N	\N	f	0	\N
16039	87	270	\N	0	\N	\N	f	0	\N
16040	87	269	\N	0	\N	\N	f	0	\N
16041	87	268	\N	0	\N	\N	f	0	\N
16042	87	267	\N	0	\N	\N	f	0	\N
16043	87	266	\N	0	\N	\N	f	0	\N
16044	87	265	\N	0	\N	\N	f	0	\N
16045	87	264	\N	0	\N	\N	f	0	\N
16046	87	263	\N	0	\N	\N	f	0	\N
16047	87	262	\N	0	\N	\N	f	0	\N
16048	87	261	\N	0	\N	\N	f	0	\N
16049	87	260	\N	0	\N	\N	f	0	\N
16050	87	259	\N	0	\N	\N	f	0	\N
16051	87	258	\N	0	\N	\N	f	0	\N
16052	87	257	\N	0	\N	\N	f	0	\N
16053	87	256	\N	0	\N	\N	f	0	\N
16054	87	255	\N	0	\N	\N	f	0	\N
16055	87	218	\N	0	\N	\N	f	0	\N
16056	87	217	\N	0	\N	\N	f	0	\N
16057	87	216	\N	0	\N	\N	f	0	\N
16058	87	215	\N	0	\N	\N	f	0	\N
16059	87	214	\N	0	\N	\N	f	0	\N
16060	87	213	\N	0	\N	\N	f	0	\N
16061	87	212	\N	0	\N	\N	f	0	\N
16062	87	211	\N	0	\N	\N	f	0	\N
16063	87	210	\N	0	\N	\N	f	0	\N
16064	87	209	\N	0	\N	\N	f	0	\N
16065	87	208	\N	0	\N	\N	f	0	\N
16066	87	207	\N	0	\N	\N	f	0	\N
16067	87	206	\N	0	\N	\N	f	0	\N
16068	87	205	\N	0	\N	\N	f	0	\N
16069	87	204	\N	0	\N	\N	f	0	\N
16070	87	203	\N	0	\N	\N	f	0	\N
16071	87	202	\N	0	\N	\N	f	0	\N
16072	87	201	\N	0	\N	\N	f	0	\N
16073	87	200	\N	0	\N	\N	f	0	\N
16074	87	199	\N	0	\N	\N	f	0	\N
16075	87	198	\N	0	\N	\N	f	0	\N
16076	87	197	\N	0	\N	\N	f	0	\N
16077	87	196	\N	0	\N	\N	f	0	\N
16078	87	195	\N	0	\N	\N	f	0	\N
16079	87	194	\N	0	\N	\N	f	0	\N
16080	87	193	\N	0	\N	\N	f	0	\N
16081	87	192	\N	0	\N	\N	f	0	\N
16082	87	191	\N	0	\N	\N	f	0	\N
16083	87	190	\N	0	\N	\N	f	0	\N
16084	87	189	\N	0	\N	\N	f	0	\N
16085	87	188	\N	0	\N	\N	f	0	\N
16086	87	187	\N	0	\N	\N	f	0	\N
16087	87	186	\N	0	\N	\N	f	0	\N
16088	87	185	\N	0	\N	\N	f	0	\N
16089	87	184	\N	0	\N	\N	f	0	\N
16090	87	183	\N	0	\N	\N	f	0	\N
16091	87	182	\N	0	\N	\N	f	0	\N
16092	87	181	\N	0	\N	\N	f	0	\N
16093	87	39	\N	0	\N	\N	f	0	\N
16094	87	38	\N	0	\N	\N	f	0	\N
16095	87	37	\N	0	\N	\N	f	0	\N
16096	87	36	\N	0	\N	\N	f	0	\N
16097	87	35	\N	0	\N	\N	f	0	\N
16098	87	34	\N	0	\N	\N	f	0	\N
16099	87	33	\N	0	\N	\N	f	0	\N
16100	87	32	\N	0	\N	\N	f	0	\N
16101	87	31	\N	0	\N	\N	f	0	\N
16102	87	30	\N	0	\N	\N	f	0	\N
16103	87	29	\N	0	\N	\N	f	0	\N
16104	87	28	\N	0	\N	\N	f	0	\N
16105	87	27	\N	0	\N	\N	f	0	\N
16106	87	26	\N	0	\N	\N	f	0	\N
16107	87	25	\N	0	\N	\N	f	0	\N
16108	87	24	\N	0	\N	\N	f	0	\N
16109	87	23	\N	0	\N	\N	f	0	\N
16110	87	22	\N	0	\N	\N	f	0	\N
16111	87	21	\N	0	\N	\N	f	0	\N
16112	87	20	\N	0	\N	\N	f	0	\N
16113	87	19	\N	0	\N	\N	f	0	\N
16114	87	18	\N	0	\N	\N	f	0	\N
16115	87	17	\N	0	\N	\N	f	0	\N
16116	87	16	\N	0	\N	\N	f	0	\N
16117	87	15	\N	0	\N	\N	f	0	\N
16118	87	14	\N	0	\N	\N	f	0	\N
16119	87	13	\N	0	\N	\N	f	0	\N
16120	87	12	\N	0	\N	\N	f	0	\N
16121	87	11	\N	0	\N	\N	f	0	\N
16122	87	10	\N	0	\N	\N	f	0	\N
16123	87	9	\N	0	\N	\N	f	0	\N
16124	87	8	\N	0	\N	\N	f	0	\N
16125	87	7	\N	0	\N	\N	f	0	\N
16126	87	6	\N	0	\N	\N	f	0	\N
16127	87	5	\N	0	\N	\N	f	0	\N
16128	87	4	\N	0	\N	\N	f	0	\N
16129	87	3	\N	0	\N	\N	f	0	\N
16130	87	2	\N	0	\N	\N	f	0	\N
16131	87	1	\N	0	\N	\N	f	0	\N
16132	87	180	\N	0	\N	\N	f	0	\N
16133	87	179	\N	0	\N	\N	f	0	\N
16134	87	178	\N	0	\N	\N	f	0	\N
16135	87	177	\N	0	\N	\N	f	0	\N
16136	87	176	\N	0	\N	\N	f	0	\N
16137	87	175	\N	0	\N	\N	f	0	\N
16138	87	174	\N	0	\N	\N	f	0	\N
16139	87	173	\N	0	\N	\N	f	0	\N
16140	87	172	\N	0	\N	\N	f	0	\N
16141	87	171	\N	0	\N	\N	f	0	\N
16142	87	170	\N	0	\N	\N	f	0	\N
16143	87	169	\N	0	\N	\N	f	0	\N
16144	87	168	\N	0	\N	\N	f	0	\N
16145	87	167	\N	0	\N	\N	f	0	\N
16146	87	166	\N	0	\N	\N	f	0	\N
16147	87	165	\N	0	\N	\N	f	0	\N
16148	87	164	\N	0	\N	\N	f	0	\N
16149	87	163	\N	0	\N	\N	f	0	\N
16150	87	162	\N	0	\N	\N	f	0	\N
16151	87	161	\N	0	\N	\N	f	0	\N
16152	87	160	\N	0	\N	\N	f	0	\N
16153	87	159	\N	0	\N	\N	f	0	\N
16154	87	158	\N	0	\N	\N	f	0	\N
16155	87	157	\N	0	\N	\N	f	0	\N
16156	87	156	\N	0	\N	\N	f	0	\N
16157	87	155	\N	0	\N	\N	f	0	\N
16158	87	154	\N	0	\N	\N	f	0	\N
16159	87	153	\N	0	\N	\N	f	0	\N
16160	87	152	\N	0	\N	\N	f	0	\N
16161	87	151	\N	0	\N	\N	f	0	\N
16162	87	150	\N	0	\N	\N	f	0	\N
16163	87	149	\N	0	\N	\N	f	0	\N
16164	87	148	\N	0	\N	\N	f	0	\N
16165	87	147	\N	0	\N	\N	f	0	\N
16166	87	146	\N	0	\N	\N	f	0	\N
16167	87	74	\N	0	\N	\N	f	0	\N
16168	87	73	\N	0	\N	\N	f	0	\N
16169	87	72	\N	0	\N	\N	f	0	\N
16170	87	71	\N	0	\N	\N	f	0	\N
16171	87	70	\N	0	\N	\N	f	0	\N
16172	87	69	\N	0	\N	\N	f	0	\N
16173	87	68	\N	0	\N	\N	f	0	\N
16174	87	67	\N	0	\N	\N	f	0	\N
16175	87	66	\N	0	\N	\N	f	0	\N
16176	87	65	\N	0	\N	\N	f	0	\N
16177	87	64	\N	0	\N	\N	f	0	\N
16178	87	63	\N	0	\N	\N	f	0	\N
16179	87	62	\N	0	\N	\N	f	0	\N
16180	87	61	\N	0	\N	\N	f	0	\N
16181	87	60	\N	0	\N	\N	f	0	\N
16182	87	59	\N	0	\N	\N	f	0	\N
16183	87	58	\N	0	\N	\N	f	0	\N
16184	87	57	\N	0	\N	\N	f	0	\N
16185	87	56	\N	0	\N	\N	f	0	\N
16186	87	55	\N	0	\N	\N	f	0	\N
16187	87	54	\N	0	\N	\N	f	0	\N
16188	87	53	\N	0	\N	\N	f	0	\N
16189	87	52	\N	0	\N	\N	f	0	\N
16190	87	51	\N	0	\N	\N	f	0	\N
16191	87	50	\N	0	\N	\N	f	0	\N
16192	87	49	\N	0	\N	\N	f	0	\N
16193	87	48	\N	0	\N	\N	f	0	\N
16194	87	47	\N	0	\N	\N	f	0	\N
16195	87	46	\N	0	\N	\N	f	0	\N
16196	87	45	\N	0	\N	\N	f	0	\N
16197	87	44	\N	0	\N	\N	f	0	\N
16198	87	43	\N	0	\N	\N	f	0	\N
16199	87	42	\N	0	\N	\N	f	0	\N
16200	87	41	\N	0	\N	\N	f	0	\N
16201	87	40	\N	0	\N	\N	f	0	\N
16202	87	401	\N	0	\N	\N	f	0	\N
16203	87	400	\N	0	\N	\N	f	0	\N
16204	87	399	\N	0	\N	\N	f	0	\N
16205	87	398	\N	0	\N	\N	f	0	\N
16206	87	397	\N	0	\N	\N	f	0	\N
16207	87	396	\N	0	\N	\N	f	0	\N
16208	87	395	\N	0	\N	\N	f	0	\N
16209	87	394	\N	0	\N	\N	f	0	\N
16210	87	393	\N	0	\N	\N	f	0	\N
16211	87	392	\N	0	\N	\N	f	0	\N
16212	87	391	\N	0	\N	\N	f	0	\N
16213	87	390	\N	0	\N	\N	f	0	\N
16214	87	389	\N	0	\N	\N	f	0	\N
16215	87	388	\N	0	\N	\N	f	0	\N
16216	87	387	\N	0	\N	\N	f	0	\N
16217	87	386	\N	0	\N	\N	f	0	\N
16218	87	385	\N	0	\N	\N	f	0	\N
16219	87	384	\N	0	\N	\N	f	0	\N
16220	87	383	\N	0	\N	\N	f	0	\N
16221	87	382	\N	0	\N	\N	f	0	\N
16222	87	381	\N	0	\N	\N	f	0	\N
16223	87	380	\N	0	\N	\N	f	0	\N
16224	87	379	\N	0	\N	\N	f	0	\N
16225	87	378	\N	0	\N	\N	f	0	\N
16226	87	377	\N	0	\N	\N	f	0	\N
16227	87	376	\N	0	\N	\N	f	0	\N
16228	87	375	\N	0	\N	\N	f	0	\N
16229	87	374	\N	0	\N	\N	f	0	\N
16230	87	373	\N	0	\N	\N	f	0	\N
16231	87	372	\N	0	\N	\N	f	0	\N
16232	87	371	\N	0	\N	\N	f	0	\N
16233	87	370	\N	0	\N	\N	f	0	\N
16234	87	369	\N	0	\N	\N	f	0	\N
16235	87	368	\N	0	\N	\N	f	0	\N
16236	87	367	\N	0	\N	\N	f	0	\N
16237	87	366	\N	0	\N	\N	f	0	\N
16238	87	365	\N	0	\N	\N	f	0	\N
16239	87	364	\N	0	\N	\N	f	0	\N
16240	87	363	\N	0	\N	\N	f	0	\N
16241	87	362	\N	0	\N	\N	f	0	\N
16242	87	361	\N	0	\N	\N	f	0	\N
16243	88	218	\N	0	\N	\N	f	0	\N
16244	88	217	\N	0	\N	\N	f	0	\N
16245	88	216	\N	0	\N	\N	f	0	\N
16246	88	215	\N	0	\N	\N	f	0	\N
16247	88	214	\N	0	\N	\N	f	0	\N
16248	88	213	\N	0	\N	\N	f	0	\N
16249	88	212	\N	0	\N	\N	f	0	\N
16250	88	211	\N	0	\N	\N	f	0	\N
16251	88	210	\N	0	\N	\N	f	0	\N
16252	88	209	\N	0	\N	\N	f	0	\N
16253	88	208	\N	0	\N	\N	f	0	\N
16254	88	207	\N	0	\N	\N	f	0	\N
16255	88	206	\N	0	\N	\N	f	0	\N
16256	88	205	\N	0	\N	\N	f	0	\N
16257	88	204	\N	0	\N	\N	f	0	\N
16258	88	203	\N	0	\N	\N	f	0	\N
16259	88	202	\N	0	\N	\N	f	0	\N
16260	88	201	\N	0	\N	\N	f	0	\N
16261	88	200	\N	0	\N	\N	f	0	\N
16262	88	199	\N	0	\N	\N	f	0	\N
16263	88	198	\N	0	\N	\N	f	0	\N
16264	88	197	\N	0	\N	\N	f	0	\N
16265	88	196	\N	0	\N	\N	f	0	\N
16266	88	195	\N	0	\N	\N	f	0	\N
16267	88	194	\N	0	\N	\N	f	0	\N
16268	88	193	\N	0	\N	\N	f	0	\N
16269	88	192	\N	0	\N	\N	f	0	\N
16270	88	191	\N	0	\N	\N	f	0	\N
16271	88	190	\N	0	\N	\N	f	0	\N
16272	88	189	\N	0	\N	\N	f	0	\N
16273	88	188	\N	0	\N	\N	f	0	\N
16274	88	187	\N	0	\N	\N	f	0	\N
16275	88	186	\N	0	\N	\N	f	0	\N
16276	88	185	\N	0	\N	\N	f	0	\N
16277	88	184	\N	0	\N	\N	f	0	\N
16278	88	183	\N	0	\N	\N	f	0	\N
16279	88	182	\N	0	\N	\N	f	0	\N
16280	88	181	\N	0	\N	\N	f	0	\N
16281	88	323	\N	0	\N	\N	f	0	\N
16282	88	322	\N	0	\N	\N	f	0	\N
16283	88	321	\N	0	\N	\N	f	0	\N
16284	88	320	\N	0	\N	\N	f	0	\N
16285	88	319	\N	0	\N	\N	f	0	\N
16286	88	318	\N	0	\N	\N	f	0	\N
16287	88	317	\N	0	\N	\N	f	0	\N
16288	88	316	\N	0	\N	\N	f	0	\N
16289	88	315	\N	0	\N	\N	f	0	\N
16290	88	314	\N	0	\N	\N	f	0	\N
16291	88	313	\N	0	\N	\N	f	0	\N
16292	88	312	\N	0	\N	\N	f	0	\N
16293	88	311	\N	0	\N	\N	f	0	\N
16294	88	310	\N	0	\N	\N	f	0	\N
16295	88	309	\N	0	\N	\N	f	0	\N
16296	88	308	\N	0	\N	\N	f	0	\N
16297	88	307	\N	0	\N	\N	f	0	\N
16298	88	306	\N	0	\N	\N	f	0	\N
16299	88	305	\N	0	\N	\N	f	0	\N
16300	88	304	\N	0	\N	\N	f	0	\N
16301	88	303	\N	0	\N	\N	f	0	\N
16302	88	302	\N	0	\N	\N	f	0	\N
16303	88	301	\N	0	\N	\N	f	0	\N
16304	88	300	\N	0	\N	\N	f	0	\N
16305	88	299	\N	0	\N	\N	f	0	\N
16306	88	298	\N	0	\N	\N	f	0	\N
16307	88	297	\N	0	\N	\N	f	0	\N
16308	88	296	\N	0	\N	\N	f	0	\N
16309	88	295	\N	0	\N	\N	f	0	\N
16310	88	294	\N	0	\N	\N	f	0	\N
16311	88	293	\N	0	\N	\N	f	0	\N
16312	88	292	\N	0	\N	\N	f	0	\N
16313	88	291	\N	0	\N	\N	f	0	\N
16314	88	109	\N	0	\N	\N	f	0	\N
16315	88	108	\N	0	\N	\N	f	0	\N
16316	88	107	\N	0	\N	\N	f	0	\N
16317	88	106	\N	0	\N	\N	f	0	\N
16318	88	105	\N	0	\N	\N	f	0	\N
16319	88	104	\N	0	\N	\N	f	0	\N
16320	88	103	\N	0	\N	\N	f	0	\N
16321	88	102	\N	0	\N	\N	f	0	\N
16322	88	101	\N	0	\N	\N	f	0	\N
16323	88	100	\N	0	\N	\N	f	0	\N
16324	88	99	\N	0	\N	\N	f	0	\N
16325	88	98	\N	0	\N	\N	f	0	\N
16326	88	97	\N	0	\N	\N	f	0	\N
16327	88	96	\N	0	\N	\N	f	0	\N
16328	88	95	\N	0	\N	\N	f	0	\N
16329	88	94	\N	0	\N	\N	f	0	\N
16330	88	93	\N	0	\N	\N	f	0	\N
16331	88	92	\N	0	\N	\N	f	0	\N
16332	88	91	\N	0	\N	\N	f	0	\N
16333	88	90	\N	0	\N	\N	f	0	\N
16334	88	89	\N	0	\N	\N	f	0	\N
16335	88	88	\N	0	\N	\N	f	0	\N
16336	88	87	\N	0	\N	\N	f	0	\N
16337	88	86	\N	0	\N	\N	f	0	\N
16338	88	85	\N	0	\N	\N	f	0	\N
16339	88	84	\N	0	\N	\N	f	0	\N
16340	88	83	\N	0	\N	\N	f	0	\N
16341	88	82	\N	0	\N	\N	f	0	\N
16342	88	81	\N	0	\N	\N	f	0	\N
16343	88	80	\N	0	\N	\N	f	0	\N
16344	88	79	\N	0	\N	\N	f	0	\N
16345	88	78	\N	0	\N	\N	f	0	\N
16346	88	77	\N	0	\N	\N	f	0	\N
16347	88	76	\N	0	\N	\N	f	0	\N
16348	88	75	\N	0	\N	\N	f	0	\N
16349	88	180	\N	0	\N	\N	f	0	\N
16350	88	179	\N	0	\N	\N	f	0	\N
16351	88	178	\N	0	\N	\N	f	0	\N
16352	88	177	\N	0	\N	\N	f	0	\N
16353	88	176	\N	0	\N	\N	f	0	\N
16354	88	175	\N	0	\N	\N	f	0	\N
16355	88	174	\N	0	\N	\N	f	0	\N
16356	88	173	\N	0	\N	\N	f	0	\N
16357	88	172	\N	0	\N	\N	f	0	\N
16358	88	171	\N	0	\N	\N	f	0	\N
16359	88	170	\N	0	\N	\N	f	0	\N
16360	88	169	\N	0	\N	\N	f	0	\N
16361	88	168	\N	0	\N	\N	f	0	\N
16362	88	167	\N	0	\N	\N	f	0	\N
16363	88	166	\N	0	\N	\N	f	0	\N
16364	88	165	\N	0	\N	\N	f	0	\N
16365	88	164	\N	0	\N	\N	f	0	\N
16366	88	163	\N	0	\N	\N	f	0	\N
16367	88	162	\N	0	\N	\N	f	0	\N
16368	88	161	\N	0	\N	\N	f	0	\N
16369	88	160	\N	0	\N	\N	f	0	\N
16370	88	159	\N	0	\N	\N	f	0	\N
16371	88	158	\N	0	\N	\N	f	0	\N
16372	88	157	\N	0	\N	\N	f	0	\N
16373	88	156	\N	0	\N	\N	f	0	\N
16374	88	155	\N	0	\N	\N	f	0	\N
16375	88	154	\N	0	\N	\N	f	0	\N
16376	88	153	\N	0	\N	\N	f	0	\N
16377	88	152	\N	0	\N	\N	f	0	\N
16378	88	151	\N	0	\N	\N	f	0	\N
16379	88	150	\N	0	\N	\N	f	0	\N
16380	88	149	\N	0	\N	\N	f	0	\N
16381	88	148	\N	0	\N	\N	f	0	\N
16382	88	147	\N	0	\N	\N	f	0	\N
16383	88	146	\N	0	\N	\N	f	0	\N
16384	88	360	\N	0	\N	\N	f	0	\N
16385	88	359	\N	0	\N	\N	f	0	\N
16386	88	358	\N	0	\N	\N	f	0	\N
16387	88	357	\N	0	\N	\N	f	0	\N
16388	88	356	\N	0	\N	\N	f	0	\N
16389	88	355	\N	0	\N	\N	f	0	\N
16390	88	354	\N	0	\N	\N	f	0	\N
16391	88	353	\N	0	\N	\N	f	0	\N
16392	88	352	\N	0	\N	\N	f	0	\N
16393	88	351	\N	0	\N	\N	f	0	\N
16394	88	350	\N	0	\N	\N	f	0	\N
16395	88	349	\N	0	\N	\N	f	0	\N
16396	88	348	\N	0	\N	\N	f	0	\N
16397	88	347	\N	0	\N	\N	f	0	\N
16398	88	346	\N	0	\N	\N	f	0	\N
16399	88	345	\N	0	\N	\N	f	0	\N
16400	88	344	\N	0	\N	\N	f	0	\N
16401	88	343	\N	0	\N	\N	f	0	\N
16402	88	342	\N	0	\N	\N	f	0	\N
16403	88	341	\N	0	\N	\N	f	0	\N
16404	88	340	\N	0	\N	\N	f	0	\N
16405	88	339	\N	0	\N	\N	f	0	\N
16406	88	338	\N	0	\N	\N	f	0	\N
16407	88	337	\N	0	\N	\N	f	0	\N
16408	88	336	\N	0	\N	\N	f	0	\N
16409	88	335	\N	0	\N	\N	f	0	\N
16410	88	334	\N	0	\N	\N	f	0	\N
16411	88	333	\N	0	\N	\N	f	0	\N
16412	88	332	\N	0	\N	\N	f	0	\N
16413	88	331	\N	0	\N	\N	f	0	\N
16414	88	330	\N	0	\N	\N	f	0	\N
16415	88	329	\N	0	\N	\N	f	0	\N
16416	88	328	\N	0	\N	\N	f	0	\N
16417	88	327	\N	0	\N	\N	f	0	\N
16418	88	326	\N	0	\N	\N	f	0	\N
16419	88	325	\N	0	\N	\N	f	0	\N
16420	88	324	\N	0	\N	\N	f	0	\N
16421	88	254	\N	0	\N	\N	f	0	\N
16422	88	253	\N	0	\N	\N	f	0	\N
16423	88	252	\N	0	\N	\N	f	0	\N
16424	88	251	\N	0	\N	\N	f	0	\N
16425	88	250	\N	0	\N	\N	f	0	\N
16426	88	249	\N	0	\N	\N	f	0	\N
16427	88	248	\N	0	\N	\N	f	0	\N
16428	88	247	\N	0	\N	\N	f	0	\N
16429	88	246	\N	0	\N	\N	f	0	\N
16430	88	245	\N	0	\N	\N	f	0	\N
16431	88	244	\N	0	\N	\N	f	0	\N
16432	88	243	\N	0	\N	\N	f	0	\N
16433	88	242	\N	0	\N	\N	f	0	\N
16434	88	241	\N	0	\N	\N	f	0	\N
16435	88	240	\N	0	\N	\N	f	0	\N
16436	88	239	\N	0	\N	\N	f	0	\N
16437	88	238	\N	0	\N	\N	f	0	\N
16438	88	237	\N	0	\N	\N	f	0	\N
16439	88	236	\N	0	\N	\N	f	0	\N
16440	88	235	\N	0	\N	\N	f	0	\N
16441	88	234	\N	0	\N	\N	f	0	\N
16442	88	233	\N	0	\N	\N	f	0	\N
16443	88	232	\N	0	\N	\N	f	0	\N
16444	88	231	\N	0	\N	\N	f	0	\N
16445	88	230	\N	0	\N	\N	f	0	\N
16446	88	229	\N	0	\N	\N	f	0	\N
16447	88	228	\N	0	\N	\N	f	0	\N
16448	88	227	\N	0	\N	\N	f	0	\N
16449	88	226	\N	0	\N	\N	f	0	\N
16450	88	225	\N	0	\N	\N	f	0	\N
16451	88	224	\N	0	\N	\N	f	0	\N
16452	88	223	\N	0	\N	\N	f	0	\N
16453	88	222	\N	0	\N	\N	f	0	\N
16454	88	221	\N	0	\N	\N	f	0	\N
16455	88	220	\N	0	\N	\N	f	0	\N
16456	88	219	\N	0	\N	\N	f	0	\N
16457	88	74	\N	0	\N	\N	f	0	\N
16458	88	73	\N	0	\N	\N	f	0	\N
16459	88	72	\N	0	\N	\N	f	0	\N
16460	88	71	\N	0	\N	\N	f	0	\N
16461	88	70	\N	0	\N	\N	f	0	\N
16462	88	69	\N	0	\N	\N	f	0	\N
16463	88	68	\N	0	\N	\N	f	0	\N
16464	88	67	\N	0	\N	\N	f	0	\N
16465	88	66	\N	0	\N	\N	f	0	\N
16466	88	65	\N	0	\N	\N	f	0	\N
16467	88	64	\N	0	\N	\N	f	0	\N
16468	88	63	\N	0	\N	\N	f	0	\N
16469	88	62	\N	0	\N	\N	f	0	\N
16470	88	61	\N	0	\N	\N	f	0	\N
16471	88	60	\N	0	\N	\N	f	0	\N
16472	88	59	\N	0	\N	\N	f	0	\N
16473	88	58	\N	0	\N	\N	f	0	\N
16474	88	57	\N	0	\N	\N	f	0	\N
16475	88	56	\N	0	\N	\N	f	0	\N
16476	88	55	\N	0	\N	\N	f	0	\N
16477	88	54	\N	0	\N	\N	f	0	\N
16478	88	53	\N	0	\N	\N	f	0	\N
16479	88	52	\N	0	\N	\N	f	0	\N
16480	88	51	\N	0	\N	\N	f	0	\N
16481	88	50	\N	0	\N	\N	f	0	\N
16482	88	49	\N	0	\N	\N	f	0	\N
16483	88	48	\N	0	\N	\N	f	0	\N
16484	88	47	\N	0	\N	\N	f	0	\N
16485	88	46	\N	0	\N	\N	f	0	\N
16486	88	45	\N	0	\N	\N	f	0	\N
16487	88	44	\N	0	\N	\N	f	0	\N
16488	88	43	\N	0	\N	\N	f	0	\N
16489	88	42	\N	0	\N	\N	f	0	\N
16490	88	41	\N	0	\N	\N	f	0	\N
16491	88	40	\N	0	\N	\N	f	0	\N
16492	88	401	\N	0	\N	\N	f	0	\N
16493	88	400	\N	0	\N	\N	f	0	\N
16494	88	399	\N	0	\N	\N	f	0	\N
16495	88	398	\N	0	\N	\N	f	0	\N
16496	88	397	\N	0	\N	\N	f	0	\N
16497	88	396	\N	0	\N	\N	f	0	\N
16498	88	395	\N	0	\N	\N	f	0	\N
16499	88	394	\N	0	\N	\N	f	0	\N
16500	88	393	\N	0	\N	\N	f	0	\N
16501	88	392	\N	0	\N	\N	f	0	\N
16502	88	391	\N	0	\N	\N	f	0	\N
16503	88	390	\N	0	\N	\N	f	0	\N
16504	88	389	\N	0	\N	\N	f	0	\N
16505	88	388	\N	0	\N	\N	f	0	\N
16506	88	387	\N	0	\N	\N	f	0	\N
16507	88	386	\N	0	\N	\N	f	0	\N
16508	88	385	\N	0	\N	\N	f	0	\N
16509	88	384	\N	0	\N	\N	f	0	\N
16510	88	383	\N	0	\N	\N	f	0	\N
16511	88	382	\N	0	\N	\N	f	0	\N
16512	88	381	\N	0	\N	\N	f	0	\N
16513	88	380	\N	0	\N	\N	f	0	\N
16514	88	379	\N	0	\N	\N	f	0	\N
16515	88	378	\N	0	\N	\N	f	0	\N
16516	88	377	\N	0	\N	\N	f	0	\N
16517	88	376	\N	0	\N	\N	f	0	\N
16518	88	375	\N	0	\N	\N	f	0	\N
16519	88	374	\N	0	\N	\N	f	0	\N
16520	88	373	\N	0	\N	\N	f	0	\N
16521	88	372	\N	0	\N	\N	f	0	\N
16522	88	371	\N	0	\N	\N	f	0	\N
16523	88	370	\N	0	\N	\N	f	0	\N
16524	88	369	\N	0	\N	\N	f	0	\N
16525	88	368	\N	0	\N	\N	f	0	\N
16526	88	367	\N	0	\N	\N	f	0	\N
16527	88	366	\N	0	\N	\N	f	0	\N
16528	88	365	\N	0	\N	\N	f	0	\N
16529	88	364	\N	0	\N	\N	f	0	\N
16530	88	363	\N	0	\N	\N	f	0	\N
16531	88	362	\N	0	\N	\N	f	0	\N
16532	88	361	\N	0	\N	\N	f	0	\N
16533	88	432	\N	0	\N	\N	f	0	\N
16534	88	431	\N	0	\N	\N	f	0	\N
16535	88	430	\N	0	\N	\N	f	0	\N
16536	88	429	\N	0	\N	\N	f	0	\N
16537	88	428	\N	0	\N	\N	f	0	\N
16538	88	427	\N	0	\N	\N	f	0	\N
16539	88	426	\N	0	\N	\N	f	0	\N
16540	88	425	\N	0	\N	\N	f	0	\N
16541	88	424	\N	0	\N	\N	f	0	\N
16542	88	423	\N	0	\N	\N	f	0	\N
16543	88	422	\N	0	\N	\N	f	0	\N
16544	88	421	\N	0	\N	\N	f	0	\N
16545	88	420	\N	0	\N	\N	f	0	\N
16546	88	419	\N	0	\N	\N	f	0	\N
16547	88	418	\N	0	\N	\N	f	0	\N
16548	88	417	\N	0	\N	\N	f	0	\N
16549	88	416	\N	0	\N	\N	f	0	\N
16550	88	415	\N	0	\N	\N	f	0	\N
16551	88	414	\N	0	\N	\N	f	0	\N
16552	88	413	\N	0	\N	\N	f	0	\N
16553	88	412	\N	0	\N	\N	f	0	\N
16554	88	411	\N	0	\N	\N	f	0	\N
16555	88	410	\N	0	\N	\N	f	0	\N
16556	88	409	\N	0	\N	\N	f	0	\N
16557	88	408	\N	0	\N	\N	f	0	\N
16558	88	407	\N	0	\N	\N	f	0	\N
16559	88	406	\N	0	\N	\N	f	0	\N
16560	88	405	\N	0	\N	\N	f	0	\N
16561	88	404	\N	0	\N	\N	f	0	\N
16562	88	403	\N	0	\N	\N	f	0	\N
16563	88	402	\N	0	\N	\N	f	0	\N
16564	88	290	\N	0	\N	\N	f	0	\N
16565	88	289	\N	0	\N	\N	f	0	\N
16566	88	288	\N	0	\N	\N	f	0	\N
16567	88	287	\N	0	\N	\N	f	0	\N
16568	88	286	\N	0	\N	\N	f	0	\N
16569	88	285	\N	0	\N	\N	f	0	\N
16570	88	284	\N	0	\N	\N	f	0	\N
16571	88	283	\N	0	\N	\N	f	0	\N
16572	88	282	\N	0	\N	\N	f	0	\N
16573	88	281	\N	0	\N	\N	f	0	\N
16574	88	280	\N	0	\N	\N	f	0	\N
16575	88	279	\N	0	\N	\N	f	0	\N
16576	88	278	\N	0	\N	\N	f	0	\N
16577	88	277	\N	0	\N	\N	f	0	\N
16578	88	276	\N	0	\N	\N	f	0	\N
16579	88	275	\N	0	\N	\N	f	0	\N
16580	88	274	\N	0	\N	\N	f	0	\N
16581	88	273	\N	0	\N	\N	f	0	\N
16582	88	272	\N	0	\N	\N	f	0	\N
16583	88	271	\N	0	\N	\N	f	0	\N
16584	88	270	\N	0	\N	\N	f	0	\N
16585	88	269	\N	0	\N	\N	f	0	\N
16586	88	268	\N	0	\N	\N	f	0	\N
16587	88	267	\N	0	\N	\N	f	0	\N
16588	88	266	\N	0	\N	\N	f	0	\N
16589	88	265	\N	0	\N	\N	f	0	\N
16590	88	264	\N	0	\N	\N	f	0	\N
16591	88	263	\N	0	\N	\N	f	0	\N
16592	88	262	\N	0	\N	\N	f	0	\N
16593	88	261	\N	0	\N	\N	f	0	\N
16594	88	260	\N	0	\N	\N	f	0	\N
16595	88	259	\N	0	\N	\N	f	0	\N
16596	88	258	\N	0	\N	\N	f	0	\N
16597	88	257	\N	0	\N	\N	f	0	\N
16598	88	256	\N	0	\N	\N	f	0	\N
16599	88	255	\N	0	\N	\N	f	0	\N
16600	88	39	\N	0	\N	\N	f	0	\N
16601	88	38	\N	0	\N	\N	f	0	\N
16602	88	37	\N	0	\N	\N	f	0	\N
16603	88	36	\N	0	\N	\N	f	0	\N
16604	88	35	\N	0	\N	\N	f	0	\N
16605	88	34	\N	0	\N	\N	f	0	\N
16606	88	33	\N	0	\N	\N	f	0	\N
16607	88	32	\N	0	\N	\N	f	0	\N
16608	88	31	\N	0	\N	\N	f	0	\N
16609	88	30	\N	0	\N	\N	f	0	\N
16610	88	29	\N	0	\N	\N	f	0	\N
16611	88	28	\N	0	\N	\N	f	0	\N
16612	88	27	\N	0	\N	\N	f	0	\N
16613	88	26	\N	0	\N	\N	f	0	\N
16614	88	25	\N	0	\N	\N	f	0	\N
16615	88	24	\N	0	\N	\N	f	0	\N
16616	88	23	\N	0	\N	\N	f	0	\N
16617	88	22	\N	0	\N	\N	f	0	\N
16618	88	21	\N	0	\N	\N	f	0	\N
16619	88	20	\N	0	\N	\N	f	0	\N
16620	88	19	\N	0	\N	\N	f	0	\N
16621	88	18	\N	0	\N	\N	f	0	\N
16622	88	17	\N	0	\N	\N	f	0	\N
16623	88	16	\N	0	\N	\N	f	0	\N
16624	88	15	\N	0	\N	\N	f	0	\N
16625	88	14	\N	0	\N	\N	f	0	\N
16626	88	13	\N	0	\N	\N	f	0	\N
16627	88	12	\N	0	\N	\N	f	0	\N
16628	88	11	\N	0	\N	\N	f	0	\N
16629	88	10	\N	0	\N	\N	f	0	\N
16630	88	9	\N	0	\N	\N	f	0	\N
16631	88	8	\N	0	\N	\N	f	0	\N
16632	88	7	\N	0	\N	\N	f	0	\N
16633	88	6	\N	0	\N	\N	f	0	\N
16634	88	5	\N	0	\N	\N	f	0	\N
16635	88	4	\N	0	\N	\N	f	0	\N
16636	88	3	\N	0	\N	\N	f	0	\N
16637	88	2	\N	0	\N	\N	f	0	\N
16638	88	1	\N	0	\N	\N	f	0	\N
16639	88	145	\N	0	\N	\N	f	0	\N
16640	88	144	\N	0	\N	\N	f	0	\N
16641	88	143	\N	0	\N	\N	f	0	\N
16642	88	142	\N	0	\N	\N	f	0	\N
16643	88	141	\N	0	\N	\N	f	0	\N
16644	88	140	\N	0	\N	\N	f	0	\N
16645	88	139	\N	0	\N	\N	f	0	\N
16646	88	138	\N	0	\N	\N	f	0	\N
16647	88	137	\N	0	\N	\N	f	0	\N
16648	88	136	\N	0	\N	\N	f	0	\N
16649	88	135	\N	0	\N	\N	f	0	\N
16650	88	134	\N	0	\N	\N	f	0	\N
16651	88	133	\N	0	\N	\N	f	0	\N
16652	88	132	\N	0	\N	\N	f	0	\N
16653	88	131	\N	0	\N	\N	f	0	\N
16654	88	130	\N	0	\N	\N	f	0	\N
16655	88	129	\N	0	\N	\N	f	0	\N
16656	88	128	\N	0	\N	\N	f	0	\N
16657	88	127	\N	0	\N	\N	f	0	\N
16658	88	126	\N	0	\N	\N	f	0	\N
16659	88	125	\N	0	\N	\N	f	0	\N
16660	88	124	\N	0	\N	\N	f	0	\N
16661	88	123	\N	0	\N	\N	f	0	\N
16662	88	122	\N	0	\N	\N	f	0	\N
16663	88	121	\N	0	\N	\N	f	0	\N
16664	88	120	\N	0	\N	\N	f	0	\N
16665	88	119	\N	0	\N	\N	f	0	\N
16666	88	118	\N	0	\N	\N	f	0	\N
16667	88	117	\N	0	\N	\N	f	0	\N
16668	88	116	\N	0	\N	\N	f	0	\N
16669	88	115	\N	0	\N	\N	f	0	\N
16670	88	114	\N	0	\N	\N	f	0	\N
16671	88	113	\N	0	\N	\N	f	0	\N
16672	88	112	\N	0	\N	\N	f	0	\N
16673	88	111	\N	0	\N	\N	f	0	\N
16674	88	110	\N	0	\N	\N	f	0	\N
16903	89	360	\N	0	\N	\N	f	0	\N
16904	89	359	\N	0	\N	\N	f	0	\N
16905	89	358	\N	0	\N	\N	f	0	\N
16906	89	357	\N	0	\N	\N	f	0	\N
16907	89	356	\N	0	\N	\N	f	0	\N
16908	89	355	\N	0	\N	\N	f	0	\N
16909	89	354	\N	0	\N	\N	f	0	\N
16910	89	353	\N	0	\N	\N	f	0	\N
16911	89	352	\N	0	\N	\N	f	0	\N
16912	89	351	\N	0	\N	\N	f	0	\N
16913	89	350	\N	0	\N	\N	f	0	\N
16914	89	349	\N	0	\N	\N	f	0	\N
16915	89	348	\N	0	\N	\N	f	0	\N
16916	89	347	\N	0	\N	\N	f	0	\N
16917	89	346	\N	0	\N	\N	f	0	\N
16918	89	345	\N	0	\N	\N	f	0	\N
16919	89	344	\N	0	\N	\N	f	0	\N
16920	89	343	\N	0	\N	\N	f	0	\N
16921	89	342	\N	0	\N	\N	f	0	\N
16922	89	341	\N	0	\N	\N	f	0	\N
16923	89	340	\N	0	\N	\N	f	0	\N
16924	89	339	\N	0	\N	\N	f	0	\N
16925	89	338	\N	0	\N	\N	f	0	\N
16926	89	337	\N	0	\N	\N	f	0	\N
16927	89	336	\N	0	\N	\N	f	0	\N
16928	89	335	\N	0	\N	\N	f	0	\N
16929	89	334	\N	0	\N	\N	f	0	\N
16930	89	333	\N	0	\N	\N	f	0	\N
16931	89	332	\N	0	\N	\N	f	0	\N
16932	89	331	\N	0	\N	\N	f	0	\N
16933	89	330	\N	0	\N	\N	f	0	\N
16934	89	329	\N	0	\N	\N	f	0	\N
16935	89	328	\N	0	\N	\N	f	0	\N
16936	89	327	\N	0	\N	\N	f	0	\N
16937	89	326	\N	0	\N	\N	f	0	\N
16938	89	325	\N	0	\N	\N	f	0	\N
16939	89	324	\N	0	\N	\N	f	0	\N
16940	89	254	\N	0	\N	\N	f	0	\N
16941	89	253	\N	0	\N	\N	f	0	\N
16942	89	252	\N	0	\N	\N	f	0	\N
16943	89	251	\N	0	\N	\N	f	0	\N
16944	89	250	\N	0	\N	\N	f	0	\N
16945	89	249	\N	0	\N	\N	f	0	\N
16946	89	248	\N	0	\N	\N	f	0	\N
16947	89	247	\N	0	\N	\N	f	0	\N
16948	89	246	\N	0	\N	\N	f	0	\N
16949	89	245	\N	0	\N	\N	f	0	\N
16950	89	244	\N	0	\N	\N	f	0	\N
16951	89	243	\N	0	\N	\N	f	0	\N
16952	89	242	\N	0	\N	\N	f	0	\N
16953	89	241	\N	0	\N	\N	f	0	\N
16954	89	240	\N	0	\N	\N	f	0	\N
16955	89	239	\N	0	\N	\N	f	0	\N
16956	89	238	\N	0	\N	\N	f	0	\N
16957	89	237	\N	0	\N	\N	f	0	\N
16958	89	236	\N	0	\N	\N	f	0	\N
16959	89	235	\N	0	\N	\N	f	0	\N
16960	89	234	\N	0	\N	\N	f	0	\N
16961	89	233	\N	0	\N	\N	f	0	\N
16962	89	232	\N	0	\N	\N	f	0	\N
16963	89	231	\N	0	\N	\N	f	0	\N
16964	89	230	\N	0	\N	\N	f	0	\N
16965	89	229	\N	0	\N	\N	f	0	\N
16966	89	228	\N	0	\N	\N	f	0	\N
16967	89	227	\N	0	\N	\N	f	0	\N
16968	89	226	\N	0	\N	\N	f	0	\N
16969	89	225	\N	0	\N	\N	f	0	\N
16970	89	224	\N	0	\N	\N	f	0	\N
16971	89	223	\N	0	\N	\N	f	0	\N
16972	89	222	\N	0	\N	\N	f	0	\N
16973	89	221	\N	0	\N	\N	f	0	\N
16974	89	220	\N	0	\N	\N	f	0	\N
16975	89	219	\N	0	\N	\N	f	0	\N
16976	89	145	\N	0	\N	\N	f	0	\N
16977	89	144	\N	0	\N	\N	f	0	\N
16978	89	143	\N	0	\N	\N	f	0	\N
16979	89	142	\N	0	\N	\N	f	0	\N
16980	89	141	\N	0	\N	\N	f	0	\N
16981	89	140	\N	0	\N	\N	f	0	\N
16982	89	139	\N	0	\N	\N	f	0	\N
16983	89	138	\N	0	\N	\N	f	0	\N
16984	89	137	\N	0	\N	\N	f	0	\N
16985	89	136	\N	0	\N	\N	f	0	\N
16986	89	135	\N	0	\N	\N	f	0	\N
16987	89	134	\N	0	\N	\N	f	0	\N
16988	89	133	\N	0	\N	\N	f	0	\N
16989	89	132	\N	0	\N	\N	f	0	\N
16990	89	131	\N	0	\N	\N	f	0	\N
16991	89	130	\N	0	\N	\N	f	0	\N
16992	89	129	\N	0	\N	\N	f	0	\N
16993	89	128	\N	0	\N	\N	f	0	\N
16994	89	127	\N	0	\N	\N	f	0	\N
16995	89	126	\N	0	\N	\N	f	0	\N
16996	89	125	\N	0	\N	\N	f	0	\N
16997	89	124	\N	0	\N	\N	f	0	\N
16998	89	123	\N	0	\N	\N	f	0	\N
16999	89	122	\N	0	\N	\N	f	0	\N
17000	89	121	\N	0	\N	\N	f	0	\N
17001	89	120	\N	0	\N	\N	f	0	\N
17002	89	119	\N	0	\N	\N	f	0	\N
17003	89	118	\N	0	\N	\N	f	0	\N
17004	89	117	\N	0	\N	\N	f	0	\N
17005	89	116	\N	0	\N	\N	f	0	\N
17006	89	115	\N	0	\N	\N	f	0	\N
17007	89	114	\N	0	\N	\N	f	0	\N
17008	89	113	\N	0	\N	\N	f	0	\N
17009	89	112	\N	0	\N	\N	f	0	\N
17010	89	111	\N	0	\N	\N	f	0	\N
17011	89	110	\N	0	\N	\N	f	0	\N
17012	89	180	\N	0	\N	\N	f	0	\N
17013	89	179	\N	0	\N	\N	f	0	\N
17014	89	178	\N	0	\N	\N	f	0	\N
17015	89	177	\N	0	\N	\N	f	0	\N
17016	89	176	\N	0	\N	\N	f	0	\N
17017	89	175	\N	0	\N	\N	f	0	\N
17018	89	174	\N	0	\N	\N	f	0	\N
17019	89	173	\N	0	\N	\N	f	0	\N
17020	89	172	\N	0	\N	\N	f	0	\N
17021	89	171	\N	0	\N	\N	f	0	\N
17022	89	170	\N	0	\N	\N	f	0	\N
17023	89	169	\N	0	\N	\N	f	0	\N
17024	89	168	\N	0	\N	\N	f	0	\N
17025	89	167	\N	0	\N	\N	f	0	\N
17026	89	166	\N	0	\N	\N	f	0	\N
17027	89	165	\N	0	\N	\N	f	0	\N
17028	89	164	\N	0	\N	\N	f	0	\N
17029	89	163	\N	0	\N	\N	f	0	\N
17030	89	162	\N	0	\N	\N	f	0	\N
17031	89	161	\N	0	\N	\N	f	0	\N
17032	89	160	\N	0	\N	\N	f	0	\N
17033	89	159	\N	0	\N	\N	f	0	\N
17034	89	158	\N	0	\N	\N	f	0	\N
17035	89	157	\N	0	\N	\N	f	0	\N
17036	89	156	\N	0	\N	\N	f	0	\N
17037	89	155	\N	0	\N	\N	f	0	\N
17038	89	154	\N	0	\N	\N	f	0	\N
17039	89	153	\N	0	\N	\N	f	0	\N
17040	89	152	\N	0	\N	\N	f	0	\N
17041	89	151	\N	0	\N	\N	f	0	\N
17042	89	150	\N	0	\N	\N	f	0	\N
17043	89	149	\N	0	\N	\N	f	0	\N
17044	89	148	\N	0	\N	\N	f	0	\N
17045	89	147	\N	0	\N	\N	f	0	\N
17046	89	146	\N	0	\N	\N	f	0	\N
17047	89	323	\N	0	\N	\N	f	0	\N
17048	89	322	\N	0	\N	\N	f	0	\N
17049	89	321	\N	0	\N	\N	f	0	\N
17050	89	320	\N	0	\N	\N	f	0	\N
17051	89	319	\N	0	\N	\N	f	0	\N
17052	89	318	\N	0	\N	\N	f	0	\N
17053	89	317	\N	0	\N	\N	f	0	\N
17054	89	316	\N	0	\N	\N	f	0	\N
17055	89	315	\N	0	\N	\N	f	0	\N
17056	89	314	\N	0	\N	\N	f	0	\N
17057	89	313	\N	0	\N	\N	f	0	\N
17058	89	312	\N	0	\N	\N	f	0	\N
17059	89	311	\N	0	\N	\N	f	0	\N
17060	89	310	\N	0	\N	\N	f	0	\N
17061	89	309	\N	0	\N	\N	f	0	\N
17062	89	308	\N	0	\N	\N	f	0	\N
17063	89	307	\N	0	\N	\N	f	0	\N
17064	89	306	\N	0	\N	\N	f	0	\N
17065	89	305	\N	0	\N	\N	f	0	\N
17066	89	304	\N	0	\N	\N	f	0	\N
17067	89	303	\N	0	\N	\N	f	0	\N
17068	89	302	\N	0	\N	\N	f	0	\N
17069	89	301	\N	0	\N	\N	f	0	\N
17070	89	300	\N	0	\N	\N	f	0	\N
17071	89	299	\N	0	\N	\N	f	0	\N
17072	89	298	\N	0	\N	\N	f	0	\N
17073	89	297	\N	0	\N	\N	f	0	\N
17074	89	296	\N	0	\N	\N	f	0	\N
17075	89	295	\N	0	\N	\N	f	0	\N
17076	89	294	\N	0	\N	\N	f	0	\N
17077	89	293	\N	0	\N	\N	f	0	\N
17078	89	292	\N	0	\N	\N	f	0	\N
17079	89	291	\N	0	\N	\N	f	0	\N
17080	89	39	\N	0	\N	\N	f	0	\N
17081	89	38	\N	0	\N	\N	f	0	\N
17082	89	37	\N	0	\N	\N	f	0	\N
17083	89	36	\N	0	\N	\N	f	0	\N
17084	89	35	\N	0	\N	\N	f	0	\N
17085	89	34	\N	0	\N	\N	f	0	\N
17086	89	33	\N	0	\N	\N	f	0	\N
17087	89	32	\N	0	\N	\N	f	0	\N
17088	89	31	\N	0	\N	\N	f	0	\N
17089	89	30	\N	0	\N	\N	f	0	\N
17090	89	29	\N	0	\N	\N	f	0	\N
17091	89	28	\N	0	\N	\N	f	0	\N
17092	89	27	\N	0	\N	\N	f	0	\N
17093	89	26	\N	0	\N	\N	f	0	\N
17094	89	25	\N	0	\N	\N	f	0	\N
17095	89	24	\N	0	\N	\N	f	0	\N
17096	89	23	\N	0	\N	\N	f	0	\N
17097	89	22	\N	0	\N	\N	f	0	\N
17098	89	21	\N	0	\N	\N	f	0	\N
17099	89	20	\N	0	\N	\N	f	0	\N
17100	89	19	\N	0	\N	\N	f	0	\N
17101	89	18	\N	0	\N	\N	f	0	\N
17102	89	17	\N	0	\N	\N	f	0	\N
17103	89	16	\N	0	\N	\N	f	0	\N
17104	89	15	\N	0	\N	\N	f	0	\N
17105	89	14	\N	0	\N	\N	f	0	\N
17106	89	13	\N	0	\N	\N	f	0	\N
17107	89	12	\N	0	\N	\N	f	0	\N
17108	89	11	\N	0	\N	\N	f	0	\N
17109	89	10	\N	0	\N	\N	f	0	\N
17110	89	9	\N	0	\N	\N	f	0	\N
17111	89	8	\N	0	\N	\N	f	0	\N
17112	89	7	\N	0	\N	\N	f	0	\N
17113	89	6	\N	0	\N	\N	f	0	\N
17114	89	5	\N	0	\N	\N	f	0	\N
17115	89	4	\N	0	\N	\N	f	0	\N
17116	89	3	\N	0	\N	\N	f	0	\N
17117	89	2	\N	0	\N	\N	f	0	\N
17118	89	1	\N	0	\N	\N	f	0	\N
17119	89	290	\N	0	\N	\N	f	0	\N
17120	89	289	\N	0	\N	\N	f	0	\N
17121	89	288	\N	0	\N	\N	f	0	\N
17122	89	287	\N	0	\N	\N	f	0	\N
17123	89	286	\N	0	\N	\N	f	0	\N
17124	89	285	\N	0	\N	\N	f	0	\N
17125	89	284	\N	0	\N	\N	f	0	\N
17126	89	283	\N	0	\N	\N	f	0	\N
17127	89	282	\N	0	\N	\N	f	0	\N
17128	89	281	\N	0	\N	\N	f	0	\N
17129	89	280	\N	0	\N	\N	f	0	\N
17130	89	279	\N	0	\N	\N	f	0	\N
17131	89	278	\N	0	\N	\N	f	0	\N
17132	89	277	\N	0	\N	\N	f	0	\N
17133	89	276	\N	0	\N	\N	f	0	\N
17134	89	275	\N	0	\N	\N	f	0	\N
17135	89	274	\N	0	\N	\N	f	0	\N
17136	89	273	\N	0	\N	\N	f	0	\N
17137	89	272	\N	0	\N	\N	f	0	\N
17138	89	271	\N	0	\N	\N	f	0	\N
17139	89	270	\N	0	\N	\N	f	0	\N
17140	89	269	\N	0	\N	\N	f	0	\N
17141	89	268	\N	0	\N	\N	f	0	\N
17142	89	267	\N	0	\N	\N	f	0	\N
17143	89	266	\N	0	\N	\N	f	0	\N
17144	89	265	\N	0	\N	\N	f	0	\N
17145	89	264	\N	0	\N	\N	f	0	\N
17146	89	263	\N	0	\N	\N	f	0	\N
17147	89	262	\N	0	\N	\N	f	0	\N
17148	89	261	\N	0	\N	\N	f	0	\N
17149	89	260	\N	0	\N	\N	f	0	\N
17150	89	259	\N	0	\N	\N	f	0	\N
17151	89	258	\N	0	\N	\N	f	0	\N
17152	89	257	\N	0	\N	\N	f	0	\N
17153	89	256	\N	0	\N	\N	f	0	\N
17154	89	255	\N	0	\N	\N	f	0	\N
17155	89	401	\N	0	\N	\N	f	0	\N
17156	89	400	\N	0	\N	\N	f	0	\N
17157	89	399	\N	0	\N	\N	f	0	\N
17158	89	398	\N	0	\N	\N	f	0	\N
17159	89	397	\N	0	\N	\N	f	0	\N
17160	89	396	\N	0	\N	\N	f	0	\N
17161	89	395	\N	0	\N	\N	f	0	\N
17162	89	394	\N	0	\N	\N	f	0	\N
17163	89	393	\N	0	\N	\N	f	0	\N
17164	89	392	\N	0	\N	\N	f	0	\N
17165	89	391	\N	0	\N	\N	f	0	\N
17166	89	390	\N	0	\N	\N	f	0	\N
17167	89	389	\N	0	\N	\N	f	0	\N
17168	89	388	\N	0	\N	\N	f	0	\N
17169	89	387	\N	0	\N	\N	f	0	\N
17170	89	386	\N	0	\N	\N	f	0	\N
17171	89	385	\N	0	\N	\N	f	0	\N
17172	89	384	\N	0	\N	\N	f	0	\N
17173	89	383	\N	0	\N	\N	f	0	\N
17174	89	382	\N	0	\N	\N	f	0	\N
17175	89	381	\N	0	\N	\N	f	0	\N
17176	89	380	\N	0	\N	\N	f	0	\N
17177	89	379	\N	0	\N	\N	f	0	\N
17178	89	378	\N	0	\N	\N	f	0	\N
17179	89	377	\N	0	\N	\N	f	0	\N
17180	89	376	\N	0	\N	\N	f	0	\N
17181	89	375	\N	0	\N	\N	f	0	\N
17182	89	374	\N	0	\N	\N	f	0	\N
17183	89	373	\N	0	\N	\N	f	0	\N
17184	89	372	\N	0	\N	\N	f	0	\N
17185	89	371	\N	0	\N	\N	f	0	\N
17186	89	370	\N	0	\N	\N	f	0	\N
17187	89	369	\N	0	\N	\N	f	0	\N
17188	89	368	\N	0	\N	\N	f	0	\N
17189	89	367	\N	0	\N	\N	f	0	\N
17190	89	366	\N	0	\N	\N	f	0	\N
17191	89	365	\N	0	\N	\N	f	0	\N
17192	89	364	\N	0	\N	\N	f	0	\N
17193	89	363	\N	0	\N	\N	f	0	\N
17194	89	362	\N	0	\N	\N	f	0	\N
17195	89	361	\N	0	\N	\N	f	0	\N
17196	89	432	\N	0	\N	\N	f	0	\N
17197	89	431	\N	0	\N	\N	f	0	\N
17198	89	430	\N	0	\N	\N	f	0	\N
17199	89	429	\N	0	\N	\N	f	0	\N
17200	89	428	\N	0	\N	\N	f	0	\N
17201	89	427	\N	0	\N	\N	f	0	\N
17202	89	426	\N	0	\N	\N	f	0	\N
17203	89	425	\N	0	\N	\N	f	0	\N
17204	89	424	\N	0	\N	\N	f	0	\N
17205	89	423	\N	0	\N	\N	f	0	\N
17206	89	422	\N	0	\N	\N	f	0	\N
17207	89	421	\N	0	\N	\N	f	0	\N
17208	89	420	\N	0	\N	\N	f	0	\N
17209	89	419	\N	0	\N	\N	f	0	\N
17210	89	418	\N	0	\N	\N	f	0	\N
17211	89	417	\N	0	\N	\N	f	0	\N
17212	89	416	\N	0	\N	\N	f	0	\N
17213	89	415	\N	0	\N	\N	f	0	\N
17214	89	414	\N	0	\N	\N	f	0	\N
17215	89	413	\N	0	\N	\N	f	0	\N
17216	89	412	\N	0	\N	\N	f	0	\N
17217	89	411	\N	0	\N	\N	f	0	\N
17218	89	410	\N	0	\N	\N	f	0	\N
17219	89	409	\N	0	\N	\N	f	0	\N
17220	89	408	\N	0	\N	\N	f	0	\N
17221	89	407	\N	0	\N	\N	f	0	\N
17222	89	406	\N	0	\N	\N	f	0	\N
17223	89	405	\N	0	\N	\N	f	0	\N
17224	89	404	\N	0	\N	\N	f	0	\N
17225	89	403	\N	0	\N	\N	f	0	\N
17226	89	402	\N	0	\N	\N	f	0	\N
17227	89	218	\N	0	\N	\N	f	0	\N
17228	89	217	\N	0	\N	\N	f	0	\N
17229	89	216	\N	0	\N	\N	f	0	\N
17230	89	215	\N	0	\N	\N	f	0	\N
17231	89	214	\N	0	\N	\N	f	0	\N
17232	89	213	\N	0	\N	\N	f	0	\N
17233	89	212	\N	0	\N	\N	f	0	\N
17234	89	211	\N	0	\N	\N	f	0	\N
17235	89	210	\N	0	\N	\N	f	0	\N
17236	89	209	\N	0	\N	\N	f	0	\N
17237	89	208	\N	0	\N	\N	f	0	\N
17238	89	207	\N	0	\N	\N	f	0	\N
17239	89	206	\N	0	\N	\N	f	0	\N
17240	89	205	\N	0	\N	\N	f	0	\N
17241	89	204	\N	0	\N	\N	f	0	\N
17242	89	203	\N	0	\N	\N	f	0	\N
17243	89	202	\N	0	\N	\N	f	0	\N
17244	89	201	\N	0	\N	\N	f	0	\N
17245	89	200	\N	0	\N	\N	f	0	\N
17246	89	199	\N	0	\N	\N	f	0	\N
17247	89	198	\N	0	\N	\N	f	0	\N
17248	89	197	\N	0	\N	\N	f	0	\N
17249	89	196	\N	0	\N	\N	f	0	\N
17250	89	195	\N	0	\N	\N	f	0	\N
17251	89	194	\N	0	\N	\N	f	0	\N
17252	89	193	\N	0	\N	\N	f	0	\N
17253	89	192	\N	0	\N	\N	f	0	\N
17254	89	191	\N	0	\N	\N	f	0	\N
17255	89	190	\N	0	\N	\N	f	0	\N
17256	89	189	\N	0	\N	\N	f	0	\N
17257	89	188	\N	0	\N	\N	f	0	\N
17258	89	187	\N	0	\N	\N	f	0	\N
17259	89	186	\N	0	\N	\N	f	0	\N
17260	89	185	\N	0	\N	\N	f	0	\N
17261	89	184	\N	0	\N	\N	f	0	\N
17262	89	183	\N	0	\N	\N	f	0	\N
17263	89	182	\N	0	\N	\N	f	0	\N
17264	89	181	\N	0	\N	\N	f	0	\N
17265	89	74	\N	0	\N	\N	f	0	\N
17266	89	73	\N	0	\N	\N	f	0	\N
17267	89	72	\N	0	\N	\N	f	0	\N
17268	89	71	\N	0	\N	\N	f	0	\N
17269	89	70	\N	0	\N	\N	f	0	\N
17270	89	69	\N	0	\N	\N	f	0	\N
17271	89	68	\N	0	\N	\N	f	0	\N
17272	89	67	\N	0	\N	\N	f	0	\N
17273	89	66	\N	0	\N	\N	f	0	\N
17274	89	65	\N	0	\N	\N	f	0	\N
17275	89	64	\N	0	\N	\N	f	0	\N
17276	89	63	\N	0	\N	\N	f	0	\N
17277	89	62	\N	0	\N	\N	f	0	\N
17278	89	61	\N	0	\N	\N	f	0	\N
17279	89	60	\N	0	\N	\N	f	0	\N
17280	89	59	\N	0	\N	\N	f	0	\N
17281	89	58	\N	0	\N	\N	f	0	\N
17282	89	57	\N	0	\N	\N	f	0	\N
17283	89	56	\N	0	\N	\N	f	0	\N
17284	89	55	\N	0	\N	\N	f	0	\N
17285	89	54	\N	0	\N	\N	f	0	\N
17286	89	53	\N	0	\N	\N	f	0	\N
17287	89	52	\N	0	\N	\N	f	0	\N
17288	89	51	\N	0	\N	\N	f	0	\N
17289	89	50	\N	0	\N	\N	f	0	\N
17290	89	49	\N	0	\N	\N	f	0	\N
17291	89	48	\N	0	\N	\N	f	0	\N
17292	89	47	\N	0	\N	\N	f	0	\N
17293	89	46	\N	0	\N	\N	f	0	\N
17294	89	45	\N	0	\N	\N	f	0	\N
17295	89	44	\N	0	\N	\N	f	0	\N
17296	89	43	\N	0	\N	\N	f	0	\N
17297	89	42	\N	0	\N	\N	f	0	\N
17298	89	41	\N	0	\N	\N	f	0	\N
17299	89	40	\N	0	\N	\N	f	0	\N
17300	89	109	\N	0	\N	\N	f	0	\N
17301	89	108	\N	0	\N	\N	f	0	\N
17302	89	107	\N	0	\N	\N	f	0	\N
17303	89	106	\N	0	\N	\N	f	0	\N
17304	89	105	\N	0	\N	\N	f	0	\N
17305	89	104	\N	0	\N	\N	f	0	\N
17306	89	103	\N	0	\N	\N	f	0	\N
17307	89	102	\N	0	\N	\N	f	0	\N
17308	89	101	\N	0	\N	\N	f	0	\N
17309	89	100	\N	0	\N	\N	f	0	\N
17310	89	99	\N	0	\N	\N	f	0	\N
17311	89	98	\N	0	\N	\N	f	0	\N
17312	89	97	\N	0	\N	\N	f	0	\N
17313	89	96	\N	0	\N	\N	f	0	\N
17314	89	95	\N	0	\N	\N	f	0	\N
17315	89	94	\N	0	\N	\N	f	0	\N
17316	89	93	\N	0	\N	\N	f	0	\N
17317	89	92	\N	0	\N	\N	f	0	\N
17318	89	91	\N	0	\N	\N	f	0	\N
17319	89	90	\N	0	\N	\N	f	0	\N
17320	89	89	\N	0	\N	\N	f	0	\N
17321	89	88	\N	0	\N	\N	f	0	\N
17322	89	87	\N	0	\N	\N	f	0	\N
17323	89	86	\N	0	\N	\N	f	0	\N
17324	89	85	\N	0	\N	\N	f	0	\N
17325	89	84	\N	0	\N	\N	f	0	\N
17326	89	83	\N	0	\N	\N	f	0	\N
17327	89	82	\N	0	\N	\N	f	0	\N
17328	89	81	\N	0	\N	\N	f	0	\N
17329	89	80	\N	0	\N	\N	f	0	\N
17330	89	79	\N	0	\N	\N	f	0	\N
17331	89	78	\N	0	\N	\N	f	0	\N
17332	89	77	\N	0	\N	\N	f	0	\N
17333	89	76	\N	0	\N	\N	f	0	\N
17334	89	75	\N	0	\N	\N	f	0	\N
17335	90	254	\N	0	\N	\N	f	0	\N
17336	90	253	\N	0	\N	\N	f	0	\N
17337	90	252	\N	0	\N	\N	f	0	\N
17338	90	251	\N	0	\N	\N	f	0	\N
17339	90	250	\N	0	\N	\N	f	0	\N
17340	90	249	\N	0	\N	\N	f	0	\N
17341	90	248	\N	0	\N	\N	f	0	\N
17342	90	247	\N	0	\N	\N	f	0	\N
17343	90	246	\N	0	\N	\N	f	0	\N
17344	90	245	\N	0	\N	\N	f	0	\N
17345	90	244	\N	0	\N	\N	f	0	\N
17346	90	243	\N	0	\N	\N	f	0	\N
17347	90	242	\N	0	\N	\N	f	0	\N
17348	90	241	\N	0	\N	\N	f	0	\N
17349	90	240	\N	0	\N	\N	f	0	\N
17350	90	239	\N	0	\N	\N	f	0	\N
17351	90	238	\N	0	\N	\N	f	0	\N
17352	90	237	\N	0	\N	\N	f	0	\N
17353	90	236	\N	0	\N	\N	f	0	\N
17354	90	235	\N	0	\N	\N	f	0	\N
17355	90	234	\N	0	\N	\N	f	0	\N
17356	90	233	\N	0	\N	\N	f	0	\N
17357	90	232	\N	0	\N	\N	f	0	\N
17358	90	231	\N	0	\N	\N	f	0	\N
17359	90	230	\N	0	\N	\N	f	0	\N
17360	90	229	\N	0	\N	\N	f	0	\N
17361	90	228	\N	0	\N	\N	f	0	\N
17362	90	227	\N	0	\N	\N	f	0	\N
17363	90	226	\N	0	\N	\N	f	0	\N
17364	90	225	\N	0	\N	\N	f	0	\N
17365	90	224	\N	0	\N	\N	f	0	\N
17366	90	223	\N	0	\N	\N	f	0	\N
17367	90	222	\N	0	\N	\N	f	0	\N
17368	90	221	\N	0	\N	\N	f	0	\N
17369	90	220	\N	0	\N	\N	f	0	\N
17370	90	219	\N	0	\N	\N	f	0	\N
17371	90	360	\N	0	\N	\N	f	0	\N
17372	90	359	\N	0	\N	\N	f	0	\N
17373	90	358	\N	0	\N	\N	f	0	\N
17374	90	357	\N	0	\N	\N	f	0	\N
17375	90	356	\N	0	\N	\N	f	0	\N
17376	90	355	\N	0	\N	\N	f	0	\N
17377	90	354	\N	0	\N	\N	f	0	\N
17378	90	353	\N	0	\N	\N	f	0	\N
17379	90	352	\N	0	\N	\N	f	0	\N
17380	90	351	\N	0	\N	\N	f	0	\N
17381	90	350	\N	0	\N	\N	f	0	\N
17382	90	349	\N	0	\N	\N	f	0	\N
17383	90	348	\N	0	\N	\N	f	0	\N
17384	90	347	\N	0	\N	\N	f	0	\N
17385	90	346	\N	0	\N	\N	f	0	\N
17386	90	345	\N	0	\N	\N	f	0	\N
17387	90	344	\N	0	\N	\N	f	0	\N
17388	90	343	\N	0	\N	\N	f	0	\N
17389	90	342	\N	0	\N	\N	f	0	\N
17390	90	341	\N	0	\N	\N	f	0	\N
17391	90	340	\N	0	\N	\N	f	0	\N
17392	90	339	\N	0	\N	\N	f	0	\N
17393	90	338	\N	0	\N	\N	f	0	\N
17394	90	337	\N	0	\N	\N	f	0	\N
17395	90	336	\N	0	\N	\N	f	0	\N
17396	90	335	\N	0	\N	\N	f	0	\N
17397	90	334	\N	0	\N	\N	f	0	\N
17398	90	333	\N	0	\N	\N	f	0	\N
17399	90	332	\N	0	\N	\N	f	0	\N
17400	90	331	\N	0	\N	\N	f	0	\N
17401	90	330	\N	0	\N	\N	f	0	\N
17402	90	329	\N	0	\N	\N	f	0	\N
17403	90	328	\N	0	\N	\N	f	0	\N
17404	90	327	\N	0	\N	\N	f	0	\N
17405	90	326	\N	0	\N	\N	f	0	\N
17406	90	325	\N	0	\N	\N	f	0	\N
17407	90	324	\N	0	\N	\N	f	0	\N
17408	90	180	\N	0	\N	\N	f	0	\N
17409	90	179	\N	0	\N	\N	f	0	\N
17410	90	178	\N	0	\N	\N	f	0	\N
17411	90	177	\N	0	\N	\N	f	0	\N
17412	90	176	\N	0	\N	\N	f	0	\N
17413	90	175	\N	0	\N	\N	f	0	\N
17414	90	174	\N	0	\N	\N	f	0	\N
17415	90	173	\N	0	\N	\N	f	0	\N
17416	90	172	\N	0	\N	\N	f	0	\N
17417	90	171	\N	0	\N	\N	f	0	\N
17418	90	170	\N	0	\N	\N	f	0	\N
17419	90	169	\N	0	\N	\N	f	0	\N
17420	90	168	\N	0	\N	\N	f	0	\N
17421	90	167	\N	0	\N	\N	f	0	\N
17422	90	166	\N	0	\N	\N	f	0	\N
17423	90	165	\N	0	\N	\N	f	0	\N
17424	90	164	\N	0	\N	\N	f	0	\N
17425	90	163	\N	0	\N	\N	f	0	\N
17426	90	162	\N	0	\N	\N	f	0	\N
17427	90	161	\N	0	\N	\N	f	0	\N
17428	90	160	\N	0	\N	\N	f	0	\N
17429	90	159	\N	0	\N	\N	f	0	\N
17430	90	158	\N	0	\N	\N	f	0	\N
17431	90	157	\N	0	\N	\N	f	0	\N
17432	90	156	\N	0	\N	\N	f	0	\N
17433	90	155	\N	0	\N	\N	f	0	\N
17434	90	154	\N	0	\N	\N	f	0	\N
17435	90	153	\N	0	\N	\N	f	0	\N
17436	90	152	\N	0	\N	\N	f	0	\N
17437	90	151	\N	0	\N	\N	f	0	\N
17438	90	150	\N	0	\N	\N	f	0	\N
17439	90	149	\N	0	\N	\N	f	0	\N
17440	90	148	\N	0	\N	\N	f	0	\N
17441	90	147	\N	0	\N	\N	f	0	\N
17442	90	146	\N	0	\N	\N	f	0	\N
17443	90	290	\N	0	\N	\N	f	0	\N
17444	90	289	\N	0	\N	\N	f	0	\N
17445	90	288	\N	0	\N	\N	f	0	\N
17446	90	287	\N	0	\N	\N	f	0	\N
17447	90	286	\N	0	\N	\N	f	0	\N
17448	90	285	\N	0	\N	\N	f	0	\N
17449	90	284	\N	0	\N	\N	f	0	\N
17450	90	283	\N	0	\N	\N	f	0	\N
17451	90	282	\N	0	\N	\N	f	0	\N
17452	90	281	\N	0	\N	\N	f	0	\N
17453	90	280	\N	0	\N	\N	f	0	\N
17454	90	279	\N	0	\N	\N	f	0	\N
17455	90	278	\N	0	\N	\N	f	0	\N
17456	90	277	\N	0	\N	\N	f	0	\N
17457	90	276	\N	0	\N	\N	f	0	\N
17458	90	275	\N	0	\N	\N	f	0	\N
17459	90	274	\N	0	\N	\N	f	0	\N
17460	90	273	\N	0	\N	\N	f	0	\N
17461	90	272	\N	0	\N	\N	f	0	\N
17462	90	271	\N	0	\N	\N	f	0	\N
17463	90	270	\N	0	\N	\N	f	0	\N
17464	90	269	\N	0	\N	\N	f	0	\N
17465	90	268	\N	0	\N	\N	f	0	\N
17466	90	267	\N	0	\N	\N	f	0	\N
17467	90	266	\N	0	\N	\N	f	0	\N
17468	90	265	\N	0	\N	\N	f	0	\N
17469	90	264	\N	0	\N	\N	f	0	\N
17470	90	263	\N	0	\N	\N	f	0	\N
17471	90	262	\N	0	\N	\N	f	0	\N
17472	90	261	\N	0	\N	\N	f	0	\N
17473	90	260	\N	0	\N	\N	f	0	\N
17474	90	259	\N	0	\N	\N	f	0	\N
17475	90	258	\N	0	\N	\N	f	0	\N
17476	90	257	\N	0	\N	\N	f	0	\N
17477	90	256	\N	0	\N	\N	f	0	\N
17478	90	255	\N	0	\N	\N	f	0	\N
17479	90	74	\N	0	\N	\N	f	0	\N
17480	90	73	\N	0	\N	\N	f	0	\N
17481	90	72	\N	0	\N	\N	f	0	\N
17482	90	71	\N	0	\N	\N	f	0	\N
17483	90	70	\N	0	\N	\N	f	0	\N
17484	90	69	\N	0	\N	\N	f	0	\N
17485	90	68	\N	0	\N	\N	f	0	\N
17486	90	67	\N	0	\N	\N	f	0	\N
17487	90	66	\N	0	\N	\N	f	0	\N
17488	90	65	\N	0	\N	\N	f	0	\N
17489	90	64	\N	0	\N	\N	f	0	\N
17490	90	63	\N	0	\N	\N	f	0	\N
17491	90	62	\N	0	\N	\N	f	0	\N
17492	90	61	\N	0	\N	\N	f	0	\N
17493	90	60	\N	0	\N	\N	f	0	\N
17494	90	59	\N	0	\N	\N	f	0	\N
17495	90	58	\N	0	\N	\N	f	0	\N
17496	90	57	\N	0	\N	\N	f	0	\N
17497	90	56	\N	0	\N	\N	f	0	\N
17498	90	55	\N	0	\N	\N	f	0	\N
17499	90	54	\N	0	\N	\N	f	0	\N
17500	90	53	\N	0	\N	\N	f	0	\N
17501	90	52	\N	0	\N	\N	f	0	\N
17502	90	51	\N	0	\N	\N	f	0	\N
17503	90	50	\N	0	\N	\N	f	0	\N
17504	90	49	\N	0	\N	\N	f	0	\N
17505	90	48	\N	0	\N	\N	f	0	\N
17506	90	47	\N	0	\N	\N	f	0	\N
17507	90	46	\N	0	\N	\N	f	0	\N
17508	90	45	\N	0	\N	\N	f	0	\N
17509	90	44	\N	0	\N	\N	f	0	\N
17510	90	43	\N	0	\N	\N	f	0	\N
17511	90	42	\N	0	\N	\N	f	0	\N
17512	90	41	\N	0	\N	\N	f	0	\N
17513	90	40	\N	0	\N	\N	f	0	\N
17514	90	109	\N	0	\N	\N	f	0	\N
17515	90	108	\N	0	\N	\N	f	0	\N
17516	90	107	\N	0	\N	\N	f	0	\N
17517	90	106	\N	0	\N	\N	f	0	\N
17518	90	105	\N	0	\N	\N	f	0	\N
17519	90	104	\N	0	\N	\N	f	0	\N
17520	90	103	\N	0	\N	\N	f	0	\N
17521	90	102	\N	0	\N	\N	f	0	\N
17522	90	101	\N	0	\N	\N	f	0	\N
17523	90	100	\N	0	\N	\N	f	0	\N
17524	90	99	\N	0	\N	\N	f	0	\N
17525	90	98	\N	0	\N	\N	f	0	\N
17526	90	97	\N	0	\N	\N	f	0	\N
17527	90	96	\N	0	\N	\N	f	0	\N
17528	90	95	\N	0	\N	\N	f	0	\N
17529	90	94	\N	0	\N	\N	f	0	\N
17530	90	93	\N	0	\N	\N	f	0	\N
17531	90	92	\N	0	\N	\N	f	0	\N
17532	90	91	\N	0	\N	\N	f	0	\N
17533	90	90	\N	0	\N	\N	f	0	\N
17534	90	89	\N	0	\N	\N	f	0	\N
17535	90	88	\N	0	\N	\N	f	0	\N
17536	90	87	\N	0	\N	\N	f	0	\N
17537	90	86	\N	0	\N	\N	f	0	\N
17538	90	85	\N	0	\N	\N	f	0	\N
17539	90	84	\N	0	\N	\N	f	0	\N
17540	90	83	\N	0	\N	\N	f	0	\N
17541	90	82	\N	0	\N	\N	f	0	\N
17542	90	81	\N	0	\N	\N	f	0	\N
17543	90	80	\N	0	\N	\N	f	0	\N
17544	90	79	\N	0	\N	\N	f	0	\N
17545	90	78	\N	0	\N	\N	f	0	\N
17546	90	77	\N	0	\N	\N	f	0	\N
17547	90	76	\N	0	\N	\N	f	0	\N
17548	90	75	\N	0	\N	\N	f	0	\N
17549	90	432	\N	0	\N	\N	f	0	\N
17550	90	431	\N	0	\N	\N	f	0	\N
17551	90	430	\N	0	\N	\N	f	0	\N
17552	90	429	\N	0	\N	\N	f	0	\N
17553	90	428	\N	0	\N	\N	f	0	\N
17554	90	427	\N	0	\N	\N	f	0	\N
17555	90	426	\N	0	\N	\N	f	0	\N
17556	90	425	\N	0	\N	\N	f	0	\N
17557	90	424	\N	0	\N	\N	f	0	\N
17558	90	423	\N	0	\N	\N	f	0	\N
17559	90	422	\N	0	\N	\N	f	0	\N
17560	90	421	\N	0	\N	\N	f	0	\N
17561	90	420	\N	0	\N	\N	f	0	\N
17562	90	419	\N	0	\N	\N	f	0	\N
17563	90	418	\N	0	\N	\N	f	0	\N
17564	90	417	\N	0	\N	\N	f	0	\N
17565	90	416	\N	0	\N	\N	f	0	\N
17566	90	415	\N	0	\N	\N	f	0	\N
17567	90	414	\N	0	\N	\N	f	0	\N
17568	90	413	\N	0	\N	\N	f	0	\N
17569	90	412	\N	0	\N	\N	f	0	\N
17570	90	411	\N	0	\N	\N	f	0	\N
17571	90	410	\N	0	\N	\N	f	0	\N
17572	90	409	\N	0	\N	\N	f	0	\N
17573	90	408	\N	0	\N	\N	f	0	\N
17574	90	407	\N	0	\N	\N	f	0	\N
17575	90	406	\N	0	\N	\N	f	0	\N
17576	90	405	\N	0	\N	\N	f	0	\N
17577	90	404	\N	0	\N	\N	f	0	\N
17578	90	403	\N	0	\N	\N	f	0	\N
17579	90	402	\N	0	\N	\N	f	0	\N
17580	90	323	\N	0	\N	\N	f	0	\N
17581	90	322	\N	0	\N	\N	f	0	\N
17582	90	321	\N	0	\N	\N	f	0	\N
17583	90	320	\N	0	\N	\N	f	0	\N
17584	90	319	\N	0	\N	\N	f	0	\N
17585	90	318	\N	0	\N	\N	f	0	\N
17586	90	317	\N	0	\N	\N	f	0	\N
17587	90	316	\N	0	\N	\N	f	0	\N
17588	90	315	\N	0	\N	\N	f	0	\N
17589	90	314	\N	0	\N	\N	f	0	\N
17590	90	313	\N	0	\N	\N	f	0	\N
17591	90	312	\N	0	\N	\N	f	0	\N
17592	90	311	\N	0	\N	\N	f	0	\N
17593	90	310	\N	0	\N	\N	f	0	\N
17594	90	309	\N	0	\N	\N	f	0	\N
17595	90	308	\N	0	\N	\N	f	0	\N
17596	90	307	\N	0	\N	\N	f	0	\N
17597	90	306	\N	0	\N	\N	f	0	\N
17598	90	305	\N	0	\N	\N	f	0	\N
17599	90	304	\N	0	\N	\N	f	0	\N
17600	90	303	\N	0	\N	\N	f	0	\N
17601	90	302	\N	0	\N	\N	f	0	\N
17602	90	301	\N	0	\N	\N	f	0	\N
17603	90	300	\N	0	\N	\N	f	0	\N
17604	90	299	\N	0	\N	\N	f	0	\N
17605	90	298	\N	0	\N	\N	f	0	\N
17606	90	297	\N	0	\N	\N	f	0	\N
17607	90	296	\N	0	\N	\N	f	0	\N
17608	90	295	\N	0	\N	\N	f	0	\N
17609	90	294	\N	0	\N	\N	f	0	\N
17610	90	293	\N	0	\N	\N	f	0	\N
17611	90	292	\N	0	\N	\N	f	0	\N
17612	90	291	\N	0	\N	\N	f	0	\N
17613	90	39	\N	0	\N	\N	f	0	\N
17614	90	38	\N	0	\N	\N	f	0	\N
17615	90	37	\N	0	\N	\N	f	0	\N
17616	90	36	\N	0	\N	\N	f	0	\N
17617	90	35	\N	0	\N	\N	f	0	\N
17618	90	34	\N	0	\N	\N	f	0	\N
17619	90	33	\N	0	\N	\N	f	0	\N
17620	90	32	\N	0	\N	\N	f	0	\N
17621	90	31	\N	0	\N	\N	f	0	\N
17622	90	30	\N	0	\N	\N	f	0	\N
17623	90	29	\N	0	\N	\N	f	0	\N
17624	90	28	\N	0	\N	\N	f	0	\N
17625	90	27	\N	0	\N	\N	f	0	\N
17626	90	26	\N	0	\N	\N	f	0	\N
17627	90	25	\N	0	\N	\N	f	0	\N
17628	90	24	\N	0	\N	\N	f	0	\N
17629	90	23	\N	0	\N	\N	f	0	\N
17630	90	22	\N	0	\N	\N	f	0	\N
17631	90	21	\N	0	\N	\N	f	0	\N
17632	90	20	\N	0	\N	\N	f	0	\N
17633	90	19	\N	0	\N	\N	f	0	\N
17634	90	18	\N	0	\N	\N	f	0	\N
17635	90	17	\N	0	\N	\N	f	0	\N
17636	90	16	\N	0	\N	\N	f	0	\N
17637	90	15	\N	0	\N	\N	f	0	\N
17638	90	14	\N	0	\N	\N	f	0	\N
17639	90	13	\N	0	\N	\N	f	0	\N
17640	90	12	\N	0	\N	\N	f	0	\N
17641	90	11	\N	0	\N	\N	f	0	\N
17642	90	10	\N	0	\N	\N	f	0	\N
17643	90	9	\N	0	\N	\N	f	0	\N
17644	90	8	\N	0	\N	\N	f	0	\N
17645	90	7	\N	0	\N	\N	f	0	\N
17646	90	6	\N	0	\N	\N	f	0	\N
17647	90	5	\N	0	\N	\N	f	0	\N
17648	90	4	\N	0	\N	\N	f	0	\N
17649	90	3	\N	0	\N	\N	f	0	\N
17650	90	2	\N	0	\N	\N	f	0	\N
17651	90	1	\N	0	\N	\N	f	0	\N
17652	90	218	\N	0	\N	\N	f	0	\N
17653	90	217	\N	0	\N	\N	f	0	\N
17654	90	216	\N	0	\N	\N	f	0	\N
17655	90	215	\N	0	\N	\N	f	0	\N
17656	90	214	\N	0	\N	\N	f	0	\N
17657	90	213	\N	0	\N	\N	f	0	\N
17658	90	212	\N	0	\N	\N	f	0	\N
17659	90	211	\N	0	\N	\N	f	0	\N
17660	90	210	\N	0	\N	\N	f	0	\N
17661	90	209	\N	0	\N	\N	f	0	\N
17662	90	208	\N	0	\N	\N	f	0	\N
17663	90	207	\N	0	\N	\N	f	0	\N
17664	90	206	\N	0	\N	\N	f	0	\N
17665	90	205	\N	0	\N	\N	f	0	\N
17666	90	204	\N	0	\N	\N	f	0	\N
17667	90	203	\N	0	\N	\N	f	0	\N
17668	90	202	\N	0	\N	\N	f	0	\N
17669	90	201	\N	0	\N	\N	f	0	\N
17670	90	200	\N	0	\N	\N	f	0	\N
17671	90	199	\N	0	\N	\N	f	0	\N
17672	90	198	\N	0	\N	\N	f	0	\N
17673	90	197	\N	0	\N	\N	f	0	\N
17674	90	196	\N	0	\N	\N	f	0	\N
17675	90	195	\N	0	\N	\N	f	0	\N
17676	90	194	\N	0	\N	\N	f	0	\N
17677	90	193	\N	0	\N	\N	f	0	\N
17678	90	192	\N	0	\N	\N	f	0	\N
17679	90	191	\N	0	\N	\N	f	0	\N
17680	90	190	\N	0	\N	\N	f	0	\N
17681	90	189	\N	0	\N	\N	f	0	\N
17682	90	188	\N	0	\N	\N	f	0	\N
17683	90	187	\N	0	\N	\N	f	0	\N
17684	90	186	\N	0	\N	\N	f	0	\N
17685	90	185	\N	0	\N	\N	f	0	\N
17686	90	184	\N	0	\N	\N	f	0	\N
17687	90	183	\N	0	\N	\N	f	0	\N
17688	90	182	\N	0	\N	\N	f	0	\N
17689	90	181	\N	0	\N	\N	f	0	\N
17690	90	401	\N	0	\N	\N	f	0	\N
17691	90	400	\N	0	\N	\N	f	0	\N
17692	90	399	\N	0	\N	\N	f	0	\N
17693	90	398	\N	0	\N	\N	f	0	\N
17694	90	397	\N	0	\N	\N	f	0	\N
17695	90	396	\N	0	\N	\N	f	0	\N
17696	90	395	\N	0	\N	\N	f	0	\N
17697	90	394	\N	0	\N	\N	f	0	\N
17698	90	393	\N	0	\N	\N	f	0	\N
17699	90	392	\N	0	\N	\N	f	0	\N
17700	90	391	\N	0	\N	\N	f	0	\N
17701	90	390	\N	0	\N	\N	f	0	\N
17702	90	389	\N	0	\N	\N	f	0	\N
17703	90	388	\N	0	\N	\N	f	0	\N
17704	90	387	\N	0	\N	\N	f	0	\N
17705	90	386	\N	0	\N	\N	f	0	\N
17706	90	385	\N	0	\N	\N	f	0	\N
17707	90	384	\N	0	\N	\N	f	0	\N
17708	90	383	\N	0	\N	\N	f	0	\N
17709	90	382	\N	0	\N	\N	f	0	\N
17710	90	381	\N	0	\N	\N	f	0	\N
17711	90	380	\N	0	\N	\N	f	0	\N
17712	90	379	\N	0	\N	\N	f	0	\N
17713	90	378	\N	0	\N	\N	f	0	\N
17714	90	377	\N	0	\N	\N	f	0	\N
17715	90	376	\N	0	\N	\N	f	0	\N
17716	90	375	\N	0	\N	\N	f	0	\N
17717	90	374	\N	0	\N	\N	f	0	\N
17718	90	373	\N	0	\N	\N	f	0	\N
17719	90	372	\N	0	\N	\N	f	0	\N
17720	90	371	\N	0	\N	\N	f	0	\N
17721	90	370	\N	0	\N	\N	f	0	\N
17722	90	369	\N	0	\N	\N	f	0	\N
17723	90	368	\N	0	\N	\N	f	0	\N
17724	90	367	\N	0	\N	\N	f	0	\N
17725	90	366	\N	0	\N	\N	f	0	\N
17726	90	365	\N	0	\N	\N	f	0	\N
17727	90	364	\N	0	\N	\N	f	0	\N
17728	90	363	\N	0	\N	\N	f	0	\N
17729	90	362	\N	0	\N	\N	f	0	\N
17730	90	361	\N	0	\N	\N	f	0	\N
17731	90	145	\N	0	\N	\N	f	0	\N
17732	90	144	\N	0	\N	\N	f	0	\N
17733	90	143	\N	0	\N	\N	f	0	\N
17734	90	142	\N	0	\N	\N	f	0	\N
17735	90	141	\N	0	\N	\N	f	0	\N
17736	90	140	\N	0	\N	\N	f	0	\N
17737	90	139	\N	0	\N	\N	f	0	\N
17738	90	138	\N	0	\N	\N	f	0	\N
17739	90	137	\N	0	\N	\N	f	0	\N
17740	90	136	\N	0	\N	\N	f	0	\N
17741	90	135	\N	0	\N	\N	f	0	\N
17742	90	134	\N	0	\N	\N	f	0	\N
17743	90	133	\N	0	\N	\N	f	0	\N
17744	90	132	\N	0	\N	\N	f	0	\N
17745	90	131	\N	0	\N	\N	f	0	\N
17746	90	130	\N	0	\N	\N	f	0	\N
17747	90	129	\N	0	\N	\N	f	0	\N
17748	90	128	\N	0	\N	\N	f	0	\N
17749	90	127	\N	0	\N	\N	f	0	\N
17750	90	126	\N	0	\N	\N	f	0	\N
17751	90	125	\N	0	\N	\N	f	0	\N
17752	90	124	\N	0	\N	\N	f	0	\N
17753	90	123	\N	0	\N	\N	f	0	\N
17754	90	122	\N	0	\N	\N	f	0	\N
17755	90	121	\N	0	\N	\N	f	0	\N
17756	90	120	\N	0	\N	\N	f	0	\N
17757	90	119	\N	0	\N	\N	f	0	\N
17758	90	118	\N	0	\N	\N	f	0	\N
17759	90	117	\N	0	\N	\N	f	0	\N
17760	90	116	\N	0	\N	\N	f	0	\N
17761	90	115	\N	0	\N	\N	f	0	\N
17762	90	114	\N	0	\N	\N	f	0	\N
17763	90	113	\N	0	\N	\N	f	0	\N
17764	90	112	\N	0	\N	\N	f	0	\N
17765	90	111	\N	0	\N	\N	f	0	\N
17766	90	110	\N	0	\N	\N	f	0	\N
17767	91	323	\N	0	\N	\N	f	0	\N
17768	91	322	\N	0	\N	\N	f	0	\N
17769	91	321	\N	0	\N	\N	f	0	\N
17770	91	320	\N	0	\N	\N	f	0	\N
17771	91	319	\N	0	\N	\N	f	0	\N
17772	91	318	\N	0	\N	\N	f	0	\N
17773	91	317	\N	0	\N	\N	f	0	\N
17774	91	316	\N	0	\N	\N	f	0	\N
17775	91	315	\N	0	\N	\N	f	0	\N
17776	91	314	\N	0	\N	\N	f	0	\N
17777	91	313	\N	0	\N	\N	f	0	\N
17778	91	312	\N	0	\N	\N	f	0	\N
17779	91	311	\N	0	\N	\N	f	0	\N
17780	91	310	\N	0	\N	\N	f	0	\N
17781	91	309	\N	0	\N	\N	f	0	\N
17782	91	308	\N	0	\N	\N	f	0	\N
17783	91	307	\N	0	\N	\N	f	0	\N
17784	91	306	\N	0	\N	\N	f	0	\N
17785	91	305	\N	0	\N	\N	f	0	\N
17786	91	304	\N	0	\N	\N	f	0	\N
17787	91	303	\N	0	\N	\N	f	0	\N
17788	91	302	\N	0	\N	\N	f	0	\N
17789	91	301	\N	0	\N	\N	f	0	\N
17790	91	300	\N	0	\N	\N	f	0	\N
17791	91	299	\N	0	\N	\N	f	0	\N
17792	91	298	\N	0	\N	\N	f	0	\N
17793	91	297	\N	0	\N	\N	f	0	\N
17794	91	296	\N	0	\N	\N	f	0	\N
17795	91	295	\N	0	\N	\N	f	0	\N
17796	91	294	\N	0	\N	\N	f	0	\N
17797	91	293	\N	0	\N	\N	f	0	\N
17798	91	292	\N	0	\N	\N	f	0	\N
17799	91	291	\N	0	\N	\N	f	0	\N
17800	91	432	\N	0	\N	\N	f	0	\N
17801	91	431	\N	0	\N	\N	f	0	\N
17802	91	430	\N	0	\N	\N	f	0	\N
17803	91	429	\N	0	\N	\N	f	0	\N
17804	91	428	\N	0	\N	\N	f	0	\N
17805	91	427	\N	0	\N	\N	f	0	\N
17806	91	426	\N	0	\N	\N	f	0	\N
17807	91	425	\N	0	\N	\N	f	0	\N
17808	91	424	\N	0	\N	\N	f	0	\N
17809	91	423	\N	0	\N	\N	f	0	\N
17810	91	422	\N	0	\N	\N	f	0	\N
17811	91	421	\N	0	\N	\N	f	0	\N
17812	91	420	\N	0	\N	\N	f	0	\N
17813	91	419	\N	0	\N	\N	f	0	\N
17814	91	418	\N	0	\N	\N	f	0	\N
17815	91	417	\N	0	\N	\N	f	0	\N
17816	91	416	\N	0	\N	\N	f	0	\N
17817	91	415	\N	0	\N	\N	f	0	\N
17818	91	414	\N	0	\N	\N	f	0	\N
17819	91	413	\N	0	\N	\N	f	0	\N
17820	91	412	\N	0	\N	\N	f	0	\N
17821	91	411	\N	0	\N	\N	f	0	\N
17822	91	410	\N	0	\N	\N	f	0	\N
17823	91	409	\N	0	\N	\N	f	0	\N
17824	91	408	\N	0	\N	\N	f	0	\N
17825	91	407	\N	0	\N	\N	f	0	\N
17826	91	406	\N	0	\N	\N	f	0	\N
17827	91	405	\N	0	\N	\N	f	0	\N
17828	91	404	\N	0	\N	\N	f	0	\N
17829	91	403	\N	0	\N	\N	f	0	\N
17830	91	402	\N	0	\N	\N	f	0	\N
17831	91	360	\N	0	\N	\N	f	0	\N
17832	91	359	\N	0	\N	\N	f	0	\N
17833	91	358	\N	0	\N	\N	f	0	\N
17834	91	357	\N	0	\N	\N	f	0	\N
17835	91	356	\N	0	\N	\N	f	0	\N
17836	91	355	\N	0	\N	\N	f	0	\N
17837	91	354	\N	0	\N	\N	f	0	\N
17838	91	353	\N	0	\N	\N	f	0	\N
17839	91	352	\N	0	\N	\N	f	0	\N
17840	91	351	\N	0	\N	\N	f	0	\N
17841	91	350	\N	0	\N	\N	f	0	\N
17842	91	349	\N	0	\N	\N	f	0	\N
17843	91	348	\N	0	\N	\N	f	0	\N
17844	91	347	\N	0	\N	\N	f	0	\N
17845	91	346	\N	0	\N	\N	f	0	\N
17846	91	345	\N	0	\N	\N	f	0	\N
17847	91	344	\N	0	\N	\N	f	0	\N
17848	91	343	\N	0	\N	\N	f	0	\N
17849	91	342	\N	0	\N	\N	f	0	\N
17850	91	341	\N	0	\N	\N	f	0	\N
17851	91	340	\N	0	\N	\N	f	0	\N
17852	91	339	\N	0	\N	\N	f	0	\N
17853	91	338	\N	0	\N	\N	f	0	\N
17854	91	337	\N	0	\N	\N	f	0	\N
17855	91	336	\N	0	\N	\N	f	0	\N
17856	91	335	\N	0	\N	\N	f	0	\N
17857	91	334	\N	0	\N	\N	f	0	\N
17858	91	333	\N	0	\N	\N	f	0	\N
17859	91	332	\N	0	\N	\N	f	0	\N
17860	91	331	\N	0	\N	\N	f	0	\N
17861	91	330	\N	0	\N	\N	f	0	\N
17862	91	329	\N	0	\N	\N	f	0	\N
17863	91	328	\N	0	\N	\N	f	0	\N
17864	91	327	\N	0	\N	\N	f	0	\N
17865	91	326	\N	0	\N	\N	f	0	\N
17866	91	325	\N	0	\N	\N	f	0	\N
17867	91	324	\N	0	\N	\N	f	0	\N
17868	91	290	\N	0	\N	\N	f	0	\N
17869	91	289	\N	0	\N	\N	f	0	\N
17870	91	288	\N	0	\N	\N	f	0	\N
17871	91	287	\N	0	\N	\N	f	0	\N
17872	91	286	\N	0	\N	\N	f	0	\N
17873	91	285	\N	0	\N	\N	f	0	\N
17874	91	284	\N	0	\N	\N	f	0	\N
17875	91	283	\N	0	\N	\N	f	0	\N
17876	91	282	\N	0	\N	\N	f	0	\N
17877	91	281	\N	0	\N	\N	f	0	\N
17878	91	280	\N	0	\N	\N	f	0	\N
17879	91	279	\N	0	\N	\N	f	0	\N
17880	91	278	\N	0	\N	\N	f	0	\N
17881	91	277	\N	0	\N	\N	f	0	\N
17882	91	276	\N	0	\N	\N	f	0	\N
17883	91	275	\N	0	\N	\N	f	0	\N
17884	91	274	\N	0	\N	\N	f	0	\N
17885	91	273	\N	0	\N	\N	f	0	\N
17886	91	272	\N	0	\N	\N	f	0	\N
17887	91	271	\N	0	\N	\N	f	0	\N
17888	91	270	\N	0	\N	\N	f	0	\N
17889	91	269	\N	0	\N	\N	f	0	\N
17890	91	268	\N	0	\N	\N	f	0	\N
17891	91	267	\N	0	\N	\N	f	0	\N
17892	91	266	\N	0	\N	\N	f	0	\N
17893	91	265	\N	0	\N	\N	f	0	\N
17894	91	264	\N	0	\N	\N	f	0	\N
17895	91	263	\N	0	\N	\N	f	0	\N
17896	91	262	\N	0	\N	\N	f	0	\N
17897	91	261	\N	0	\N	\N	f	0	\N
17898	91	260	\N	0	\N	\N	f	0	\N
17899	91	259	\N	0	\N	\N	f	0	\N
17900	91	258	\N	0	\N	\N	f	0	\N
17901	91	257	\N	0	\N	\N	f	0	\N
17902	91	256	\N	0	\N	\N	f	0	\N
17903	91	255	\N	0	\N	\N	f	0	\N
17904	91	39	\N	0	\N	\N	f	0	\N
17905	91	38	\N	0	\N	\N	f	0	\N
17906	91	37	\N	0	\N	\N	f	0	\N
17907	91	36	\N	0	\N	\N	f	0	\N
17908	91	35	\N	0	\N	\N	f	0	\N
17909	91	34	\N	0	\N	\N	f	0	\N
17910	91	33	\N	0	\N	\N	f	0	\N
17911	91	32	\N	0	\N	\N	f	0	\N
17912	91	31	\N	0	\N	\N	f	0	\N
17913	91	30	\N	0	\N	\N	f	0	\N
17914	91	29	\N	0	\N	\N	f	0	\N
17915	91	28	\N	0	\N	\N	f	0	\N
17916	91	27	\N	0	\N	\N	f	0	\N
17917	91	26	\N	0	\N	\N	f	0	\N
17918	91	25	\N	0	\N	\N	f	0	\N
17919	91	24	\N	0	\N	\N	f	0	\N
17920	91	23	\N	0	\N	\N	f	0	\N
17921	91	22	\N	0	\N	\N	f	0	\N
17922	91	21	\N	0	\N	\N	f	0	\N
17923	91	20	\N	0	\N	\N	f	0	\N
17924	91	19	\N	0	\N	\N	f	0	\N
17925	91	18	\N	0	\N	\N	f	0	\N
17926	91	17	\N	0	\N	\N	f	0	\N
17927	91	16	\N	0	\N	\N	f	0	\N
17928	91	15	\N	0	\N	\N	f	0	\N
17929	91	14	\N	0	\N	\N	f	0	\N
17930	91	13	\N	0	\N	\N	f	0	\N
17931	91	12	\N	0	\N	\N	f	0	\N
17932	91	11	\N	0	\N	\N	f	0	\N
17933	91	10	\N	0	\N	\N	f	0	\N
17934	91	9	\N	0	\N	\N	f	0	\N
17935	91	8	\N	0	\N	\N	f	0	\N
17936	91	7	\N	0	\N	\N	f	0	\N
17937	91	6	\N	0	\N	\N	f	0	\N
17938	91	5	\N	0	\N	\N	f	0	\N
17939	91	4	\N	0	\N	\N	f	0	\N
17940	91	3	\N	0	\N	\N	f	0	\N
17941	91	2	\N	0	\N	\N	f	0	\N
17942	91	1	\N	0	\N	\N	f	0	\N
17943	91	180	\N	0	\N	\N	f	0	\N
17944	91	179	\N	0	\N	\N	f	0	\N
17945	91	178	\N	0	\N	\N	f	0	\N
17946	91	177	\N	0	\N	\N	f	0	\N
17947	91	176	\N	0	\N	\N	f	0	\N
17948	91	175	\N	0	\N	\N	f	0	\N
17949	91	174	\N	0	\N	\N	f	0	\N
17950	91	173	\N	0	\N	\N	f	0	\N
17951	91	172	\N	0	\N	\N	f	0	\N
17952	91	171	\N	0	\N	\N	f	0	\N
17953	91	170	\N	0	\N	\N	f	0	\N
17954	91	169	\N	0	\N	\N	f	0	\N
17955	91	168	\N	0	\N	\N	f	0	\N
17956	91	167	\N	0	\N	\N	f	0	\N
17957	91	166	\N	0	\N	\N	f	0	\N
17958	91	165	\N	0	\N	\N	f	0	\N
17959	91	164	\N	0	\N	\N	f	0	\N
17960	91	163	\N	0	\N	\N	f	0	\N
17961	91	162	\N	0	\N	\N	f	0	\N
17962	91	161	\N	0	\N	\N	f	0	\N
17963	91	160	\N	0	\N	\N	f	0	\N
17964	91	159	\N	0	\N	\N	f	0	\N
17965	91	158	\N	0	\N	\N	f	0	\N
17966	91	157	\N	0	\N	\N	f	0	\N
17967	91	156	\N	0	\N	\N	f	0	\N
17968	91	155	\N	0	\N	\N	f	0	\N
17969	91	154	\N	0	\N	\N	f	0	\N
17970	91	153	\N	0	\N	\N	f	0	\N
17971	91	152	\N	0	\N	\N	f	0	\N
17972	91	151	\N	0	\N	\N	f	0	\N
17973	91	150	\N	0	\N	\N	f	0	\N
17974	91	149	\N	0	\N	\N	f	0	\N
17975	91	148	\N	0	\N	\N	f	0	\N
17976	91	147	\N	0	\N	\N	f	0	\N
17977	91	146	\N	0	\N	\N	f	0	\N
17978	91	254	\N	0	\N	\N	f	0	\N
17979	91	253	\N	0	\N	\N	f	0	\N
17980	91	252	\N	0	\N	\N	f	0	\N
17981	91	251	\N	0	\N	\N	f	0	\N
17982	91	250	\N	0	\N	\N	f	0	\N
17983	91	249	\N	0	\N	\N	f	0	\N
17984	91	248	\N	0	\N	\N	f	0	\N
17985	91	247	\N	0	\N	\N	f	0	\N
17986	91	246	\N	0	\N	\N	f	0	\N
17987	91	245	\N	0	\N	\N	f	0	\N
17988	91	244	\N	0	\N	\N	f	0	\N
17989	91	243	\N	0	\N	\N	f	0	\N
17990	91	242	\N	0	\N	\N	f	0	\N
17991	91	241	\N	0	\N	\N	f	0	\N
17992	91	240	\N	0	\N	\N	f	0	\N
17993	91	239	\N	0	\N	\N	f	0	\N
17994	91	238	\N	0	\N	\N	f	0	\N
17995	91	237	\N	0	\N	\N	f	0	\N
17996	91	236	\N	0	\N	\N	f	0	\N
17997	91	235	\N	0	\N	\N	f	0	\N
17998	91	234	\N	0	\N	\N	f	0	\N
17999	91	233	\N	0	\N	\N	f	0	\N
18000	91	232	\N	0	\N	\N	f	0	\N
18001	91	231	\N	0	\N	\N	f	0	\N
18002	91	230	\N	0	\N	\N	f	0	\N
18003	91	229	\N	0	\N	\N	f	0	\N
18004	91	228	\N	0	\N	\N	f	0	\N
18005	91	227	\N	0	\N	\N	f	0	\N
18006	91	226	\N	0	\N	\N	f	0	\N
18007	91	225	\N	0	\N	\N	f	0	\N
18008	91	224	\N	0	\N	\N	f	0	\N
18009	91	223	\N	0	\N	\N	f	0	\N
18010	91	222	\N	0	\N	\N	f	0	\N
18011	91	221	\N	0	\N	\N	f	0	\N
18012	91	220	\N	0	\N	\N	f	0	\N
18013	91	219	\N	0	\N	\N	f	0	\N
18014	91	218	\N	0	\N	\N	f	0	\N
18015	91	217	\N	0	\N	\N	f	0	\N
18016	91	216	\N	0	\N	\N	f	0	\N
18017	91	215	\N	0	\N	\N	f	0	\N
18018	91	214	\N	0	\N	\N	f	0	\N
18019	91	213	\N	0	\N	\N	f	0	\N
18020	91	212	\N	0	\N	\N	f	0	\N
18021	91	211	\N	0	\N	\N	f	0	\N
18022	91	210	\N	0	\N	\N	f	0	\N
18023	91	209	\N	0	\N	\N	f	0	\N
18024	91	208	\N	0	\N	\N	f	0	\N
18025	91	207	\N	0	\N	\N	f	0	\N
18026	91	206	\N	0	\N	\N	f	0	\N
18027	91	205	\N	0	\N	\N	f	0	\N
18028	91	204	\N	0	\N	\N	f	0	\N
18029	91	203	\N	0	\N	\N	f	0	\N
18030	91	202	\N	0	\N	\N	f	0	\N
18031	91	201	\N	0	\N	\N	f	0	\N
18032	91	200	\N	0	\N	\N	f	0	\N
18033	91	199	\N	0	\N	\N	f	0	\N
18034	91	198	\N	0	\N	\N	f	0	\N
18035	91	197	\N	0	\N	\N	f	0	\N
18036	91	196	\N	0	\N	\N	f	0	\N
18037	91	195	\N	0	\N	\N	f	0	\N
18038	91	194	\N	0	\N	\N	f	0	\N
18039	91	193	\N	0	\N	\N	f	0	\N
18040	91	192	\N	0	\N	\N	f	0	\N
18041	91	191	\N	0	\N	\N	f	0	\N
18042	91	190	\N	0	\N	\N	f	0	\N
18043	91	189	\N	0	\N	\N	f	0	\N
18044	91	188	\N	0	\N	\N	f	0	\N
18045	91	187	\N	0	\N	\N	f	0	\N
18046	91	186	\N	0	\N	\N	f	0	\N
18047	91	185	\N	0	\N	\N	f	0	\N
18048	91	184	\N	0	\N	\N	f	0	\N
18049	91	183	\N	0	\N	\N	f	0	\N
18050	91	182	\N	0	\N	\N	f	0	\N
18051	91	181	\N	0	\N	\N	f	0	\N
18052	91	401	\N	0	\N	\N	f	0	\N
18053	91	400	\N	0	\N	\N	f	0	\N
18054	91	399	\N	0	\N	\N	f	0	\N
18055	91	398	\N	0	\N	\N	f	0	\N
18056	91	397	\N	0	\N	\N	f	0	\N
18057	91	396	\N	0	\N	\N	f	0	\N
18058	91	395	\N	0	\N	\N	f	0	\N
18059	91	394	\N	0	\N	\N	f	0	\N
18060	91	393	\N	0	\N	\N	f	0	\N
18061	91	392	\N	0	\N	\N	f	0	\N
18062	91	391	\N	0	\N	\N	f	0	\N
18063	91	390	\N	0	\N	\N	f	0	\N
18064	91	389	\N	0	\N	\N	f	0	\N
18065	91	388	\N	0	\N	\N	f	0	\N
18066	91	387	\N	0	\N	\N	f	0	\N
18067	91	386	\N	0	\N	\N	f	0	\N
18068	91	385	\N	0	\N	\N	f	0	\N
18069	91	384	\N	0	\N	\N	f	0	\N
18070	91	383	\N	0	\N	\N	f	0	\N
18071	91	382	\N	0	\N	\N	f	0	\N
18072	91	381	\N	0	\N	\N	f	0	\N
18073	91	380	\N	0	\N	\N	f	0	\N
18074	91	379	\N	0	\N	\N	f	0	\N
18075	91	378	\N	0	\N	\N	f	0	\N
18076	91	377	\N	0	\N	\N	f	0	\N
18077	91	376	\N	0	\N	\N	f	0	\N
18078	91	375	\N	0	\N	\N	f	0	\N
18079	91	374	\N	0	\N	\N	f	0	\N
18080	91	373	\N	0	\N	\N	f	0	\N
18081	91	372	\N	0	\N	\N	f	0	\N
18082	91	371	\N	0	\N	\N	f	0	\N
18083	91	370	\N	0	\N	\N	f	0	\N
18084	91	369	\N	0	\N	\N	f	0	\N
18085	91	368	\N	0	\N	\N	f	0	\N
18086	91	367	\N	0	\N	\N	f	0	\N
18087	91	366	\N	0	\N	\N	f	0	\N
18088	91	365	\N	0	\N	\N	f	0	\N
18089	91	364	\N	0	\N	\N	f	0	\N
18090	91	363	\N	0	\N	\N	f	0	\N
18091	91	362	\N	0	\N	\N	f	0	\N
18092	91	361	\N	0	\N	\N	f	0	\N
18093	92	109	\N	0	\N	\N	f	0	\N
18094	92	108	\N	0	\N	\N	f	0	\N
18095	92	107	\N	0	\N	\N	f	0	\N
18096	92	106	\N	0	\N	\N	f	0	\N
18097	92	105	\N	0	\N	\N	f	0	\N
18098	92	104	\N	0	\N	\N	f	0	\N
18099	92	103	\N	0	\N	\N	f	0	\N
18100	92	102	\N	0	\N	\N	f	0	\N
18101	92	101	\N	0	\N	\N	f	0	\N
18102	92	100	\N	0	\N	\N	f	0	\N
18103	92	99	\N	0	\N	\N	f	0	\N
18104	92	98	\N	0	\N	\N	f	0	\N
18105	92	97	\N	0	\N	\N	f	0	\N
18106	92	96	\N	0	\N	\N	f	0	\N
18107	92	95	\N	0	\N	\N	f	0	\N
18108	92	94	\N	0	\N	\N	f	0	\N
18109	92	93	\N	0	\N	\N	f	0	\N
18110	92	92	\N	0	\N	\N	f	0	\N
18111	92	91	\N	0	\N	\N	f	0	\N
18112	92	90	\N	0	\N	\N	f	0	\N
18113	92	89	\N	0	\N	\N	f	0	\N
18114	92	88	\N	0	\N	\N	f	0	\N
18115	92	87	\N	0	\N	\N	f	0	\N
18116	92	86	\N	0	\N	\N	f	0	\N
18117	92	85	\N	0	\N	\N	f	0	\N
18118	92	84	\N	0	\N	\N	f	0	\N
18119	92	83	\N	0	\N	\N	f	0	\N
18120	92	82	\N	0	\N	\N	f	0	\N
18121	92	81	\N	0	\N	\N	f	0	\N
18122	92	80	\N	0	\N	\N	f	0	\N
18123	92	79	\N	0	\N	\N	f	0	\N
18124	92	78	\N	0	\N	\N	f	0	\N
18125	92	77	\N	0	\N	\N	f	0	\N
18126	92	76	\N	0	\N	\N	f	0	\N
18127	92	75	\N	0	\N	\N	f	0	\N
18128	92	218	\N	0	\N	\N	f	0	\N
18129	92	217	\N	0	\N	\N	f	0	\N
18130	92	216	\N	0	\N	\N	f	0	\N
18131	92	215	\N	0	\N	\N	f	0	\N
18132	92	214	\N	0	\N	\N	f	0	\N
18133	92	213	\N	0	\N	\N	f	0	\N
18134	92	212	\N	0	\N	\N	f	0	\N
18135	92	211	\N	0	\N	\N	f	0	\N
18136	92	210	\N	0	\N	\N	f	0	\N
18137	92	209	\N	0	\N	\N	f	0	\N
18138	92	208	\N	0	\N	\N	f	0	\N
18139	92	207	\N	0	\N	\N	f	0	\N
18140	92	206	\N	0	\N	\N	f	0	\N
18141	92	205	\N	0	\N	\N	f	0	\N
18142	92	204	\N	0	\N	\N	f	0	\N
18143	92	203	\N	0	\N	\N	f	0	\N
18144	92	202	\N	0	\N	\N	f	0	\N
18145	92	201	\N	0	\N	\N	f	0	\N
18146	92	200	\N	0	\N	\N	f	0	\N
18147	92	199	\N	0	\N	\N	f	0	\N
18148	92	198	\N	0	\N	\N	f	0	\N
18149	92	197	\N	0	\N	\N	f	0	\N
18150	92	196	\N	0	\N	\N	f	0	\N
18151	92	195	\N	0	\N	\N	f	0	\N
18152	92	194	\N	0	\N	\N	f	0	\N
18153	92	193	\N	0	\N	\N	f	0	\N
18154	92	192	\N	0	\N	\N	f	0	\N
18155	92	191	\N	0	\N	\N	f	0	\N
18156	92	190	\N	0	\N	\N	f	0	\N
18157	92	189	\N	0	\N	\N	f	0	\N
18158	92	188	\N	0	\N	\N	f	0	\N
18159	92	187	\N	0	\N	\N	f	0	\N
18160	92	186	\N	0	\N	\N	f	0	\N
18161	92	185	\N	0	\N	\N	f	0	\N
18162	92	184	\N	0	\N	\N	f	0	\N
18163	92	183	\N	0	\N	\N	f	0	\N
18164	92	182	\N	0	\N	\N	f	0	\N
18165	92	181	\N	0	\N	\N	f	0	\N
18166	92	180	\N	0	\N	\N	f	0	\N
18167	92	179	\N	0	\N	\N	f	0	\N
18168	92	178	\N	0	\N	\N	f	0	\N
18169	92	177	\N	0	\N	\N	f	0	\N
18170	92	176	\N	0	\N	\N	f	0	\N
18171	92	175	\N	0	\N	\N	f	0	\N
18172	92	174	\N	0	\N	\N	f	0	\N
18173	92	173	\N	0	\N	\N	f	0	\N
18174	92	172	\N	0	\N	\N	f	0	\N
18175	92	171	\N	0	\N	\N	f	0	\N
18176	92	170	\N	0	\N	\N	f	0	\N
18177	92	169	\N	0	\N	\N	f	0	\N
18178	92	168	\N	0	\N	\N	f	0	\N
18179	92	167	\N	0	\N	\N	f	0	\N
18180	92	166	\N	0	\N	\N	f	0	\N
18181	92	165	\N	0	\N	\N	f	0	\N
18182	92	164	\N	0	\N	\N	f	0	\N
18183	92	163	\N	0	\N	\N	f	0	\N
18184	92	162	\N	0	\N	\N	f	0	\N
18185	92	161	\N	0	\N	\N	f	0	\N
18186	92	160	\N	0	\N	\N	f	0	\N
18187	92	159	\N	0	\N	\N	f	0	\N
18188	92	158	\N	0	\N	\N	f	0	\N
18189	92	157	\N	0	\N	\N	f	0	\N
18190	92	156	\N	0	\N	\N	f	0	\N
18191	92	155	\N	0	\N	\N	f	0	\N
18192	92	154	\N	0	\N	\N	f	0	\N
18193	92	153	\N	0	\N	\N	f	0	\N
18194	92	152	\N	0	\N	\N	f	0	\N
18195	92	151	\N	0	\N	\N	f	0	\N
18196	92	150	\N	0	\N	\N	f	0	\N
18197	92	149	\N	0	\N	\N	f	0	\N
18198	92	148	\N	0	\N	\N	f	0	\N
18199	92	147	\N	0	\N	\N	f	0	\N
18200	92	146	\N	0	\N	\N	f	0	\N
18201	92	290	\N	0	\N	\N	f	0	\N
18202	92	289	\N	0	\N	\N	f	0	\N
18203	92	288	\N	0	\N	\N	f	0	\N
18204	92	287	\N	0	\N	\N	f	0	\N
18205	92	286	\N	0	\N	\N	f	0	\N
18206	92	285	\N	0	\N	\N	f	0	\N
18207	92	284	\N	0	\N	\N	f	0	\N
18208	92	283	\N	0	\N	\N	f	0	\N
18209	92	282	\N	0	\N	\N	f	0	\N
18210	92	281	\N	0	\N	\N	f	0	\N
18211	92	280	\N	0	\N	\N	f	0	\N
18212	92	279	\N	0	\N	\N	f	0	\N
18213	92	278	\N	0	\N	\N	f	0	\N
18214	92	277	\N	0	\N	\N	f	0	\N
18215	92	276	\N	0	\N	\N	f	0	\N
18216	92	275	\N	0	\N	\N	f	0	\N
18217	92	274	\N	0	\N	\N	f	0	\N
18218	92	273	\N	0	\N	\N	f	0	\N
18219	92	272	\N	0	\N	\N	f	0	\N
18220	92	271	\N	0	\N	\N	f	0	\N
18221	92	270	\N	0	\N	\N	f	0	\N
18222	92	269	\N	0	\N	\N	f	0	\N
18223	92	268	\N	0	\N	\N	f	0	\N
18224	92	267	\N	0	\N	\N	f	0	\N
18225	92	266	\N	0	\N	\N	f	0	\N
18226	92	265	\N	0	\N	\N	f	0	\N
18227	92	264	\N	0	\N	\N	f	0	\N
18228	92	263	\N	0	\N	\N	f	0	\N
18229	92	262	\N	0	\N	\N	f	0	\N
18230	92	261	\N	0	\N	\N	f	0	\N
18231	92	260	\N	0	\N	\N	f	0	\N
18232	92	259	\N	0	\N	\N	f	0	\N
18233	92	258	\N	0	\N	\N	f	0	\N
18234	92	257	\N	0	\N	\N	f	0	\N
18235	92	256	\N	0	\N	\N	f	0	\N
18236	92	255	\N	0	\N	\N	f	0	\N
18237	92	254	\N	0	\N	\N	f	0	\N
18238	92	253	\N	0	\N	\N	f	0	\N
18239	92	252	\N	0	\N	\N	f	0	\N
18240	92	251	\N	0	\N	\N	f	0	\N
18241	92	250	\N	0	\N	\N	f	0	\N
18242	92	249	\N	0	\N	\N	f	0	\N
18243	92	248	\N	0	\N	\N	f	0	\N
18244	92	247	\N	0	\N	\N	f	0	\N
18245	92	246	\N	0	\N	\N	f	0	\N
18246	92	245	\N	0	\N	\N	f	0	\N
18247	92	244	\N	0	\N	\N	f	0	\N
18248	92	243	\N	0	\N	\N	f	0	\N
18249	92	242	\N	0	\N	\N	f	0	\N
18250	92	241	\N	0	\N	\N	f	0	\N
18251	92	240	\N	0	\N	\N	f	0	\N
18252	92	239	\N	0	\N	\N	f	0	\N
18253	92	238	\N	0	\N	\N	f	0	\N
18254	92	237	\N	0	\N	\N	f	0	\N
18255	92	236	\N	0	\N	\N	f	0	\N
18256	92	235	\N	0	\N	\N	f	0	\N
18257	92	234	\N	0	\N	\N	f	0	\N
18258	92	233	\N	0	\N	\N	f	0	\N
18259	92	232	\N	0	\N	\N	f	0	\N
18260	92	231	\N	0	\N	\N	f	0	\N
18261	92	230	\N	0	\N	\N	f	0	\N
18262	92	229	\N	0	\N	\N	f	0	\N
18263	92	228	\N	0	\N	\N	f	0	\N
18264	92	227	\N	0	\N	\N	f	0	\N
18265	92	226	\N	0	\N	\N	f	0	\N
18266	92	225	\N	0	\N	\N	f	0	\N
18267	92	224	\N	0	\N	\N	f	0	\N
18268	92	223	\N	0	\N	\N	f	0	\N
18269	92	222	\N	0	\N	\N	f	0	\N
18270	92	221	\N	0	\N	\N	f	0	\N
18271	92	220	\N	0	\N	\N	f	0	\N
18272	92	219	\N	0	\N	\N	f	0	\N
18273	92	74	\N	0	\N	\N	f	0	\N
18274	92	73	\N	0	\N	\N	f	0	\N
18275	92	72	\N	0	\N	\N	f	0	\N
18276	92	71	\N	0	\N	\N	f	0	\N
18277	92	70	\N	0	\N	\N	f	0	\N
18278	92	69	\N	0	\N	\N	f	0	\N
18279	92	68	\N	0	\N	\N	f	0	\N
18280	92	67	\N	0	\N	\N	f	0	\N
18281	92	66	\N	0	\N	\N	f	0	\N
18282	92	65	\N	0	\N	\N	f	0	\N
18283	92	64	\N	0	\N	\N	f	0	\N
18284	92	63	\N	0	\N	\N	f	0	\N
18285	92	62	\N	0	\N	\N	f	0	\N
18286	92	61	\N	0	\N	\N	f	0	\N
18287	92	60	\N	0	\N	\N	f	0	\N
18288	92	59	\N	0	\N	\N	f	0	\N
18289	92	58	\N	0	\N	\N	f	0	\N
18290	92	57	\N	0	\N	\N	f	0	\N
18291	92	56	\N	0	\N	\N	f	0	\N
18292	92	55	\N	0	\N	\N	f	0	\N
18293	92	54	\N	0	\N	\N	f	0	\N
18294	92	53	\N	0	\N	\N	f	0	\N
18295	92	52	\N	0	\N	\N	f	0	\N
18296	92	51	\N	0	\N	\N	f	0	\N
18297	92	50	\N	0	\N	\N	f	0	\N
18298	92	49	\N	0	\N	\N	f	0	\N
18299	92	48	\N	0	\N	\N	f	0	\N
18300	92	47	\N	0	\N	\N	f	0	\N
18301	92	46	\N	0	\N	\N	f	0	\N
18302	92	45	\N	0	\N	\N	f	0	\N
18303	92	44	\N	0	\N	\N	f	0	\N
18304	92	43	\N	0	\N	\N	f	0	\N
18305	92	42	\N	0	\N	\N	f	0	\N
18306	92	41	\N	0	\N	\N	f	0	\N
18307	92	40	\N	0	\N	\N	f	0	\N
18308	92	145	\N	0	\N	\N	f	0	\N
18309	92	144	\N	0	\N	\N	f	0	\N
18310	92	143	\N	0	\N	\N	f	0	\N
18311	92	142	\N	0	\N	\N	f	0	\N
18312	92	141	\N	0	\N	\N	f	0	\N
18313	92	140	\N	0	\N	\N	f	0	\N
18314	92	139	\N	0	\N	\N	f	0	\N
18315	92	138	\N	0	\N	\N	f	0	\N
18316	92	137	\N	0	\N	\N	f	0	\N
18317	92	136	\N	0	\N	\N	f	0	\N
18318	92	135	\N	0	\N	\N	f	0	\N
18319	92	134	\N	0	\N	\N	f	0	\N
18320	92	133	\N	0	\N	\N	f	0	\N
18321	92	132	\N	0	\N	\N	f	0	\N
18322	92	131	\N	0	\N	\N	f	0	\N
18323	92	130	\N	0	\N	\N	f	0	\N
18324	92	129	\N	0	\N	\N	f	0	\N
18325	92	128	\N	0	\N	\N	f	0	\N
18326	92	127	\N	0	\N	\N	f	0	\N
18327	92	126	\N	0	\N	\N	f	0	\N
18328	92	125	\N	0	\N	\N	f	0	\N
18329	92	124	\N	0	\N	\N	f	0	\N
18330	92	123	\N	0	\N	\N	f	0	\N
18331	92	122	\N	0	\N	\N	f	0	\N
18332	92	121	\N	0	\N	\N	f	0	\N
18333	92	120	\N	0	\N	\N	f	0	\N
18334	92	119	\N	0	\N	\N	f	0	\N
18335	92	118	\N	0	\N	\N	f	0	\N
18336	92	117	\N	0	\N	\N	f	0	\N
18337	92	116	\N	0	\N	\N	f	0	\N
18338	92	115	\N	0	\N	\N	f	0	\N
18339	92	114	\N	0	\N	\N	f	0	\N
18340	92	113	\N	0	\N	\N	f	0	\N
18341	92	112	\N	0	\N	\N	f	0	\N
18342	92	111	\N	0	\N	\N	f	0	\N
18343	92	110	\N	0	\N	\N	f	0	\N
18344	92	432	\N	0	\N	\N	f	0	\N
18345	92	431	\N	0	\N	\N	f	0	\N
18346	92	430	\N	0	\N	\N	f	0	\N
18347	92	429	\N	0	\N	\N	f	0	\N
18348	92	428	\N	0	\N	\N	f	0	\N
18349	92	427	\N	0	\N	\N	f	0	\N
18350	92	426	\N	0	\N	\N	f	0	\N
18351	92	425	\N	0	\N	\N	f	0	\N
18352	92	424	\N	0	\N	\N	f	0	\N
18353	92	423	\N	0	\N	\N	f	0	\N
18354	92	422	\N	0	\N	\N	f	0	\N
18355	92	421	\N	0	\N	\N	f	0	\N
18356	92	420	\N	0	\N	\N	f	0	\N
18357	92	419	\N	0	\N	\N	f	0	\N
18358	92	418	\N	0	\N	\N	f	0	\N
18359	92	417	\N	0	\N	\N	f	0	\N
18360	92	416	\N	0	\N	\N	f	0	\N
18361	92	415	\N	0	\N	\N	f	0	\N
18362	92	414	\N	0	\N	\N	f	0	\N
18363	92	413	\N	0	\N	\N	f	0	\N
18364	92	412	\N	0	\N	\N	f	0	\N
18365	92	411	\N	0	\N	\N	f	0	\N
18366	92	410	\N	0	\N	\N	f	0	\N
18367	92	409	\N	0	\N	\N	f	0	\N
18368	92	408	\N	0	\N	\N	f	0	\N
18369	92	407	\N	0	\N	\N	f	0	\N
18370	92	406	\N	0	\N	\N	f	0	\N
18371	92	405	\N	0	\N	\N	f	0	\N
18372	92	404	\N	0	\N	\N	f	0	\N
18373	92	403	\N	0	\N	\N	f	0	\N
18374	92	402	\N	0	\N	\N	f	0	\N
18375	92	323	\N	0	\N	\N	f	0	\N
18376	92	322	\N	0	\N	\N	f	0	\N
18377	92	321	\N	0	\N	\N	f	0	\N
18378	92	320	\N	0	\N	\N	f	0	\N
18379	92	319	\N	0	\N	\N	f	0	\N
18380	92	318	\N	0	\N	\N	f	0	\N
18381	92	317	\N	0	\N	\N	f	0	\N
18382	92	316	\N	0	\N	\N	f	0	\N
18383	92	315	\N	0	\N	\N	f	0	\N
18384	92	314	\N	0	\N	\N	f	0	\N
18385	92	313	\N	0	\N	\N	f	0	\N
18386	92	312	\N	0	\N	\N	f	0	\N
18387	92	311	\N	0	\N	\N	f	0	\N
18388	92	310	\N	0	\N	\N	f	0	\N
18389	92	309	\N	0	\N	\N	f	0	\N
18390	92	308	\N	0	\N	\N	f	0	\N
18391	92	307	\N	0	\N	\N	f	0	\N
18392	92	306	\N	0	\N	\N	f	0	\N
18393	92	305	\N	0	\N	\N	f	0	\N
18394	92	304	\N	0	\N	\N	f	0	\N
18395	92	303	\N	0	\N	\N	f	0	\N
18396	92	302	\N	0	\N	\N	f	0	\N
18397	92	301	\N	0	\N	\N	f	0	\N
18398	92	300	\N	0	\N	\N	f	0	\N
18399	92	299	\N	0	\N	\N	f	0	\N
18400	92	298	\N	0	\N	\N	f	0	\N
18401	92	297	\N	0	\N	\N	f	0	\N
18402	92	296	\N	0	\N	\N	f	0	\N
18403	92	295	\N	0	\N	\N	f	0	\N
18404	92	294	\N	0	\N	\N	f	0	\N
18405	92	293	\N	0	\N	\N	f	0	\N
18406	92	292	\N	0	\N	\N	f	0	\N
18407	92	291	\N	0	\N	\N	f	0	\N
18408	92	360	\N	0	\N	\N	f	0	\N
18409	92	359	\N	0	\N	\N	f	0	\N
18410	92	358	\N	0	\N	\N	f	0	\N
18411	92	357	\N	0	\N	\N	f	0	\N
18412	92	356	\N	0	\N	\N	f	0	\N
18413	92	355	\N	0	\N	\N	f	0	\N
18414	92	354	\N	0	\N	\N	f	0	\N
18415	92	353	\N	0	\N	\N	f	0	\N
18416	92	352	\N	0	\N	\N	f	0	\N
18417	92	351	\N	0	\N	\N	f	0	\N
18418	92	350	\N	0	\N	\N	f	0	\N
18419	92	349	\N	0	\N	\N	f	0	\N
18420	92	348	\N	0	\N	\N	f	0	\N
18421	92	347	\N	0	\N	\N	f	0	\N
18422	92	346	\N	0	\N	\N	f	0	\N
18423	92	345	\N	0	\N	\N	f	0	\N
18424	92	344	\N	0	\N	\N	f	0	\N
18425	92	343	\N	0	\N	\N	f	0	\N
18426	92	342	\N	0	\N	\N	f	0	\N
18427	92	341	\N	0	\N	\N	f	0	\N
18428	92	340	\N	0	\N	\N	f	0	\N
18429	92	339	\N	0	\N	\N	f	0	\N
18430	92	338	\N	0	\N	\N	f	0	\N
18431	92	337	\N	0	\N	\N	f	0	\N
18432	92	336	\N	0	\N	\N	f	0	\N
18433	92	335	\N	0	\N	\N	f	0	\N
18434	92	334	\N	0	\N	\N	f	0	\N
18435	92	333	\N	0	\N	\N	f	0	\N
18436	92	332	\N	0	\N	\N	f	0	\N
18437	92	331	\N	0	\N	\N	f	0	\N
18438	92	330	\N	0	\N	\N	f	0	\N
18439	92	329	\N	0	\N	\N	f	0	\N
18440	92	328	\N	0	\N	\N	f	0	\N
18441	92	327	\N	0	\N	\N	f	0	\N
18442	92	326	\N	0	\N	\N	f	0	\N
18443	92	325	\N	0	\N	\N	f	0	\N
18444	92	324	\N	0	\N	\N	f	0	\N
18445	93	145	\N	0	\N	\N	f	0	\N
18446	93	144	\N	0	\N	\N	f	0	\N
18447	93	143	\N	0	\N	\N	f	0	\N
18448	93	142	\N	0	\N	\N	f	0	\N
18449	93	141	\N	0	\N	\N	f	0	\N
18450	93	140	\N	0	\N	\N	f	0	\N
18451	93	139	\N	0	\N	\N	f	0	\N
18452	93	138	\N	0	\N	\N	f	0	\N
18453	93	137	\N	0	\N	\N	f	0	\N
18454	93	136	\N	0	\N	\N	f	0	\N
18455	93	135	\N	0	\N	\N	f	0	\N
18456	93	134	\N	0	\N	\N	f	0	\N
18457	93	133	\N	0	\N	\N	f	0	\N
18458	93	132	\N	0	\N	\N	f	0	\N
18459	93	131	\N	0	\N	\N	f	0	\N
18460	93	130	\N	0	\N	\N	f	0	\N
18461	93	129	\N	0	\N	\N	f	0	\N
18462	93	128	\N	0	\N	\N	f	0	\N
18463	93	127	\N	0	\N	\N	f	0	\N
18464	93	126	\N	0	\N	\N	f	0	\N
18465	93	125	\N	0	\N	\N	f	0	\N
18466	93	124	\N	0	\N	\N	f	0	\N
18467	93	123	\N	0	\N	\N	f	0	\N
18468	93	122	\N	0	\N	\N	f	0	\N
18469	93	121	\N	0	\N	\N	f	0	\N
18470	93	120	\N	0	\N	\N	f	0	\N
18471	93	119	\N	0	\N	\N	f	0	\N
18472	93	118	\N	0	\N	\N	f	0	\N
18473	93	117	\N	0	\N	\N	f	0	\N
18474	93	116	\N	0	\N	\N	f	0	\N
18475	93	115	\N	0	\N	\N	f	0	\N
18476	93	114	\N	0	\N	\N	f	0	\N
18477	93	113	\N	0	\N	\N	f	0	\N
18478	93	112	\N	0	\N	\N	f	0	\N
18479	93	111	\N	0	\N	\N	f	0	\N
18480	93	110	\N	0	\N	\N	f	0	\N
18481	93	254	\N	0	\N	\N	f	0	\N
18482	93	253	\N	0	\N	\N	f	0	\N
18483	93	252	\N	0	\N	\N	f	0	\N
18484	93	251	\N	0	\N	\N	f	0	\N
18485	93	250	\N	0	\N	\N	f	0	\N
18486	93	249	\N	0	\N	\N	f	0	\N
18487	93	248	\N	0	\N	\N	f	0	\N
18488	93	247	\N	0	\N	\N	f	0	\N
18489	93	246	\N	0	\N	\N	f	0	\N
18490	93	245	\N	0	\N	\N	f	0	\N
18491	93	244	\N	0	\N	\N	f	0	\N
18492	93	243	\N	0	\N	\N	f	0	\N
18493	93	242	\N	0	\N	\N	f	0	\N
18494	93	241	\N	0	\N	\N	f	0	\N
18495	93	240	\N	0	\N	\N	f	0	\N
18496	93	239	\N	0	\N	\N	f	0	\N
18497	93	238	\N	0	\N	\N	f	0	\N
18498	93	237	\N	0	\N	\N	f	0	\N
18499	93	236	\N	0	\N	\N	f	0	\N
18500	93	235	\N	0	\N	\N	f	0	\N
18501	93	234	\N	0	\N	\N	f	0	\N
18502	93	233	\N	0	\N	\N	f	0	\N
18503	93	232	\N	0	\N	\N	f	0	\N
18504	93	231	\N	0	\N	\N	f	0	\N
18505	93	230	\N	0	\N	\N	f	0	\N
18506	93	229	\N	0	\N	\N	f	0	\N
18507	93	228	\N	0	\N	\N	f	0	\N
18508	93	227	\N	0	\N	\N	f	0	\N
18509	93	226	\N	0	\N	\N	f	0	\N
18510	93	225	\N	0	\N	\N	f	0	\N
18511	93	224	\N	0	\N	\N	f	0	\N
18512	93	223	\N	0	\N	\N	f	0	\N
18513	93	222	\N	0	\N	\N	f	0	\N
18514	93	221	\N	0	\N	\N	f	0	\N
18515	93	220	\N	0	\N	\N	f	0	\N
18516	93	219	\N	0	\N	\N	f	0	\N
18517	93	39	\N	0	\N	\N	f	0	\N
18518	93	38	\N	0	\N	\N	f	0	\N
18519	93	37	\N	0	\N	\N	f	0	\N
18520	93	36	\N	0	\N	\N	f	0	\N
18521	93	35	\N	0	\N	\N	f	0	\N
18522	93	34	\N	0	\N	\N	f	0	\N
18523	93	33	\N	0	\N	\N	f	0	\N
18524	93	32	\N	0	\N	\N	f	0	\N
18525	93	31	\N	0	\N	\N	f	0	\N
18526	93	30	\N	0	\N	\N	f	0	\N
18527	93	29	\N	0	\N	\N	f	0	\N
18528	93	28	\N	0	\N	\N	f	0	\N
18529	93	27	\N	0	\N	\N	f	0	\N
18530	93	26	\N	0	\N	\N	f	0	\N
18531	93	25	\N	0	\N	\N	f	0	\N
18532	93	24	\N	0	\N	\N	f	0	\N
18533	93	23	\N	0	\N	\N	f	0	\N
18534	93	22	\N	0	\N	\N	f	0	\N
18535	93	21	\N	0	\N	\N	f	0	\N
18536	93	20	\N	0	\N	\N	f	0	\N
18537	93	19	\N	0	\N	\N	f	0	\N
18538	93	18	\N	0	\N	\N	f	0	\N
18539	93	17	\N	0	\N	\N	f	0	\N
18540	93	16	\N	0	\N	\N	f	0	\N
18541	93	15	\N	0	\N	\N	f	0	\N
18542	93	14	\N	0	\N	\N	f	0	\N
18543	93	13	\N	0	\N	\N	f	0	\N
18544	93	12	\N	0	\N	\N	f	0	\N
18545	93	11	\N	0	\N	\N	f	0	\N
18546	93	10	\N	0	\N	\N	f	0	\N
18547	93	9	\N	0	\N	\N	f	0	\N
18548	93	8	\N	0	\N	\N	f	0	\N
18549	93	7	\N	0	\N	\N	f	0	\N
18550	93	6	\N	0	\N	\N	f	0	\N
18551	93	5	\N	0	\N	\N	f	0	\N
18552	93	4	\N	0	\N	\N	f	0	\N
18553	93	3	\N	0	\N	\N	f	0	\N
18554	93	2	\N	0	\N	\N	f	0	\N
18555	93	1	\N	0	\N	\N	f	0	\N
18556	93	218	\N	0	\N	\N	f	0	\N
18557	93	217	\N	0	\N	\N	f	0	\N
18558	93	216	\N	0	\N	\N	f	0	\N
18559	93	215	\N	0	\N	\N	f	0	\N
18560	93	214	\N	0	\N	\N	f	0	\N
18561	93	213	\N	0	\N	\N	f	0	\N
18562	93	212	\N	0	\N	\N	f	0	\N
18563	93	211	\N	0	\N	\N	f	0	\N
18564	93	210	\N	0	\N	\N	f	0	\N
18565	93	209	\N	0	\N	\N	f	0	\N
18566	93	208	\N	0	\N	\N	f	0	\N
18567	93	207	\N	0	\N	\N	f	0	\N
18568	93	206	\N	0	\N	\N	f	0	\N
18569	93	205	\N	0	\N	\N	f	0	\N
18570	93	204	\N	0	\N	\N	f	0	\N
18571	93	203	\N	0	\N	\N	f	0	\N
18572	93	202	\N	0	\N	\N	f	0	\N
18573	93	201	\N	0	\N	\N	f	0	\N
18574	93	200	\N	0	\N	\N	f	0	\N
18575	93	199	\N	0	\N	\N	f	0	\N
18576	93	198	\N	0	\N	\N	f	0	\N
18577	93	197	\N	0	\N	\N	f	0	\N
18578	93	196	\N	0	\N	\N	f	0	\N
18579	93	195	\N	0	\N	\N	f	0	\N
18580	93	194	\N	0	\N	\N	f	0	\N
18581	93	193	\N	0	\N	\N	f	0	\N
18582	93	192	\N	0	\N	\N	f	0	\N
18583	93	191	\N	0	\N	\N	f	0	\N
18584	93	190	\N	0	\N	\N	f	0	\N
18585	93	189	\N	0	\N	\N	f	0	\N
18586	93	188	\N	0	\N	\N	f	0	\N
18587	93	187	\N	0	\N	\N	f	0	\N
18588	93	186	\N	0	\N	\N	f	0	\N
18589	93	185	\N	0	\N	\N	f	0	\N
18590	93	184	\N	0	\N	\N	f	0	\N
18591	93	183	\N	0	\N	\N	f	0	\N
18592	93	182	\N	0	\N	\N	f	0	\N
18593	93	181	\N	0	\N	\N	f	0	\N
18594	93	109	\N	0	\N	\N	f	0	\N
18595	93	108	\N	0	\N	\N	f	0	\N
18596	93	107	\N	0	\N	\N	f	0	\N
18597	93	106	\N	0	\N	\N	f	0	\N
18598	93	105	\N	0	\N	\N	f	0	\N
18599	93	104	\N	0	\N	\N	f	0	\N
18600	93	103	\N	0	\N	\N	f	0	\N
18601	93	102	\N	0	\N	\N	f	0	\N
18602	93	101	\N	0	\N	\N	f	0	\N
18603	93	100	\N	0	\N	\N	f	0	\N
18604	93	99	\N	0	\N	\N	f	0	\N
18605	93	98	\N	0	\N	\N	f	0	\N
18606	93	97	\N	0	\N	\N	f	0	\N
18607	93	96	\N	0	\N	\N	f	0	\N
18608	93	95	\N	0	\N	\N	f	0	\N
18609	93	94	\N	0	\N	\N	f	0	\N
18610	93	93	\N	0	\N	\N	f	0	\N
18611	93	92	\N	0	\N	\N	f	0	\N
18612	93	91	\N	0	\N	\N	f	0	\N
18613	93	90	\N	0	\N	\N	f	0	\N
18614	93	89	\N	0	\N	\N	f	0	\N
18615	93	88	\N	0	\N	\N	f	0	\N
18616	93	87	\N	0	\N	\N	f	0	\N
18617	93	86	\N	0	\N	\N	f	0	\N
18618	93	85	\N	0	\N	\N	f	0	\N
18619	93	84	\N	0	\N	\N	f	0	\N
18620	93	83	\N	0	\N	\N	f	0	\N
18621	93	82	\N	0	\N	\N	f	0	\N
18622	93	81	\N	0	\N	\N	f	0	\N
18623	93	80	\N	0	\N	\N	f	0	\N
18624	93	79	\N	0	\N	\N	f	0	\N
18625	93	78	\N	0	\N	\N	f	0	\N
18626	93	77	\N	0	\N	\N	f	0	\N
18627	93	76	\N	0	\N	\N	f	0	\N
18628	93	75	\N	0	\N	\N	f	0	\N
18629	93	360	\N	0	\N	\N	f	0	\N
18630	93	359	\N	0	\N	\N	f	0	\N
18631	93	358	\N	0	\N	\N	f	0	\N
18632	93	357	\N	0	\N	\N	f	0	\N
18633	93	356	\N	0	\N	\N	f	0	\N
18634	93	355	\N	0	\N	\N	f	0	\N
18635	93	354	\N	0	\N	\N	f	0	\N
18636	93	353	\N	0	\N	\N	f	0	\N
18637	93	352	\N	0	\N	\N	f	0	\N
18638	93	351	\N	0	\N	\N	f	0	\N
18639	93	350	\N	0	\N	\N	f	0	\N
18640	93	349	\N	0	\N	\N	f	0	\N
18641	93	348	\N	0	\N	\N	f	0	\N
18642	93	347	\N	0	\N	\N	f	0	\N
18643	93	346	\N	0	\N	\N	f	0	\N
18644	93	345	\N	0	\N	\N	f	0	\N
18645	93	344	\N	0	\N	\N	f	0	\N
18646	93	343	\N	0	\N	\N	f	0	\N
18647	93	342	\N	0	\N	\N	f	0	\N
18648	93	341	\N	0	\N	\N	f	0	\N
18649	93	340	\N	0	\N	\N	f	0	\N
18650	93	339	\N	0	\N	\N	f	0	\N
18651	93	338	\N	0	\N	\N	f	0	\N
18652	93	337	\N	0	\N	\N	f	0	\N
18653	93	336	\N	0	\N	\N	f	0	\N
18654	93	335	\N	0	\N	\N	f	0	\N
18655	93	334	\N	0	\N	\N	f	0	\N
18656	93	333	\N	0	\N	\N	f	0	\N
18657	93	332	\N	0	\N	\N	f	0	\N
18658	93	331	\N	0	\N	\N	f	0	\N
18659	93	330	\N	0	\N	\N	f	0	\N
18660	93	329	\N	0	\N	\N	f	0	\N
18661	93	328	\N	0	\N	\N	f	0	\N
18662	93	327	\N	0	\N	\N	f	0	\N
18663	93	326	\N	0	\N	\N	f	0	\N
18664	93	325	\N	0	\N	\N	f	0	\N
18665	93	324	\N	0	\N	\N	f	0	\N
18666	93	432	\N	0	\N	\N	f	0	\N
18667	93	431	\N	0	\N	\N	f	0	\N
18668	93	430	\N	0	\N	\N	f	0	\N
18669	93	429	\N	0	\N	\N	f	0	\N
18670	93	428	\N	0	\N	\N	f	0	\N
18671	93	427	\N	0	\N	\N	f	0	\N
18672	93	426	\N	0	\N	\N	f	0	\N
18673	93	425	\N	0	\N	\N	f	0	\N
18674	93	424	\N	0	\N	\N	f	0	\N
18675	93	423	\N	0	\N	\N	f	0	\N
18676	93	422	\N	0	\N	\N	f	0	\N
18677	93	421	\N	0	\N	\N	f	0	\N
18678	93	420	\N	0	\N	\N	f	0	\N
18679	93	419	\N	0	\N	\N	f	0	\N
18680	93	418	\N	0	\N	\N	f	0	\N
18681	93	417	\N	0	\N	\N	f	0	\N
18682	93	416	\N	0	\N	\N	f	0	\N
18683	93	415	\N	0	\N	\N	f	0	\N
18684	93	414	\N	0	\N	\N	f	0	\N
18685	93	413	\N	0	\N	\N	f	0	\N
18686	93	412	\N	0	\N	\N	f	0	\N
18687	93	411	\N	0	\N	\N	f	0	\N
18688	93	410	\N	0	\N	\N	f	0	\N
18689	93	409	\N	0	\N	\N	f	0	\N
18690	93	408	\N	0	\N	\N	f	0	\N
18691	93	407	\N	0	\N	\N	f	0	\N
18692	93	406	\N	0	\N	\N	f	0	\N
18693	93	405	\N	0	\N	\N	f	0	\N
18694	93	404	\N	0	\N	\N	f	0	\N
18695	93	403	\N	0	\N	\N	f	0	\N
18696	93	402	\N	0	\N	\N	f	0	\N
18697	93	323	\N	0	\N	\N	f	0	\N
18698	93	322	\N	0	\N	\N	f	0	\N
18699	93	321	\N	0	\N	\N	f	0	\N
18700	93	320	\N	0	\N	\N	f	0	\N
18701	93	319	\N	0	\N	\N	f	0	\N
18702	93	318	\N	0	\N	\N	f	0	\N
18703	93	317	\N	0	\N	\N	f	0	\N
18704	93	316	\N	0	\N	\N	f	0	\N
18705	93	315	\N	0	\N	\N	f	0	\N
18706	93	314	\N	0	\N	\N	f	0	\N
18707	93	313	\N	0	\N	\N	f	0	\N
18708	93	312	\N	0	\N	\N	f	0	\N
18709	93	311	\N	0	\N	\N	f	0	\N
18710	93	310	\N	0	\N	\N	f	0	\N
18711	93	309	\N	0	\N	\N	f	0	\N
18712	93	308	\N	0	\N	\N	f	0	\N
18713	93	307	\N	0	\N	\N	f	0	\N
18714	93	306	\N	0	\N	\N	f	0	\N
18715	93	305	\N	0	\N	\N	f	0	\N
18716	93	304	\N	0	\N	\N	f	0	\N
18717	93	303	\N	0	\N	\N	f	0	\N
18718	93	302	\N	0	\N	\N	f	0	\N
18719	93	301	\N	0	\N	\N	f	0	\N
18720	93	300	\N	0	\N	\N	f	0	\N
18721	93	299	\N	0	\N	\N	f	0	\N
18722	93	298	\N	0	\N	\N	f	0	\N
18723	93	297	\N	0	\N	\N	f	0	\N
18724	93	296	\N	0	\N	\N	f	0	\N
18725	93	295	\N	0	\N	\N	f	0	\N
18726	93	294	\N	0	\N	\N	f	0	\N
18727	93	293	\N	0	\N	\N	f	0	\N
18728	93	292	\N	0	\N	\N	f	0	\N
18729	93	291	\N	0	\N	\N	f	0	\N
18730	93	180	\N	0	\N	\N	f	0	\N
18731	93	179	\N	0	\N	\N	f	0	\N
18732	93	178	\N	0	\N	\N	f	0	\N
18733	93	177	\N	0	\N	\N	f	0	\N
18734	93	176	\N	0	\N	\N	f	0	\N
18735	93	175	\N	0	\N	\N	f	0	\N
18736	93	174	\N	0	\N	\N	f	0	\N
18737	93	173	\N	0	\N	\N	f	0	\N
18738	93	172	\N	0	\N	\N	f	0	\N
18739	93	171	\N	0	\N	\N	f	0	\N
18740	93	170	\N	0	\N	\N	f	0	\N
18741	93	169	\N	0	\N	\N	f	0	\N
18742	93	168	\N	0	\N	\N	f	0	\N
18743	93	167	\N	0	\N	\N	f	0	\N
18744	93	166	\N	0	\N	\N	f	0	\N
18745	93	165	\N	0	\N	\N	f	0	\N
18746	93	164	\N	0	\N	\N	f	0	\N
18747	93	163	\N	0	\N	\N	f	0	\N
18748	93	162	\N	0	\N	\N	f	0	\N
18749	93	161	\N	0	\N	\N	f	0	\N
18750	93	160	\N	0	\N	\N	f	0	\N
18751	93	159	\N	0	\N	\N	f	0	\N
18752	93	158	\N	0	\N	\N	f	0	\N
18753	93	157	\N	0	\N	\N	f	0	\N
18754	93	156	\N	0	\N	\N	f	0	\N
18755	93	155	\N	0	\N	\N	f	0	\N
18756	93	154	\N	0	\N	\N	f	0	\N
18757	93	153	\N	0	\N	\N	f	0	\N
18758	93	152	\N	0	\N	\N	f	0	\N
18759	93	151	\N	0	\N	\N	f	0	\N
18760	93	150	\N	0	\N	\N	f	0	\N
18761	93	149	\N	0	\N	\N	f	0	\N
18762	93	148	\N	0	\N	\N	f	0	\N
18763	93	147	\N	0	\N	\N	f	0	\N
18764	93	146	\N	0	\N	\N	f	0	\N
18765	93	74	\N	0	\N	\N	f	0	\N
18766	93	73	\N	0	\N	\N	f	0	\N
18767	93	72	\N	0	\N	\N	f	0	\N
18768	93	71	\N	0	\N	\N	f	0	\N
18769	93	70	\N	0	\N	\N	f	0	\N
18770	93	69	\N	0	\N	\N	f	0	\N
18771	93	68	\N	0	\N	\N	f	0	\N
18772	93	67	\N	0	\N	\N	f	0	\N
18773	93	66	\N	0	\N	\N	f	0	\N
18774	93	65	\N	0	\N	\N	f	0	\N
18775	93	64	\N	0	\N	\N	f	0	\N
18776	93	63	\N	0	\N	\N	f	0	\N
18777	93	62	\N	0	\N	\N	f	0	\N
18778	93	61	\N	0	\N	\N	f	0	\N
18779	93	60	\N	0	\N	\N	f	0	\N
18780	93	59	\N	0	\N	\N	f	0	\N
18781	93	58	\N	0	\N	\N	f	0	\N
18782	93	57	\N	0	\N	\N	f	0	\N
18783	93	56	\N	0	\N	\N	f	0	\N
18784	93	55	\N	0	\N	\N	f	0	\N
18785	93	54	\N	0	\N	\N	f	0	\N
18786	93	53	\N	0	\N	\N	f	0	\N
18787	93	52	\N	0	\N	\N	f	0	\N
18788	93	51	\N	0	\N	\N	f	0	\N
18789	93	50	\N	0	\N	\N	f	0	\N
18790	93	49	\N	0	\N	\N	f	0	\N
18791	93	48	\N	0	\N	\N	f	0	\N
18792	93	47	\N	0	\N	\N	f	0	\N
18793	93	46	\N	0	\N	\N	f	0	\N
18794	93	45	\N	0	\N	\N	f	0	\N
18795	93	44	\N	0	\N	\N	f	0	\N
18796	93	43	\N	0	\N	\N	f	0	\N
18797	93	42	\N	0	\N	\N	f	0	\N
18798	93	41	\N	0	\N	\N	f	0	\N
18799	93	40	\N	0	\N	\N	f	0	\N
18800	93	401	\N	0	\N	\N	f	0	\N
18801	93	400	\N	0	\N	\N	f	0	\N
18802	93	399	\N	0	\N	\N	f	0	\N
18803	93	398	\N	0	\N	\N	f	0	\N
18804	93	397	\N	0	\N	\N	f	0	\N
18805	93	396	\N	0	\N	\N	f	0	\N
18806	93	395	\N	0	\N	\N	f	0	\N
18807	93	394	\N	0	\N	\N	f	0	\N
18808	93	393	\N	0	\N	\N	f	0	\N
18809	93	392	\N	0	\N	\N	f	0	\N
18810	93	391	\N	0	\N	\N	f	0	\N
18811	93	390	\N	0	\N	\N	f	0	\N
18812	93	389	\N	0	\N	\N	f	0	\N
18813	93	388	\N	0	\N	\N	f	0	\N
18814	93	387	\N	0	\N	\N	f	0	\N
18815	93	386	\N	0	\N	\N	f	0	\N
18816	93	385	\N	0	\N	\N	f	0	\N
18817	93	384	\N	0	\N	\N	f	0	\N
18818	93	383	\N	0	\N	\N	f	0	\N
18819	93	382	\N	0	\N	\N	f	0	\N
18820	93	381	\N	0	\N	\N	f	0	\N
18821	93	380	\N	0	\N	\N	f	0	\N
18822	93	379	\N	0	\N	\N	f	0	\N
18823	93	378	\N	0	\N	\N	f	0	\N
18824	93	377	\N	0	\N	\N	f	0	\N
18825	93	376	\N	0	\N	\N	f	0	\N
18826	93	375	\N	0	\N	\N	f	0	\N
18827	93	374	\N	0	\N	\N	f	0	\N
18828	93	373	\N	0	\N	\N	f	0	\N
18829	93	372	\N	0	\N	\N	f	0	\N
18830	93	371	\N	0	\N	\N	f	0	\N
18831	93	370	\N	0	\N	\N	f	0	\N
18832	93	369	\N	0	\N	\N	f	0	\N
18833	93	368	\N	0	\N	\N	f	0	\N
18834	93	367	\N	0	\N	\N	f	0	\N
18835	93	366	\N	0	\N	\N	f	0	\N
18836	93	365	\N	0	\N	\N	f	0	\N
18837	93	364	\N	0	\N	\N	f	0	\N
18838	93	363	\N	0	\N	\N	f	0	\N
18839	93	362	\N	0	\N	\N	f	0	\N
18840	93	361	\N	0	\N	\N	f	0	\N
18841	93	290	\N	0	\N	\N	f	0	\N
18842	93	289	\N	0	\N	\N	f	0	\N
18843	93	288	\N	0	\N	\N	f	0	\N
18844	93	287	\N	0	\N	\N	f	0	\N
18845	93	286	\N	0	\N	\N	f	0	\N
18846	93	285	\N	0	\N	\N	f	0	\N
18847	93	284	\N	0	\N	\N	f	0	\N
18848	93	283	\N	0	\N	\N	f	0	\N
18849	93	282	\N	0	\N	\N	f	0	\N
18850	93	281	\N	0	\N	\N	f	0	\N
18851	93	280	\N	0	\N	\N	f	0	\N
18852	93	279	\N	0	\N	\N	f	0	\N
18853	93	278	\N	0	\N	\N	f	0	\N
18854	93	277	\N	0	\N	\N	f	0	\N
18855	93	276	\N	0	\N	\N	f	0	\N
18856	93	275	\N	0	\N	\N	f	0	\N
18857	93	274	\N	0	\N	\N	f	0	\N
18858	93	273	\N	0	\N	\N	f	0	\N
18859	93	272	\N	0	\N	\N	f	0	\N
18860	93	271	\N	0	\N	\N	f	0	\N
18861	93	270	\N	0	\N	\N	f	0	\N
18862	93	269	\N	0	\N	\N	f	0	\N
18863	93	268	\N	0	\N	\N	f	0	\N
18864	93	267	\N	0	\N	\N	f	0	\N
18865	93	266	\N	0	\N	\N	f	0	\N
18866	93	265	\N	0	\N	\N	f	0	\N
18867	93	264	\N	0	\N	\N	f	0	\N
18868	93	263	\N	0	\N	\N	f	0	\N
18869	93	262	\N	0	\N	\N	f	0	\N
18870	93	261	\N	0	\N	\N	f	0	\N
18871	93	260	\N	0	\N	\N	f	0	\N
18872	93	259	\N	0	\N	\N	f	0	\N
18873	93	258	\N	0	\N	\N	f	0	\N
18874	93	257	\N	0	\N	\N	f	0	\N
18875	93	256	\N	0	\N	\N	f	0	\N
18876	93	255	\N	0	\N	\N	f	0	\N
\.


--
-- Data for Name: markets; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY markets (id, name, shadow_bets, shadow_bet_rate, opened_at, closed_at, created_at, updated_at, published_at, state, total_bets, sport_id, initial_shadow_bets, price_multiplier, started_at) FROM stdin;
1		1000	0.750000	2012-08-04 00:00:00	2012-08-11 00:55:00	2013-09-25 01:34:05.782935	2013-09-25 01:34:05.782936	2012-08-04 00:00:00		0	1	\N	1	2012-08-10 23:25:00
2		1000	0.750000	2012-08-13 00:00:00	2012-08-19 23:55:00	2013-09-25 01:34:05.869208	2013-09-25 01:34:05.869209	2012-08-13 00:00:00		0	1	\N	1	2012-08-19 23:55:00
3		1000	0.750000	2012-09-28 00:00:00	2012-10-05 00:15:00	2013-09-25 01:34:05.890293	2013-09-25 01:34:05.890293	2012-09-28 00:00:00		0	1	\N	1	2012-10-05 00:15:00
4		1000	0.750000	2012-09-17 00:00:00	2012-09-24 00:15:00	2013-09-25 01:34:05.893011	2013-09-25 01:34:05.893012	2012-09-17 00:00:00		0	1	\N	1	2012-09-23 16:55:00
5		1000	0.750000	2012-10-09 00:00:00	2012-10-16 00:25:00	2013-09-25 01:34:06.113295	2013-09-25 01:34:06.113296	2012-10-09 00:00:00		0	1	\N	1	2012-10-16 00:25:00
6		1000	0.750000	2012-10-15 00:00:00	2012-10-22 00:15:00	2013-09-25 01:34:06.137921	2013-09-25 01:34:06.137921	2012-10-15 00:00:00		0	1	\N	1	2012-10-21 16:55:00
7		1000	0.750000	2012-11-27 00:00:00	2012-12-04 01:25:00	2013-09-25 01:34:06.306791	2013-09-25 01:34:06.306792	2012-11-27 00:00:00		0	1	\N	1	2012-12-04 01:25:00
8		1000	0.750000	2012-09-14 00:00:00	2012-09-21 00:15:00	2013-09-25 01:34:06.329495	2013-09-25 01:34:06.329495	2012-09-14 00:00:00		0	1	\N	1	2012-09-21 00:15:00
9		1000	0.750000	2012-09-18 00:00:00	2012-09-25 00:25:00	2013-09-25 01:34:06.331997	2013-09-25 01:34:06.331998	2012-09-18 00:00:00		0	1	\N	1	2012-09-25 00:25:00
10		1000	0.750000	2012-09-24 00:00:00	2012-10-01 00:15:00	2013-09-25 01:34:06.369632	2013-09-25 01:34:06.369632	2012-09-24 00:00:00		0	1	\N	1	2012-09-30 16:55:00
11		1000	0.750000	2012-10-02 00:00:00	2012-10-09 00:25:00	2013-09-25 01:34:06.5887	2013-09-25 01:34:06.5887	2012-10-02 00:00:00		0	1	\N	1	2012-10-09 00:25:00
12		1000	0.750000	2012-10-22 00:00:00	2012-10-29 00:15:00	2013-09-25 01:34:06.610309	2013-09-25 01:34:06.61031	2012-10-22 00:00:00		0	1	\N	1	2012-10-28 16:55:00
13		1000	0.750000	2012-09-11 00:00:00	2012-09-18 00:25:00	2013-09-25 01:34:06.764143	2013-09-25 01:34:06.764144	2012-09-11 00:00:00		0	1	\N	1	2012-09-18 00:25:00
14		1000	0.750000	2012-10-26 00:00:00	2012-11-02 00:15:00	2013-09-25 01:34:06.807362	2013-09-25 01:34:06.807363	2012-10-26 00:00:00		0	1	\N	1	2012-11-02 00:15:00
15		1000	0.750000	2012-12-30 00:00:00	2013-01-06 00:55:00	2013-09-25 01:34:06.810096	2013-09-25 01:34:06.810096	2012-12-30 00:00:00		0	1	\N	1	2013-01-05 21:25:00
16		1000	0.750000	2013-01-06 00:00:00	2013-01-13 00:55:00	2013-09-25 01:34:06.889952	2013-09-25 01:34:06.889952	2013-01-06 00:00:00		0	1	\N	1	2013-01-12 21:25:00
17		1000	0.750000	2012-10-23 00:00:00	2012-10-30 00:25:00	2013-09-25 01:34:06.975993	2013-09-25 01:34:06.975994	2012-10-23 00:00:00		0	1	\N	1	2012-10-30 00:25:00
18		1000	0.750000	2012-11-05 00:00:00	2012-11-12 01:15:00	2013-09-25 01:34:07.001456	2013-09-25 01:34:07.001456	2012-11-05 00:00:00		0	1	\N	1	2012-11-11 17:55:00
19		1000	0.750000	2012-12-17 00:00:00	2012-12-24 01:15:00	2013-09-25 01:34:07.195585	2013-09-25 01:34:07.195585	2012-12-17 00:00:00		0	1	\N	1	2012-12-23 17:55:00
20		1000	0.750000	2012-08-07 00:00:00	2012-08-13 23:55:00	2013-09-25 01:34:07.431292	2013-09-25 01:34:07.431292	2012-08-07 00:00:00		0	1	\N	1	2012-08-13 23:55:00
21		1000	0.750000	2012-09-04 00:00:00	2012-09-11 02:10:00	2013-09-25 01:34:07.433847	2013-09-25 01:34:07.433847	2012-09-04 00:00:00		0	1	\N	1	2012-09-10 22:55:00
22		1000	0.750000	2012-11-06 00:00:00	2012-11-13 01:25:00	2013-09-25 01:34:07.476241	2013-09-25 01:34:07.476242	2012-11-06 00:00:00		0	1	\N	1	2012-11-13 01:25:00
23		1000	0.750000	2012-11-30 00:00:00	2012-12-07 01:15:00	2013-09-25 01:34:07.478841	2013-09-25 01:34:07.478841	2012-11-30 00:00:00		0	1	\N	1	2012-12-07 01:15:00
26		1000	0.750000	2012-11-12 00:00:00	2012-11-19 01:15:00	2013-09-25 01:34:07.762694	2013-09-25 01:34:07.762694	2012-11-12 00:00:00		0	1	\N	1	2012-11-18 17:55:00
27		1000	0.750000	2012-12-04 00:00:00	2012-12-11 01:25:00	2013-09-25 01:34:07.959966	2013-09-25 01:34:07.959967	2012-12-04 00:00:00		0	1	\N	1	2012-12-11 01:25:00
29		1000	0.750000	2012-08-14 00:00:00	2012-08-20 23:55:00	2013-09-25 01:34:08.050152	2013-09-25 01:34:08.050153	2012-08-14 00:00:00		0	1	\N	1	2012-08-20 23:55:00
30		1000	0.750000	2012-11-23 00:00:00	2012-11-30 01:15:00	2013-09-25 01:34:08.073519	2013-09-25 01:34:08.07352	2012-11-23 00:00:00		0	1	\N	1	2012-11-30 01:15:00
31		1000	0.750000	2012-12-16 00:00:00	2012-12-23 01:25:00	2013-09-25 01:34:08.095039	2013-09-25 01:34:08.09504	2012-12-16 00:00:00		0	1	\N	1	2012-12-23 01:25:00
32		1000	0.750000	2012-08-24 00:00:00	2012-08-31 02:55:00	2013-09-25 01:34:08.118602	2013-09-25 01:34:08.118603	2012-08-24 00:00:00		0	1	\N	1	2012-08-30 22:25:00
33		1000	0.750000	2012-09-07 00:00:00	2012-09-14 00:15:00	2013-09-25 01:34:08.330983	2013-09-25 01:34:08.330984	2012-09-07 00:00:00		0	1	\N	1	2012-09-14 00:15:00
34		1000	0.750000	2012-10-16 00:00:00	2012-10-23 00:25:00	2013-09-25 01:34:08.352431	2013-09-25 01:34:08.352432	2012-10-16 00:00:00		0	1	\N	1	2012-10-23 00:25:00
35		1000	0.750000	2012-11-02 00:00:00	2012-11-09 01:15:00	2013-09-25 01:34:08.354983	2013-09-25 01:34:08.354983	2012-11-02 00:00:00		0	1	\N	1	2012-11-09 01:15:00
36		1000	0.750000	2012-08-18 00:00:00	2012-08-24 23:55:00	2013-09-25 01:34:08.378415	2013-09-25 01:34:08.378416	2012-08-18 00:00:00		0	1	\N	1	2012-08-24 23:25:00
37		1000	0.750000	2012-10-08 00:00:00	2012-10-15 00:15:00	2013-09-25 01:34:08.463888	2013-09-25 01:34:08.463889	2012-10-08 00:00:00		0	1	\N	1	2012-10-14 16:55:00
38		1000	0.750000	2012-11-13 00:00:00	2012-11-20 01:25:00	2013-09-25 01:34:08.698122	2013-09-25 01:34:08.698122	2012-11-13 00:00:00		0	1	\N	1	2012-11-20 01:25:00
39		1000	0.750000	2012-08-19 00:00:00	2012-08-25 23:55:00	2013-09-25 01:34:08.723139	2013-09-25 01:34:08.72314	2012-08-19 00:00:00		0	1	\N	1	2012-08-25 19:55:00
40		1000	0.750000	2012-08-17 00:00:00	2012-08-23 23:55:00	2013-09-25 01:34:08.791575	2013-09-25 01:34:08.791575	2012-08-17 00:00:00		0	1	\N	1	2012-08-23 22:55:00
41		1000	0.750000	2012-10-05 00:00:00	2012-10-12 00:15:00	2013-09-25 01:34:08.855206	2013-09-25 01:34:08.855207	2012-10-05 00:00:00		0	1	\N	1	2012-10-12 00:15:00
42		1000	0.750000	2012-12-31 00:00:00	2013-01-06 21:25:00	2013-09-25 01:34:08.857729	2013-09-25 01:34:08.85773	2012-12-31 00:00:00		0	1	\N	1	2013-01-06 17:55:00
43		1000	0.750000	2012-08-03 00:00:00	2012-08-10 00:25:00	2013-09-25 01:34:08.934883	2013-09-25 01:34:08.934883	2012-08-03 00:00:00		0	1	\N	1	2012-08-09 22:55:00
44		1000	0.750000	2012-08-05 00:00:00	2012-08-12 01:55:00	2013-09-25 01:34:09.065817	2013-09-25 01:34:09.065818	2012-08-05 00:00:00		0	1	\N	1	2012-08-11 22:55:00
45		1000	0.750000	2012-08-06 00:00:00	2012-08-12 17:25:00	2013-09-25 01:34:09.107577	2013-09-25 01:34:09.107579	2012-08-06 00:00:00		0	1	\N	1	2012-08-12 17:25:00
46		1000	0.750000	2012-08-23 00:00:00	2012-08-30 00:25:00	2013-09-25 01:34:09.128391	2013-09-25 01:34:09.128391	2012-08-23 00:00:00		0	1	\N	1	2012-08-29 22:55:00
47		1000	0.750000	2012-09-03 00:00:00	2012-09-10 00:15:00	2013-09-25 01:34:09.176282	2013-09-25 01:34:09.176283	2012-09-03 00:00:00		0	1	\N	1	2012-09-09 16:55:00
48		1000	0.750000	2012-10-12 00:00:00	2012-10-19 00:15:00	2013-09-25 01:34:09.394403	2013-09-25 01:34:09.394403	2012-10-12 00:00:00		0	1	\N	1	2012-10-19 00:15:00
49		1000	0.750000	2012-08-30 00:00:00	2012-09-06 00:25:00	2013-09-25 01:34:09.435018	2013-09-25 01:34:09.435018	2012-08-30 00:00:00		0	1	\N	1	2012-09-06 00:25:00
50		1000	0.750000	2012-10-19 00:00:00	2012-10-26 00:15:00	2013-09-25 01:34:09.438878	2013-09-25 01:34:09.438879	2012-10-19 00:00:00		0	1	\N	1	2012-10-26 00:15:00
51		1000	0.750000	2012-11-09 00:00:00	2012-11-16 01:15:00	2013-09-25 01:34:09.459849	2013-09-25 01:34:09.459849	2012-11-09 00:00:00		0	1	\N	1	2012-11-16 01:15:00
52		1000	0.750000	2012-11-20 00:00:00	2012-11-27 01:25:00	2013-09-25 01:34:09.462293	2013-09-25 01:34:09.462293	2012-11-20 00:00:00		0	1	\N	1	2012-11-27 01:25:00
53		1000	0.750000	2012-08-10 00:00:00	2012-08-16 23:55:00	2013-09-25 01:34:09.464823	2013-09-25 01:34:09.464823	2012-08-10 00:00:00		0	1	\N	1	2012-08-16 23:55:00
54		1000	0.750000	2012-08-12 00:00:00	2012-08-19 00:55:00	2013-09-25 01:34:09.527428	2013-09-25 01:34:09.527429	2012-08-12 00:00:00		0	1	\N	1	2012-08-18 22:55:00
55		1000	0.750000	2012-08-20 00:00:00	2012-08-26 23:55:00	2013-09-25 01:34:09.63384	2013-09-25 01:34:09.63384	2012-08-20 00:00:00		0	1	\N	1	2012-08-26 19:55:00
56		1000	0.750000	2012-09-10 00:00:00	2012-09-17 00:15:00	2013-09-25 01:34:09.681216	2013-09-25 01:34:09.681217	2012-09-10 00:00:00		0	1	\N	1	2012-09-16 16:55:00
57		1000	0.750000	2012-09-21 00:00:00	2012-09-28 00:15:00	2013-09-25 01:34:09.878144	2013-09-25 01:34:09.878145	2012-09-21 00:00:00		0	1	\N	1	2012-09-28 00:15:00
58		1000	0.750000	2012-09-25 00:00:00	2012-10-02 00:25:00	2013-09-25 01:34:09.898384	2013-09-25 01:34:09.898384	2012-09-25 00:00:00		0	1	\N	1	2012-10-02 00:25:00
59		1000	0.750000	2012-10-01 00:00:00	2012-10-08 00:15:00	2013-09-25 01:34:09.901027	2013-09-25 01:34:09.901028	2012-10-01 00:00:00		0	1	\N	1	2012-10-07 16:55:00
60		1000	0.750000	2012-10-30 00:00:00	2012-11-06 01:25:00	2013-09-25 01:34:10.1342	2013-09-25 01:34:10.134201	2012-10-30 00:00:00		0	1	\N	1	2012-11-06 01:25:00
61		1000	0.750000	2012-11-16 00:00:00	2012-11-23 01:15:00	2013-09-25 01:34:10.136657	2013-09-25 01:34:10.136658	2012-11-16 00:00:00		0	1	\N	1	2012-11-22 17:25:00
62		1000	0.750000	2012-11-19 00:00:00	2012-11-26 01:15:00	2013-09-25 01:34:10.202839	2013-09-25 01:34:10.20284	2012-11-19 00:00:00		0	1	\N	1	2012-11-25 17:55:00
63		1000	0.750000	2012-12-03 00:00:00	2012-12-10 01:15:00	2013-09-25 01:34:10.396132	2013-09-25 01:34:10.396133	2012-12-03 00:00:00		0	1	\N	1	2012-12-09 17:55:00
64		1000	0.750000	2012-12-07 00:00:00	2012-12-14 01:15:00	2013-09-25 01:34:10.591134	2013-09-25 01:34:10.591134	2012-12-07 00:00:00		0	1	\N	1	2012-12-14 01:15:00
65		1000	0.750000	2013-01-07 00:00:00	2013-01-13 21:25:00	2013-09-25 01:34:10.612219	2013-09-25 01:34:10.61222	2013-01-07 00:00:00		0	1	\N	1	2013-01-13 17:55:00
66		1000	0.750000	2012-08-11 00:00:00	2012-08-18 01:55:00	2013-09-25 01:34:10.691736	2013-09-25 01:34:10.691736	2012-08-11 00:00:00		0	1	\N	1	2012-08-17 23:25:00
67		1000	0.750000	2012-10-29 00:00:00	2012-11-05 01:15:00	2013-09-25 01:34:10.739244	2013-09-25 01:34:10.739244	2012-10-29 00:00:00		0	1	\N	1	2012-11-04 17:55:00
68		1000	0.750000	2012-11-26 00:00:00	2012-12-03 01:15:00	2013-09-25 01:34:10.948812	2013-09-25 01:34:10.948813	2012-11-26 00:00:00		0	1	\N	1	2012-12-02 17:55:00
69		1000	0.750000	2012-12-10 00:00:00	2012-12-17 01:15:00	2013-09-25 01:34:11.163225	2013-09-25 01:34:11.163226	2012-12-10 00:00:00		0	1	\N	1	2012-12-16 17:55:00
70		1000	0.750000	2012-12-11 00:00:00	2012-12-18 01:25:00	2013-09-25 01:34:11.400125	2013-09-25 01:34:11.400126	2012-12-11 00:00:00		0	1	\N	1	2012-12-18 01:25:00
24	Week 17	1000	0.750000	2012-12-24 00:00:00	2012-12-31 01:15:00	2013-09-25 01:34:07.501	2013-09-25 01:34:07.501	2012-12-24 00:00:00		0	1	\N	1	2012-12-30 17:55:00
28	Week 4	1000	0.750000	2013-01-28 00:00:00	2013-02-03 23:25:00	2013-09-25 01:34:08.005	2013-09-25 01:34:08.005	2013-01-28 00:00:00		0	1	\N	1	2013-02-03 23:25:00
72	Week 1	1000	0.750000	2012-08-03 00:00:00	2012-08-13 23:55:00	2013-09-25 01:34:11.488366	2013-09-25 01:34:11.488366	2012-08-03 00:00:00		0	1	\N	1	2012-08-09 22:55:00
73	Week 3	1000	0.750000	2012-08-17 00:00:00	2012-08-26 23:55:00	2013-09-25 01:34:11.747377	2013-09-25 01:34:11.747379	2012-08-17 00:00:00		0	1	\N	1	2012-08-23 22:55:00
74	Week 2	1000	0.750000	2012-09-07 00:00:00	2012-09-18 00:25:00	2013-09-25 01:34:12.005791	2013-09-25 01:34:12.005793	2012-09-07 00:00:00		0	1	\N	1	2012-09-14 00:15:00
75	Week 3	1000	0.750000	2012-09-14 00:00:00	2012-09-25 00:25:00	2013-09-25 01:34:12.263252	2013-09-25 01:34:12.263253	2012-09-14 00:00:00		0	1	\N	1	2012-09-21 00:15:00
76	Week 6	1000	0.750000	2012-10-05 00:00:00	2012-10-16 00:25:00	2013-09-25 01:34:12.521577	2013-09-25 01:34:12.521577	2012-10-05 00:00:00		0	1	\N	1	2012-10-12 00:15:00
77	Week 10	1000	0.750000	2012-11-02 00:00:00	2012-11-13 01:25:00	2013-09-25 01:34:12.776826	2013-09-25 01:34:12.776827	2012-11-02 00:00:00		0	1	\N	1	2012-11-09 01:15:00
78	Week 1	1000	0.750000	2012-12-30 00:00:00	2013-01-06 21:25:00	2013-09-25 01:34:12.99138	2013-09-25 01:34:12.991381	2012-12-30 00:00:00		0	1	\N	1	2013-01-05 21:25:00
79	Week 2	1000	0.750000	2013-01-06 00:00:00	2013-01-13 21:25:00	2013-09-25 01:34:13.146896	2013-09-25 01:34:13.146897	2013-01-06 00:00:00		0	1	\N	1	2013-01-12 21:25:00
25	Week 0	1000	0.750000	2012-07-30 00:00:00	2012-08-05 23:55:00	2013-09-25 01:34:07.76	2013-09-25 01:34:07.76	2012-07-30 00:00:00		0	1	\N	1	2012-08-05 23:55:00
80	Week 2	1000	0.750000	2012-08-10 00:00:00	2012-08-20 23:55:00	2013-09-25 01:34:13.316777	2013-09-25 01:34:13.316778	2012-08-10 00:00:00		0	1	\N	1	2012-08-16 23:55:00
81	Week 4	1000	0.750000	2012-08-23 00:00:00	2012-08-31 02:55:00	2013-09-25 01:34:13.575116	2013-09-25 01:34:13.575117	2012-08-23 00:00:00		0	1	\N	1	2012-08-29 22:55:00
82	Week 7	1000	0.750000	2012-10-12 00:00:00	2012-10-23 00:25:00	2013-09-25 01:34:13.846617	2013-09-25 01:34:13.846618	2012-10-12 00:00:00		0	1	\N	1	2012-10-19 00:15:00
83	Week 13	1000	0.750000	2012-11-23 00:00:00	2012-12-04 01:25:00	2013-09-25 01:34:14.064832	2013-09-25 01:34:14.064833	2012-11-23 00:00:00		0	1	\N	1	2012-11-30 01:15:00
84	Week 15	1000	0.750000	2012-12-07 00:00:00	2012-12-18 01:25:00	2013-09-25 01:34:14.325144	2013-09-25 01:34:14.325145	2012-12-07 00:00:00		0	1	\N	1	2012-12-14 01:15:00
85	Week 16	1000	0.750000	2012-12-16 00:00:00	2012-12-24 01:15:00	2013-09-25 01:34:14.579243	2013-09-25 01:34:14.579244	2012-12-16 00:00:00		0	1	\N	1	2012-12-23 01:25:00
86	Week 4	1000	0.750000	2012-09-21 00:00:00	2012-10-02 00:25:00	2013-09-25 01:34:15.034446	2013-09-25 01:34:15.034447	2012-09-21 00:00:00		0	1	\N	1	2012-09-28 00:15:00
87	Week 11	1000	0.750000	2012-11-09 00:00:00	2012-11-20 01:25:00	2013-09-25 01:34:15.270994	2013-09-25 01:34:15.270995	2012-11-09 00:00:00		0	1	\N	1	2012-11-16 01:15:00
88	Week 14	1000	0.750000	2012-11-30 00:00:00	2012-12-11 01:25:00	2013-09-25 01:34:15.492455	2013-09-25 01:34:15.492456	2012-11-30 00:00:00		0	1	\N	1	2012-12-07 01:15:00
71	Week 3	1000	0.750000	2013-01-14 00:00:00	2013-01-20 23:25:00	2013-09-25 01:34:11.402	2013-09-25 01:34:11.402	2013-01-14 00:00:00		0	1	\N	1	2013-01-20 19:55:00
89	Week 1	1000	0.750000	2012-08-30 00:00:00	2012-09-11 02:10:00	2013-09-25 01:34:15.846664	2013-09-25 01:34:15.846665	2012-08-30 00:00:00		0	1	\N	1	2012-09-06 00:25:00
90	Week 5	1000	0.750000	2012-09-28 00:00:00	2012-10-09 00:25:00	2013-09-25 01:34:16.106262	2013-09-25 01:34:16.106263	2012-09-28 00:00:00		0	1	\N	1	2012-10-05 00:15:00
91	Week 8	1000	0.750000	2012-10-19 00:00:00	2012-10-30 00:25:00	2013-09-25 01:34:16.362132	2013-09-25 01:34:16.362132	2012-10-19 00:00:00		0	1	\N	1	2012-10-26 00:15:00
92	Week 9	1000	0.750000	2012-10-26 00:00:00	2012-11-06 01:25:00	2013-09-25 01:34:16.560287	2013-09-25 01:34:16.560288	2012-10-26 00:00:00		0	1	\N	1	2012-11-02 00:15:00
93	Week 12	1000	0.750000	2012-11-16 00:00:00	2012-11-27 01:25:00	2013-09-25 01:34:16.770693	2013-09-25 01:34:16.770694	2012-11-16 00:00:00		0	1	\N	1	2012-11-22 17:25:00
\.


--
-- Data for Name: oauth2_access_tokens; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY oauth2_access_tokens (id, user_id, client_id, refresh_token_id, token, expires_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: oauth2_authorization_codes; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY oauth2_authorization_codes (id, user_id, client_id, token, expires_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: oauth2_clients; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY oauth2_clients (id, name, redirect_uri, website, identifier, secret, created_at, updated_at) FROM stdin;
1	FairMarketFantasy	localhost:3000	localhost:3000	fairmarketfantasy	f4n7Astic	2013-09-25 08:33:22.186092	2013-09-25 08:33:22.195859
\.


--
-- Data for Name: oauth2_refresh_tokens; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY oauth2_refresh_tokens (id, user_id, client_id, token, expires_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY players (id, stats_id, sport_id, name, name_abbr, birthdate, height, weight, college, "position", jersey_number, status, total_games, total_points, created_at, updated_at, team) FROM stdin;
1	99b8d78e-6d23-4e85-8eef-d286ba5ddc0c	1	Marcus Cannon	M.Cannon	1988-05-06	77	335	Texas Christian	OL	61	ACT	0	0	2013-09-25 01:34:01.759323	2013-09-25 01:34:01.759324	NE
2	600ae879-d95a-4ac4-ae4e-72c05a05f1ad	1	Shane Vereen	S.Vereen	1989-03-02	70	205	California	RB	34	IR	0	0	2013-09-25 01:34:01.763518	2013-09-25 01:34:01.763519	NE
3	2602b60c-31b1-43fd-b507-9b803fbfbc84	1	T.J. Moe	T.Moe		72	200	Missouri	WR	84	IR	0	0	2013-09-25 01:34:01.766676	2013-09-25 01:34:01.766676	NE
4	a527b7db-0b52-4379-9e4c-2e08c1fe1bed	1	Stephen Gostkowski	S.Gostkowski	1984-01-28	73	215	Memphis	K	3	ACT	0	0	2013-09-25 01:34:01.767973	2013-09-25 01:34:01.767974	NE
5	5b0ed7fc-21ed-426f-b8b6-145116cbc9ee	1	Sebastian Vollmer	S.Vollmer	1984-07-10	80	320	Houston	OT	76	ACT	0	0	2013-09-25 01:34:01.769171	2013-09-25 01:34:01.769172	NE
6	f5d20030-d934-45e3-8282-e34c6c83ad84	1	LeGarrette Blount	L.Blount	1986-12-05	72	250	Oregon	RB	29	ACT	0	0	2013-09-25 01:34:01.770376	2013-09-25 01:34:01.770377	NE
7	9d404288-65c5-414f-8ea5-ceb97eccaea0	1	Matt Slater	M.Slater	1985-09-09	72	210	UCLA	WR	18	ACT	0	0	2013-09-25 01:34:01.771606	2013-09-25 01:34:01.771607	NE
8	2bb70d56-a79a-4fa1-ae37-99858a3ffd55	1	Julian Edelman	J.Edelman	1986-05-22	70	198	Kent State	WR	11	ACT	0	0	2013-09-25 01:34:01.772842	2013-09-25 01:34:01.772843	NE
9	2142a164-48ad-47d6-bb27-0bc58c6b2e62	1	Rob Gronkowski	R.Gronkowski	1989-05-14	78	265	Arizona	TE	87	ACT	0	0	2013-09-25 01:34:01.773996	2013-09-25 01:34:01.773996	NE
10	cbe81592-1ee2-4bf1-870a-2578c4c8267e	1	Tavon Wilson	T.Wilson	1990-03-19	72	215	Illinois	DB	27	ACT	0	0	2013-09-25 01:34:01.775205	2013-09-25 01:34:01.775206	NE
11	74e93dc0-514a-4ebe-9fe4-45445f0b4f98	1	Logan Mankins	L.Mankins	1982-03-10	76	308	Fresno State	G	70	ACT	0	0	2013-09-25 01:34:01.776487	2013-09-25 01:34:01.776488	NE
12	23cc596c-3ffa-4ce8-8f59-e8dbba656ada	1	Will Svitek	W.Svitek	1982-01-08	78	310	Stanford	OT	74	ACT	0	0	2013-09-25 01:34:01.777744	2013-09-25 01:34:01.777744	NE
13	170b4c5f-a345-4899-8d81-e8982b0f3d65	1	Stevan Ridley	S.Ridley	1989-01-27	71	220	LSU	RB	22	ACT	0	0	2013-09-25 01:34:01.77905	2013-09-25 01:34:01.779051	NE
14	bd080c6f-c43c-4766-99ea-64f07926ed82	1	Chris Barker	C.Barker	1990-08-03	74	310	Nevada	G	64	ACT	0	0	2013-09-25 01:34:01.780241	2013-09-25 01:34:01.780242	NE
15	93927d6e-9271-4c1e-8239-cc20fd788ba9	1	Nate Ebner	N.Ebner	1988-12-14	72	210	Ohio State	DB	43	ACT	0	0	2013-09-25 01:34:01.781423	2013-09-25 01:34:01.781423	NE
16	10616740-2c72-4207-b8ed-9da09ecba854	1	Ryan Wendell	R.Wendell	1986-03-04	74	300	Fresno State	OL	62	ACT	0	0	2013-09-25 01:34:01.782425	2013-09-25 01:34:01.782426	NE
17	2b4e17f2-27b8-4c98-9b27-1d4c0d7949de	1	Kenbrell Thompkins	K.Thompkins		72	195	Cincinnati	WR	85	ACT	0	0	2013-09-25 01:34:01.783444	2013-09-25 01:34:01.783444	NE
18	44810f37-f2d0-4386-a955-6a77c9c2b043	1	Brice Schwab	B.Schwab	1990-03-27	79	302	Arizona State	T	60	IR	0	0	2013-09-25 01:34:01.78447	2013-09-25 01:34:01.784471	NE
19	b077b3b2-2fed-4c9f-9b8f-c4ff50a4f911	1	Nate Solder	N.Solder	1988-04-12	80	320	Colorado	OT	77	ACT	0	0	2013-09-25 01:34:01.78549	2013-09-25 01:34:01.78549	NE
20	a2802951-e573-4e8f-ad31-14b9ae5f8e7c	1	Duron Harmon	D.Harmon	1991-01-24	73	205	Rutgers	DB	30	ACT	0	0	2013-09-25 01:34:01.786564	2013-09-25 01:34:01.786565	NE
21	566dc8de-b2ab-4796-992e-a0a93e0dcc38	1	Markus Zusevics	M.Zusevics	1989-04-25	77	300	Iowa	T	66	IR	0	0	2013-09-25 01:34:01.78761	2013-09-25 01:34:01.787611	NE
22	41c44740-d0f6-44ab-8347-3b5d515e5ecf	1	Tom Brady	T.Brady	1977-08-03	76	225	Michigan	QB	12	ACT	0	0	2013-09-25 01:34:01.788618	2013-09-25 01:34:01.788618	NE
23	dba5e3ec-2c77-4f65-ad6e-cee246f816ef	1	Brandon Bolden	B.Bolden	1990-01-26	71	220	Mississippi	RB	38	ACT	0	0	2013-09-25 01:34:01.78963	2013-09-25 01:34:01.78963	NE
24	c6555772-de3c-4310-a046-5b6b9faf6580	1	Adrian Wilson	A.Wilson	1979-10-12	75	230	North Carolina State	SAF	24	IR	0	0	2013-09-25 01:34:01.790633	2013-09-25 01:34:01.790633	NE
25	88d2dbf4-3b9f-43ea-bac6-a8722cb24f43	1	Devin McCourty	D.McCourty	1987-08-13	70	195	Rutgers	DB	32	ACT	0	0	2013-09-25 01:34:01.791631	2013-09-25 01:34:01.791631	NE
26	a78b6faa-0606-445c-901b-b79c1f2771bd	1	Leon Washington	L.Washington	1982-08-29	68	192	Florida State	RB	33	ACT	0	0	2013-09-25 01:34:01.79257	2013-09-25 01:34:01.792571	NE
27	b30e620b-1f67-450f-a499-95f59808baac	1	Dan Connolly	D.Connolly	1982-09-02	76	305	Southeast Missouri State	OL	63	ACT	0	0	2013-09-25 01:34:01.793708	2013-09-25 01:34:01.793709	NE
28	1789597d-7344-4afb-bb7d-0d0124b5810a	1	Matthew Mulligan	M.Mulligan	1985-01-18	76	267	Maine	TE	88	ACT	0	0	2013-09-25 01:34:01.794666	2013-09-25 01:34:01.794666	NE
29	9d04accc-a404-406f-b93c-0878410e55a6	1	James Develin	J.Develin	1988-07-23	75	255	Brown	RB	46	ACT	0	0	2013-09-25 01:34:01.795628	2013-09-25 01:34:01.795628	NE
30	3144b871-b1b8-40c5-9a5c-1495d68a1e0a	1	Steve Gregory	S.Gregory	1983-01-08	71	200	Syracuse	SAF	28	ACT	0	0	2013-09-25 01:34:01.796601	2013-09-25 01:34:01.796602	NE
31	f82d4ebb-cda9-4b79-ade0-9ef468d2c101	1	Ryan Mallett	R.Mallett	1988-06-05	78	245	Arkansas	QB	15	ACT	0	0	2013-09-25 01:34:01.797599	2013-09-25 01:34:01.797599	NE
32	5b59a91a-3a9c-4473-b2eb-7673c8ec80b8	1	Josh Boyce	J.Boyce	1990-01-22	71	205	Texas Christian	WR	82	ACT	0	0	2013-09-25 01:34:01.798535	2013-09-25 01:34:01.798535	NE
33	a02fe2cf-3446-4a03-883c-314494087086	1	Zach Sudfeld	Z.Sudfeld	1989-04-17	79	260	Nevada	TE	44	ACT	0	0	2013-09-25 01:34:01.799609	2013-09-25 01:34:01.799609	NE
34	973bfe3c-6d0d-4130-a79c-f860650b1da6	1	Danny Amendola	D.Amendola	1985-11-02	71	195	Texas Tech	WR	80	ACT	0	0	2013-09-25 01:34:01.800589	2013-09-25 01:34:01.80059	NE
35	e35971ad-5efa-44aa-bbb0-b386e126c6de	1	Tyronne Green	T.Green	1986-04-06	74	316	Auburn	G	68	IR	0	0	2013-09-25 01:34:01.80154	2013-09-25 01:34:01.801541	NE
36	ac673b16-3268-43df-a521-4dfd864698cc	1	Aaron Dobson	A.Dobson	1991-06-13	75	200	Marshall	WR	17	ACT	0	0	2013-09-25 01:34:01.802461	2013-09-25 01:34:01.802461	NE
37	bd71e5e9-5b0e-41d0-a55d-076370b129ff	1	Mark Harrison	M.Harrison	1990-12-11	75	230	Rutgers	WR	13	NON	0	0	2013-09-25 01:34:01.803452	2013-09-25 01:34:01.803452	NE
38	add7a245-2444-491f-bdfb-b1b0d76f6a28	1	Michael Hoomanawanui	M.Hoomanawanui	1988-07-04	76	260	Illinois	TE	47	ACT	0	0	2013-09-25 01:34:01.804386	2013-09-25 01:34:01.804386	NE
39	DEF-NE	1	NE Defense	NE		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:01.805399	2013-09-25 01:34:01.805399	NE
40	c5dfc54e-fd64-468f-81a8-073918776412	1	Bernard Pierce	B.Pierce	1990-05-10	72	218	Temple	RB	30	ACT	0	0	2013-09-25 01:34:02.102278	2013-09-25 01:34:02.102279	BAL
41	46bb9a85-523c-4530-95c3-2c2a9737e65f	1	Ed Dickson	E.Dickson	1987-07-25	76	255	Oregon	TE	84	ACT	0	0	2013-09-25 01:34:02.105326	2013-09-25 01:34:02.105327	BAL
42	36e8d27f-0dae-42a9-9d57-f34fbd325a6f	1	Tandon Doss	T.Doss	1989-09-22	74	205	Indiana	WR	17	ACT	0	0	2013-09-25 01:34:02.10673	2013-09-25 01:34:02.106731	BAL
43	7363ca26-1f1d-4706-9b6a-67e8e969eaea	1	Billy Bajema	B.Bajema	1982-10-31	76	259	Oklahoma State	TE	86	ACT	0	0	2013-09-25 01:34:02.108103	2013-09-25 01:34:02.108104	BAL
44	7f3ef024-eb34-46af-8b9e-544cdf09378f	1	Tyrod Taylor	T.Taylor	1989-08-03	73	215	Virginia Tech	QB	2	ACT	0	0	2013-09-25 01:34:02.109458	2013-09-25 01:34:02.109458	BAL
45	5b4b39d4-97e1-4a97-a1e5-764ec6d3bedd	1	Bryant McKinnie	B.McKinnie	1979-09-23	80	360	Miami (FL)	OT	78	ACT	0	0	2013-09-25 01:34:02.110715	2013-09-25 01:34:02.110715	BAL
46	bcce08ec-736e-40c1-bb8d-ebe2d489f331	1	Shaun Draughn	S.Draughn	1987-12-07	72	205	North Carolina	RB	38	ACT	0	0	2013-09-25 01:34:02.113952	2013-09-25 01:34:02.113953	BAL
47	ffec1b11-6b1b-482d-86f0-3bf4f6391dbf	1	Marlon Brown	M.Brown	1991-04-22	77	205	Georgia	WR	14	ACT	0	0	2013-09-25 01:34:02.115254	2013-09-25 01:34:02.115255	BAL
48	50287cd3-afea-47f4-aa56-98a82aa87cf0	1	Ryan Jensen	R.Jensen	1991-05-27	75	304	Colorado State-Pueblo	C	77	ACT	0	0	2013-09-25 01:34:02.116506	2013-09-25 01:34:02.116507	BAL
49	ce4d7d70-307f-4093-bf54-432b8b405eb4	1	Jacoby Jones	J.Jones	1984-07-11	74	212	Lane	WR	12	ACT	0	0	2013-09-25 01:34:02.117852	2013-09-25 01:34:02.117852	BAL
50	c323cdb9-74bc-4d68-9358-609f80eedbb7	1	Deonte Thompson	D.Thompson	1989-02-14	72	200	Florida	WR	83	ACT	0	0	2013-09-25 01:34:02.119064	2013-09-25 01:34:02.119065	BAL
51	f7163bae-d4da-4d38-847e-e0315605b9d0	1	A.Q. Shipley	A.Shipley	1986-05-22	73	309	Penn State	C	68	ACT	0	0	2013-09-25 01:34:02.120273	2013-09-25 01:34:02.120273	BAL
52	4be70f75-f978-4e90-92fd-70927c672931	1	Matt Elam	M.Elam	1991-09-21	70	206	Florida	FS	26	ACT	0	0	2013-09-25 01:34:02.121469	2013-09-25 01:34:02.12147	BAL
53	45fe5280-b366-4c8a-8f2e-99fa5a4ff631	1	Kelechi Osemele	K.Osemele	1989-06-24	77	333	Iowa State	T	72	ACT	0	0	2013-09-25 01:34:02.122687	2013-09-25 01:34:02.122688	BAL
54	cef0560a-22e8-4049-a48f-496328550aa2	1	Michael Huff	M.Huff	1983-03-06	72	211	Texas	SAF	29	ACT	0	0	2013-09-25 01:34:02.123866	2013-09-25 01:34:02.123867	BAL
55	2dff7d82-426e-42d6-8c7c-170ad3a24ad6	1	Rick Wagner	R.Wagner	1989-10-21	78	308	Wisconsin	T	71	ACT	0	0	2013-09-25 01:34:02.125087	2013-09-25 01:34:02.125088	BAL
56	b7b58f9b-49c2-4d68-a331-ed66e901bb40	1	Dallas Clark	D.Clark	1979-06-12	75	252	Iowa	TE	87	ACT	0	0	2013-09-25 01:34:02.126371	2013-09-25 01:34:02.126371	BAL
57	64797df2-efd3-4b27-86ee-1d48f7edb09f	1	Joe Flacco	J.Flacco	1985-01-16	78	245	Delaware	QB	5	ACT	0	0	2013-09-25 01:34:02.127518	2013-09-25 01:34:02.127519	BAL
58	7e3c0631-1bff-49af-b6bc-9c66c59a579d	1	Gino Gradkowski	G.Gradkowski	1988-11-05	75	300	Delaware	G	66	ACT	0	0	2013-09-25 01:34:02.128574	2013-09-25 01:34:02.128574	BAL
59	bf46fb03-b257-413f-af21-6823e00c81b5	1	James Ihedigbo	J.Ihedigbo	1983-12-03	73	214	Massachusetts	SS	32	ACT	0	0	2013-09-25 01:34:02.129614	2013-09-25 01:34:02.129615	BAL
60	67da5b5c-0db9-4fbc-b98d-7eb8e97b69f6	1	Kyle Juszczyk	K.Juszczyk	1991-04-23	73	248	Harvard	FB	40	ACT	0	0	2013-09-25 01:34:02.130634	2013-09-25 01:34:02.130635	BAL
61	f01c7712-3887-458e-8351-1c3e31c67091	1	Christian Thompson	C.Thompson	1990-06-04	72	211	South Carolina State	SAF	33	SUS	0	0	2013-09-25 01:34:02.131644	2013-09-25 01:34:02.131644	BAL
62	20a0bad2-d530-4ff4-a2df-5c0a21a1f5db	1	Justin Tucker	J.Tucker	1989-11-21	72	180	Texas	K	9	ACT	0	0	2013-09-25 01:34:02.132638	2013-09-25 01:34:02.132639	BAL
63	29c9a73e-f66f-437d-8dce-3cbc76aee835	1	Brandon Stokley	B.Stokley	1976-06-23	72	194	Louisiana-Lafayette	WR	80	ACT	0	0	2013-09-25 01:34:02.133634	2013-09-25 01:34:02.133634	BAL
64	fafd2927-7e17-4e85-afa2-aa2c019229ed	1	Marshal Yanda	M.Yanda	1984-09-15	75	315	Iowa	G	73	ACT	0	0	2013-09-25 01:34:02.134619	2013-09-25 01:34:02.134619	BAL
65	4a6ed95c-3cc6-4914-97e4-da2171d7c93b	1	Vonta Leach	V.Leach	1981-11-06	72	260	East Carolina	FB	44	ACT	0	0	2013-09-25 01:34:02.135591	2013-09-25 01:34:02.135591	BAL
66	9e70c666-9371-4659-b075-2d52e303ef4a	1	Jeromy Miles	J.Miles	1987-07-20	74	214	Massachusetts	SAF	0	ACT	0	0	2013-09-25 01:34:02.136506	2013-09-25 01:34:02.136506	BAL
67	e2577abf-7f24-4987-89f5-51676c39c2f6	1	Dennis Pitta	D.Pitta	1985-06-29	76	245	Brigham Young	TE	88	IR	0	0	2013-09-25 01:34:02.137528	2013-09-25 01:34:02.137529	BAL
68	712617bb-3379-46e9-86c6-af1c098e0a72	1	Ray Rice	R.Rice	1987-01-22	68	212	Rutgers	RB	27	ACT	0	0	2013-09-25 01:34:02.138483	2013-09-25 01:34:02.138484	BAL
69	d820c4d6-c312-4318-b528-65fe1b63dfaf	1	Aaron Mellette	A.Mellette	1989-12-28	74	217	Elon	WR	13	IR	0	0	2013-09-25 01:34:02.139435	2013-09-25 01:34:02.139436	BAL
70	98a87efc-1bdd-49fd-8dd1-d03d41e6e374	1	Michael Oher	M.Oher	1986-05-28	76	315	Mississippi	OT	74	ACT	0	0	2013-09-25 01:34:02.140361	2013-09-25 01:34:02.140361	BAL
71	04e8ea8f-8424-4196-a0fd-7dff3740c734	1	Anthony Levine	A.Levine	1987-03-27	71	199	Tennessee State	SAF	41	ACT	0	0	2013-09-25 01:34:02.141295	2013-09-25 01:34:02.141295	BAL
72	a735765c-3ca8-4557-b06e-a30fd415982c	1	Torrey Smith	T.Smith	1989-01-26	72	205	Maryland	WR	82	ACT	0	0	2013-09-25 01:34:02.142223	2013-09-25 01:34:02.142224	BAL
73	a135ab63-8b05-48b0-b0df-98b67c27e10d	1	Jah Reid	J.Reid	1988-07-21	79	335	Central Florida	OT	76	ACT	0	0	2013-09-25 01:34:02.143144	2013-09-25 01:34:02.143145	BAL
74	DEF-BAL	1	BAL Defense	BAL		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:02.144136	2013-09-25 01:34:02.144136	BAL
75	f1ce3e7d-6afc-4db4-94f0-475bd63507b3	1	Andrew Whitworth	A.Whitworth	1981-12-12	79	335	LSU	OT	77	ACT	0	0	2013-09-25 01:34:02.435658	2013-09-25 01:34:02.43566	CIN
76	73e133bf-d3f7-4fda-bd25-2fde66cb8ee1	1	Josh Johnson	J.Johnson	1986-05-15	75	205	San Diego	QB	8	ACT	0	0	2013-09-25 01:34:02.43883	2013-09-25 01:34:02.438831	CIN
77	1a2fbc23-e6db-4d2f-a152-2c774341b7c4	1	Marvin Jones	M.Jones	1990-03-12	74	195	California	WR	82	ACT	0	0	2013-09-25 01:34:02.44058	2013-09-25 01:34:02.440581	CIN
78	f1d063d5-bbcb-43fe-869b-88c26a34523b	1	Dennis Roland	D.Roland	1983-03-10	81	322	Georgia	OT	74	ACT	0	0	2013-09-25 01:34:02.441956	2013-09-25 01:34:02.441957	CIN
79	a877e5f6-37c5-4c7c-9f23-9e3a9f9d0d84	1	Clint Boling	C.Boling	1989-05-09	77	311	Georgia	G	65	ACT	0	0	2013-09-25 01:34:02.443253	2013-09-25 01:34:02.443253	CIN
80	29c7af89-652f-439b-b916-dd8f44d70a22	1	Zac Robinson	Z.Robinson	1986-09-29	75	208	Oklahoma State	QB	5	PUP	0	0	2013-09-25 01:34:02.444488	2013-09-25 01:34:02.444489	CIN
81	17a056be-39c0-4913-bacf-1663f3ac4a56	1	Andre Smith	A.Smith	1987-01-25	76	335	Alabama	OT	71	ACT	0	0	2013-09-25 01:34:02.445674	2013-09-25 01:34:02.445674	CIN
82	24cf6148-f0af-4103-a215-e06956764953	1	Giovani Bernard	G.Bernard	1991-11-22	69	208	North Carolina	RB	25	ACT	0	0	2013-09-25 01:34:02.447	2013-09-25 01:34:02.447001	CIN
83	7f73e63f-6875-4883-9113-baee8fb7bd5c	1	BenJarvus Green-Ellis	B.Green-Ellis	1985-07-02	71	220	Mississippi	RB	42	ACT	0	0	2013-09-25 01:34:02.448247	2013-09-25 01:34:02.448248	CIN
84	e017e12b-07a7-4a35-b837-2faa9ffe3ce8	1	Mike Nugent	M.Nugent	1982-03-02	70	190	Ohio State	K	2	ACT	0	0	2013-09-25 01:34:02.44945	2013-09-25 01:34:02.449451	CIN
85	9ad039f5-fe77-4fa4-8342-e9022ab7d629	1	Kyle Cook	K.Cook	1983-07-25	75	310	Michigan State	C	64	ACT	0	0	2013-09-25 01:34:02.450634	2013-09-25 01:34:02.450635	CIN
86	1726a359-9444-4761-a1f2-cb35ee6fa60e	1	Mohamed Sanu	M.Sanu	1989-08-22	74	210	Rutgers	WR	12	ACT	0	0	2013-09-25 01:34:02.451846	2013-09-25 01:34:02.451847	CIN
87	86d12627-9ee1-42a5-9974-13cea2cb1fe7	1	Mike Pollak	M.Pollak	1985-02-16	75	300	Arizona State	G	67	ACT	0	0	2013-09-25 01:34:02.453121	2013-09-25 01:34:02.453122	CIN
88	4a99b4bf-e03e-4253-8b9b-c070ef796daf	1	Ryan Whalen	R.Whalen	1989-07-26	73	202	Stanford	WR	88	ACT	0	0	2013-09-25 01:34:02.454459	2013-09-25 01:34:02.454459	CIN
89	b44773b9-af17-4d6c-a453-132e20849712	1	Jermaine Gresham	J.Gresham	1988-06-16	77	260	Oklahoma	TE	84	ACT	0	0	2013-09-25 01:34:02.455587	2013-09-25 01:34:02.455587	CIN
90	9029830c-1394-494f-a92c-e192697913cf	1	Reggie Nelson	R.Nelson	1983-09-21	71	210	Florida	SAF	20	ACT	0	0	2013-09-25 01:34:02.457739	2013-09-25 01:34:02.45774	CIN
91	2aa0f66e-52c1-4606-a1ea-242c61c04534	1	Chris Pressley	C.Pressley	1986-08-08	71	256	Wisconsin	FB	36	PUP	0	0	2013-09-25 01:34:02.458833	2013-09-25 01:34:02.458834	CIN
92	1a316ec7-47cc-4cc4-b624-bbbf276da7b9	1	Cedric Peerman	C.Peerman	1986-10-10	70	211	Virginia	RB	30	ACT	0	0	2013-09-25 01:34:02.459882	2013-09-25 01:34:02.459882	CIN
93	14ecf9dd-3a77-4847-8e62-407cd1182f1c	1	Tyler Eifert	T.Eifert	1990-09-08	78	251	Notre Dame	TE	85	ACT	0	0	2013-09-25 01:34:02.460958	2013-09-25 01:34:02.460958	CIN
94	c9e9bbc5-2aeb-4f72-9b7c-1a688fb235fb	1	Shawn Williams	S.Williams	1991-05-13	72	213	Georgia	SS	40	ACT	0	0	2013-09-25 01:34:02.461976	2013-09-25 01:34:02.461977	CIN
95	f6cbde33-a78b-49bf-a41f-112caba8e556	1	Dane Sanzenbacher	D.Sanzenbacher	1988-10-13	71	184	Ohio State	WR	11	ACT	0	0	2013-09-25 01:34:02.463015	2013-09-25 01:34:02.463016	CIN
96	2b9494e4-953a-4aac-afe7-edd2d7be27da	1	George Iloka	G.Iloka	1990-03-31	76	217	Boise State	SAF	43	ACT	0	0	2013-09-25 01:34:02.464024	2013-09-25 01:34:02.464025	CIN
97	1ab63530-c678-4fec-86a5-b8b509abf7b7	1	Trevor Robinson	T.Robinson	1990-05-16	77	300	Notre Dame	G	66	ACT	0	0	2013-09-25 01:34:02.465033	2013-09-25 01:34:02.465034	CIN
98	b6325c85-c313-4cfb-a299-9884d5e9e389	1	Orson Charles	O.Charles	1991-01-27	75	245	Georgia	TE	80	ACT	0	0	2013-09-25 01:34:02.465984	2013-09-25 01:34:02.465985	CIN
99	bd8052bd-0898-430b-99c9-2529e895ae79	1	Rex Burkhead	R.Burkhead	1990-07-02	70	218	Nebraska	RB	33	ACT	0	0	2013-09-25 01:34:02.466923	2013-09-25 01:34:02.466923	CIN
100	3289f9ce-e1d1-40ed-9d3f-242a1712c586	1	Brandon Tate	B.Tate	1987-10-05	73	195	North Carolina	WR	19	ACT	0	0	2013-09-25 01:34:02.467866	2013-09-25 01:34:02.467866	CIN
101	d2a0e5af-3850-4f16-8e40-a0b1d15c2ce1	1	Andy Dalton	A.Dalton	1987-10-29	74	220	Texas Christian	QB	14	ACT	0	0	2013-09-25 01:34:02.468813	2013-09-25 01:34:02.468814	CIN
102	00df8f1d-199c-43a1-a929-849e9c844c8c	1	Anthony Collins	A.Collins	1985-11-02	77	315	Kansas	OT	73	ACT	0	0	2013-09-25 01:34:02.469809	2013-09-25 01:34:02.469809	CIN
103	b3e1206d-38e3-4ad3-be9e-8bf3daa62cad	1	Kevin Zeitler	K.Zeitler	1990-03-08	76	315	Wisconsin	G	68	ACT	0	0	2013-09-25 01:34:02.470798	2013-09-25 01:34:02.470799	CIN
104	c9701373-23f6-4058-9189-8d9c085f3c49	1	A.J. Green	A.Green	1988-07-31	76	207	Georgia	WR	18	ACT	0	0	2013-09-25 01:34:02.471812	2013-09-25 01:34:02.471812	CIN
105	20b3705b-5cc4-4759-9315-d4230b4a7872	1	Tanner Hawkinson	T.Hawkinson		77	300	Kansas	T	72	ACT	0	0	2013-09-25 01:34:02.472763	2013-09-25 01:34:02.472764	CIN
106	049632f6-5a72-473f-9dd9-652a78eeb077	1	Taylor Mays	T.Mays	1988-02-07	75	220	USC	SAF	26	ACT	0	0	2013-09-25 01:34:02.473735	2013-09-25 01:34:02.473736	CIN
107	308cde80-c1e5-46a8-8df4-19a191b49c95	1	Andrew Hawkins	A.Hawkins	1986-03-10	67	180	Toledo	WR	16	IR	0	0	2013-09-25 01:34:02.47469	2013-09-25 01:34:02.47469	CIN
108	55a668a4-8ce1-464b-a686-47eac2e9b9a5	1	Alex Smith	A.Smith	1982-05-22	76	250	Stanford	TE	81	ACT	0	0	2013-09-25 01:34:02.475638	2013-09-25 01:34:02.475638	CIN
109	DEF-CIN	1	CIN Defense	CIN		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:02.476613	2013-09-25 01:34:02.476614	CIN
110	1f09583f-dcc1-43e8-a7fc-f063d2c96508	1	Matt Schaub	M.Schaub	1981-06-25	77	235	Virginia	QB	8	ACT	0	0	2013-09-25 01:34:02.735326	2013-09-25 01:34:02.735327	HOU
111	20170818-32ab-4892-987e-ea75efcd8c4f	1	T.J. Yates	T.Yates	1987-05-28	76	217	North Carolina	QB	13	ACT	0	0	2013-09-25 01:34:02.73821	2013-09-25 01:34:02.738211	HOU
112	044d5384-6a9f-4843-ad3e-909d362381f6	1	Derek Newton	D.Newton	1987-11-16	78	313	Arkansas State	T	75	ACT	0	0	2013-09-25 01:34:02.739506	2013-09-25 01:34:02.739507	HOU
113	5486420b-b40c-4e7c-ab47-9d70b1673c3b	1	D.J. Swearinger	D.Swearinger		70	208	South Carolina	SS	36	ACT	0	0	2013-09-25 01:34:02.740577	2013-09-25 01:34:02.740577	HOU
114	d89d2aef-c383-4ddf-bed8-3761aed35b10	1	Arian Foster	A.Foster	1986-08-24	73	234	Tennessee	RB	23	ACT	0	0	2013-09-25 01:34:02.741587	2013-09-25 01:34:02.741587	HOU
115	9dd8978c-53cc-4bd2-af51-c272618b800a	1	Lestar Jean	L.Jean	1988-02-05	75	202	Florida Atlantic	WR	18	ACT	0	0	2013-09-25 01:34:02.742601	2013-09-25 01:34:02.742601	HOU
116	1b3d350a-478b-4542-a430-d12cc96adc22	1	Case Keenum	C.Keenum	1988-02-17	73	205	Houston	QB	7	ACT	0	0	2013-09-25 01:34:02.743592	2013-09-25 01:34:02.743593	HOU
117	848b34eb-1ca8-435c-a805-957aa71d4883	1	Andre Johnson	A.Johnson	1981-07-11	75	230	Miami (FL)	WR	80	ACT	0	0	2013-09-25 01:34:02.744588	2013-09-25 01:34:02.744589	HOU
118	743f8917-e781-4345-a1ca-0a7d07b91a08	1	Ed Reed	E.Reed	1978-09-11	71	205	Miami (FL)	FS	20	ACT	0	0	2013-09-25 01:34:02.745614	2013-09-25 01:34:02.745614	HOU
119	9fe21c07-823a-47a1-a4dd-0c611c0280c5	1	Brandon Brooks	B.Brooks	1989-08-19	77	335	Miami (OH)	G	79	ACT	0	0	2013-09-25 01:34:02.746586	2013-09-25 01:34:02.746587	HOU
120	4b6a70aa-3123-4ac4-939d-00f81fde0e33	1	Eddie Pleasant	E.Pleasant	1988-12-17	70	210	Oregon	DB	35	ACT	0	0	2013-09-25 01:34:02.747614	2013-09-25 01:34:02.747615	HOU
121	37c05a5b-aead-4e8e-ac3d-47c8570f6a96	1	Cierre Wood	C.Wood	1991-02-21	71	215	Notre Dame	RB	41	ACT	0	0	2013-09-25 01:34:02.748588	2013-09-25 01:34:02.748589	HOU
122	cb1df42c-b59c-4e23-a9a2-fbfc2b39ef71	1	Ryan Griffin	R.Griffin	1990-09-20	78	254	Connecticut	TE	84	ACT	0	0	2013-09-25 01:34:02.749562	2013-09-25 01:34:02.749563	HOU
123	aec7c02c-00c9-4449-a710-5693e7ae1b65	1	Greg Jones	G.Jones	1981-05-09	73	251	Florida State	FB	33	ACT	0	0	2013-09-25 01:34:02.750564	2013-09-25 01:34:02.750564	HOU
124	b180e643-9f63-41ed-b491-ba3c81e48f39	1	Cody White	C.White	1988-07-01	75	303	Illinois State	G	67	ACT	0	0	2013-09-25 01:34:02.751621	2013-09-25 01:34:02.751622	HOU
125	b99a4918-8664-4664-878e-8f583a5e423f	1	Wade Smith	W.Smith	1981-04-26	76	295	Memphis	G	74	ACT	0	0	2013-09-25 01:34:02.752585	2013-09-25 01:34:02.752585	HOU
126	e08060d3-ed70-4d3e-9692-baa92ec1199f	1	Brennan Williams	B.Williams	1991-02-05	78	310	North Carolina	T	73	IR	0	0	2013-09-25 01:34:02.753577	2013-09-25 01:34:02.753578	HOU
127	5c48ade7-4b9a-4757-9643-87a6e3839e2b	1	DeAndre Hopkins	D.Hopkins	1992-06-06	73	218	Clemson	WR	10	ACT	0	0	2013-09-25 01:34:02.754539	2013-09-25 01:34:02.754539	HOU
128	fa9d0178-a2a7-402f-ad11-c7bea0b80705	1	Ben Jones	B.Jones	1989-07-02	74	308	Georgia	C	60	ACT	0	0	2013-09-25 01:34:02.75552	2013-09-25 01:34:02.755521	HOU
129	d2a7d37d-045a-4086-bbee-48d2cfb43a19	1	Alan Bonner	A.Bonner	1990-11-05	70	191	Jacksonville State	WR	16	IR	0	0	2013-09-25 01:34:02.756506	2013-09-25 01:34:02.756507	HOU
130	f26bd260-a1eb-42ab-8768-bc8ad24e4f9e	1	Duane Brown	D.Brown	1985-08-30	76	303	Virginia Tech	OT	76	ACT	0	0	2013-09-25 01:34:02.75744	2013-09-25 01:34:02.75744	HOU
131	9d99148c-0898-4ba1-9454-c5efbdc01f33	1	DeVier Posey	D.Posey	1990-03-15	73	210	Ohio State	WR	11	ACT	0	0	2013-09-25 01:34:02.758386	2013-09-25 01:34:02.758387	HOU
132	496680c4-2432-481b-883c-6f311da3a4a3	1	David Quessenberry	D.Quessenberry	1990-08-24	77	306	San Jose State	T	77	IR	0	0	2013-09-25 01:34:02.759311	2013-09-25 01:34:02.759312	HOU
133	59ae165a-f7ae-4c36-829d-81d031fc3061	1	Garrett Graham	G.Graham	1986-08-04	75	243	Wisconsin	TE	88	ACT	0	0	2013-09-25 01:34:02.761491	2013-09-25 01:34:02.761492	HOU
134	f7b49d9d-2ce4-459f-8065-fa3b52d28069	1	Kareem Jackson	K.Jackson	1988-04-10	70	188	Alabama	DB	25	ACT	0	0	2013-09-25 01:34:02.762514	2013-09-25 01:34:02.762514	HOU
135	3d916bd3-e7f2-4607-9ad7-32e04935fd86	1	Keshawn Martin	K.Martin	1990-03-15	71	194	Michigan State	WR	82	ACT	0	0	2013-09-25 01:34:02.763505	2013-09-25 01:34:02.763506	HOU
136	fc41b323-9ab9-4ea3-ae4f-fb0b3c5a4a8e	1	Alec Lemon	A.Lemon		73	203	Syracuse	WR	17	IR	0	0	2013-09-25 01:34:02.76453	2013-09-25 01:34:02.76453	HOU
137	a1a28375-1dcf-43d5-974f-bd6b42d05875	1	Shiloh Keo	S.Keo	1987-12-17	71	208	Idaho	SAF	31	ACT	0	0	2013-09-25 01:34:02.765495	2013-09-25 01:34:02.765496	HOU
138	75b812dc-cb66-43a8-93b5-b989c5dd073e	1	Andrew Gardner	A.Gardner	1986-04-04	78	308	Georgia Tech	OT	66	ACT	0	0	2013-09-25 01:34:02.766512	2013-09-25 01:34:02.766513	HOU
139	38c79072-f438-4c96-8aff-3981bf399fbd	1	Danieal Manning	D.Manning	1982-08-09	71	212	Abilene Christian	SAF	38	ACT	0	0	2013-09-25 01:34:02.767505	2013-09-25 01:34:02.767506	HOU
140	7e5ce2d0-6487-4a9f-83b6-634886ee78f3	1	Owen Daniels	O.Daniels	1982-11-09	75	249	Wisconsin	TE	81	ACT	0	0	2013-09-25 01:34:02.768511	2013-09-25 01:34:02.768512	HOU
141	c5516d6a-bee1-435e-b45c-73492683e2a5	1	Chris Myers	C.Myers	1981-09-15	76	286	Miami (FL)	C	55	ACT	0	0	2013-09-25 01:34:02.769509	2013-09-25 01:34:02.76951	HOU
142	c7d8781f-b9f6-4e0f-b0b6-29fce3985f3e	1	Randy Bullock	R.Bullock	1989-12-16	69	206	Texas A&M	K	4	ACT	0	0	2013-09-25 01:34:02.770463	2013-09-25 01:34:02.770463	HOU
143	9a8a3b4d-3e5c-4a65-a96e-cb9f0221b0e3	1	Ryan Harris	R.Harris	1985-03-11	77	302	Notre Dame	OT	68	ACT	0	0	2013-09-25 01:34:02.771398	2013-09-25 01:34:02.771399	HOU
144	c8e9990a-9d89-411c-9d99-c0afa7eaef8c	1	Ben Tate	B.Tate	1988-08-21	71	217	Auburn	RB	44	ACT	0	0	2013-09-25 01:34:02.772468	2013-09-25 01:34:02.772469	HOU
145	DEF-HOU	1	HOU Defense	HOU		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:02.773491	2013-09-25 01:34:02.773491	HOU
146	901a3f95-ae8a-4f1f-8321-11ec42b8b198	1	Jeff Linkenbach	J.Linkenbach	1987-06-09	78	325	Cincinnati	OT	72	ACT	0	0	2013-09-25 01:34:03.059233	2013-09-25 01:34:03.059234	IND
147	a766cfd8-0aaf-4935-bd1b-b6f4d7b225f7	1	Justin Anderson	J.Anderson	1988-04-15	77	340	Georgia	G	79	IR	0	0	2013-09-25 01:34:03.062489	2013-09-25 01:34:03.06249	IND
148	7a2612f3-ea18-444c-95ee-f1ca597d6fb0	1	Antoine Bethea	A.Bethea	1984-07-07	71	206	Howard	SAF	41	ACT	0	0	2013-09-25 01:34:03.06424	2013-09-25 01:34:03.064241	IND
149	d552daac-a3c9-42e0-84f9-cbbe42b8be01	1	Gosder Cherilus	G.Cherilus	1984-06-28	79	314	Boston College	OT	78	ACT	0	0	2013-09-25 01:34:03.065579	2013-09-25 01:34:03.06558	IND
150	1bec10bf-8eae-4018-b2a5-2d623e1bbbc1	1	Donald Brown	D.Brown	1987-04-11	70	207	Connecticut	RB	31	ACT	0	0	2013-09-25 01:34:03.066808	2013-09-25 01:34:03.066809	IND
151	1400c086-a5b0-45b1-a0f8-7cdc9e803917	1	Joe Reitz	J.Reitz	1985-08-24	79	323	Western Michigan	G	76	ACT	0	0	2013-09-25 01:34:03.068038	2013-09-25 01:34:03.068038	IND
152	5ae43ebf-f94d-4ce9-8278-84c1df6eb969	1	Donald Thomas	D.Thomas	1985-09-25	76	306	Connecticut	G	66	IR	0	0	2013-09-25 01:34:03.069285	2013-09-25 01:34:03.069286	IND
153	020cf3d6-745a-4418-a3dc-7dda7a86d0bf	1	Trent Richardson	T.Richardson	1991-07-10	69	225	Alabama	RB	34	ACT	0	0	2013-09-25 01:34:03.070518	2013-09-25 01:34:03.070519	IND
154	3a4f8a1f-8425-4109-9ba3-9899f79f2532	1	Vick Ballard	V.Ballard	1990-07-16	70	224	Mississippi State	RB	33	IR	0	0	2013-09-25 01:34:03.071945	2013-09-25 01:34:03.071946	IND
155	b8426cea-f8b9-4061-8d56-e70d1230103e	1	T.Y. Hilton	T.Y.Hilton	1989-11-14	69	179	Florida International	WR	13	ACT	0	0	2013-09-25 01:34:03.073196	2013-09-25 01:34:03.073197	IND
156	34150f4d-5646-4027-a85f-e74ed7eebfca	1	LaRon Landry	L.Landry	1984-10-14	72	226	LSU	SAF	30	ACT	0	0	2013-09-25 01:34:03.074475	2013-09-25 01:34:03.074476	IND
157	cc745cc3-d52a-454b-98c8-ac9155a9405c	1	Dwayne Allen	D.Allen	1990-02-24	75	265	Clemson	TE	83	IR	0	0	2013-09-25 01:34:03.075667	2013-09-25 01:34:03.075668	IND
158	c879fa29-f881-4557-86a2-c9d6cee627a6	1	Dominique Jones	D.Jones	1987-08-15	75	270	Shepherd	TE	46	ACT	0	0	2013-09-25 01:34:03.076836	2013-09-25 01:34:03.076836	IND
159	b28f7867-8f2a-444b-b6d1-3264497bf963	1	Mike McGlynn	M.McGlynn	1985-03-08	76	325	Pittsburgh	OG	75	ACT	0	0	2013-09-25 01:34:03.078049	2013-09-25 01:34:03.078049	IND
160	05f8aa7b-3df8-4091-963d-1d4eabb56fa9	1	Khaled Holmes	K.Holmes	1990-01-19	75	319	USC	C	62	ACT	0	0	2013-09-25 01:34:03.079284	2013-09-25 01:34:03.079284	IND
161	e3181493-6a2a-4e95-aa6f-3fc1ddeb7512	1	Andrew Luck	A.Luck	1989-09-12	76	239	Stanford	QB	12	ACT	0	0	2013-09-25 01:34:03.0805	2013-09-25 01:34:03.0805	IND
162	b565f20f-6fac-4efe-84d3-9082f86da25a	1	Samson Satele	S.Satele	1984-11-29	75	300	Hawaii	C	64	ACT	0	0	2013-09-25 01:34:03.081573	2013-09-25 01:34:03.081574	IND
163	9ecf8040-10f9-4a5c-92da-1b4d77bd6760	1	Adam Vinatieri	A.Vinatieri	1972-12-28	72	208	South Dakota State	K	4	ACT	0	0	2013-09-25 01:34:03.08261	2013-09-25 01:34:03.082611	IND
164	94fc7e6c-8c37-4713-abef-68154ac41d06	1	Reggie Wayne	R.Wayne	1978-11-17	72	200	Miami (FL)	WR	87	ACT	0	0	2013-09-25 01:34:03.083629	2013-09-25 01:34:03.083629	IND
165	bd0fd245-64ec-45ee-ac8d-b0072239ea63	1	Sergio Brown	S.Brown	1988-05-22	74	217	Notre Dame	SAF	38	ACT	0	0	2013-09-25 01:34:03.084643	2013-09-25 01:34:03.084643	IND
166	15b3cceb-1696-49cf-9b7a-bb8f5ad8d32b	1	LaVon Brazill	L.Brazill	1989-03-15	71	194	Ohio	WR	15	SUS	0	0	2013-09-25 01:34:03.085677	2013-09-25 01:34:03.085677	IND
167	9102665d-a658-4264-81c3-b9810776ddf0	1	Coby Fleener	C.Fleener	1988-09-20	78	247	Stanford	TE	80	ACT	0	0	2013-09-25 01:34:03.086707	2013-09-25 01:34:03.086708	IND
168	4d079a3a-eaf1-4a78-961d-4e187f7bfbe8	1	Griff Whalen	G.Whalen	1990-03-01	71	197	Stanford	WR	17	ACT	0	0	2013-09-25 01:34:03.08767	2013-09-25 01:34:03.08767	IND
169	7d8eba61-208d-4d91-86cd-704ad05cb7f4	1	Matt Hasselbeck	M.Hasselbeck	1975-09-25	76	235	Boston College	QB	8	ACT	0	0	2013-09-25 01:34:03.088653	2013-09-25 01:34:03.088653	IND
170	b44fa657-e4ea-4cc8-9581-33740bc417e6	1	Anthony Castonzo	A.Castonzo	1988-08-09	79	307	Boston College	T	74	ACT	0	0	2013-09-25 01:34:03.089585	2013-09-25 01:34:03.089586	IND
171	2db8a161-7b3a-4a3c-b915-c5be5b3cd39b	1	Hugh Thornton	H.Thornton	1991-06-28	75	334	Illinois	G	69	ACT	0	0	2013-09-25 01:34:03.090796	2013-09-25 01:34:03.090797	IND
172	5ea7b90f-1e47-45a7-bfdd-b069d26ee53e	1	David Reed	D.Reed	1987-03-22	72	195	Utah	WR	85	ACT	0	0	2013-09-25 01:34:03.091991	2013-09-25 01:34:03.091992	IND
173	c1bf6448-7cbc-4014-b9ce-6a73e44a5d71	1	Stanley Havili	S.Havili	1987-11-14	72	243	USC	FB	39	ACT	0	0	2013-09-25 01:34:03.0934	2013-09-25 01:34:03.093401	IND
174	3a2134f2-8598-48d8-8874-7c92825424c4	1	Delano Howell	D.Howell	1989-11-17	71	196	Stanford	SAF	26	ACT	0	0	2013-09-25 01:34:03.094624	2013-09-25 01:34:03.094625	IND
175	bd413539-9351-454e-9d61-4e8635d7e9f5	1	Jack Doyle	J.Doyle		78	258	Western Kentucky	TE	84	ACT	0	0	2013-09-25 01:34:03.096098	2013-09-25 01:34:03.096099	IND
176	e8f466ff-4138-4a71-a4f5-dfd1ee6cb2b9	1	Xavier Nixon	X.Nixon	1990-09-17	78	309	Florida	T	0	ACT	0	0	2013-09-25 01:34:03.097735	2013-09-25 01:34:03.097736	IND
177	8f22eb36-5282-407a-b6f9-f9b62e5f7318	1	Ahmad Bradshaw	A.Bradshaw	1986-03-19	70	214	Marshall	RB	44	ACT	0	0	2013-09-25 01:34:03.100117	2013-09-25 01:34:03.100118	IND
178	c456e060-d4d8-46cb-acf4-296edfb4f7bd	1	Darrius Heyward-Bey	D.Heyward-Bey	1987-02-26	74	219	Maryland	WR	81	ACT	0	0	2013-09-25 01:34:03.101611	2013-09-25 01:34:03.101612	IND
179	04c9c78a-dea5-4a9b-b813-4dec898108cf	1	Joe Lefeged	J.Lefeged	1988-06-02	72	204	Rutgers	SAF	35	ACT	0	0	2013-09-25 01:34:03.103038	2013-09-25 01:34:03.103039	IND
180	DEF-IND	1	IND Defense	IND		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:03.104103	2013-09-25 01:34:03.104104	IND
181	f35de60c-6841-4f8a-835e-02ba528be416	1	Eric Decker	E.Decker	1987-03-15	75	214	Minnesota	WR	87	ACT	0	0	2013-09-25 01:34:03.395602	2013-09-25 01:34:03.395603	DEN
182	d7ed32dc-b05b-4a90-b29c-7fcb4527d2c5	1	Knowshon Moreno	K.Moreno	1987-07-16	71	220	Georgia	RB	27	ACT	0	0	2013-09-25 01:34:03.398657	2013-09-25 01:34:03.398658	DEN
183	55f094bf-4d4f-492f-b1de-7c4d6aec66a8	1	Manny Ramirez	M.Ramirez	1983-02-13	75	320	Texas Tech	OG	66	ACT	0	0	2013-09-25 01:34:03.400531	2013-09-25 01:34:03.400532	DEN
184	2ba94880-d59e-4efb-8de9-abb432286614	1	J.D. Walton	J.Walton	1987-03-24	75	305	Baylor	C	50	PUP	0	0	2013-09-25 01:34:03.401812	2013-09-25 01:34:03.401813	DEN
185	67f5e782-f91c-4536-9818-cf4a0e7e821d	1	Matt Prater	M.Prater	1984-08-10	70	195	Central Florida	K	5	ACT	0	0	2013-09-25 01:34:03.403085	2013-09-25 01:34:03.403086	DEN
186	de587dab-dcc9-4e33-8ddf-90f581fae2ec	1	Wes Welker	W.Welker	1981-05-01	69	185	Texas Tech	WR	83	ACT	0	0	2013-09-25 01:34:03.404264	2013-09-25 01:34:03.404264	DEN
187	483242d7-57c0-4d7e-921b-d836df3a0abb	1	Greg Orton	G.Orton	1986-12-07	75	199	Purdue	WR	89	IR	0	0	2013-09-25 01:34:03.405435	2013-09-25 01:34:03.405435	DEN
188	65578d87-d998-4de3-8866-90bbdb43faa9	1	Chris Clark	C.Clark	1985-10-01	77	305	Southern Mississippi	OT	75	ACT	0	0	2013-09-25 01:34:03.406669	2013-09-25 01:34:03.40667	DEN
189	40a19e4d-a6c1-4bee-a7b4-5ed61ae75323	1	Zac Dysert	Z.Dysert	1990-02-08	75	221	Miami (OH)	QB	2	ACT	0	0	2013-09-25 01:34:03.407976	2013-09-25 01:34:03.407977	DEN
190	0f0ff562-af1c-4be8-8011-1f71e8441e00	1	Mike Adams	M.Adams	1981-03-24	71	200	Delaware	SAF	20	ACT	0	0	2013-09-25 01:34:03.409345	2013-09-25 01:34:03.409346	DEN
191	919805f1-5497-43dd-b477-de3b0b835e5e	1	Joel Dreessen	J.Dreessen	1982-07-26	76	245	Colorado State	TE	81	ACT	0	0	2013-09-25 01:34:03.4106	2013-09-25 01:34:03.410601	DEN
192	6d54b233-5b67-4e16-9b4d-7e32f28abd07	1	Rahim Moore	R.Moore	1990-02-11	73	195	UCLA	SAF	26	ACT	0	0	2013-09-25 01:34:03.411796	2013-09-25 01:34:03.411796	DEN
193	87f6826a-f35a-4b49-9673-da54ccb9becd	1	Julius Thomas	J.Thomas	1988-06-27	77	250	Portland State	TE	80	ACT	0	0	2013-09-25 01:34:03.413008	2013-09-25 01:34:03.413009	DEN
194	4fea49d2-1024-4019-8312-d9d3113055cd	1	Quinton Carter	Q.Carter	1988-07-20	73	200	Oklahoma	SAF	28	IR	0	0	2013-09-25 01:34:03.414235	2013-09-25 01:34:03.414236	DEN
195	c3a7ec5c-db82-44ae-ab74-b5220448375a	1	David Bruton	D.Bruton	1987-07-23	74	217	Notre Dame	SAF	30	ACT	0	0	2013-09-25 01:34:03.415422	2013-09-25 01:34:03.415423	DEN
196	aae6d92e-5f28-43ee-b0dc-522e80e99f76	1	Peyton Manning	P.Manning	1976-03-24	77	230	Tennessee	QB	18	ACT	0	0	2013-09-25 01:34:03.416588	2013-09-25 01:34:03.416589	DEN
197	5997e86a-8bee-44ae-b640-7688815e12d7	1	Orlando Franklin	O.Franklin	1987-12-16	79	320	Miami (FL)	OT	74	ACT	0	0	2013-09-25 01:34:03.417784	2013-09-25 01:34:03.417785	DEN
198	2a30e8a3-682d-44d3-80b0-7ced588a9e73	1	Chris Kuper	C.Kuper	1982-12-19	76	303	North Dakota	G	73	ACT	0	0	2013-09-25 01:34:03.418819	2013-09-25 01:34:03.418819	DEN
199	f9c87103-362b-4c00-9453-a0b4dc963a06	1	Steve Vallos	S.Vallos	1983-12-28	75	310	Wake Forest	C	60	ACT	0	0	2013-09-25 01:34:03.419844	2013-09-25 01:34:03.419845	DEN
200	6ef43c53-53d7-4b0f-ad99-17664d663ae8	1	Virgil Green	V.Green	1988-08-03	77	255	Nevada-Reno	TE	85	ACT	0	0	2013-09-25 01:34:03.420837	2013-09-25 01:34:03.420837	DEN
201	2386681b-ea65-4d13-a668-f2dbafe8790e	1	Dan Koppen	D.Koppen	1979-09-12	74	300	Boston College	C	67	IR	0	0	2013-09-25 01:34:03.421961	2013-09-25 01:34:03.421962	DEN
202	a9217999-fa6d-4474-a176-1cf9013224ea	1	Zane Beadles	Z.Beadles	1986-11-19	76	305	Utah	G	68	ACT	0	0	2013-09-25 01:34:03.422979	2013-09-25 01:34:03.42298	DEN
203	c80dc191-dcf3-4adc-a9da-57bc70f75ae6	1	Ryan Clady	R.Clady	1986-09-06	78	315	Boise State	OT	78	IR	0	0	2013-09-25 01:34:03.423988	2013-09-25 01:34:03.423988	DEN
204	b33de0e6-973c-40b3-a9c6-1a7e6cb1b540	1	Justin Boren	J.Boren	1988-04-28	74	315	Ohio State	G	72	IR	0	0	2013-09-25 01:34:03.425002	2013-09-25 01:34:03.425003	DEN
205	81fed5e8-2a1a-4f77-904e-78912a4a91bb	1	Duke Ihenacho	D.Ihenacho	1989-06-16	73	207	San Jose State	SAF	33	ACT	0	0	2013-09-25 01:34:03.426037	2013-09-25 01:34:03.426038	DEN
206	6e024d51-d5fb-40cc-8a07-495f81347ad1	1	Ronnie Hillman	R.Hillman	1991-09-14	70	195	San Diego State	RB	21	ACT	0	0	2013-09-25 01:34:03.427044	2013-09-25 01:34:03.427044	DEN
207	1b102bf3-d9b0-47eb-b862-a0240362bf23	1	Trindon Holliday	T.Holliday	1986-04-27	65	170	LSU	WR	11	ACT	0	0	2013-09-25 01:34:03.428086	2013-09-25 01:34:03.428086	DEN
208	428258ce-f7ac-4e8b-a665-485beb03aa73	1	Omar Bolden	O. Bolden	1988-12-20	70	195	Arizona State	SAF	31	ACT	0	0	2013-09-25 01:34:03.429096	2013-09-25 01:34:03.429096	DEN
209	f7841baa-9284-4c03-b698-442570651c6c	1	C.J. Anderson	C.Anderson	1991-02-10	68	224	California	RB	22	ACT	0	0	2013-09-25 01:34:03.430038	2013-09-25 01:34:03.430038	DEN
210	042f89b0-2442-420f-888a-cb10d188903d	1	Louis Vasquez	L.Vasquez	1987-04-11	77	335	Texas Tech	G	65	ACT	0	0	2013-09-25 01:34:03.430968	2013-09-25 01:34:03.430968	DEN
211	e89bed19-f222-41b6-9b85-cc6cccddcd5b	1	Jacob Tamme	J.Tamme	1985-03-15	75	230	Kentucky	TE	84	ACT	0	0	2013-09-25 01:34:03.431891	2013-09-25 01:34:03.431892	DEN
212	0847010c-9a77-4f0b-9d63-c8b4b224d263	1	Brock Osweiler	B.Osweiler	1990-11-22	80	240	Arizona State	QB	17	ACT	0	0	2013-09-25 01:34:03.432822	2013-09-25 01:34:03.432823	DEN
213	6e444737-a1e1-4ddd-b963-cd6a9496fde0	1	Demaryius Thomas	D.Thomas	1987-12-25	75	229	Georgia Tech	WR	88	ACT	0	0	2013-09-25 01:34:03.433745	2013-09-25 01:34:03.433746	DEN
214	fbcbda6b-3c05-4c8e-82f8-e5e851262a07	1	Andre Caldwell	A.Caldwell	1985-04-15	72	200	Florida	WR	12	ACT	0	0	2013-09-25 01:34:03.434679	2013-09-25 01:34:03.43468	DEN
215	e1156c37-6175-4a40-a4d1-8a5b77f9da28	1	Montee Ball	M.Ball	1990-12-05	70	215	Wisconsin	RB	28	ACT	0	0	2013-09-25 01:34:03.435597	2013-09-25 01:34:03.435598	DEN
216	a8ce5cf5-78ce-4204-8030-5fbab0c0ad34	1	Winston Justice	W.Justice	1984-09-14	78	317	USC	OT	77	ACT	0	0	2013-09-25 01:34:03.436531	2013-09-25 01:34:03.436531	DEN
217	53f7e9ec-9819-4364-9875-a987a190f098	1	John Moffitt	J.Moffitt	1986-10-28	76	319	Wisconsin	G	72	ACT	0	0	2013-09-25 01:34:03.43745	2013-09-25 01:34:03.43745	DEN
218	DEF-DEN	1	DEN Defense	DEN		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:03.438322	2013-09-25 01:34:03.438322	DEN
219	bd10efdf-d8e7-4e23-ab1a-1e42fb65131b	1	Alfred Morris	A.Morris	1988-12-12	70	218	Florida Atlantic	RB	46	ACT	0	0	2013-09-25 01:34:03.854375	2013-09-25 01:34:03.854376	WAS
220	dfbf3f25-3c42-484e-8859-16b159c0146c	1	Phillip Thomas	P.Thomas	1989-03-01	72	208	Fresno State	SS	41	IR	0	0	2013-09-25 01:34:03.857756	2013-09-25 01:34:03.85776	WAS
221	a25feaa2-93f5-4236-9d07-696b371af3d6	1	Chris Chester	C.Chester	1983-01-12	75	309	Oklahoma	G	66	ACT	0	0	2013-09-25 01:34:03.859582	2013-09-25 01:34:03.859583	WAS
222	3c551b79-cd83-475b-924a-20c63c901947	1	Jordan Pugh	J.Pugh	1988-01-29	71	210	Texas A&M	SAF	32	ACT	0	0	2013-09-25 01:34:03.861009	2013-09-25 01:34:03.86101	WAS
223	f0fff5db-14db-45b8-8956-7f59b62c14b2	1	Dezmon Briscoe	D.Briscoe	1989-08-31	74	210	Kansas	WR	19	IR	0	0	2013-09-25 01:34:03.862263	2013-09-25 01:34:03.862264	WAS
224	8cef3644-bd81-4645-b5d0-0a15ea8d6548	1	Santana Moss	S.Moss	1979-06-01	70	189	Miami (FL)	WR	89	ACT	0	0	2013-09-25 01:34:03.863468	2013-09-25 01:34:03.863469	WAS
225	7f7b2a5a-be4e-40d1-9cd0-9a7dd225a8c0	1	Kory Lichtensteiger	K.Lichtensteiger	1985-03-22	74	284	Bowling Green State	G	78	ACT	0	0	2013-09-25 01:34:03.864709	2013-09-25 01:34:03.864709	WAS
226	1133c99a-972c-440e-a969-95c46565d033	1	Will Montgomery	W.Montgomery	1983-02-13	75	304	Virginia Tech	C	63	ACT	0	0	2013-09-25 01:34:03.865897	2013-09-25 01:34:03.865897	WAS
227	b070601c-7985-4a1c-b71a-9f72bb5dbc59	1	Trent Williams	T.Williams	1988-07-19	77	328	Oklahoma	OT	71	ACT	0	0	2013-09-25 01:34:03.867094	2013-09-25 01:34:03.867094	WAS
228	e174b76d-323a-41c5-be68-e766aa060d5c	1	Darrel Young	D.Young	1987-04-08	71	251	Villanova	FB	36	ACT	0	0	2013-09-25 01:34:03.868273	2013-09-25 01:34:03.868273	WAS
229	7964133e-9987-4a74-a700-afe2dbe2a62a	1	Reed Doughty	R.Doughty	1982-11-04	73	206	Northern Colorado	SAF	37	ACT	0	0	2013-09-25 01:34:03.869449	2013-09-25 01:34:03.86945	WAS
230	8b5b9714-9533-4c7d-aa30-3ad3da3452aa	1	Rex Grossman	R.Grossman	1980-08-23	73	225	Florida	QB	8	ACT	0	0	2013-09-25 01:34:03.870627	2013-09-25 01:34:03.870627	WAS
231	38f5843a-8318-4eb7-b517-c83d415e77a4	1	Niles Paul	N.Paul	1989-08-09	73	233	Nebraska	WR	84	ACT	0	0	2013-09-25 01:34:03.871768	2013-09-25 01:34:03.871768	WAS
232	e461d721-5ca5-4896-8fe5-12e452a003b3	1	Josh Leribeus	J.Leribeus	1989-07-02	75	315	Southern Methodist	G	67	ACT	0	0	2013-09-25 01:34:03.872863	2013-09-25 01:34:03.872863	WAS
233	5514afb6-bd43-49a8-9bf7-b8baaaecdabe	1	Kai Forbath	K.Forbath	1987-09-02	71	197	UCLA	K	2	ACT	0	0	2013-09-25 01:34:03.873862	2013-09-25 01:34:03.873864	WAS
234	675c0338-159b-403b-8d62-39356e193519	1	Fred Davis	F.Davis	1986-01-15	76	247	USC	TE	83	ACT	0	0	2013-09-25 01:34:03.875007	2013-09-25 01:34:03.875007	WAS
235	32e4b488-5109-4186-963e-ce7907dfc9e1	1	Brandon Meriweather	B.Meriweather	1984-01-14	71	197	Miami (FL)	FS	31	ACT	0	0	2013-09-25 01:34:03.876162	2013-09-25 01:34:03.876163	WAS
236	bbd0942c-6f77-4f83-a6d0-66ec6548019e	1	Kirk Cousins	K.Cousins	1988-08-19	75	209	Michigan State	QB	12	ACT	0	0	2013-09-25 01:34:03.877325	2013-09-25 01:34:03.877325	WAS
237	455347a8-81f8-477b-908d-4e22a71723ae	1	Roy Helu	R.Helu	1988-12-07	71	215	Nebraska	RB	29	ACT	0	0	2013-09-25 01:34:03.878393	2013-09-25 01:34:03.878394	WAS
238	5f39061b-a32f-4b8a-b8d5-3e26afffd723	1	John Potter	J.Potter	1990-01-24	73	219	Western Michigan	K	1	ACT	0	0	2013-09-25 01:34:03.879445	2013-09-25 01:34:03.879445	WAS
239	9798d4cd-516f-4b1a-b388-cafe570db95b	1	Tyler Polumbus	T.Polumbus	1985-04-10	80	305	Colorado	OT	74	ACT	0	0	2013-09-25 01:34:03.880497	2013-09-25 01:34:03.880498	WAS
240	0cb97421-cccf-4cce-ac0f-92d47986defc	1	Adam Gettis	A.Gettis	1988-12-09	74	292	Iowa	G	73	ACT	0	0	2013-09-25 01:34:03.88156	2013-09-25 01:34:03.88156	WAS
241	81c637e8-8f81-4455-887c-9763f1d18b15	1	Bacarri Rambo	B.Rambo	1990-06-27	72	211	Georgia	SS	24	ACT	0	0	2013-09-25 01:34:03.882623	2013-09-25 01:34:03.882624	WAS
242	0366fd06-19a3-4b69-8448-6bfbfad1250b	1	Chris Thompson	C.Thompson	1990-10-20	67	192	Florida State	RB	25	ACT	0	0	2013-09-25 01:34:03.883672	2013-09-25 01:34:03.883672	WAS
243	ad83d795-455f-4f3e-bdad-bf4fa7b6eabc	1	Josh Morgan	J.Morgan	1985-06-20	73	220	Virginia Tech	WR	15	ACT	0	0	2013-09-25 01:34:03.884682	2013-09-25 01:34:03.884683	WAS
244	c3bf8d3e-3b2e-4f9e-ad74-c0a684035f17	1	Jordan Reed	J.Reed	1990-07-03	74	236	Florida	TE	86	ACT	0	0	2013-09-25 01:34:03.885624	2013-09-25 01:34:03.885624	WAS
245	8dfb370d-460c-4bfc-9d62-888687248783	1	Robert Griffin III	R.Griffin III	1990-02-12	74	217	Baylor	QB	10	ACT	0	0	2013-09-25 01:34:03.886617	2013-09-25 01:34:03.886618	WAS
246	1c1f0577-f9c7-4406-b2ab-b9e42ddb1af3	1	Tom Compton	T.Compton	1989-05-10	78	314	South Dakota	T	68	ACT	0	0	2013-09-25 01:34:03.887621	2013-09-25 01:34:03.887621	WAS
247	f60331a0-29ac-4cde-96c7-270154ff7d48	1	Evan Royster	E.Royster	1987-11-26	72	216	Penn State	RB	22	ACT	0	0	2013-09-25 01:34:03.888592	2013-09-25 01:34:03.888593	WAS
248	a824d9ff-12a4-4ed2-812d-404b0b4e52f9	1	Pierre Garcon	P.Garcon	1986-08-08	72	212	Mount Union	WR	88	ACT	0	0	2013-09-25 01:34:03.889552	2013-09-25 01:34:03.889553	WAS
249	34d11cb2-9493-47a3-8085-aee23542cc79	1	Jose Gumbs	J.Gumbs	1988-04-20	70	210	Monmouth (N.J.)	SAF	48	ACT	0	0	2013-09-25 01:34:03.890573	2013-09-25 01:34:03.890573	WAS
250	b030b668-0f41-484f-8e94-9fc576b8af63	1	Aldrick Robinson	A.Robinson	1988-09-24	70	181	Southern Methodist	WR	11	ACT	0	0	2013-09-25 01:34:03.891653	2013-09-25 01:34:03.891654	WAS
251	7fdb82e6-e6db-4314-820a-633351a8675a	1	Maurice Hurt	M.Hurt	1987-09-08	75	329	Florida	G	79	PUP	0	0	2013-09-25 01:34:03.892664	2013-09-25 01:34:03.892664	WAS
252	7877c393-beb4-4f40-a6c5-d864ca6e5172	1	Leonard Hankerson	L.Hankerson	1989-01-30	74	211	Miami (FL)	WR	85	ACT	0	0	2013-09-25 01:34:03.893757	2013-09-25 01:34:03.893757	WAS
253	518c96c5-65bb-4559-8074-9cdb2ca32f99	1	Logan Paulsen	L.Paulsen	1987-02-26	77	261	UCLA	TE	82	ACT	0	0	2013-09-25 01:34:03.894839	2013-09-25 01:34:03.89484	WAS
254	DEF-WAS	1	WAS Defense	WAS		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:03.895825	2013-09-25 01:34:03.895825	WAS
255	651366dc-4297-484d-9e20-308c3bbca8b8	1	Ryan Taylor	R.Taylor	1987-11-16	75	254	North Carolina	TE	82	ACT	0	0	2013-09-25 01:34:04.280285	2013-09-25 01:34:04.280287	GB
256	4cf02857-f50c-4a6f-b94d-ff12d8f701b0	1	Don Barclay	D.Barclay	1989-04-18	76	305	West Virginia	G	67	ACT	0	0	2013-09-25 01:34:04.283674	2013-09-25 01:34:04.283675	GB
257	409377a4-293c-4eee-a9d1-02a46449a540	1	Morgan Burnett	M.Burnett	1989-01-13	73	209	Georgia Tech	SAF	42	ACT	0	0	2013-09-25 01:34:04.285454	2013-09-25 01:34:04.285455	GB
258	b5584569-4a6d-4739-a810-eec2b5edeea4	1	James Jones	J.Jones	1984-03-31	73	208	San Jose State	WR	89	ACT	0	0	2013-09-25 01:34:04.286725	2013-09-25 01:34:04.286726	GB
259	e0856548-6fd5-4f83-9aa0-91f1bf4cbbd8	1	Mason Crosby	M.Crosby	1984-09-03	73	207	Colorado	K	2	ACT	0	0	2013-09-25 01:34:04.287981	2013-09-25 01:34:04.287983	GB
260	2f80e90d-dbff-4395-81c9-4e61c247d0f1	1	Bryan Bulaga	B.Bulaga	1989-03-21	77	314	Iowa	OT	75	IR	0	0	2013-09-25 01:34:04.289242	2013-09-25 01:34:04.289243	GB
261	a750e7ca-12ab-4d7c-bc65-f58793c3ed16	1	David Bakhtiari	D.Bakhtiari	1991-09-30	76	300	Colorado	T	69	ACT	0	0	2013-09-25 01:34:04.290472	2013-09-25 01:34:04.290472	GB
262	0dfd5d3f-ebb5-4efe-8df1-2ebda0e5185e	1	Marshall Newhouse	M.Newhouse	1988-09-29	76	319	Texas Christian	OT	74	ACT	0	0	2013-09-25 01:34:04.291664	2013-09-25 01:34:04.291665	GB
263	de070f62-4494-4a98-8a76-0929c19be685	1	James Starks	J.Starks	1986-02-25	74	218	Buffalo	RB	44	ACT	0	0	2013-09-25 01:34:04.292863	2013-09-25 01:34:04.292863	GB
264	e030ef2b-1dcc-4c66-b8de-0016ca0d52d2	1	Micah Hyde	M.Hyde	1990-12-31	72	197	Iowa	FS	33	ACT	0	0	2013-09-25 01:34:04.29404	2013-09-25 01:34:04.29404	GB
265	04cc9dd3-de57-4d20-ad28-ff2be479937f	1	Sederrick Cunningham	S.Cunningham	1989-07-14	71	192	Furman	WR	13	IR	0	0	2013-09-25 01:34:04.295321	2013-09-25 01:34:04.295322	GB
266	9f2aebe4-b654-4f0e-a437-ec46f20b6bfe	1	Jordy Nelson	J.Nelson	1985-05-31	75	217	Kansas State	WR	87	ACT	0	0	2013-09-25 01:34:04.296683	2013-09-25 01:34:04.296684	GB
267	8eafc2b1-3e22-4416-b690-9a1232669f62	1	Andrew Quarless	A.Quarless	1988-10-06	76	252	Penn State	TE	81	ACT	0	0	2013-09-25 01:34:04.297931	2013-09-25 01:34:04.297932	GB
268	2c80e71d-c173-4c07-aeda-69371e969591	1	Evan Dietrich-Smith	E.Dietrich-Smith	1986-07-19	74	308	Idaho State	C	62	ACT	0	0	2013-09-25 01:34:04.299151	2013-09-25 01:34:04.299152	GB
269	f59c0b26-a651-408c-b8d4-efe9ffa333c8	1	Kevin Dorsey	K.Dorsey	1990-02-23	75	210	Maryland	WR	16	IR	0	0	2013-09-25 01:34:04.300167	2013-09-25 01:34:04.300168	GB
270	9c2bf2fc-d6cb-479d-8ece-f2ab4d1cda91	1	Josh Sitton	J.Sitton	1986-06-06	75	318	Central Florida	G	71	ACT	0	0	2013-09-25 01:34:04.301192	2013-09-25 01:34:04.301192	GB
271	f9ec0e39-86d2-4f99-84d6-b4e7bb387d8b	1	Lane Taylor	L.Taylor	1989-11-22	75	324	Oklahoma State	G	65	ACT	0	0	2013-09-25 01:34:04.302198	2013-09-25 01:34:04.302198	GB
272	e804ffee-597a-434f-8e72-7db5893225d6	1	Brandon Bostick	B.Bostick	1989-05-03	75	245	Newberry College	TE	86	ACT	0	0	2013-09-25 01:34:04.303345	2013-09-25 01:34:04.303346	GB
273	0ce48193-e2fa-466e-a986-33f751add206	1	Aaron Rodgers	A.Rodgers	1983-12-02	74	225	California	QB	12	ACT	0	0	2013-09-25 01:34:04.304383	2013-09-25 01:34:04.304383	GB
274	b24e6d69-1482-499d-970f-10b64b5ecb8d	1	M.D. Jennings	M.Jennings	1988-07-25	72	195	Arkansas State	SAF	43	ACT	0	0	2013-09-25 01:34:04.305404	2013-09-25 01:34:04.305404	GB
275	a7152c92-426c-4c6b-9629-da63f5c60ff8	1	John Kuhn	J.Kuhn	1982-09-09	72	250	Shippensburg	FB	30	ACT	0	0	2013-09-25 01:34:04.306429	2013-09-25 01:34:04.30643	GB
276	6c7704c2-f833-46aa-9f9c-d975d5ad1297	1	Chris Banjo	C.Banjo	1990-02-26	70	204	Southern Methodist	DB	32	ACT	0	0	2013-09-25 01:34:04.307441	2013-09-25 01:34:04.307442	GB
277	6d7ca819-8c58-4c41-bba7-643ba9553eb8	1	Greg Van Roten	G.Van Roten	1990-02-26	76	295	Penn	G	64	ACT	0	0	2013-09-25 01:34:04.308414	2013-09-25 01:34:04.308414	GB
278	eec73720-d572-44cc-8f60-be5099b6c4b2	1	Seneca Wallace	S.Wallace	1980-08-06	71	205	Iowa State	QB	9	ACT	0	0	2013-09-25 01:34:04.30938	2013-09-25 01:34:04.30938	GB
279	fed730f2-4d9c-4797-86a5-5668147d6150	1	Jermichael Finley	J.Finley	1987-03-26	77	247	Texas	TE	88	ACT	0	0	2013-09-25 01:34:04.310356	2013-09-25 01:34:04.310357	GB
280	671d2fd7-41bb-457a-8e93-904ee7d94eb1	1	J.C. Tretter	J.Tretter		76	307	Cornell	T	73	PUP	0	0	2013-09-25 01:34:04.311317	2013-09-25 01:34:04.311317	GB
281	356b9d62-d732-4110-b2b5-1b2d74f7640c	1	Johnathan Franklin	J.Franklin	1989-10-23	70	205	UCLA	RB	23	ACT	0	0	2013-09-25 01:34:04.312386	2013-09-25 01:34:04.312387	GB
282	3283f152-d373-43b3-b88f-f6f261c48e81	1	Randall Cobb	R.Cobb	1990-08-22	70	192	Kentucky	WR	18	ACT	0	0	2013-09-25 01:34:04.313355	2013-09-25 01:34:04.313356	GB
283	8920894c-dc0e-4ed6-96e5-b96eadcf2092	1	Jarrett Boykin	J.Boykin	1989-11-04	74	218	Virginia Tech	WR	11	ACT	0	0	2013-09-25 01:34:04.31432	2013-09-25 01:34:04.31432	GB
284	e1551780-84cb-48a4-b5c8-268c437bd671	1	Jerron McMillian	J.McMillian	1989-04-02	71	203	Maine	SAF	22	ACT	0	0	2013-09-25 01:34:04.315267	2013-09-25 01:34:04.315267	GB
285	030f508b-be11-478e-bf68-d21e70fcff7b	1	Eddie Lacy	E.Lacy	1991-01-01	71	231	Alabama	RB	27	ACT	0	0	2013-09-25 01:34:04.316193	2013-09-25 01:34:04.316194	GB
286	7ea2fcfd-0099-4e62-8f6e-efa0197bbb99	1	DuJuan Harris	D.Harris	1988-09-03	67	197	Troy	RB	26	IR	0	0	2013-09-25 01:34:04.31714	2013-09-25 01:34:04.317141	GB
287	3ebbc479-fec5-4463-8eb1-b9b09b0d3bc2	1	T.J. Lang	T.Lang	1987-09-20	76	318	Eastern Michigan	G	70	ACT	0	0	2013-09-25 01:34:04.318063	2013-09-25 01:34:04.318063	GB
288	7ff9bc26-5cbf-4891-b7c8-3a3e804e77cb	1	Derek Sherrod	D.Sherrod	1989-04-23	77	321	Mississippi State	OT	78	PUP	0	0	2013-09-25 01:34:04.319013	2013-09-25 01:34:04.319014	GB
289	f03e7491-7eff-45bb-b4a0-03e89b8cdc8d	1	Sean Richardson	S.Richardson	1990-01-21	74	216	Vanderbilt	SAF	28	PUP	0	0	2013-09-25 01:34:04.319995	2013-09-25 01:34:04.319995	GB
290	DEF-GB	1	GB Defense	GB		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:04.320953	2013-09-25 01:34:04.320954	GB
291	3fd6bc25-acc1-40c1-b813-610be538a736	1	Jerome Simpson	J.Simpson	1986-02-04	74	190	Coastal Carolina	WR	81	ACT	0	0	2013-09-25 01:34:04.586594	2013-09-25 01:34:04.586595	MIN
292	407f1923-6659-4564-800f-25b8746d6d3e	1	Harrison Smith	H.Smith	1989-02-02	74	214	Notre Dame	SAF	22	ACT	0	0	2013-09-25 01:34:04.589751	2013-09-25 01:34:04.589752	MIN
293	8204c701-b2a6-479a-9be6-0b03854bebf8	1	Charlie Johnson	C.Johnson	1984-05-02	76	305	Oklahoma State	OT	74	ACT	0	0	2013-09-25 01:34:04.591533	2013-09-25 01:34:04.591534	MIN
294	bcce626d-b0b5-4b1a-98a8-e6021d5af145	1	Jamarca Sanford	J.Sanford	1985-08-27	70	200	Mississippi	SAF	33	ACT	0	0	2013-09-25 01:34:04.592942	2013-09-25 01:34:04.592942	MIN
295	d9168af9-6bf7-47de-ba56-19d6a3a4548b	1	Matt Kalil	M.Kalil	1989-07-06	79	295	USC	OT	75	ACT	0	0	2013-09-25 01:34:04.594221	2013-09-25 01:34:04.594221	MIN
296	1ed30e79-c25f-4ce1-a17f-94a4bf6d3686	1	J'Marcus Webb	J.Webb	1988-08-08	79	333	West Texas A&M	OT	73	ACT	0	0	2013-09-25 01:34:04.595494	2013-09-25 01:34:04.595499	MIN
297	3467ae3e-4ddf-450d-8f36-b741ea3a2564	1	Christian Ponder	C.Ponder	1988-02-25	74	229	Florida State	QB	7	ACT	0	0	2013-09-25 01:34:04.59673	2013-09-25 01:34:04.596731	MIN
298	1059e9dc-97df-4643-9116-883a0573d8b1	1	Kyle Rudolph	K.Rudolph	1989-11-09	78	259	Notre Dame	TE	82	ACT	0	0	2013-09-25 01:34:04.598053	2013-09-25 01:34:04.598054	MIN
299	6499ef2a-c7a9-4f14-abeb-8cc165333249	1	Brandon Fusco	B.Fusco	1988-07-26	76	306	Slippery Rock	OL	63	ACT	0	0	2013-09-25 01:34:04.599308	2013-09-25 01:34:04.599309	MIN
300	8ceab66f-c5eb-4d5a-970f-8210e3e20f7f	1	John Carlson	J.Carlson	1984-05-12	77	251	Notre Dame	TE	89	ACT	0	0	2013-09-25 01:34:04.600551	2013-09-25 01:34:04.600552	MIN
301	cccc9f16-9508-434f-b7a4-9a29cb0cacf9	1	Rhett Ellison	R.Ellison	1988-10-03	77	250	USC	TE	40	ACT	0	0	2013-09-25 01:34:04.603325	2013-09-25 01:34:04.603326	MIN
302	e9dd371e-fb41-4a6b-9ebc-714e0cd7ce96	1	DeMarcus Love	D.Love	1988-03-07	76	315	Arkansas	T	73	SUS	0	0	2013-09-25 01:34:04.604628	2013-09-25 01:34:04.604629	MIN
303	8263e101-aa33-435f-bf0f-388e1c4eeb59	1	Matt Cassel	M.Cassel	1982-05-17	76	230	USC	QB	16	ACT	0	0	2013-09-25 01:34:04.605893	2013-09-25 01:34:04.605894	MIN
304	8c5067dc-1617-42fa-82eb-0596392ab20a	1	Zach Line	Z.Line		72	232	Southern Methodist	RB	48	IR	0	0	2013-09-25 01:34:04.607121	2013-09-25 01:34:04.607122	MIN
305	9163afa3-2f7d-4fc0-bf96-f5d8f618969a	1	Joe Berger	J.Berger	1982-05-25	77	315	Michigan Tech	OL	61	ACT	0	0	2013-09-25 01:34:04.608322	2013-09-25 01:34:04.608323	MIN
306	39ee3bee-1177-49cd-a78b-7a790ffd0b84	1	Andrew Sendejo	A.Sendejo	1987-09-09	73	225	Rice	SAF	34	ACT	0	0	2013-09-25 01:34:04.6095	2013-09-25 01:34:04.609501	MIN
307	ff937065-a20f-4968-a138-8ecd3a8b7cdb	1	Greg Jennings	G.Jennings	1983-09-21	71	198	Western Michigan	WR	15	ACT	0	0	2013-09-25 01:34:04.61068	2013-09-25 01:34:04.61068	MIN
308	d1b9ef33-5b6e-4fb8-b253-aee9b2893ddd	1	Jeff Baca	J.Baca	1990-01-10	75	302	UCLA	G	60	ACT	0	0	2013-09-25 01:34:04.61186	2013-09-25 01:34:04.611861	MIN
309	7f87c105-e608-4911-8897-31cc5a443175	1	John Sullivan	J.Sullivan	1985-08-08	76	301	Notre Dame	C	65	ACT	0	0	2013-09-25 01:34:04.612894	2013-09-25 01:34:04.612895	MIN
310	ab58c0ac-a747-47e6-9b3c-505e41d2bd3d	1	Adrian Peterson	A.Peterson	1985-03-21	73	217	Oklahoma	RB	28	ACT	0	0	2013-09-25 01:34:04.614015	2013-09-25 01:34:04.614016	MIN
311	8bfeffe7-99e3-4db0-8f18-cbc0f64ec24b	1	Mistral Raymond	M.Raymond	1987-09-07	73	202	South Florida	SAF	41	ACT	0	0	2013-09-25 01:34:04.615035	2013-09-25 01:34:04.615035	MIN
312	250199f2-1387-4b55-b96f-17fedea6db7f	1	Joe Webb	J.Webb	1986-11-14	76	220	Alabama-Birmingham	QB	14	ACT	0	0	2013-09-25 01:34:04.616055	2013-09-25 01:34:04.616056	MIN
313	da85107c-365c-4d58-90ab-479d97d798b4	1	Cordarrelle Patterson	C.Patterson	1991-03-17	74	216	Tennessee	WR	84	ACT	0	0	2013-09-25 01:34:04.617053	2013-09-25 01:34:04.617053	MIN
314	6a11f09e-268c-4e5a-9b0f-cc0f4bc353c3	1	Jarius Wright	J.Wright	1989-11-25	70	180	Arkansas	WR	17	ACT	0	0	2013-09-25 01:34:04.618185	2013-09-25 01:34:04.618186	MIN
315	9a776cbe-2400-49bb-8b02-4708167ef674	1	Greg Childs	G.Childs	1990-03-10	75	217	Arkansas	WR	85	PUP	0	0	2013-09-25 01:34:04.619289	2013-09-25 01:34:04.61929	MIN
316	afac3e25-d72d-43f7-be4b-d33ed91a0bf8	1	Blair Walsh	B.Walsh	1990-01-08	70	192	Georgia	K	3	ACT	0	0	2013-09-25 01:34:04.620362	2013-09-25 01:34:04.620363	MIN
317	08747f6d-ce8f-4510-bf10-98451dab51e1	1	McLeod Bethel-Thompson	M.Bethel-Thompson	1988-07-03	76	230	Sacramento State	QB	4	ACT	0	0	2013-09-25 01:34:04.621422	2013-09-25 01:34:04.621423	MIN
318	5bcf4917-b164-4873-b2ca-0ec150749753	1	Phil Loadholt	P.Loadholt	1986-01-21	80	343	Oklahoma	OT	71	ACT	0	0	2013-09-25 01:34:04.622443	2013-09-25 01:34:04.622444	MIN
319	5db03086-c670-4adb-98ed-b6a59a4f9270	1	Robert Blanton	R.Blanton	1989-09-07	73	200	Notre Dame	SAF	36	ACT	0	0	2013-09-25 01:34:04.623428	2013-09-25 01:34:04.623428	MIN
320	865740d9-3838-4733-a0eb-52193f101c32	1	Jerome Felton	J.Felton	1986-07-03	72	246	Furman	FB	42	ACT	0	0	2013-09-25 01:34:04.624417	2013-09-25 01:34:04.624417	MIN
321	65b991ed-ad0c-41d8-bbe0-95fc147c9441	1	Matt Asiata	M.Asiata	1987-07-24	71	220	Utah	RB	44	ACT	0	0	2013-09-25 01:34:04.625362	2013-09-25 01:34:04.625362	MIN
322	06669e1d-f9f7-4774-abc2-6ed2f7e7647f	1	Toby Gerhart	T.Gerhart	1987-03-28	72	231	Stanford	RB	32	ACT	0	0	2013-09-25 01:34:04.626305	2013-09-25 01:34:04.626305	MIN
323	DEF-MIN	1	MIN Defense	MIN		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:04.627246	2013-09-25 01:34:04.627246	MIN
324	e4039abe-35b3-4b78-9752-e714ef01cecd	1	Kemal Ishmael	K.Ishmael	1991-05-06	71	206	Central Florida	DB	36	ACT	0	0	2013-09-25 01:34:04.94769	2013-09-25 01:34:04.947691	ATL
325	7e648a0b-fdc8-4661-a587-5826f2cac11b	1	Matt Ryan	M.Ryan	1985-05-17	76	220	Boston College	QB	2	ACT	0	0	2013-09-25 01:34:04.950953	2013-09-25 01:34:04.950954	ATL
326	3d980847-dec6-4fc1-a4bb-63bd0bfcb078	1	Steven Jackson	S.Jackson	1983-07-22	74	240	Oregon State	RB	39	ACT	0	0	2013-09-25 01:34:04.952749	2013-09-25 01:34:04.95275	ATL
327	67d56171-7522-430c-b7d9-8f7e2b6624d3	1	Levine Toilolo	L.Toilolo	1991-07-01	80	260	Stanford	TE	80	ACT	0	0	2013-09-25 01:34:04.954159	2013-09-25 01:34:04.95416	ATL
328	0b3217b9-ba37-4222-95cb-a7a222441e8b	1	Julio Jones	J.Jones	1989-02-03	75	220	Alabama	WR	11	ACT	0	0	2013-09-25 01:34:04.955379	2013-09-25 01:34:04.95538	ATL
329	382154cf-7cc6-494c-8426-9f78aa4c4b90	1	Tony Gonzalez	T.Gonzalez	1976-02-27	77	243	California	TE	88	ACT	0	0	2013-09-25 01:34:04.956556	2013-09-25 01:34:04.956557	ATL
330	e2524e8f-d304-4c8b-8165-55a09daa4801	1	Justin Blalock	J.Blalock	1983-12-20	76	329	Texas	G	63	ACT	0	0	2013-09-25 01:34:04.957687	2013-09-25 01:34:04.957688	ATL
331	c2dfb0f8-67e7-47d0-b4c5-997af6c36417	1	Peter Konz	P.Konz	1989-06-09	77	314	Wisconsin	G	66	ACT	0	0	2013-09-25 01:34:04.958803	2013-09-25 01:34:04.958803	ATL
332	221fb65c-a55f-4673-9445-19d090c3ecdf	1	Shann Schillinger	S.Schillinger	1986-05-22	72	202	Montana	SAF	29	ACT	0	0	2013-09-25 01:34:04.959851	2013-09-25 01:34:04.959851	ATL
333	008ebc66-7148-4f73-ac09-516f86c38cda	1	Josh Vaughan	J.Vaughan	1986-12-03	72	232	Richmond	RB	30	ACT	0	0	2013-09-25 01:34:04.961076	2013-09-25 01:34:04.961077	ATL
334	51e470b5-73ea-49b2-ae83-c26256a30812	1	Roddy White	R.White	1981-11-02	72	212	Alabama-Birmingham	WR	84	ACT	0	0	2013-09-25 01:34:04.962111	2013-09-25 01:34:04.962112	ATL
335	fde420b8-93ab-478d-8f27-817409f33652	1	Jason Snelling	J.Snelling	1983-12-29	71	223	Virginia	RB	44	ACT	0	0	2013-09-25 01:34:04.963115	2013-09-25 01:34:04.963116	ATL
336	8104d1e0-15c1-4ad5-b2e2-95e6b932b151	1	Drew Davis	D.Davis	1989-01-04	73	205	Oregon	WR	19	ACT	0	0	2013-09-25 01:34:04.964151	2013-09-25 01:34:04.964152	ATL
337	fa59e399-7416-4217-8285-9f7df2d10ad9	1	Dominique Davis	D.Davis	1989-07-17	75	198	East Carolina	QB	4	ACT	0	0	2013-09-25 01:34:04.965218	2013-09-25 01:34:04.965218	ATL
338	af883091-fc4e-4fcc-8092-8d12e6bb5609	1	Antone Smith	A.Smith	1985-09-17	69	190	Florida State	RB	35	ACT	0	0	2013-09-25 01:34:04.966198	2013-09-25 01:34:04.966199	ATL
339	59b3f179-beb9-4c31-82ba-b4aea4e3b6f2	1	Mike Johnson	M.Johnson	1987-04-02	77	312	Alabama	G	79	IR	0	0	2013-09-25 01:34:04.967222	2013-09-25 01:34:04.967222	ATL
340	38d4d3fa-4539-4eb5-98b6-fe7bba5ff281	1	Sam Baker	S.Baker	1985-05-30	77	307	USC	OT	72	ACT	0	0	2013-09-25 01:34:04.968275	2013-09-25 01:34:04.968276	ATL
341	3cb58404-6768-43a6-9ead-78972ac1f10b	1	Harland Gunn	H.Gunn	1989-08-30	74	324	Miami (FL)	G	69	ACT	0	0	2013-09-25 01:34:04.969304	2013-09-25 01:34:04.969305	ATL
342	e4ba7c28-6942-411e-a528-1dc1a8a8ccc7	1	Harry Douglas	H.Douglas	1984-09-16	72	182	Louisville	WR	83	ACT	0	0	2013-09-25 01:34:04.970288	2013-09-25 01:34:04.970288	ATL
343	49f6d095-101f-4e58-aed0-59925ac04c8a	1	Jeremy Trueblood	J.Trueblood	1983-05-10	80	320	Boston College	OT	65	ACT	0	0	2013-09-25 01:34:04.971279	2013-09-25 01:34:04.97128	ATL
344	cad3dc25-68fe-4115-b72c-41e59a674a99	1	Joe Hawley	J.Hawley	1988-10-22	75	297	Nevada-Las Vegas	G	61	ACT	0	0	2013-09-25 01:34:04.972263	2013-09-25 01:34:04.972263	ATL
345	349f647e-bfc3-4d84-af89-b33f8a08e26e	1	Patrick DiMarco	P.DiMarco	1989-04-30	73	243	South Carolina	FB	42	ACT	0	0	2013-09-25 01:34:04.97323	2013-09-25 01:34:04.973231	ATL
346	1f026b72-5d1a-4c7b-a1ef-1ef89b054e56	1	Kevin Cone	K.Cone	1988-03-20	74	216	Georgia Tech	WR	15	ACT	0	0	2013-09-25 01:34:04.974207	2013-09-25 01:34:04.974208	ATL
347	15de0eca-4c32-4d62-91ab-fd4104513c46	1	Bradie Ewing	B.Ewing	1989-12-26	71	239	Wisconsin	FB	34	IR	0	0	2013-09-25 01:34:04.976477	2013-09-25 01:34:04.976477	ATL
348	5fdee77b-5578-4f91-a3e1-4ea7b57bf1eb	1	Garrett Reynolds	G.Reynolds	1987-07-01	79	317	North Carolina	T	75	ACT	0	0	2013-09-25 01:34:04.977634	2013-09-25 01:34:04.977635	ATL
349	95fcde43-6d48-4468-8986-86e951d25fe5	1	Adam Nissley	A.Nissley	1988-05-06	78	267	Central Florida	TE	86	IR	0	0	2013-09-25 01:34:04.978631	2013-09-25 01:34:04.978632	ATL
350	218d1644-603e-4da3-9ce1-48ce3927494f	1	Matt Bryant	M.Bryant	1975-05-29	69	203	Baylor	K	3	ACT	0	0	2013-09-25 01:34:04.979737	2013-09-25 01:34:04.979737	ATL
351	c3d73869-aa05-4c6c-8bb0-b7630bc495a9	1	Lamar Holmes	L.Holmes	1989-07-08	78	323	Southern Mississippi	T	76	ACT	0	0	2013-09-25 01:34:04.98078	2013-09-25 01:34:04.98078	ATL
352	9ea8eb0a-32f3-4eab-992f-71e607ec65eb	1	Sean Renfree	S.Renfree	1990-04-28	75	219	Duke	QB	12	IR	0	0	2013-09-25 01:34:04.981779	2013-09-25 01:34:04.98178	ATL
353	e965df63-0d31-42d7-b93e-3f2778647a61	1	Ryan Schraeder	R.Schraeder	1988-05-04	79	300	Valdosta State	T	73	ACT	0	0	2013-09-25 01:34:04.982773	2013-09-25 01:34:04.982774	ATL
354	4f092f1b-57c9-4f96-902c-0f0ad4d7b03f	1	Andrew Szczerba	A.Szczerba	1988-07-16	78	260	Penn State	TE	85	IR	0	0	2013-09-25 01:34:04.983796	2013-09-25 01:34:04.983796	ATL
355	f6fd0d1f-9d12-4d37-a65d-3d34a47331bc	1	William Moore	W.Moore	1985-05-18	72	218	Missouri	SAF	25	ACT	0	0	2013-09-25 01:34:04.984809	2013-09-25 01:34:04.98481	ATL
356	8cd72bd8-13bc-4593-90e2-d96e8ffa1840	1	Thomas DeCoud	T.DeCoud	1985-03-19	72	193	California	SAF	28	ACT	0	0	2013-09-25 01:34:04.985824	2013-09-25 01:34:04.985825	ATL
357	424dda80-1a85-4339-bc1a-8175f528bef8	1	Chase Coffman	C.Coffman	1986-11-10	78	250	Missouri	TE	86	ACT	0	0	2013-09-25 01:34:04.986992	2013-09-25 01:34:04.986993	ATL
358	91a95850-9514-49d5-b2b0-f8e21156daa0	1	Jacquizz Rodgers	J.Rodgers	1990-02-06	66	196	Oregon State	RB	32	ACT	0	0	2013-09-25 01:34:04.987987	2013-09-25 01:34:04.987988	ATL
359	67a54559-a3e2-477f-9701-56da8984289a	1	Zeke Motta	Z.Motta	1990-05-14	74	213	Notre Dame	SS	41	ACT	0	0	2013-09-25 01:34:04.988962	2013-09-25 01:34:04.988962	ATL
360	DEF-ATL	1	ATL Defense	ATL		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:04.990014	2013-09-25 01:34:04.990014	ATL
361	46664226-53c3-4ef9-9aeb-f708e3e8269f	1	Mike Iupati	M.Iupati	1987-05-12	77	331	Idaho	G	77	ACT	0	0	2013-09-25 01:34:05.351713	2013-09-25 01:34:05.351714	SF
362	16cc9ade-f9ad-4d32-b5b9-d7568ee80f58	1	Garrett Celek	G.Celek	1988-05-29	77	252	Michigan State	TE	88	ACT	0	0	2013-09-25 01:34:05.354914	2013-09-25 01:34:05.354915	SF
363	fe767946-236d-4c04-9c59-5e3edd51acfe	1	Michael Crabtree	M.Crabtree	1987-09-14	73	214	Texas Tech	WR	15	PUP	0	0	2013-09-25 01:34:05.35667	2013-09-25 01:34:05.356671	SF
364	d7055ba2-f8b4-4407-b491-60c05dff6162	1	Alex Boone	A.Boone	1987-05-04	80	300	Ohio State	OT	75	ACT	0	0	2013-09-25 01:34:05.358019	2013-09-25 01:34:05.35802	SF
365	3699dfd9-d437-43f7-b674-adbb31e7e64b	1	Colt McCoy	C.McCoy	1986-09-05	73	220	Texas	QB	2	ACT	0	0	2013-09-25 01:34:05.359299	2013-09-25 01:34:05.3593	SF
366	02f3eb16-982c-48ff-b731-7456812ab200	1	Anthony Davis	A.Davis	1989-10-11	77	323	Rutgers	OT	76	ACT	0	0	2013-09-25 01:34:05.360618	2013-09-25 01:34:05.360618	SF
367	da8d175e-d233-4a0b-b5db-91e371971577	1	Adam Snyder	A.Snyder	1982-01-30	78	325	Oregon	G	68	ACT	0	0	2013-09-25 01:34:05.36194	2013-09-25 01:34:05.361941	SF
368	bc9d248e-db3f-4010-9267-59584b637825	1	Darcel McBath	D.McBath	1985-10-28	73	198	Texas Tech	SAF	28	IR	0	0	2013-09-25 01:34:05.363245	2013-09-25 01:34:05.363246	SF
369	9be8224a-4a19-4f6a-a2be-ecbd3a24868c	1	Bruce Miller	B.Miller	1987-08-06	74	248	Central Florida	FB	49	ACT	0	0	2013-09-25 01:34:05.364484	2013-09-25 01:34:05.364484	SF
370	21d172c4-1c74-44b8-9131-aee05a2beb60	1	Mario Manningham	M.Manningham	1986-05-25	72	185	Michigan	WR	82	PUP	0	0	2013-09-25 01:34:05.365718	2013-09-25 01:34:05.365718	SF
371	173f1122-520e-43ae-95c9-a854bd272b29	1	C.J. Spillman	C.Spillman	1986-05-06	72	199	Marshall	SAF	27	ACT	0	0	2013-09-25 01:34:05.366984	2013-09-25 01:34:05.366984	SF
372	0a95e792-6455-4927-9539-f95fa7f41fbb	1	Vernon Davis	V.Davis	1984-01-31	75	250	Maryland	TE	85	ACT	0	0	2013-09-25 01:34:05.368333	2013-09-25 01:34:05.368334	SF
373	d5cd4c8a-d534-4dee-aef1-3d1f7e974b61	1	B.J. Daniels	B.Daniels	1989-10-24	72	217	South Florida	QB	5	ACT	0	0	2013-09-25 01:34:05.369616	2013-09-25 01:34:05.369616	SF
374	f2b3c3e1-535c-42ca-85a5-3f76b63b23bd	1	Jon Baldwin	J.Baldwin	1989-08-10	76	230	Pittsburgh	WR	84	ACT	0	0	2013-09-25 01:34:05.371083	2013-09-25 01:34:05.371085	SF
375	7bf077c7-40f9-4015-ac73-93f1b7418a24	1	Kendall Hunter	K.Hunter	1988-09-16	67	199	Oklahoma State	RB	32	ACT	0	0	2013-09-25 01:34:05.372331	2013-09-25 01:34:05.372332	SF
376	8f24a248-b328-43ec-8677-67600e42a8f7	1	Vance McDonald	V.McDonald	1990-06-13	76	267	Rice	TE	89	ACT	0	0	2013-09-25 01:34:05.37357	2013-09-25 01:34:05.373571	SF
377	c9c6ff4b-952e-41d5-863a-5d5313afcfa6	1	LaMichael James	L.James	1989-10-22	69	195	Oregon	RB	23	ACT	0	0	2013-09-25 01:34:05.374767	2013-09-25 01:34:05.374768	SF
378	2bd18508-91d1-463f-ab87-18a41fe7ca32	1	Donte Whitner	D.Whitner	1985-07-24	70	208	Ohio State	SAF	31	ACT	0	0	2013-09-25 01:34:05.375952	2013-09-25 01:34:05.375953	SF
379	52b93a85-f011-4049-8268-cd4de896b6e2	1	Marlon Moore	M.Moore	1987-09-03	72	190	Fresno State	WR	19	ACT	0	0	2013-09-25 01:34:05.377144	2013-09-25 01:34:05.377144	SF
380	e5247e5f-c4af-4a9b-8c7c-da75ef7fbf8d	1	Phil Dawson	P.Dawson	1975-01-23	71	200	Texas	K	9	ACT	0	0	2013-09-25 01:34:05.378199	2013-09-25 01:34:05.378199	SF
381	ce205f70-4bcd-4cc8-b4bf-b2e2a530b9dd	1	Brandon Carswell	B.Carswell	1989-05-22	73	201	USC	WR	84	IR	0	0	2013-09-25 01:34:05.379235	2013-09-25 01:34:05.379236	SF
382	4d628a09-3631-4166-85f6-45f41a74e992	1	Joe Staley	J.Staley	1984-08-30	77	315	Central Michigan	OT	74	ACT	0	0	2013-09-25 01:34:05.380267	2013-09-25 01:34:05.380267	SF
383	c6c558e1-e2b2-4fb5-a5a3-ee58526f10d8	1	Chris Harper	C.Harper	1989-09-10	73	229	Kansas State	WR	13	ACT	0	0	2013-09-25 01:34:05.3813	2013-09-25 01:34:05.381301	SF
384	33629816-c735-4a70-9e7c-eec8445eab7a	1	Quinton Patton	Q.Patton	1990-08-09	72	204	Louisiana Tech	WR	11	ACT	0	0	2013-09-25 01:34:05.382451	2013-09-25 01:34:05.382452	SF
385	eb1d1304-1900-4587-ae06-75c77efd85a8	1	Anquan Boldin	A.Boldin	1980-10-03	73	223	Florida State	WR	81	ACT	0	0	2013-09-25 01:34:05.383442	2013-09-25 01:34:05.383442	SF
386	ead15824-3958-47f8-9e2e-09670fca7a67	1	Alex Debniak	A.Debniak		74	240	Stanford	FB	44	IR	0	0	2013-09-25 01:34:05.384461	2013-09-25 01:34:05.384462	SF
387	c615cf52-bc61-43ed-bb76-39695ca019c0	1	Eric Reid	E.Reid	1991-12-10	73	213	LSU	FS	35	ACT	0	0	2013-09-25 01:34:05.385419	2013-09-25 01:34:05.385419	SF
388	6a2b129d-a9e5-4131-b491-82269b323f77	1	Frank Gore	F.Gore	1983-05-14	69	217	Miami (FL)	RB	21	ACT	0	0	2013-09-25 01:34:05.386412	2013-09-25 01:34:05.386413	SF
389	0e581a51-e705-45e2-85d3-bc2c073e626e	1	Joe Looney	J.Looney	1990-08-31	75	309	Wake Forest	G	78	ACT	0	0	2013-09-25 01:34:05.387374	2013-09-25 01:34:05.387375	SF
390	670e7379-29d7-4b64-b289-b8a6f3e12b6a	1	Marcus Lattimore	M.Lattimore	1991-10-29	71	221	South Carolina	RB	38	NON	0	0	2013-09-25 01:34:05.389689	2013-09-25 01:34:05.38969	SF
391	550de3e4-1167-4011-bd19-95a736179f1b	1	Owen Marecic	O.Marecic	1988-10-04	72	245	Stanford	FB	48	ACT	0	0	2013-09-25 01:34:05.390682	2013-09-25 01:34:05.390683	SF
392	423cfbc1-446f-4670-b9dc-4b8d7f67745d	1	Kyle Williams	K.Williams	1988-07-19	70	186	Arizona State	WR	10	ACT	0	0	2013-09-25 01:34:05.391688	2013-09-25 01:34:05.391688	SF
393	d00b8cd0-86fb-4d44-9816-7011747ad3fd	1	Kassim Osgood	K.Osgood	1980-05-20	77	220	San Diego State	WR	14	ACT	0	0	2013-09-25 01:34:05.392662	2013-09-25 01:34:05.392662	SF
394	d03aa6ca-ae90-44cb-954f-507213a73b22	1	Daniel Kilgore	D.Kilgore	1987-12-18	75	308	Appalachian State	G	67	ACT	0	0	2013-09-25 01:34:05.39361	2013-09-25 01:34:05.39361	SF
395	e3dd75f8-7b4c-420d-8f0f-a95b8a90ab66	1	Craig Dahl	C.Dahl	1985-06-17	73	212	North Dakota State	SAF	43	ACT	0	0	2013-09-25 01:34:05.394626	2013-09-25 01:34:05.394627	SF
396	3fed6499-3bcb-42f4-b583-5579a97b5e30	1	Anthony Dixon	A.Dixon	1987-09-24	73	233	Mississippi State	RB	24	ACT	0	0	2013-09-25 01:34:05.395575	2013-09-25 01:34:05.395576	SF
397	2a5b21e2-e2f1-435b-b05f-aa6b3169554d	1	Luke Marquardt	L.Marquardt	1990-03-23	80	315	Azusa Pacific	T	64	NON	0	0	2013-09-25 01:34:05.396552	2013-09-25 01:34:05.396552	SF
398	a893e70f-e3a6-4f2c-98c0-0f83c2be00d6	1	Jonathan Goodwin	J.Goodwin	1978-12-02	75	318	Michigan	C	59	ACT	0	0	2013-09-25 01:34:05.397553	2013-09-25 01:34:05.397554	SF
399	068b70bc-9558-4e99-b729-754fd28937ed	1	Colin Kaepernick	C.Kaepernick	1987-11-03	76	230	Nevada	QB	7	ACT	0	0	2013-09-25 01:34:05.398524	2013-09-25 01:34:05.398524	SF
400	d19bff06-99b5-42d9-92fe-f60a419b4392	1	Raymond Ventrone	R.Ventrone	1982-10-21	70	200	Villanova	DB	41	ACT	0	0	2013-09-25 01:34:05.39955	2013-09-25 01:34:05.399551	SF
401	DEF-SF	1	SF Defense	SF		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:05.400496	2013-09-25 01:34:05.400496	SF
402	e0a63251-5428-43a1-88c1-c000215ac5ce	1	Derrick Coleman	D.Coleman	1990-10-18	73	240	UCLA	RB	40	ACT	0	0	2013-09-25 01:34:05.742745	2013-09-25 01:34:05.742746	SEA
403	fddbbbff-19a2-4982-b4af-d8cbccbe2215	1	Sidney Rice	S.Rice	1986-09-01	76	202	South Carolina	WR	18	ACT	0	0	2013-09-25 01:34:05.746058	2013-09-25 01:34:05.746059	SEA
404	63fd9abe-4bdf-4611-9497-0c67e030ce01	1	Robert Turbin	R.Turbin	1989-12-02	70	222	Utah State	RB	22	ACT	0	0	2013-09-25 01:34:05.747836	2013-09-25 01:34:05.747836	SEA
405	09cbfefb-2ef4-4d07-8ac3-fafccc9a2106	1	Zach Miller	Z.Miller	1985-12-11	77	255	Arizona State	TE	86	ACT	0	0	2013-09-25 01:34:05.749533	2013-09-25 01:34:05.749534	SEA
406	be62bf39-c737-416f-a1ea-6b9d61684a62	1	J.R. Sweezy	J.Sweezy	1989-04-08	77	298	North Carolina State	G	64	ACT	0	0	2013-09-25 01:34:05.750847	2013-09-25 01:34:05.750848	SEA
407	16c67c97-ffd9-4f92-917d-ad6124ce1f6e	1	Luke Willson	L.Willson	1990-01-15	77	251	Rice	TE	82	ACT	0	0	2013-09-25 01:34:05.752069	2013-09-25 01:34:05.75207	SEA
408	82bce0be-9a87-4b6d-a85b-623bf8d1674e	1	Marshawn Lynch	M.Lynch	1986-04-22	71	215	California	RB	24	ACT	0	0	2013-09-25 01:34:05.753351	2013-09-25 01:34:05.753352	SEA
409	53b0a001-2efe-4009-8ff1-572b687d4397	1	James Carpenter	J.Carpenter	1989-03-22	77	321	Alabama	OT	77	ACT	0	0	2013-09-25 01:34:05.755043	2013-09-25 01:34:05.755044	SEA
410	bbb63a36-8613-4675-8e5e-34200d245ff0	1	Spencer Ware	S.Ware	1991-11-23	70	228	LSU	RB	44	ACT	0	0	2013-09-25 01:34:05.756427	2013-09-25 01:34:05.756428	SEA
411	40cda44b-2ee3-4ad1-834e-995e30db84d4	1	Steven Hauschka	S.Hauschka	1985-06-29	76	210	North Carolina State	K	4	ACT	0	0	2013-09-25 01:34:05.757697	2013-09-25 01:34:05.757698	SEA
412	3752af7b-f40d-4f82-8072-4fb84d15090d	1	Percy Harvin	P.Harvin	1988-05-28	71	184	Florida	WR	11	PUP	0	0	2013-09-25 01:34:05.758914	2013-09-25 01:34:05.758915	SEA
413	38293bdb-87d5-4219-be46-44fea6741483	1	Russell Okung	R.Okung	1987-10-07	77	310	Oklahoma State	OT	76	IR	0	0	2013-09-25 01:34:05.760272	2013-09-25 01:34:05.760273	SEA
414	b1674df8-2270-4ade-a168-00159259c0b8	1	Max Unger	M.Unger	1986-04-14	77	305	Oregon	C	60	ACT	0	0	2013-09-25 01:34:05.761531	2013-09-25 01:34:05.761532	SEA
415	1f49b95a-97cb-426e-8bd0-aeeb4b5b0ad1	1	Kam Chancellor	K.Chancellor	1988-04-03	75	232	Virginia Tech	SAF	31	ACT	0	0	2013-09-25 01:34:05.762802	2013-09-25 01:34:05.762803	SEA
416	70ff9d3e-4339-46da-908f-4aed688f4a1f	1	Stephen Williams	S.Williams	1986-06-29	77	208	Toledo	WR	83	ACT	0	0	2013-09-25 01:34:05.763957	2013-09-25 01:34:05.763958	SEA
417	cf8e8522-6220-4612-a8a1-72c496dac536	1	Christine Michael	C.Michael	1990-11-09	70	220	Texas A&M	RB	33	ACT	0	0	2013-09-25 01:34:05.76501	2013-09-25 01:34:05.765011	SEA
418	41d6830d-9512-4f40-bd74-2125b2f84416	1	Tarvaris Jackson	T.Jackson	1983-04-21	74	225	Alabama State	QB	7	ACT	0	0	2013-09-25 01:34:05.766089	2013-09-25 01:34:05.76609	SEA
419	409d4cac-ee90-4470-9710-ebe671678339	1	Russell Wilson	R.Wilson	1988-11-29	71	206	Wisconsin	QB	3	ACT	0	0	2013-09-25 01:34:05.76711	2013-09-25 01:34:05.767111	SEA
420	e1b29179-074b-4c91-8797-763b76ac618a	1	Doug Baldwin	D.Baldwin	1988-09-21	70	189	Stanford	WR	89	ACT	0	0	2013-09-25 01:34:05.76813	2013-09-25 01:34:05.768131	SEA
421	a5210045-10f8-4f59-9547-675fd0f27840	1	Kellen Davis	K.Davis	1985-10-11	79	265	Michigan State	TE	87	ACT	0	0	2013-09-25 01:34:05.769126	2013-09-25 01:34:05.769127	SEA
422	4094730d-a3ad-4c7e-a899-a3c8001748d9	1	Earl Thomas	E.Thomas	1989-05-07	70	202	Texas	FS	29	ACT	0	0	2013-09-25 01:34:05.770201	2013-09-25 01:34:05.770201	SEA
423	af867ba7-f44e-4c1f-a4b3-61a9b5a7065d	1	Alvin Bailey	A.Bailey	1991-08-26	75	320	Arkansas	T	78	ACT	0	0	2013-09-25 01:34:05.771279	2013-09-25 01:34:05.77128	SEA
424	2790db28-d487-43fa-a65e-0c80da7cb9c8	1	Breno Giacomini	B.Giacomini	1985-09-27	79	318	Louisville	OT	68	ACT	0	0	2013-09-25 01:34:05.772301	2013-09-25 01:34:05.772302	SEA
425	c88d9352-b835-45ed-a909-1cfec09a58bc	1	Golden Tate	G.Tate	1988-08-02	70	202	Notre Dame	WR	81	ACT	0	0	2013-09-25 01:34:05.773299	2013-09-25 01:34:05.773299	SEA
426	9bdcd809-94c8-467c-a088-02f92acfeb18	1	Caylin Hauptmann	C.Hauptmann	1991-07-10	75	300	Florida International	OL	0	ACT	0	0	2013-09-25 01:34:05.774236	2013-09-25 01:34:05.774236	SEA
427	7e5b8212-df93-4069-b3f0-be4b5cb47389	1	Jermaine Kearse	J.Kearse	1990-02-06	73	209	Washington	WR	15	ACT	0	0	2013-09-25 01:34:05.775175	2013-09-25 01:34:05.775175	SEA
428	d58339ad-6ec1-41cd-98d7-964ac47d7225	1	Jeron Johnson	J.Johnson	1988-06-12	70	212	Boise State	SAF	32	ACT	0	0	2013-09-25 01:34:05.776189	2013-09-25 01:34:05.77619	SEA
429	7fe2ad54-5650-4019-aab9-0f9b82c796f4	1	Paul McQuistan	P.McQuistan	1983-04-30	78	315	Weber State	T	67	ACT	0	0	2013-09-25 01:34:05.777194	2013-09-25 01:34:05.777195	SEA
430	0ec13c88-ecfd-437b-a84a-36ce94b51a8f	1	Lemuel Jeanpierre	L.Jeanpierre	1987-05-19	75	301	South Carolina	G	61	ACT	0	0	2013-09-25 01:34:05.778178	2013-09-25 01:34:05.778179	SEA
431	dfd8f952-5326-4f54-8914-c588c0cdacfb	1	Michael Bowie	M.Bowie	1991-09-25	77	330	NE Oklahoma State	T	73	ACT	0	0	2013-09-25 01:34:05.779177	2013-09-25 01:34:05.779177	SEA
432	DEF-SEA	1	SEA Defense	SEA		0	0		DEF	0	ACT	0	0	2013-09-25 01:34:05.780157	2013-09-25 01:34:05.780157	SEA
\.


--
-- Data for Name: recipients; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY recipients (id, stripe_id, user_id) FROM stdin;
\.


--
-- Data for Name: rosters; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY rosters (id, owner_id, created_at, updated_at, market_id, contest_id, buy_in, remaining_salary, score, contest_rank, amount_paid, paid_at, cancelled_cause, cancelled_at, state, positions, submitted_at, contest_type_id, cancelled) FROM stdin;
\.


--
-- Data for Name: rosters_players; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY rosters_players (id, player_id, roster_id, purchase_price, player_stats_id, market_id) FROM stdin;
\.


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
20130916232308
20130917212917
20130919060532
20130919155011
20130920014928
20130922210034
20130923200006
20130923223731
20130923225741
20130924194925
20130925042905
\.


--
-- Data for Name: sports; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY sports (id, name, created_at, updated_at) FROM stdin;
1	NFL	2013-09-25 08:33:01.906291	2013-09-25 08:33:01.906291
\.


--
-- Data for Name: stat_events; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY stat_events (id, activity, data, point_value, created_at, updated_at, player_stats_id, game_stats_id) FROM stdin;
\.


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY teams (id, sport_id, abbrev, name, conference, division, market, state, country, lat, long, standings, created_at, updated_at) FROM stdin;
1	1	NE	Patriots	AFC	AFC East	New England	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.427795	2013-09-25 01:34:01.427796
2	1	BAL	Ravens	AFC	AFC North	Baltimore	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.431882	2013-09-25 01:34:01.431883
3	1	CIN	Bengals	AFC	AFC North	Cincinnati	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.433547	2013-09-25 01:34:01.433548
4	1	HOU	Texans	AFC	AFC South	Houston	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.434703	2013-09-25 01:34:01.434704
5	1	IND	Colts	AFC	AFC South	Indianapolis	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.435818	2013-09-25 01:34:01.435819
6	1	DEN	Broncos	AFC	AFC West	Denver	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.43702	2013-09-25 01:34:01.437021
7	1	WAS	Redskins	NFC	NFC East	Washington	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.438153	2013-09-25 01:34:01.438154
8	1	GB	Packers	NFC	NFC North	Green Bay	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.439342	2013-09-25 01:34:01.439343
9	1	MIN	Vikings	NFC	NFC North	Minnesota	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.440497	2013-09-25 01:34:01.440498
10	1	ATL	Falcons	NFC	NFC South	Atlanta	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.441691	2013-09-25 01:34:01.441692
11	1	SF	49ers	NFC	NFC West	San Francisco	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.44283	2013-09-25 01:34:01.442831
12	1	SEA	Seahawks	NFC	NFC West	Seattle	\N	USA	0.000000	0.000000		2013-09-25 01:34:01.443974	2013-09-25 01:34:01.443975
\.


--
-- Data for Name: transaction_records; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY transaction_records (id, event, user_id, roster_id, amount, contest_id) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY users (id, name, created_at, updated_at, email, encrypted_password, reset_password_token, reset_password_sent_at, remember_created_at, sign_in_count, current_sign_in_at, last_sign_in_at, current_sign_in_ip, last_sign_in_ip, provider, uid, confirmation_token, confirmed_at, unconfirmed_email, confirmation_sent_at, admin, image_url, total_points, total_wins, win_percentile) FROM stdin;
1	SYSTEM USER	2013-09-25 08:33:01.88072	2013-09-25 08:33:01.88072	fantasysports@mustw.in	$2a$10$fxfw.E5kW6u2YPsv8dSl4.DWQ3Nc4nLvL8trVCkHQp7hlGq4.HL/O	\N	\N	\N	0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	f	\N	0	0	0
\.


--
-- Data for Name: venues; Type: TABLE DATA; Schema: public; Owner: fantasysports
--

COPY venues (id, stats_id, country, state, city, type, name, surface) FROM stdin;
\.


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
-- Name: credit_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY credit_cards
    ADD CONSTRAINT credit_cards_pkey PRIMARY KEY (id);


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
-- Name: invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


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
-- Name: oauth2_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY oauth2_access_tokens
    ADD CONSTRAINT oauth2_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth2_authorization_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY oauth2_authorization_codes
    ADD CONSTRAINT oauth2_authorization_codes_pkey PRIMARY KEY (id);


--
-- Name: oauth2_clients_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY oauth2_clients
    ADD CONSTRAINT oauth2_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth2_refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: fantasysports; Tablespace: 
--

ALTER TABLE ONLY oauth2_refresh_tokens
    ADD CONSTRAINT oauth2_refresh_tokens_pkey PRIMARY KEY (id);


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
-- Name: index_oauth2_access_tokens_on_client_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_access_tokens_on_client_id ON oauth2_access_tokens USING btree (client_id);


--
-- Name: index_oauth2_access_tokens_on_expires_at; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_access_tokens_on_expires_at ON oauth2_access_tokens USING btree (expires_at);


--
-- Name: index_oauth2_access_tokens_on_token; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_oauth2_access_tokens_on_token ON oauth2_access_tokens USING btree (token);


--
-- Name: index_oauth2_access_tokens_on_user_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_access_tokens_on_user_id ON oauth2_access_tokens USING btree (user_id);


--
-- Name: index_oauth2_authorization_codes_on_client_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_authorization_codes_on_client_id ON oauth2_authorization_codes USING btree (client_id);


--
-- Name: index_oauth2_authorization_codes_on_expires_at; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_authorization_codes_on_expires_at ON oauth2_authorization_codes USING btree (expires_at);


--
-- Name: index_oauth2_authorization_codes_on_token; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_oauth2_authorization_codes_on_token ON oauth2_authorization_codes USING btree (token);


--
-- Name: index_oauth2_authorization_codes_on_user_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_authorization_codes_on_user_id ON oauth2_authorization_codes USING btree (user_id);


--
-- Name: index_oauth2_clients_on_identifier; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_oauth2_clients_on_identifier ON oauth2_clients USING btree (identifier);


--
-- Name: index_oauth2_refresh_tokens_on_client_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_refresh_tokens_on_client_id ON oauth2_refresh_tokens USING btree (client_id);


--
-- Name: index_oauth2_refresh_tokens_on_expires_at; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_refresh_tokens_on_expires_at ON oauth2_refresh_tokens USING btree (expires_at);


--
-- Name: index_oauth2_refresh_tokens_on_token; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX index_oauth2_refresh_tokens_on_token ON oauth2_refresh_tokens USING btree (token);


--
-- Name: index_oauth2_refresh_tokens_on_user_id; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE INDEX index_oauth2_refresh_tokens_on_user_id ON oauth2_refresh_tokens USING btree (user_id);


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
-- Name: player_game_activity; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX player_game_activity ON stat_events USING btree (player_stats_id, game_stats_id, activity);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: fantasysports; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- Name: public; Type: ACL; Schema: -; Owner: mike
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM mike;
GRANT ALL ON SCHEMA public TO mike;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

