#!/usr/bin/perl
# test.pl - test suite for the growing code toolkit
#
# usage: perl test.pl
#
# verifies that interpreter, compiler, and evolution
# all produce consistent and correct results.

use strict;
use warnings;
use File::Basename;

my $dir = dirname(__FILE__);
my $pass = 0;
my $fail = 0;

sub ok {
	my $cond = shift;
	my $name = shift;
	if($cond){
		print "  ok    $name\n";
		$pass++;
	} else {
		print "  FAIL  $name\n";
		$fail++;
	}
}

sub run_cmd {
	my $cmd = shift;
	my $out = `$cmd 2>&1`;
	chomp $out;
	return $out;
}

# ==========================================
print "--- interpreter tests ---\n";
# ==========================================

# count.tot should produce 1..10
{
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/count.tot'");
	my @vals = split /\n/, $out;
	ok(scalar @vals == 10, "count.tot produces 10 values");
	ok($vals[0] == 1 && $vals[9] == 10, "count.tot produces 1..10");
}

# evolved-count.tot should start with 1,2,3...
{
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/evolved-count.tot' 10000 10");
	my @vals = split /\n/, $out;
	ok(scalar @vals == 10, "evolved-count.tot produces 10 values (limited)");
	ok($vals[0] == 1 && $vals[4] == 5, "evolved-count.tot counts correctly");
}

# evolved-evens.tot should produce even numbers
{
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/evolved-evens.tot' 10000 5");
	my @vals = split /\n/, $out;
	ok(scalar @vals == 5, "evolved-evens.tot produces 5 values (limited)");
	ok($vals[0] == 2 && $vals[1] == 4 && $vals[2] == 6, "evolved-evens.tot produces 2,4,6...");
}

# max_steps limit works
{
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/evolved-count.tot' 10 100");
	my @vals = split /\n/, $out;
	ok(scalar @vals < 100, "step limit halts infinite programs");
}

# max_output limit works
{
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/evolved-count.tot' 10000 3");
	my @vals = split /\n/, $out;
	ok(scalar @vals == 3, "output limit caps at 3");
}

# ==========================================
print "\n--- compiler tests ---\n";
# ==========================================

# check if gcc is available
my $has_gcc = !system("which gcc >/dev/null 2>&1");

if($has_gcc){
	# compile count.tot and check output matches interpreter
	{
		my $interp = run_cmd("perl '$dir/run.pl' '$dir/examples/count.tot'");
		my $c_code = run_cmd("perl '$dir/toten.pl' compile '$dir/examples/count.tot'");
		ok(length($c_code) > 0, "compiler produces C output");
		ok(scalar($c_code =~ /^#include/), "C output has proper header");

		# compile and run
		system("perl '$dir/toten.pl' compile '$dir/examples/count.tot' | gcc -x c - -o /tmp/toten_test_count 2>/dev/null");
		if(-f '/tmp/toten_test_count'){
			my $compiled = run_cmd("/tmp/toten_test_count");
			ok($compiled eq $interp, "compiled count.tot matches interpreter output");
			unlink '/tmp/toten_test_count';
		} else {
			ok(0, "compiled count.tot matches interpreter output (compile failed)");
		}
	}

	# compile evolved-count.tot — runs forever, so pipe to head
	{
		system("perl '$dir/toten.pl' compile '$dir/examples/evolved-count.tot' | gcc -x c - -o /tmp/toten_test_ecount 2>/dev/null");
		if(-f '/tmp/toten_test_ecount'){
			my $compiled = run_cmd("/tmp/toten_test_ecount | head -5");
			my @vals = split /\n/, $compiled;
			ok($vals[0] == 1 && $vals[4] == 5, "compiled evolved-count starts 1,2,3,4,5");
			unlink '/tmp/toten_test_ecount';
		} else {
			ok(0, "compiled evolved-count starts 1,2,3,4,5 (compile failed)");
		}
	}
} else {
	print "  skip  (gcc not found — skipping compiler tests)\n";
}

# ==========================================
print "\n--- random generation tests ---\n";
# ==========================================

{
	my $out = run_cmd("perl '$dir/toten.pl' random 10");
	my @lines = split /\n/, $out;
	ok(scalar @lines == 5, "random 10 bytes produces 5 instructions");

	# each line should be "opcode operand"
	my $valid = 1;
	for(@lines){
		$valid = 0 unless /^\w+ \d$/;
	}
	ok($valid, "random output is valid toten format");
}

{
	# two random runs should differ (probabilistic but near-certain)
	my $a = run_cmd("perl '$dir/toten.pl' random 20");
	my $b = run_cmd("perl '$dir/toten.pl' random 20");
	ok($a ne $b, "random generation is non-deterministic");
}

# ==========================================
print "\n--- minimizer tests ---\n";
# ==========================================

{
	my $out = run_cmd("perl '$dir/minimize.pl' '$dir/examples/evolved-evens.tot'");
	ok(scalar($out =~ /7 -> 6/), "minimizer removes vestigial instruction from evolved-evens");
	ok(scalar($out =~ /^setc 1$/m), "minimized program retains setc 1");
	ok(scalar($out !~ /mod 0/), "minimizer removed dead mod 0");
}

{
	# minimizing count.tot removes zero 1 (var 1 defaults to 0 already)
	my $out = run_cmd("perl '$dir/minimize.pl' '$dir/examples/count.tot'");
	ok(scalar($out =~ /11 -> 10/), "minimizer removes redundant zero from count.tot");
}

# ==========================================
print "\n--- tracer tests ---\n";
# ==========================================

{
	my $out = run_cmd("perl '$dir/trace.pl' '$dir/examples/evolved-count.tot' 12");
	ok(scalar($out =~ /program listing/), "tracer shows program listing");
	ok(scalar($out =~ /execution trace/), "tracer shows execution trace");
	ok(scalar($out =~ /=> 1/), "tracer shows output values");
	ok(scalar($out =~ /-> line 0/), "tracer shows jump targets");
	ok(scalar($out =~ /acc->v2/), "tracer shows accumulator pointer");
}

# ==========================================
print "\n--- swap opcode tests ---\n";
# ==========================================

{
	# swap-test.tot: mark 1, setc 5, mark 2, setc 3, swap 1 → v1=3, v2=5
	my $out = run_cmd("perl '$dir/run.pl' '$dir/examples/swap-test.tot'");
	my @vals = split /\n/, $out;
	ok($vals[0] == 3 && $vals[1] == 5, "swap exchanges register values");
}

{
	# trace shows swap annotation
	my $out = run_cmd("perl '$dir/trace.pl' '$dir/examples/swap-test.tot'");
	ok(scalar($out =~ /v2<->v1/), "tracer annotates swap operation");
}

# ==========================================
print "\n--- auto-minimize tests ---\n";
# ==========================================

{
	my $out = run_cmd("perl '$dir/evolve.pl' evens 300 --seed 42");
	ok(scalar($out =~ /minimized from/), "auto-minimize reports reduction after evolution");
}

# ==========================================
print "\n--- island model tests ---\n";
# ==========================================

{
	my $out = run_cmd("perl '$dir/evolve.pl' count 100 --seed 42 --islands 3");
	ok(scalar($out =~ /islands=3/), "island model shows island count in header");
	ok(scalar($out =~ /\[\d\]/), "island model shows island index in progress");
	ok(scalar($out =~ /PERFECT ALGORITHM/), "island model finds solution");
}

# ==========================================
print "\n--- evolution tests ---\n";
# ==========================================

# count should be easily solvable with fixed seed
{
	my $out = run_cmd("perl '$dir/evolve.pl' count 200 --seed 42");
	ok(scalar($out =~ /PERFECT ALGORITHM/), "evolve count finds perfect algorithm (seed 42)");
	ok(scalar($out =~ /GENERALIZED/), "evolved count generalizes beyond training");
}

# evens with fixed seed
{
	my $out = run_cmd("perl '$dir/evolve.pl' evens 300 --seed 42");
	ok(scalar($out =~ /matched/), "evolve evens produces matches");
	# just verify evolution ran and produced some output
	$out =~ /matched (\d+)/;
	ok(($1 // 0) >= 1, "evolved evens matches at least 1 value");
}

# custom sequence
{
	my $out = run_cmd("perl '$dir/evolve.pl' '2,4,6' 100 --seed 42");
	ok(scalar($out =~ /target:.*2, 4, 6/), "custom sequence accepted");
	ok(scalar($out =~ /matched/), "custom sequence evolution runs");
}

# stats export
{
	my $sf = "/tmp/toten_test_stats.csv";
	run_cmd("perl '$dir/evolve.pl' count 50 --seed 42 --stats $sf");
	ok(-f $sf, "stats CSV file created");
	if(-f $sf){
		open my $fh, '<', $sf;
		my $header = <$fh>;
		chomp $header;
		ok($header eq 'gen,best_fitness,avg_fitness,best_len,matched', "stats CSV has correct header");
		my $lines = 0;
		$lines++ while <$fh>;
		close $fh;
		ok($lines == 50, "stats CSV has one row per generation");
		unlink $sf;
	}
}

# save flag
{
	my $sf = "/tmp/toten_test_save.tot";
	run_cmd("perl '$dir/evolve.pl' count 50 --seed 42 --save $sf");
	ok(-f $sf, "save flag creates .tot file");
	if(-f $sf){
		my $out = run_cmd("perl '$dir/run.pl' $sf 10000 5");
		my @vals = split /\n/, $out;
		ok(scalar @vals > 0, "saved program runs and produces output");
		unlink $sf;
	}
}

# ==========================================
print "\n--- compiler tests (all examples) ---\n";
# ==========================================

if($has_gcc){
	my @examples = glob("$dir/examples/*.tot");
	for my $ex (sort @examples){
		my $name = $ex;
		$name =~ s|.*/||;  # basename
		# get interpreter output (limit to 20 values)
		my $interp = run_cmd("perl '$dir/run.pl' '$ex' 10000 20");
		# compile to C and build
		my $bin = "/tmp/toten_test_" . $name;
		$bin =~ s/\.tot$//;
		system("perl '$dir/toten.pl' compile '$ex' | gcc -x c - -o '$bin' 2>/dev/null");
		if(-f $bin){
			# run compiled binary, limit output with head
			my $compiled = run_cmd("'$bin' | head -20");
			ok($compiled eq $interp, "compile $name matches interpreter");
			unlink $bin;
		} else {
			ok(0, "compile $name matches interpreter (gcc failed)");
		}
	}
} else {
	print "  skip  (gcc not found — skipping compiler tests)\n";
}

# ==========================================
print "\n" . "=" x 40 . "\n";
printf "%d passed, %d failed, %d total\n", $pass, $fail, $pass + $fail;
exit($fail > 0 ? 1 : 0);
