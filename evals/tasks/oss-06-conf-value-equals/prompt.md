Our deploy connected to the database without TLS. `deploy.conf` has

```
db.url=postgres://db.example.invalid/app?sslmode=require
```

but `bin/confget db.url deploy.conf` prints `postgres://db.example.invalid/app?sslmode`, and the rest of the value is lost.

Please fix it so `conf_get` returns exactly the value the file sets, for any key and any value the config format in
`README.md` allows.
