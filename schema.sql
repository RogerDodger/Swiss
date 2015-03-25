CREATE TABLE events (
	id INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	round INTEGER NOT NULL,
	winval INTEGER NOT NULL DEFAULT 3,
	created TIMESTAMP
);

CREATE TABLE players (
	id INTEGER PRIMARY KEY,
	event_id INTEGER REFERENCES events(id),
	name TEXT NOT NULL,
	seed REAL
);

CREATE TABLE matches (
	event_id INTEGER REFERENCES events(id) NOT NULL,
	p1_id INTEGER REFERENCES players(id),
	p2_id INTEGER REFERENCES players(id),
	round INTEGER,
	PRIMARY KEY (p1_id, p2_id, round)
);

CREATE TABLE scores (
	player_id INTEGER REFERENCES players(id),
	round INTEGER,
	value REAL NOT NULL,
	PRIMARY KEY (player_id, round)
);

-- Virtual tables
CREATE VIEW _players_event AS
SELECT
	players.id AS id, players.name AS name, seed, winval, round, event_id, dropped
FROM
	players,events
WHERE
	event_id = events.id;

CREATE VIEW _players_score AS
SELECT
	*, IFNULL((SELECT SUM(value) FROM scores WHERE player_id=me.id), 0) AS score
FROM
	_players_event me;

CREATE VIEW _players_winrate AS
SELECT
	*, score / (round * winval) AS winrate
FROM
	_players_score;

CREATE VIEW playersx AS
SELECT
	*, (SELECT AVG(winrate) FROM _players_winrate
			WHERE id IN (SELECT p1_id FROM matches WHERE p2_id = me.id)
			OR id IN (SELECT p2_id FROM matches WHERE p1_id = me.id)) AS owrate
FROM
	_players_winrate me
ORDER BY
	score DESC, owrate DESC, seed DESC;
