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

sub last_insert_id {
	my $self = shift;
	$self->dbh->last_insert_id(undef, undef, shift, "id");
}

sub player {
	my ($self, $id) = @_;
	$self->_find("players", $id);
}

sub playerx {
	my ($self, $id) = @_;
	$self->_find("playersx", $id);
}

sub _find {
	my ($self, $tbl, $id) = @_;

	croak "Bad table name" unless grep { $tbl eq $_ }
		qw/events players playersx matches scores/;

	my $stmt = qq{ SELECT * FROM $tbl WHERE id = ? };
	my $sth = $self->{_sth}{$tbl} //= $self->dbh->prepare($stmt);
	$sth->execute($id);

	if (my $player = $sth->fetchrow_hashref) {
		return $player;
	}
	else {
		croak "$tbl($id) not found";
	}
}

1;
