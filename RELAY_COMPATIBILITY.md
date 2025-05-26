# Relay Compatibility Analysis

## Current Nostrface Relays:
- wss://relay.damus.io - Popular, used by Damus client
- wss://relay.nostr.band - Aggregator relay
- wss://nos.lol - Nos.social relay
- wss://nostr.wine - Paid relay (might require auth)
- wss://relay.snort.social - Snort client relay
- wss://relay.nostr.bg - Regional relay
- wss://purplepag.es - Special purpose relay
- wss://relay.nostr.com.au - Regional relay
- wss://nostr-pub.wellorder.net - General relay
- wss://nostr.mutinywallet.com - Wallet-specific relay

## Common Issues:

1. **Authentication**: Some relays like nostr.wine require NIP-42 authentication
2. **Rate Limiting**: Many relays limit events per time period
3. **Event Validation**: Relays verify signatures and event structure
4. **Relay Rules**: Some relays only accept certain event kinds or from certain pubkeys

## Recommendations:

1. **Add more common relays** that other clients use:
   - wss://relay.nostr.info
   - wss://nostr.fmt.wiz.biz
   - wss://relay.current.fyi
   - wss://nostr.bitcoiner.social

2. **Implement proper OK response handling** to know which relays accepted the event

3. **Show relay status** in the UI so users know where their follows are stored

4. **Allow users to configure their own relays** for better compatibility with their other clients