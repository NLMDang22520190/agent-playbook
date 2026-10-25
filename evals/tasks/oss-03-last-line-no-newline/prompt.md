`sum.sh` ignores the last number when the file does not end with a newline.

```
$ printf '1\n2\n3' > n.txt
$ bash sum.sh n.txt
3
```

Expected 6. Files exported from some editors and tools have no final newline, so this silently gives wrong totals.
Files that do end with a newline must keep working, and an empty file should still print 0.

Please fix `sum.sh`.
