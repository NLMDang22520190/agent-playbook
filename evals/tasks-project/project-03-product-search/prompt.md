We want a search box on the shop page.

Ticket SHOP-240:
- New function `searchProducts(products, query)` in `src/catalog.js`.
- It returns the products whose name or sku contains the query, ignoring case, sorted by name A to Z (ignoring case).
- An empty query returns every product. The input list is not changed.
