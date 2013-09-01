/* The pricing function. Right now, it's a straight linear shot and assumes a 100k salary cap with a 1k minimum price */
CREATE OR REPLACE FUNCTION price(bets numeric, total_bets numeric, buy_in numeric, OUT price numeric) RETURNS numeric AS $$
BEGIN
	SELECT GREATEST(1000, (bets + buy_in) * 100000 / (total_bets + buy_in)) INTO price;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

/* get the price of a player for a roster. if the roster has the player, returns the sell price. if the roster
does not have the player, returns the buy price */
CREATE OR REPLACE FUNCTION get_price(_roster_id integer, _player_id integer, OUT _price numeric) RETURNS numeric AS $$
DECLARE
	_roster rosters;
	_bets numeric;
	_total_bets numeric;
	_buy_in numeric := 0;
BEGIN
	SELECT * from rosters where id = _roster_id INTO _roster;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'roster % does not exist', _roster_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'player % could not be found in market or is locked%', _player_id, _roster.market_id;
	END IF;

	SELECT total_bets from markets WHERE id = _roster.market_id INTO _total_bets;
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


/* buy a player for a roster */
CREATE OR REPLACE FUNCTION buy(_roster_id integer, _player_id integer) RETURNS market_orders AS $$
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

	select price(_bets, _total_bets, _roster.buy_in) INTO _price;
	IF _price > _roster.remaining_salary THEN
		RAISE EXCEPTION 'roster % does not have sufficient funds (%) to purchase player % for %', _roster_id, _roster.remaining_salary, _player_id, _price;
	END IF;

	--perform the updates.
	INSERT INTO rosters_players(player_id, roster_id) values (_player_id, _roster_id);
	UPDATE markets SET total_bets = total_bets + _roster.buy_in WHERE id = _roster.market_id;
	UPDATE market_players SET bets = bets + _roster.buy_in WHERE market_id = _roster.market_id and player_id = _player_id;
	UPDATE rosters SET remaining_salary = remaining_salary - _price where id = _roster_id;
	INSERT INTO market_orders (market_id, roster_id, action, player_id, price)
		   VALUES (_roster.market_id, _roster_id, 'buy', _player_id, _price) RETURNING * INTO retval;
  RETURN retval;
END;
$$ LANGUAGE plpgsql;


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

	-- Get price, test salary cap
	SELECT total_bets from markets WHERE id = _roster.market_id INTO _total_bets FOR UPDATE;
	IF _total_bets IS NULL THEN
		RAISE EXCEPTION 'total_bets is null for market %', _roster.market_id;
	END IF;

	SELECT bets FROM market_players WHERE player_id = _player_id AND market_id = _roster.market_id AND
			(locked_at is null or locked_at > CURRENT_TIMESTAMP) INTO _bets;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'could not find player %', _player_id;
	END IF;

	select price(_bets, _total_bets, 0) INTO _price;

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

CREATE OR REPLACE FUNCTION test_market() RETURNS VOID AS $$
BEGIN
	delete from markets;
	delete from players;
	delete from market_players;
	delete from rosters;
	delete from market_orders;

	insert into markets values (1, 'test', 300, 1,
	CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
	'published', 300, 1);

	insert into players(id, name, total_games, total_points) values
	(1, 'bob', 0, 0),
	(2, 'jim', 0, 0),
	(3, 'tom', 0, 0);

	insert into rosters(id, owner_id, market_id, buy_in, remaining_salary, contest_type, state) values
	(1, 1, 1, 10, 100000, 'h2h', 'active'),
	(2, 1, 1, 10, 100000, 'h2h', 'active'),
	(3, 1, 1, 10, 100000, 'h2h', 'active');

	INSERT INTO market_players VALUES
	(1, 1, 1, 0, 100),
	(2, 1, 2, 0, 100),
	(3, 1, 3, 0, 100);

END;
$$ LANGUAGE plpgsql;


------------------------- publish markets ------------------------


CREATE OR REPLACE FUNCTION publish_market(_market_id integer) RETURNS VOID AS $$
DECLARE
	_total_ppg numeric;
	_market markets;
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

	--just to be safe, re-set the total bets to shadow bets
	UPDATE markets set total_bets = shadow_bets where id = _market_id;

	--ensure that the market has games and the games have players
	PERFORM game_stats_id from games_markets where market_id = _market_id;
	IF NOT FOUND THEN
		UPDATE markets SET state = 'closed', closed_at = CURRENT_TIMESTAMP where id = _market_id;
		RAISE NOTICE 'market % has no associated games -- will be closed', _market_id;
		return;
	END IF;

	--ensure that there are no associated market_players, rosters, rosters_players, 
	DELETE FROM market_players WHERE market_id = _market_id;
	DELETE FROM market_orders where market_id = _market_id;
	DELETE FROM rosters where market_id = _market_id;

	--get the total ppg
	select sum(
		(total_points + .01) / (total_games + .1) -- ghetto lagrangian filtering
	)
	from players where team in (
		select home_team from games g, games_markets gm where gm.market_id = _market_id and g.stats_id = gm.game_stats_id union
		select away_team from games g, games_markets gm where gm.market_id = _market_id and g.stats_id = gm.game_stats_id)
	INTO _total_ppg;

	--for each game, enter players into market_players with the game's start time as their lock date
	INSERT INTO market_players (market_id, player_id, shadow_bets, bets, locked_at)
		SELECT 
			_market_id, p.id, 
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets, 
			(((p.total_points + .01) / (p.total_games + .1)) / _total_ppg) * _market.shadow_bets, 
			g.game_time
		FROM players p, games g, games_markets gm WHERE
		gm.market_id = _market_id AND
		g.stats_id = gm.game_stats_id AND
		(p.team = g.home_team OR p.team = g.away_team);

	--set market to published
	UPDATE markets SET state = 'published' where id = _market_id;
	RAISE NOTICE 'published market %', _market_id;
END;
$$ LANGUAGE plpgsql;













