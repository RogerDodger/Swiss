#!/usr/bin/env perl

use Swiss;
my $swiss = Swiss->new;
my $event = $swiss->event(shift);

my $sth = $swiss->dbh->prepare(q{
	SELECT COUNT(*) FROM players WHERE event_id = ?
});
$sth->execute($event->{id});
my $p = ($sth->fetchrow_array)[0];

my $matches = $swiss->dbh->prepare(q{
	SELECT * FROM matches WHERE event_id = ? AND round = ?
});
$matches->execute($event->{id}, $event->{round});

my $rowf = <<'EOF';
%s & \hspace{6pt} %s \hspace{6pt} & \hspace{6pt} %s \hspace{6pt} & %s-%s \\
EOF

my $table = '';
my $n = 0;
while (my $match = $matches->fetchrow_hashref) {
	my $p1 = $swiss->playerx($match->{p1_id});
	my $p2 = $swiss->playerx($match->{p2_id});

	$table .= sprintf $rowf,
		++$n, $p1->{name}, $p2->{name}, $p1->{score}, $p2->{score};
}

my $bye = $swiss->dbh->prepare(q{
	SELECT * FROM players me
		WHERE event_id = ? AND dropped = 0
		AND 0 = (SELECT COUNT(*) FROM matches WHERE round = ?
			AND (p1_id = me.id OR p2_id = me.id))
});
$bye->execute($event->{id}, $event->{round});

if (my $row = $bye->fetchrow_hashref) {
	my $p = $swiss->playerx($row->{id});
	$table .= sprintf $rowf,
		"", $p->{name}, '\textit{Bye}', $p->{score} - $event->{winval}, q{\,\,\,};
}

my $template = do { local $/; <DATA> };
my $latex = sprintf( $template,
	$p*12 * $event->{round} - $p*12,
	$event->{name}, $event->{round},
	$table,
);

my $fn = lc ($event->{name} . " round " . $event->{round});
$fn =~ s/\s+/-/g;
chdir "/tmp";
open my $fh, '>', "$fn.tex";
print $fh $latex;
close $fh;
system "xelatex $fn.tex";
system "mv $fn.pdf ~/Dropbox/magic/$fn.pdf";

__DATA__
% !TEX TS-program = xelatex
% !TEX encoding = UTF-8

\documentclass[11pt]{article}

\usepackage{fontspec}
\defaultfontfeatures{Mapping=tex-text}
\usepackage{xunicode}
\usepackage{xltxtra}

\usepackage{geometry}
\geometry{a4paper}
\usepackage[parfill]{parskip}

\begin{document}

\hfill

\vspace{%spt}

{\large \textbf{%s -- Round %d}}

\begin{tabular}{cr|lc}
	Game & Player 1 \hspace{6pt} & \hspace{6pt} Player 2 & \\
	\hline
	%s
\end{tabular}

\end{document}
