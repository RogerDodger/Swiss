#!/usr/bin/env perl
use 5.01;
use strict;

use Swiss;
use Scalar::Util qw/looks_like_number/;

my $swiss = Swiss->new;
my $event = $swiss->event(shift);

my $matches = $swiss->dbh->prepare(q{
	SELECT * FROM matches WHERE event_id = ? AND round = ?
});
$matches->execute($event->{id}, $event->{round});

my $score = $swiss->dbh->prepare(q{
	INSERT INTO scores (player_id, round, value) VALUES (?, ?, ?)
});

while (my $row = $matches->fetchrow_hashref) {
	my $p1 = $swiss->player($row->{p1_id});
	my $p2 = $swiss->player($row->{p2_id});

	my ($s1, $s2);
	PROMPT: {
		printf "%10s - %-10s ... ", $p1->{name}, $p2->{name};
		chomp(my $in = <STDIN>);
		($s1, $s2) = split /-/, $in;

		for ($s1, $s2) {
			redo PROMPT unless looks_like_number $_;
			redo PROMPT unless 0 <= $_ && $_ <= $event->{winval};
		}
	}

	$score->execute($p1->{id}, $event->{round}, $s1);
	$score->execute($p2->{id}, $event->{round}, $s2);
}
