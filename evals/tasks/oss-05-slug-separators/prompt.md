Product links break as soon as a product name has a space in it. `Summer Sale 2026` gets the link
`/p/summer%20sale%202026` instead of `/p/summer-sale-2026`, and some shared links do not open at all.

Please fix it so that every product name, whatever characters it holds, gets a slug that follows the rule in
`docs/urls.md`.
