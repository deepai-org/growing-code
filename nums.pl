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