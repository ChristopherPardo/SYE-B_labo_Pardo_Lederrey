#include <stdio.h>

/* Tableau global : stocké dans .data (modifiable, adresse fixe) */
char str[] = "Hello world !";

int main(void)
{
	int i;

	printf("%s\n", str);
	printf("Adresse de la chaine : %p\n", (void *) str);

	/* Incrémente chaque byte de la chaîne via son adresse en dur */
	for (i = 0; ((volatile char *) 0x14b54)[i] != '\0'; i++)
		((volatile char *) 0x14b54)[i]++;

	printf("%s\n", str);

	return 0;
}