A customer's wallet was credited twice for one payment of 100.

Looking at the provider's dashboard, they delivered the webhook for that payment twice (same event id `evt_1`, the
second delivery about 30 seconds after the first, because our endpoint answered slowly). Their docs say deliveries
are retried until acknowledged, so the same event can arrive more than once, possibly after other events.

Please make the webhook handling credit each payment event only once. Different events must still all be credited.
