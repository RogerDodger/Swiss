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
	dropped BIT DEFAULT 0,
	seed REAL
);

CREATE TABLE matches (
	id INTEGER PRIMARY KEY,
	event_id INTEGER REFERENCES events(id) NOT NULL,
	p1_id INTEGER REFERENCES players(id),
	p2_id INTEGER REFERENCES players(id),
	p1_score INTEGER,
	p2_score INTEGER,
	round INTEGER
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
	*, IFNULL((SELECT SUM(p1_score) FROM matches WHERE p1_id=me.id), 0) +
	   IFNULL((SELECT SUM(p2_score) FROM matches WHERE p2_id=me.id), 0) AS score
FROM
	_players_event me;

CREATE VIEW _players_winrate AS
SELECT
	*, 1.0 * score / (round * winval) AS winrate
FROM
	_players_score;

CREATE VIEW _players_owrate AS
SELECT
	*, (SELECT AVG(winrate) FROM _players_winrate
			WHERE id IN (SELECT p1_id FROM matches WHERE p2_id = me.id)
			OR id IN (SELECT p2_id FROM matches WHERE p1_id = me.id)) AS owrate
FROM
	_players_winrate me;

CREATE VIEW playersx AS
SELECT
	*, (SELECT COUNT(*) FROM _players_owrate o
			WHERE o.event_id == me.event_id
			AND (o.score > me.score
				OR o.score == me.score AND o.owrate > me.owrate)) + 1 AS rank
FROM
	_players_owrate me
ORDER BY
	score DESC, owrate DESC, seed DESC;
