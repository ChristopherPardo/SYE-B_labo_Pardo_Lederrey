/*
 * Copyright (C) 2014-2017 Daniel Rossier <daniel.rossier@heig-vd.ch>
 * Copyright (C) 2019-2020 Julián Burella Pérez <julian.burellaperez@heig-vd.ch>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#include <dirent.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <dirent.h>
#include <sys/stat.h>
#include <syscall.h>



/*
 * Main function of ls application.
 * The ls application is very very short and does not support any options like
 * -l -a etc. It is only possible to give a subdir name to list the directory
 * entries of this subdir.
 */

int main(int argc, char **argv)
{
	DIR *stream;
	struct dirent *p_entry;
	char *dir;
	int extended = 0;
	const char *usage = "Usage: ls [DIR]\n";

	if (argc == 1) {
		dir = ".";
	} else if (argc == 2) {
		dir = argv[1];
	} else {
		printf("%s", usage);
		exit(1);
	}

	stream = opendir(dir);

	if (stream == NULL)
		exit(1);

	while ((p_entry = readdir(stream)) != NULL) {
		printf("%s%s\n", p_entry->d_name, p_entry->d_type == DT_DIR ? "/" : "");
	}

	exit(0);
}

