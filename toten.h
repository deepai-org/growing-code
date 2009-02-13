
zero 1
mark 3
setc 10
mark 2
setv 1
sub 3
ifnot 2
stop 0
inc 1
print 1
up 1

########################################
@ops= qw |if ifnot up down print add sub mul inc dec mod zero setv setc mark stop|;
$m=10;
while(<>){
	if($FF){$FF=0}else{$FF=1}
	chomp $_;
	if($FF) {
		print $ops[$_%$#ops];
		}
	else {
		print " ".$_%$m."\n";
		}
	}
########################################
for(1..$ARGV[0]){
	print int(rand(256))."\n";
	}
