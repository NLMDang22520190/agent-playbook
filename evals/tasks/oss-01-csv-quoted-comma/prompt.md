`total_by_column` gives wrong results (or crashes with a ValueError) as soon as a text field contains a comma. Spreadsheet
exports quote such fields, for example:

```
desc,qty
"Pens, blue",3
Paper,2
```

`total_by_column(text, 'qty')` should be 5 here. Quoted fields can also contain doubled quotes (`"He said ""hi"""`), as
in any normal CSV export.

Please fix it. Keep it standard library only; no new dependencies.
