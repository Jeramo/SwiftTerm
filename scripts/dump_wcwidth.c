/*
 * dump_wcwidth LOCALE > OUT : wcwidth(3) of every code point under LOCALE,
 * one "HEX WIDTH" line each, for regen_wcwidth_data.py.
 *
 *   cc -o dump_wcwidth scripts/dump_wcwidth.c && ./dump_wcwidth en_US.UTF-8 > darwin.txt
 */
#include <locale.h>
#include <stdio.h>
#include <wchar.h>

int
main (int argc, char **argv)
{
	if (argc < 2 || setlocale (LC_ALL, argv [1]) == NULL) {
		fprintf (stderr, "usage: dump_wcwidth UTF-8-LOCALE\n");
		return 1;
	}
	for (unsigned cp = 0; cp < 0x110000; cp++) {
		if (cp >= 0xD800 && cp <= 0xDFFF)
			continue;
		printf ("%X %d\n", cp, wcwidth ((wchar_t) cp));
	}
	return 0;
}
