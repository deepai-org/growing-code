@varops= qw|if ifnot print add sub mul div inc dec mod zero setv mark swap stop|;

$pre='#include <stdio.h>
int main()
{

';
$post='}
';

while(<>) {
	chomp $_;
	push(@file, $_) if /\w+\s\d+/;	
	}

$lines=$#file + 1;
#print "$lines lines\n";

for(@file){
	push(@op, (split(/\s/,$_))[0]);
	push(@opand, (split(/\s/,$_))[1]);
	}
# acc starts at variable 0 in the interpreter, so always declare it
push(@varn, 0);
for($i=0;$i<=$#op;$i++){
	if(grep($op[$i]eq$_, @varops)){
		push(@varn, $opand[$i]) unless grep($_ == $opand[$i],@varn);
		}
	}
#print $#varn+1 ." vars\n";
for($i=0;$i<=$#varn;$i++) {
	#print "$varn[$i] --> $i\n";
	$vari{$varn[$i]}=$i;
	}
print $pre;
for($i=0;$i<=$#varn;$i++){
	print "int VAR_$vari{$varn[$i]}=0;\n";
	}
print "int* acc=&VAR_$vari{0};\nint _swap_tmp=0;\n";

for($i=0;$i<=$#op;$i++) {
	#print "LINE_$i: $op[$i] $vari{$opand[$i]}\n";
	$op=$op[$i];
	$opand=$opand[$i];
	#unless($vari{$opand} and $vari{$opand} ne "0") {print "\n$opand\n"}
	print "LINE_$i: ";
	if($op eq "stop") {print "return 0;"; goto EOL}
	if($op eq "mark") {print "acc=&VAR_$vari{$opand};"; goto EOL}
	if($op eq "setc") {print "*acc=$opand;"; goto EOL}
	if($op eq "setv") {print "*acc=VAR_$vari{$opand};"; goto EOL}
	if($op eq "zero") {print "VAR_$vari{$opand}=0;"; goto EOL}
	if($op eq "sub") {print "*acc-=VAR_$vari{$opand};"; goto EOL}
	if($op eq "add") {print "*acc+=VAR_$vari{$opand};"; goto EOL}
	if($op eq "mul") {print "*acc*=VAR_$vari{$opand};"; goto EOL}
	if($op eq "div") {print "*acc = (VAR_$vari{$opand}) ? *acc/VAR_$vari{$opand} : 0;"; goto EOL}
	if($op eq "mod") {print "*acc = (VAR_$vari{$opand}) ? *acc%VAR_$vari{$opand} : 0;"; goto EOL}
	if($op eq "inc") {print "VAR_$vari{$opand}++;"; goto EOL}
	if($op eq "dec") {print "VAR_$vari{$opand}--;"; goto EOL}
	if($op eq "swap") {print "_swap_tmp=*acc; *acc=VAR_$vari{$opand}; VAR_$vari{$opand}=_swap_tmp;"; goto EOL}
	if($op eq "print") {print 'printf("%d\n"'.",VAR_$vari{$opand});"; goto EOL}
	if($op eq "if" or $op eq "ifnot") {
		my $dline=$i+2;
		if($dline>$#op){print "return 0;"; goto EOL;}
		print "if(VAR_$vari{$opand}".
					($op eq "if"?'==':'!=')
					."0) goto LINE_$dline;";
		goto EOL;
		}
	if($op eq "up" or $op eq "down") {
		if($opand == 0){print ";"; goto EOL;}
		my $seeking=$i;
		#print "\$seeking is $seeking\n";
		#print "\$opand is $opand\n";
		for($steps=$opand;$steps != 0;$steps--){
		#	print "\$steps is $steps\n";
			do {
				if($op eq "up"){
					$seeking--;
					}
				else {
					$seeking++;
					}
				if($seeking>$#op or $seeking < 0) {print ";";goto EOL;}
				} while ($op[$seeking] ne "mark");
			}
		print "goto LINE_$seeking;";
		goto EOL;
		}
	die "bad op";
	EOL:
	print "\n";
	}
print $post;




