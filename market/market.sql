
------------------------------------- PRICE --------------------------------------------

/* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, OUT _price numeric ) RETURNS numeric AS $$
BEGIN
	SELECT GREATEST(1000, (bets + buy_in) * 100000 / (total_bets + buy_in)) INTO _price;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

------------------------------------------ Player Prices -----------------------------------------

--BUY prices for all players in the market. returns the player_id and the price
DROP FUNCTION buy_prices(integer);

CREATE OR REPLACE FUNCTION buy_prices(_roster_id integer)
RETURNS TABLE(player_id integer, buy_price numeric) AS $$
BEGIN
	RETURN QUERY
	SELECT mp.player_id, price(mp.bets, m.total_bets, r.buy_in)
	FROM market_players mp, markets m, rosters r
	WHERE
		r.id = _roster_id AND
		r.market_id = m.id AND
		r.market_id = mp.market_id AND
		mp.player_id NOT IN (SELECT player_id FROM rosters_players where roster_id = _roster_id)
		ORDER BY mp.player_id;
END;
$$ LANGUAGE plpgsql;

-- SELL prices for all players in the roster, as well as the price paid
-- returns player_id, current SELL price of player, and the purchase price
DROP FUNCTION sell_prices(integer);

CREATE OR REPLACE FUNCTION sell_prices(_roster_id integer)
RETURNS TABLE(player_id integer, sell_price numeric, purchase_price numeric) AS $$
BEGIN
	RETURN QUERY
	SELECT mp.player_id, price(mp.bets, m.total_bets, 0), rp.purchase_price
	FROM market_players mp, markets m, rosters r, rosters_players rp
	WHERE
		r.id = _roster_id AND
		rp.roster_id = _roster_id AND
		mp.player_id = rp.player_id AND
		r.market_id = m.id
	ORDER by mp.player_id;
END;
$$ LANGUAGE plpgsql;


/* get the price of a player for a roster. if the roster has the player, returns the sell price. if the roster
does not have the player, returns the buy price */
CREATE OR REPLACE FUNCTION get_price(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_buy_in numeric := 0;
BEGIN
	SELECT * FROM rosters where id = _roster_id INTO _roster;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % could not be found in market or is locked%', _player_id, _roster.market_id;
	END IF;

	SELECT total_bets FROM markets WHERE id = _roster.market_id INTO _total_bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find total_bets in market %', _roster.market_id;
	END IF;

	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF NOT FOUND THEN
		_buy_in := _roster.buy_in;
		RAISE NOTICE 'buy in is set to: %', _buy_in;
	END IF;
	SELECT price(_bets, _total_bets, _buy_in) INTO _price;
END;
$$ LANGUAGE plpgsql;

------------------------------------------ BUY ---------------------------------------

/* buy a player for a roster */
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_price numeric;
  retval market_orders;
BEGIN
	SELECT * FROM rosters where id = _roster_id INTO _roster FOR UPDATE;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	-- Check if roster already has player.
	--A PERFORM statement sets FOUND true if it produces (and discards) one or more rows, false if no row is produced.
	PERFORM id FROM rosters_players WHERE roster_id = _roster_id AND player_id = _player_id;
	IF FOUND THEN
		RAISE EXCEPTION 'player % already in roster %', _player_id, _roster_id;
	END IF;

	-- TODO: test positional requirements here
	-- Get price, test salary cap
	SELECT total_bets from markets WHERE id = _roster.market_id INTO _total_bets FOR UPDATE;
	IF _total_bets IS NULL THEN
		RAISE EXCEPTION 'total_bets is null for market %', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player % or player is locked', _player_id;
	END IF;

	SELECT price(_bets, _total_bets, _roster.buy_in) INTO _price;
	IF _price > _roster.remaining_salary THEN
		RAISE EXCEPTION 'roster % does not have sufficient funds (%) to purchase player % for %', _roster_id, _roster.remaining_salary, _player_id, _price;
	END IF;

	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id, purchase_price) values (_player_id, _roster_id, _price);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price where id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price) RETURNING * INTO retval;
  RETURN retval;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------- SELL ----------------------------------------------------

/* sell a player on a roster */
CREATE OR REPLACE FUNCTION sell(_roster_id integer, _player_id integer) RETURNS market_orders AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_price numeric;
  retval market_orders;
BEGIN
	SELECT * from rosters where id = _roster_id INTO _roster FOR UPDATE;
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
	SELECT total_bets FROM markets WHERE id = _roster.market_id INTO _total_bets FOR UPDATE;
	IF _total_bets IS NULL THEN
		RAISE EXCEPTION 'total_bets is null for market %', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;

	SELECT price(_bets, _total_bets, 0) INTO _price;

	--perform the updates.
	DELETE FROM rosters_players WHERE player_id = _player_id AND roster_id = _roster_id;
	UPDATE markets SET total_bets = total_bets - _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets - _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters set remaining_salary = remaining_salary + _price where id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
	  	VALUES (_roster.market_id, _roster_id, 'sell', _player_id, _price) RETURNING * INTO retval;
  RETURN retval;
END;
$$ LANGUAGE plpgsql;


------------------------- publish markets ------------------------

--TODO: check close date is start time of latest game?
CREATE OR REPLACE FUNCTION publish_market(_market_id integer) RETURNS VOID AS $$
DECLARE
	_market markets;
	_total_ppg numeric;
	_game games;
	_bets numeric;
BEGIN
	--ensure that the market exists and may be published
	SELECT * FROM markets WHERE id = _market_id AND published_at < CURRENT_TIMESTAMP AND
			(state is null OR state = '') FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE NOTICE 'market % is not publishable', _market_id;
		RETURN;
	END IF;

	--check that shadow_bets is something reasonable
	IF _market.shadow_bets = 0 THEN
		RAISE NOTICE 'shadow bets is 0, setting to 1000';
		UPDATE markets set shadow_bets = 1000 where id = _market_id;
	END IF;

	--make sure the shadow bet rate is reasonable
	IF _market.shadow_bet_rate <= 0 THEN
		UPDATE markets set shadow_bet_rate = 1 where id = _market_id;
	END IF;

	--just to be safe, re-set the total bets to shadow bets
	UPDATE markets set total_bets = shadow_bets, initial_shadow_bets = shadow_bets where id = _market_id;

	--ensure that the market has games and the games have players
	PERFORM game_stats_id from games_markets where market_id = _market_id;
	IF NOT FOUND THEN
		UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP where id = _market_id;
		RAISE NOTICE 'market % has no associated games -- will be closed', _market_id;
		return;
	END IF;

	--ensure that there are no associated market_players, market_orders, or rosters.
	--TODO: this is nice for dev and testing but may be a little dangerous in production
	DELETE FROM market_players WHERE market_id = _market_id;
	DELETE FROM market_orders where market_id = _market_id;
	DELETE FROM rosters_players WHERE roster_id IN (SELECT roster_id FROM rosters WHERE market_id = _market_id);
	DELETE FROM rosters where market_id = _market_id;

	--get the total ppg
	SELECT sum(
		(total_points + .01) / (total_games + .1) -- ghetto lagrangian filtering
	)
	from players where team in (
		SELECT home_team from games g, games_markets gm where gm.market_id = _market_id and g.stats_id = gm.game_stats_id
		union
		SELECT away_team from games g, games_markets gm where gm.market_id = _market_id and g.stats_id = gm.game_stats_id)
	INTO _total_ppg;

	--for each game, enter players into market_players with the game's start time as their lock date
	INSERT INTO market_players (market_id, player_id, shadow_bets, locked_at)
		SELECT
			_market_id, p.id,
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets,
			g.game_time
		FROM players p, games g, games_markets gm WHERE
		gm.market_id = _market_id AND
		g.stats_id = gm.game_stats_id AND
		(p.team = g.home_team OR p.team = g.away_team);

	--set bets and initial_shadow_bets shadow bets for all those players we just added
	UPDATE market_players SET bets = shadow_bets, initial_shadow_bets = shadow_bets where market_id = _market_id;

	--set market to published
	UPDATE markets SET state = 'published', published_at = CURRENT_TIMESTAMP where id = _market_id;

	--TEMPORARY: add contest types to market
	INSERT INTO contest_types(market_id, name, description, max_entries, buy_in, rake, payout_structure) VALUES
	(_market_id, '100k', '100k lalapalooza!', 0, 10, 0.03, '[50000, 25000, 12000, 6000, 3000, 2000, 1000, 500, 500]'),
	(_market_id, '970', 'Free contest, winner gets 10 FanFrees!', 10, 0, 0, '[F10]'),
	(_market_id, '970', '10 teams, $2 entry fee, winner takes home $19.40', 10, 2, 0.03, '[19.40]'),
	(_market_id, '970', '10 teams, $10 entrye fee, winner takes home $97.00', 10, 10, 0.03, '[97]'),
	(_market_id, '194', 'Free contest, top 25 winners get 2 FanFrees!', 50, 0, 0, '[F2]'),
	(_market_id, '194', '50 teams, $2 entry fee, top 25 winners take home $3.88', 50, 2, 0.03, '{0-24: 3.88}'),
	(_market_id, '194', '50 teams, $10 entrye fee, top 25 winners take home $19.40', 50, 10, 0.03, '{0-24: 19.40}'),
	(_market_id, 'h2h', 'Free h2h contest, winner gets 1 FanFree!', 2, 0, 0, '[F1]'),
	(_market_id, 'h2h', 'h2h contest, $2 entry fee, winner takes home $3.88', 2, 2, 0.03, '[3.88]'),
	(_market_id, 'h2h', 'h2h contest, $10 entry fee, winner takes home $19.40', 2, 10, 0.03, '[19.40]');

	RAISE NOTICE 'published market %', _market_id;
END;
$$ LANGUAGE plpgsql;

---------------------------------- open market --------------------------------------

--if given a published market, updates shadow bets as appropriate.
-- if the shadow-bets drop to zero, or the open time is due, it formally opens the market
DROP FUNCTION open_market(integer);

CREATE OR REPLACE FUNCTION open_market(_market_id integer, OUT _market markets) RETURNS markets AS $$
DECLARE
	_real_bets numeric;
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

	IF _market.opened_at > CURRENT_TIMESTAMP THEN
		--not yet time to open, so let's determine how many bets have been placed
		_new_shadow_bets = _market.initial_shadow_bets - _real_bets * _market.shadow_bet_rate;
		IF _new_shadow_bets < 0 THEN
			_new_shadow_bets = 0;
		END IF;
		IF _new_shadow_bets != 0 AND _market.shadow_bets - _new_shadow_bets < 10 THEN
			--don't bother with the update
			RAISE NOTICE 'not worth updating';
			RETURN;
		END IF;
	ELSE
		RAISE NOTICE 'market % is past due to open', _market_id;
	END IF;

	IF _new_shadow_bets = 0 THEN
		RAISE NOTICE 'opening market %', _market_id;

		--remove all shadow bets from the market
		UPDATE markets SET shadow_bets = 0, total_bets = _real_bets,
			state='opened', opened_at = CURRENT_TIMESTAMP WHERE id = _market_id;

		--remove shadow bets from all players in the market
		UPDATE market_players SET bets = bets-shadow_bets, shadow_bets = 0 where market_id = _market_id;

		--update purchase price for all orders yet placed - in both market_order and rosters_players
	    FOR _market_player IN SELECT * FROM market_players where market_id = _market_id LOOP
	    	SELECT price(_market_player.bets, _market.total_bets, 0) INTO _price;
	    	UPDATE rosters_players SET purchase_price = _price WHERE player_id = _market_player.player_id;
	    	UPDATE market_orders SET price = _price WHERE player_id = _market_player.player_id;
	    END LOOP;

	    --update the remaining salary for all rosters in the market
	    FOR _roster_id IN SELECT id FROM rosters WHERE market_id = _market_id LOOP
	    	UPDATE rosters SET remaining_salary = 100000 - (SELECT sum(price) FROM market_orders WHERE roster_id = _roster_id) WHERE id = _roster_id;
	    END LOOP;

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
$$ LANGUAGE plpgsql;


---------------------------------- close market --------------------------------------

--if given an opened market that is due to close, closes the market.
--besides setting the state of the market to closed, it also
CREATE OR REPLACE FUNCTION close_market(_market_id integer) RETURNS VOID AS $$
DECLARE
	_market markets;
	_real_bets numeric;
	_new_shadow_bets numeric := 0;
BEGIN
	--ensure that the market exists and may be opened
	SELECT * FROM markets WHERE id = _market_id AND state = 'opened' AND closed_at <= CURRENT_TIMESTAMP FOR UPDATE into _market;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'market % is not closable', _market_id;
	END IF;

	--update the market
	UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP where id = _market_id;

	--I think I'll do the rest in ruby.

END;
$$ LANGUAGE plpgsql;








