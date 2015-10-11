package Swiss;
use 5.01;
use strict;

use Carp qw/croak/;
use DBI;
use FindBin qw/$Bin/;
use Scalar::Util qw/looks_like_number/;

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	# Database connection
	my $fn = "$Bin/swiss.db";
	my $exists = -e $fn;
	my $dbh = DBI->connect("dbi:SQLite:$fn","","", { sqlite_unicode => 1 });

	# First run, create tables
	if (!$exists) {
		open my $fh, '<', 'schema.sql';
		local $/ = ';';
		while (my $stmt = readline $fh) {
			$dbh->do($stmt);
		}
		close $fh;
	}

	$self->dbh($dbh);

	return $self;
}

sub dbh {
	my $self = shift;
	$self->{dbh} = shift if @_;
	$self->{dbh};
}

sub event {
	my $self = shift;
	$self->{event} = $self->_find("events", shift) if @_;
	$self->{event};
}

sub events {
	my $self = shift;
	return $self->_list("events");
}

sub last_insert_id {
	my $self = shift;
	$self->dbh->last_insert_id(undef, undef, shift, "id");
}

sub matches {
	my ($self, $id, $round) = @_;

	my $stmt = qq{ SELECT * FROM matches WHERE event_id = ? };
	$stmt .= q{ AND round = ? } if defined $round;
	my $sth = $self->_sth($stmt);
	$sth->execute($id, defined $round ? $round : ());
	return $sth->fetchall_arrayref({});
}

sub player {
	my ($self, $id) = @_;
	$self->_find("players", $id);
}

sub players {
	my ($self, $id) = @_;

	my $sth = $self->_sth(qq{ SELECT * FROM players WHERE event_id = ? });
	$sth->execute($id);
	return $sth->fetchall_arrayref({});
}

sub playerx {
	my ($self, $id) = @_;
	$self->_find("playersx", $id);
}

sub playersx {
	my ($self, $id) = @_;

	my $sth = $self->_sth(qq{ SELECT * FROM playersx WHERE event_id = ? });
	$sth->execute($id);
	return $sth->fetchall_arrayref({});
}

sub _chk_tblname {
	my ($self, $tbl) = @_;

	croak "Bad table name" unless grep { $tbl eq $_ }
		qw/events players playersx matches/;
}

sub _list {
	my ($self, $tbl) = @_;
	$self->_chk_tblname($tbl);

	my $sth = $self->_sth(qq{ SELECT * FROM $tbl });
	$sth->execute;
	return $sth->fetchall_arrayref({});
}

sub _find {
	my ($self, $tbl, $id) = @_;
	$self->_chk_tblname($tbl);

	my $stmt = qq{ SELECT * FROM $tbl WHERE id = ? };
	my $sth = $self->{_sth}{"find$tbl"} //= $self->dbh->prepare($stmt);
	$sth->execute($id);

	if (my $row = $sth->fetchrow_hashref) {
		return $row;
	}
	else {
		croak "$tbl($id) not found";
	}
}

sub _sth {
	my ($self, $stmt) = @_;
	return $self->{_sth}{$stmt} //= $self->dbh->prepare($stmt);
}

1;
