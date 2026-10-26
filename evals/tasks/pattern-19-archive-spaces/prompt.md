Files with a space in their name never make it into the archive. `bin/archive photos/ out/` prints a count that
looks right, but `my notes.txt` is not in `out/`. Please fix it so every file under the source directory is archived,
whatever its name.
