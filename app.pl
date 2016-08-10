use Mojolicious::Lite;
use v5.14;

use Data::Dump;
use Graph::Matching qw/max_weight_matching/;
use Swiss;

my $swiss = Swiss->new;

get '/' => sub {
	my $c = shift;
	$c->render(template => 'event/list', events => $swiss->events);
};

post '/event/new' => sub {
	my $c = shift;

	return unless length $c->param('name');

	my $sth = $swiss->_sth(q{ INSERT INTO events (name, round, created) VALUES (?, 0, ?) });
	$sth->execute($c->param('name'), time);

	$c->redirect_to('/');
};

under '/event/:id' => sub {
	my $c = shift;
	my $id = $c->param('id');

	return unless $id =~ /^\d+$/;
	return $c->stash->{event} = $swiss->event($id);
};

get '/' => sub {
	my $c = shift;
	$c->render(
		template => 'event/view',
		players => $swiss->players($c->stash->{event}{id})
	);
};

get '/crosstable' => sub {
	my $c = shift;
	$c->render(
		template => 'event/crosstable',
		players => $swiss->playersx($c->stash->{event}{id})
	);
};

get '/round/:round' => sub {
	my $c = shift;
	$c->render_exception unless $c->param('round') =~ /^\d+$/ and $c->param('round') <= $c->stash->{event}{round};

	my $matches = $swiss->matches($c->stash->{event}{id}, $c->param('round'));
	for my $match (@$matches) {
		$match->{p1} = $swiss->playerx($match->{p1_id});
		$match->{p2} = $swiss->playerx($match->{p2_id});
	}

	$c->render(
		template => 'event/round',
		matches => $matches,
	);
};

post '/round/new' => sub {
	my $c = shift;

	my $players = $swiss->playersx($c->stash->{event}{id});
	my $matches = $swiss->matches($c->stash->{event}{id});

	my $penrematch = 10000;
	my $pengroup = @$players;

	my @gmax = (0);
	my $head = $players->[0];
	for my $player (@$players) {
		if ($gmax[-1] != 0 && $gmax[-1] % 2 == 0 && $head->{score} != $player->{score}) {
			push @gmax, 0;
			$head = $player;
		}
		$player->{pos} = $gmax[-1]++;
		$player->{group} = $#gmax;
	}

	my @matrix;
	for my $player (@$players) {
		my %played;
		for my $match (@$matches) {
			$played{$match->{p2_id}} = 1 if $match->{p1_id} == $player->{id};
			$played{$match->{p1_id}} = 1 if $match->{p2_id} == $player->{id};
		}


		my $step = int ($gmax[$player->{group}]) / 2;
		my $target = $player->{pos} + ($player->{pos} >= $step ? -$step : $step);

		my @row;
		for my $opp (@$players) {
			if ($player->{id} == $opp->{id}) {
				push @row, undef;
				next;
			}

			my $weight = 1;
			if ($played{$opp->{id}}) {
				$weight += $penrematch;
			}
			if ($player->{group} == $opp->{group}) {
				$weight += abs($opp->{pos} - $target);
			}
			else {
				$weight += $pengroup * abs($player->{group} - $opp->{group});
				$weight += abs(($player->{group} < $opp->{group}) * $gmax[$opp->{group}] - $opp->{pos});
			}
			push @row, 100000 - $weight;
		}
		push @matrix, \@row;
	}

	my @graph;
	for my $i (0..$#matrix) {
		for my $j ($i+1..$#matrix) {
			push @graph, [ $i, $j, $matrix[$i][$j] + $matrix[$j][$i] ];
		}
	}

	my %matching = max_weight_matching(\@graph);

	my %seen;
	my @pairs;
	while (my ($l, $r) = each %matching) {
		next if $seen{$l};
		$seen{$r} = 1;
		push @pairs, [
			$players->[$l]->{id},
			$players->[$r]->{id},
			$players->[$l]->{score} + $players->[$r]->{score}
		];
	}

	my $sth = $swiss->_sth(q{
		INSERT INTO matches (p1_id, p2_id, round, event_id) VALUES (?,?,?,?)
	});

	for my $pair (reverse sort { $a->[2] <=> $b->[2] } @pairs) {
		$sth->execute(
			@{$pair}[0,1],
			$c->stash->{event}{round} + 1,
			$c->stash->{event}{id}
		);
	}

	$swiss->_sth(q{
		UPDATE events SET round=round+1 WHERE id = ? })->execute($c->stash->{event}{id});

	$c->redirect_to('/event/' . $c->stash->{event}{id});
};

post '/round/:round' => sub {
	my $c = shift;
	return unless $c->param('round') =~ /^\d+$/ and $c->param('round') <= $c->stash->{event}{round};

	my $sth = $swiss->_sth(q{ UPDATE matches SET p1_score=?, p2_score=? WHERE id=? });

	my $matches = $swiss->matches($c->stash->{event}{id}, $c->param('round'));
	for my $match (@$matches) {
		my $p1_score = $c->param($match->{id} . "_p1");
		my $p2_score = $c->param($match->{id} . "_p2");

		if ($p1_score =~ /^\d+$/ && $p2_score =~ /^\d+$/ && $p1_score + $p2_score <= $c->stash->{event}{winval}) {
			$sth->execute(int $p1_score, int $p2_score, $match->{id});
		}
	}

	$c->redirect_to($c->req->url);
};

post '/player/new' => sub {
	my $c = shift;

	return unless length $c->param('name');

	my $sth = $swiss->_sth(q{ INSERT INTO players (event_id, name, seed) VALUES (?, ?, ?) });
	$sth->execute($c->stash->{event}{id}, $c->param('name'), $c->param('seed') || 100 + rand);

	$c->redirect_to('/event/' . $c->stash->{event}{id});
};

app->start;
__DATA__

@@ layouts/default.html.ep

<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf8">
		<title>Swiss</title>
		<style>
			label {
				display: block;
			}
			.name {
				padding: 0 0.5em;
			}
		</style>
	</head>
	<body>
		<h1><a href="/">Swiss</a></h1>

		% if (defined stash('event')) {
		<h2>
			<a href="/event/<%= stash('event')->{id} %>">
				<%= stash('event')->{name} %>
			</a>
		</h2>
		% }

		<%= content %>
	</body>
</html>

@@ event/list.html.ep
% layout 'default';
% use POSIX qw/strftime/;

<form action="/event/new/" method="post">
	<table>
		<tbody>
			<tr>
				<td><input type="text" name="name" placeholder="Event name" size="24" required></td>
				<td><input type="submit" value="New event"></td>
			</tr>
			% for my $event (reverse @$events) {
			<tr>
				<td>
					<a href="/event/<%= $event->{id} %>">
						<%= $event->{name} %>
					</a>
				</td>
				<td><%= strftime("%d %b %Y", localtime $event->{created}) %></td>
			</tr>
			% }
		</tbody>
	</table>
</form>

@@ event/view.html.ep
% layout 'default';

<form action="/event/<%= $event->{id} %>/player/new" method="post">
	<table>
		<tbody>
			<tr>
				<td><input type="text" name="name" placeholder="Player name" size="24" required></td>
				<td><input type="text" name="seed" placeholder="Seed" size="8"></td>
				<td><input type="submit" value="Add player"></td>
			</tr>
			% for my $player (@$players) {
			<tr>
				<td><%= $player->{name} %></td>
				<td><%= sprintf("%.5f", $player->{seed}) %></td>
				<td></td>
			</tr>
			% }
		</tbody>
	</table>
</form>

<a href="/event/<%= $event->{id} %>/crosstable">Crosstable</a><br>
% for my $round (1..$event->{round}) {
<a href="/event/<%= $event->{id} %>/round/<%= $round %>">Round <%= $round %></a><br>
% }
<form action="/event/<%= $event->{id} %>/round/new" method="post">
	<input type="submit" value="New round">
</form>

@@ event/round.html.ep
% layout 'default';

<h3>Round <%= param('round') %></h3>

<form method="post">
	<table>
		<tbody>
			% for my $match (@$matches) {
			<tr>
				<td><%= $match->{p1}{name} %></td>
				<td>
					<input type="text" size="2" value="<%= $match->{p1_score} %>"
						name="<%= $match->{id} %>_p1">
				</td>
				<td>-</td>
				<td>
					<input type="text" size="2" value="<%= $match->{p2_score} %>"
						name="<%= $match->{id} %>_p2">
				</td>
				<td><%= $match->{p2}{name} %></td>
			</tr>
			% }
		</tbody>
	</table>
	<input type="submit" value="Update">
</form>

@@ event/crosstable.html.ep
% layout 'default';

<table>
	<tbody>
		<tr>
			<th>Rank</th>
			<th>Player</th>
			<th>Score</th>
			<th>Win rate</th>
			<th>OWR</th>
		</tr>

		% for my $player (@$players) {
		<tr>
			<td style="text-align: center"><%= $player->{rank} %></td>
			<td><%= $player->{name} %></td>
			<td style="text-align: center"><%= $player->{score} %></td>
			<td style="text-align: center"><%= sprintf "%.2f", $player->{winrate} // 0 %></td>
			<td style="text-align: center"><%= sprintf "%.2f", $player->{owrate} // 0 %></td>
		</tr>
		% }
	</tbody>
</table>
