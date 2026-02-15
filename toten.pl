#!/usr/bin/perl
# toten.pl - unified driver for the growing code toolkit
#
# usage: perl toten.pl <command> [args...]
#
# commands:
#   run      <file.tot> [steps] [max_out]   run a toten program
#   compile  [file.tot]                     compile toten to C
#   evolve   [target] [gens] [--seed/--save] evolve programs
#   random   [N]                            generate a random program
#   help                                    show this message

use strict;
use warnings;

my $dir;
BEGIN {
	use File::Basename;
	$dir = dirname(__FILE__);
}

my $cmd = shift @ARGV || 'help';

if($cmd eq 'run'){
	die "usage: toten.pl run <file.tot> [max_steps] [max_output]\n" unless @ARGV;
	exec 'perl', "$dir/run.pl", @ARGV;

} elsif($cmd eq 'compile'){
	if(@ARGV && $ARGV[0] ne '-'){
		open my $fh, '<', $ARGV[0] or die "can't open $ARGV[0]: $!\n";
		open my $pipe, '|-', 'perl', "$dir/toc.pl" or die "can't run toc.pl: $!\n";
		print $pipe $_ while <$fh>;
		close $fh;
		close $pipe;
	} else {
		exec 'perl', "$dir/toc.pl";
	}

} elsif($cmd eq 'evolve'){
	exec 'perl', "$dir/evolve.pl", @ARGV;

} elsif($cmd eq 'random'){
	my $n = $ARGV[0] || 24;
	open my $pipe, '-|', "perl $dir/random.pl $n | perl $dir/nums.pl"
		or die "can't run pipeline: $!\n";
	print while <$pipe>;
	close $pipe;

} elsif($cmd eq 'help' || $cmd eq '-h' || $cmd eq '--help'){
	print <<'USAGE';
toten.pl - the growing code toolkit

commands:
  run <file.tot> [steps] [max_out]    interpret a toten program directly
  compile [file.tot]                  compile toten to C (stdout)
  evolve [target] [gens] [flags]      evolve programs toward a target
  random [N]                          generate a random toten program (default N=24)
  help                                show this message

examples:
  perl toten.pl run examples/count.tot
  perl toten.pl compile examples/count.tot | gcc -x c - -o count && ./count
  perl toten.pl evolve count 500 --seed 42 --save best.tot
  perl toten.pl random 30
  perl toten.pl random 24 > rand.tot && perl toten.pl run rand.tot

targets for evolve:
  count, squares, fib, primes, evens, odds, powers, or a number N
USAGE

} else {
	die "unknown command '$cmd'\ntry: perl toten.pl help\n";
}
