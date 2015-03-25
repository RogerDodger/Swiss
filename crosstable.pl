#!/usr/bin/env perl

use Swiss;
my $swiss = Swiss->new;
my $event = $swiss->event(shift);

my $playersx = $swiss->dbh->prepare(q{
	SELECT * FROM playersx WHERE event_id = ?
});
$playersx->execute($event->{id});

my $table;
my $rowf = q{ %s & %s & %s & %.2f & %.2f \\\\ };
my ($rank, $rank_low, $lasts, $lasto) = (0, 0, 1 << 32, 1);
while (my $p = $playersx->fetchrow_hashref) {
	$rank_low++;
	if ($lasts > $p->{score} || $lasto > $p->{owrate}) {
		$rank = $rank_low;
		$lasts = $p->{score};
		$lasto = $p->{owrate};
	}
	$table .= sprintf $rowf,
		$rank, $p->{name}, $p->{score}, $p->{winrate}, $p->{owrate};
}

my $template = do { local $/; <DATA> };
my $latex = sprintf( $template,
	$event->{name},
	$table,
);

my $fn = lc ($event->{name} . " crosstable");
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

{\large \textbf{%s -- Crosstable}}

\begin{tabular}{ccccc}
	Rank & Player & Score & Win rate & OWR \\
	\hline
	%s
\end{tabular}

\end{document}
