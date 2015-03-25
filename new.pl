#!/usr/bin/env perl
use 5.01;
use strict;

use Swiss;
use Data::Dump;
use List::Util qw/shuffle/;

my $swiss = Swiss->new;

if (my $method = main->can(shift)) {
	$method->(@ARGV);
}

sub event {
	my $name = shift or die "No event name given";

	my $stmt = q{ INSERT INTO events (name, round, created) VALUES (?, 0, ?) };
	my $sth = $swiss->dbh->prepare($stmt);
	$sth->execute($name, time);

	dd $swiss->event($swiss->last_insert_id("events"));
}

sub players {
	my $event = $swiss->event(shift);

	my $stmt = q{ INSERT INTO players (event_id, name, seed) VALUES (?, ?, ?) };
	my $sth = $swiss->dbh->prepare($stmt);

	while (chomp(my $in = <STDIN>)) {
		$sth->execute($event->{id}, $in, rand);
		dd $swiss->player($swiss->last_insert_id("players"));
	}
}

sub round {
	my $eid = shift;

	my $tick = $swiss->dbh->prepare(q{
		UPDATE events SET round = round + 1 WHERE id = ?
	});
	$tick->execute($eid);

	my $event = $swiss->event($eid);

	my $bye = $swiss->dbh->prepare(q{
		INSERT INTO scores (player_id, round, value) VALUES (?, ?, ?)
	});

	my $match = $swiss->dbh->prepare(q{
		INSERT INTO matches (event_id, p1_id, p2_id, round) VALUES (?, ?, ?, ?)
	});

	my $_seen = $swiss->dbh->prepare(q{
		SELECT COUNT(*) FROM matches WHERE
			p1_id = ? AND p2_id = ? OR
			p2_id = ? AND p1_id = ?
	});
	my $seen = sub {
		my ($p1, $p2);
		$_seen->execute($p1->{id}, $p2->{id}, $p1->{id}, $p2->{id});
		return ($_seen->fetchrow_array)[0];
	};

	my $players = $swiss->dbh->prepare(q{
		SELECT id,score FROM playersx WHERE event_id = ? AND dropped = 0
	});
	$players->execute($eid);

	my @players = @{ $players->fetchall_arrayref({}) };

	# Pairing algorithm goes here
	while (@players) {
		my $p1 = shift @players;
		my $p2 = shift @players;

		if (!$p2) {
			$bye->execute($p1->{id}, $event->{round}, $event->{winval});
		}
		else {
			my @seen;
			while ($seen->($p1, $p2)) {
				last if !@players;
				push @seen, $p2;
				pop @players;
			}

			@players = (@seen, @players);
			$match->execute($event->{id}, $p1->{id}, $p2->{id}, $event->{round});
		}
	}
}
