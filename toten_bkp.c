#include <stdio.h>
int main()
{
int* acc;

int VAR_1;
int VAR_2;
int VAR_3;

LINE_1: VAR_1=0;
LINE_2: acc=&VAR_3;
LINE_3: *acc=10;
LINE_4: acc=&VAR_2;
LINE_5: *acc=VAR_1;
LINE_6: *acc-=VAR_3;
LINE_7: if(VAR_2!=0) goto LINE_9;
LINE_8: return 0;
LINE_9: VAR_1++;
LINE_10: printf("%d\n",VAR_1);
LINE_11: goto LINE_4;

}