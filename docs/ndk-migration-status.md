# NDK Migration Status

## Overview
The migration from the `nostr` package to `dart_ndk` has been partially completed. The core NDK infrastructure is in place, but some services still depend on the old package for backwards compatibility.

## Completed Migration

### Phase 1: NDK Setup ✅
- Added NDK dependency from local path
- Created `NdkService` wrapper for centralized NDK management
- Implemented providers for NDK initialization

### Phase 2: Model Adapters ✅
- Created `NostrEventAdapter` for converting between NostrEvent and Nip01Event
- Created `NostrProfileAdapter` for converting between NostrProfile and Metadata
- Added `ContactListAdapter` extension for working with contact lists
- Updated NostrProfile model to include missing fields (lud06, lastUpdated)

### Phase 3: Service Migration ✅
- **ProfileServiceNdk**: Fully migrated profile fetching, following, and metadata management
- **DirectMessageServiceNdk**: Structure migrated, but encryption/decryption needs implementation
- **NdkEventSigner**: Custom event signer integrating with KeyManagementService

### Phase 4: New Features ✅
- **ReactionsServiceNdk**: NIP-25 reactions support
- **ListsServiceNdk**: NIP-51 lists (mute lists, bookmarks, pins)

### Phase 5: Build Fixes ✅
- Fixed API differences (pubkey vs pubKey)
- Updated all event creation to use correct NDK constructors
- Added missing dependencies (logging, bip340)
- Fixed provider initialization issues

## Pending Migration

### Services Still Using Old Package
1. **ProfileServiceV2** - Core profile service used by ProfileBufferServiceIndexed
2. **NostrRelayService** - Original relay management service
3. **DirectMessageService** - Original DM service with working encryption
4. **KeyManagementService** - Still imports old nostr package
5. **Various utility files** - nostr_utils.dart, follow_debug.dart

### Encryption/Decryption
- NIP-04 encryption/decryption not yet implemented in NdkEventSigner
- DirectMessageServiceNdk cannot encrypt/decrypt messages yet
- Need to implement using bip340 and crypto libraries

### Test Files
- Many test files still import the old nostr package
- test_follow_publish.dart temporarily disabled
- Tests need updating to use NDK models and services

## Current Architecture

```
┌─────────────────────────────────────────┐
│            Flutter App                   │
├─────────────────────────────────────────┤
│         Provider Layer                   │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │ Old Services │  │  NDK Services   │  │
│  │ (nostr pkg)  │  │  (dart_ndk)     │  │
│  └─────────────┘  └─────────────────┘  │
├─────────────────────────────────────────┤
│         Adapter Layer                    │
│     (Model conversion between            │
│      old and new formats)                │
├─────────────────────────────────────────┤
│  ┌──────────┐        ┌──────────────┐  │
│  │Old nostr │        │   dart_ndk    │  │
│  │ package  │        │   package     │  │
│  └──────────┘        └──────────────┘  │
└─────────────────────────────────────────┘
```

## Next Steps

1. **Gradual Service Migration**
   - Migrate ProfileServiceV2 to use NDK
   - Update ProfileBufferServiceIndexed to use ProfileServiceNdk
   - Migrate remaining relay and DM services

2. **Implement Encryption**
   - Implement NIP-04 encryption/decryption without old package
   - Consider implementing NIP-44 for better encryption

3. **Remove Old Dependencies**
   - Once all services migrated, remove old nostr package
   - Update all imports and test files

4. **Testing**
   - Update test files to use NDK models
   - Add integration tests for NDK services
   - Ensure backward compatibility during migration

## Benefits Realized

- ✅ Better performance with optimized relay management
- ✅ Support for new NIPs (reactions, lists)
- ✅ More robust event verification
- ✅ Cleaner API with proper typing
- ⏳ Unified relay set management (pending full migration)
- ⏳ Advanced caching strategies (pending full migration)

## Known Issues

1. Direct message encryption/decryption not working
2. ProfileServiceV2 still required by ProfileBufferServiceIndexed
3. Some imports still reference old nostr package
4. Test files need updating

## Recommendations

1. Continue gradual migration to avoid breaking changes
2. Implement encryption functions as priority
3. Create integration tests for migrated services
4. Document API differences for other developers