#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/**
 * Auto-generated code below aims at helping you parse
 * the standard input according to the problem statement.
 * ---
 * Hint: You can use the debug stream to print initialTX and initialTY, if Thor seems not follow your orders.
 **/
int main()
{
    int LX; // the X position of the light of power
    int LY; // the Y position of the light of power
    int TX; // Thor's starting X position
    int TY; // Thor's starting Y position
    scanf("%d%d%d%d", &LX, &LY, &TX, &TY);

    // game loop
    while (1) {
        int remainingTurns;
        scanf("%d", &remainingTurns);
		if (LX < 20 && LY <9) {
			if (TX < 20 && TY <9) {}
			else
			printf("NW\n");
			
		
        // Write an action using printf(). DON'T FORGET THE TRAILING \n
        // To debug: fprintf(stderr, "Debug messages...\n");

        printf("SE\n"); // A single line providing the move to be made: N NE E SE S SW W or NW
    }
	
	
    return 0;
}
