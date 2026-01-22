/// Stealth Meta-Address Registry Contract
///
/// This contract serves as the central registry for stealth addresses on Starknet.
/// It provides two core functions:
/// 1. Store and retrieve stealth meta-addresses for users
/// 2. Record and emit announcements for stealth payments
///
/// ## Security Considerations
/// - Meta-addresses are public information (derived from public keys)
/// - Anyone can register their own meta-address
/// - Anyone can announce (announcements are just notifications)
/// - No access control needed for core functionality

#[starknet::contract]
pub mod StealthRegistry {
    use starknet::{ContractAddress, get_caller_address, get_block_number};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, 
        StoragePathEntry, Map
    };
    use core::traits::TryInto;
    use core::num::traits::ops::checked::CheckedAdd;
    use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistry;
    use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::IStealthRegistryAdmin;
    use starknet_stealth_addresses::types::meta_address::{StealthMetaAddress, StealthMetaAddressTrait};
    use starknet_stealth_addresses::errors::Errors;
    use starknet_stealth_addresses::crypto::constants::is_valid_public_key;
    use starknet_stealth_addresses::types::announcement::SchemeId;

    // ========================================================================
    // CONSTANTS
    // ========================================================================

    /// Default minimum block gap between announcements (0 = disabled)
    const DEFAULT_MIN_ANNOUNCE_BLOCK_GAP: u64 = 0;

    /// Maximum allowed minimum block gap (caps admin rate limiting)
    const MAX_MIN_ANNOUNCE_BLOCK_GAP: u64 = 7200;

    fn zero_address() -> ContractAddress {
        0.try_into().unwrap()
    }

    // ========================================================================
    // STORAGE
    // ========================================================================

    #[storage]
    struct Storage {
        /// Owner for admin operations
        owner: ContractAddress,

        /// Pending owner for two-step transfer (0 = none)
        pending_owner: ContractAddress,

        /// Maps user address to their stealth meta-address
        meta_addresses: Map<ContractAddress, StealthMetaAddress>,
        
        /// Total number of announcements (for indexing)
        announcement_count: u64,
        
        /// Minimum block gap between announcements per caller (0 = disabled)
        min_announce_block_gap: u64,

        /// Block number when min_announce_block_gap was last updated
        min_announce_block_gap_start: u64,

        /// Last block number an address announced from
        last_announce_block: Map<ContractAddress, u64>,

        /// Protocol version for upgrades
        version: u8,
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        MetaAddressRegistered: MetaAddressRegistered,
        MetaAddressUpdated: MetaAddressUpdated,
        Announcement: Announcement,
        MinAnnounceBlockGapUpdated: MinAnnounceBlockGapUpdated,
        OwnershipTransferStarted: OwnershipTransferStarted,
        OwnershipTransferCanceled: OwnershipTransferCanceled,
        OwnershipTransferred: OwnershipTransferred,
    }

    /// Emitted when a user registers their stealth meta-address
    #[derive(Drop, starknet::Event)]
    pub struct MetaAddressRegistered {
        #[key]
        pub user: ContractAddress,
        pub scheme_id: u8,
        pub spending_pubkey_x: felt252,
        pub spending_pubkey_y: felt252,
        pub viewing_pubkey_x: felt252,
        pub viewing_pubkey_y: felt252,
    }

    /// Emitted when a user updates their stealth meta-address
    #[derive(Drop, starknet::Event)]
    pub struct MetaAddressUpdated {
        #[key]
        pub user: ContractAddress,
        pub scheme_id: u8,
        pub spending_pubkey_x: felt252,
        pub spending_pubkey_y: felt252,
        pub viewing_pubkey_x: felt252,
        pub viewing_pubkey_y: felt252,
    }

    /// Emitted when a stealth payment is announced
    /// 
    /// This is the CRITICAL event that recipients scan to detect payments.
    /// Indexed fields (scheme_id, view_tag) enable efficient filtering.
    #[derive(Drop, starknet::Event)]
    pub struct Announcement {
        /// Cryptographic scheme (indexed for filtering by scheme)
        #[key]
        pub scheme_id: u8,
        
        /// Ephemeral public key X coordinate
        pub ephemeral_pubkey_x: felt252,
        
        /// Ephemeral public key Y coordinate
        pub ephemeral_pubkey_y: felt252,
        
        /// Stealth address receiving funds
        pub stealth_address: ContractAddress,
        
        /// View tag for efficient scanning (indexed)
        #[key]
        pub view_tag: u8,
        
        /// Optional metadata (token type, hints, etc.)
        pub metadata: felt252,
        
        /// Announcement index for ordering
        pub index: u64,
    }

    /// Emitted when the announce rate limit is updated
    #[derive(Drop, starknet::Event)]
    pub struct MinAnnounceBlockGapUpdated {
        pub old_gap: u64,
        pub new_gap: u64,
    }

    /// Emitted when ownership transfer is initiated
    #[derive(Drop, starknet::Event)]
    pub struct OwnershipTransferStarted {
        pub previous_owner: ContractAddress,
        pub new_owner: ContractAddress,
    }

    /// Emitted when ownership transfer is canceled
    #[derive(Drop, starknet::Event)]
    pub struct OwnershipTransferCanceled {
        pub previous_owner: ContractAddress,
        pub canceled_owner: ContractAddress,
    }

    /// Emitted when ownership transfer is completed
    #[derive(Drop, starknet::Event)]
    pub struct OwnershipTransferred {
        pub previous_owner: ContractAddress,
        pub new_owner: ContractAddress,
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        assert(owner != zero_address(), Errors::INVALID_OWNER);
        self.owner.write(owner);
        self.pending_owner.write(zero_address());
        self.version.write(1);
        self.announcement_count.write(0);
        self.min_announce_block_gap.write(DEFAULT_MIN_ANNOUNCE_BLOCK_GAP);
        self.min_announce_block_gap_start.write(0);
    }

    // ========================================================================
    // EXTERNAL FUNCTIONS
    // ========================================================================

    #[abi(embed_v0)]
    impl StealthRegistryImpl of IStealthRegistry<ContractState> {
        /// Register a new stealth meta-address
        fn register_stealth_meta_address(
            ref self: ContractState,
            spending_pubkey_x: felt252,
            spending_pubkey_y: felt252,
            viewing_pubkey_x: felt252,
            viewing_pubkey_y: felt252,
            scheme_id: u8
        ) {
            let caller = get_caller_address();
            
            // Check not already registered
            let existing = self.meta_addresses.entry(caller).read();
            assert(!existing.is_valid(), Errors::META_ADDRESS_ALREADY_REGISTERED);
            
            // Validate keys (non-zero, canonical Y, on-curve)
            assert(
                is_valid_public_key(spending_pubkey_x, spending_pubkey_y),
                Errors::INVALID_META_ADDRESS
            );
            assert(
                is_valid_public_key(viewing_pubkey_x, viewing_pubkey_y),
                Errors::INVALID_META_ADDRESS
            );

            // Validate scheme and key relationship
            if scheme_id == SchemeId::STARK_CURVE_ECDH {
                assert(spending_pubkey_x == viewing_pubkey_x, Errors::INVALID_META_ADDRESS);
                assert(spending_pubkey_y == viewing_pubkey_y, Errors::INVALID_META_ADDRESS);
            } else if scheme_id != SchemeId::STARK_CURVE_DUAL_KEY {
                assert(false, Errors::INVALID_SCHEME_ID);
            }
            
            // Store meta-address
            let meta_address = StealthMetaAddress {
                scheme_id,
                spending_pubkey_x,
                spending_pubkey_y,
                viewing_pubkey_x,
                viewing_pubkey_y,
            };
            self.meta_addresses.entry(caller).write(meta_address);
            
            // Emit event
            self.emit(MetaAddressRegistered {
                user: caller,
                scheme_id,
                spending_pubkey_x,
                spending_pubkey_y,
                viewing_pubkey_x,
                viewing_pubkey_y,
            });
        }

        /// Update an existing stealth meta-address
        fn update_stealth_meta_address(
            ref self: ContractState,
            spending_pubkey_x: felt252,
            spending_pubkey_y: felt252,
            viewing_pubkey_x: felt252,
            viewing_pubkey_y: felt252,
            scheme_id: u8
        ) {
            let caller = get_caller_address();
            
            // Check already registered
            let existing = self.meta_addresses.entry(caller).read();
            assert(existing.is_valid(), Errors::META_ADDRESS_NOT_FOUND);
            
            // Validate new public key (non-zero; optional strict curve check)
            assert(
                is_valid_public_key(spending_pubkey_x, spending_pubkey_y), 
                Errors::INVALID_META_ADDRESS
            );
            assert(
                is_valid_public_key(viewing_pubkey_x, viewing_pubkey_y),
                Errors::INVALID_META_ADDRESS
            );

            if scheme_id == SchemeId::STARK_CURVE_ECDH {
                assert(spending_pubkey_x == viewing_pubkey_x, Errors::INVALID_META_ADDRESS);
                assert(spending_pubkey_y == viewing_pubkey_y, Errors::INVALID_META_ADDRESS);
            } else if scheme_id != SchemeId::STARK_CURVE_DUAL_KEY {
                assert(false, Errors::INVALID_SCHEME_ID);
            }
            
            // Update meta-address
            let meta_address = StealthMetaAddress {
                scheme_id,
                spending_pubkey_x,
                spending_pubkey_y,
                viewing_pubkey_x,
                viewing_pubkey_y,
            };
            self.meta_addresses.entry(caller).write(meta_address);
            
            // Emit event
            self.emit(MetaAddressUpdated {
                user: caller,
                scheme_id,
                spending_pubkey_x,
                spending_pubkey_y,
                viewing_pubkey_x,
                viewing_pubkey_y,
            });
        }

        /// Get meta-address for a user
        fn get_stealth_meta_address(
            self: @ContractState,
            user: ContractAddress
        ) -> StealthMetaAddress {
            self.meta_addresses.entry(user).read()
        }

        /// Check if user has registered
        fn has_meta_address(self: @ContractState, user: ContractAddress) -> bool {
            let meta = self.meta_addresses.entry(user).read();
            meta.is_valid()
        }

        /// Announce a stealth payment
        fn announce(
            ref self: ContractState,
            scheme_id: u8,
            ephemeral_pubkey_x: felt252,
            ephemeral_pubkey_y: felt252,
            stealth_address: ContractAddress,
            view_tag: u8,
            metadata: felt252
        ) {
            // Only schemes 0 and 1 supported (STARK curve ECDH)
            assert(
                scheme_id == SchemeId::STARK_CURVE_ECDH
                    || scheme_id == SchemeId::STARK_CURVE_DUAL_KEY,
                Errors::INVALID_SCHEME_ID
            );

            // Validate ephemeral key (non-zero; optional strict curve check)
            assert(
                is_valid_public_key(ephemeral_pubkey_x, ephemeral_pubkey_y), 
                Errors::INVALID_EPHEMERAL_KEY
            );

            // Optional rate limiting (per caller)
            let min_gap = self.min_announce_block_gap.read();
            if min_gap != 0 {
                let caller = get_caller_address();
                let last = self.last_announce_block.entry(caller).read();
                let current_block = get_block_number();
                let start_block = self.min_announce_block_gap_start.read();

                if last != 0 && last >= start_block {
                    assert(current_block >= last + min_gap, Errors::RATE_LIMITED);
                }

                self.last_announce_block.entry(caller).write(current_block);
            }
            
            // Get and increment announcement count
            let index = self.announcement_count.read();
            let next_index = index.checked_add(1).expect(Errors::ANNOUNCEMENT_COUNT_OVERFLOW);
            self.announcement_count.write(next_index);
            
            // Emit announcement event
            self.emit(Announcement {
                scheme_id,
                ephemeral_pubkey_x,
                ephemeral_pubkey_y,
                stealth_address,
                view_tag,
                metadata,
                index,
            });
        }

        /// Get total announcement count
        fn get_announcement_count(self: @ContractState) -> u64 {
            self.announcement_count.read()
        }
    }

    // ========================================================================
    // ADMIN FUNCTIONS
    // ========================================================================

    #[abi(embed_v0)]
    impl StealthRegistryAdminImpl of IStealthRegistryAdmin<ContractState> {
        /// Set minimum block gap between announcements (0 = disabled)
        fn set_min_announce_block_gap(ref self: ContractState, min_gap: u64) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, Errors::UNAUTHORIZED);
            assert(min_gap <= MAX_MIN_ANNOUNCE_BLOCK_GAP, Errors::MIN_GAP_TOO_LARGE);

            let old_gap = self.min_announce_block_gap.read();
            self.min_announce_block_gap.write(min_gap);
            self.min_announce_block_gap_start.write(get_block_number());

            self.emit(MinAnnounceBlockGapUpdated {
                old_gap,
                new_gap: min_gap,
            });
        }

        /// Get minimum block gap between announcements
        fn get_min_announce_block_gap(self: @ContractState) -> u64 {
            self.min_announce_block_gap.read()
        }

        /// Get registry owner
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        /// Get pending owner
        fn get_pending_owner(self: @ContractState) -> ContractAddress {
            self.pending_owner.read()
        }

        /// Begin two-step ownership transfer
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, Errors::UNAUTHORIZED);
            assert(new_owner != zero_address(), Errors::INVALID_OWNER);

            self.pending_owner.write(new_owner);

            self.emit(OwnershipTransferStarted {
                previous_owner: owner,
                new_owner,
            });
        }

        /// Cancel a pending ownership transfer
        fn cancel_ownership_transfer(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, Errors::UNAUTHORIZED);

            let pending = self.pending_owner.read();
            assert(pending != zero_address(), Errors::NO_PENDING_OWNER);
            self.pending_owner.write(zero_address());

            self.emit(OwnershipTransferCanceled {
                previous_owner: owner,
                canceled_owner: pending,
            });
        }

        /// Accept ownership transfer
        fn accept_ownership(ref self: ContractState) {
            let caller = get_caller_address();
            let pending = self.pending_owner.read();

            assert(pending != zero_address(), Errors::NO_PENDING_OWNER);
            assert(caller == pending, Errors::UNAUTHORIZED);

            let previous = self.owner.read();
            self.owner.write(pending);
            self.pending_owner.write(zero_address());

            self.emit(OwnershipTransferred {
                previous_owner: previous,
                new_owner: pending,
            });
        }
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    #[generate_trait]
    pub impl StealthRegistryViewImpl of StealthRegistryViewTrait {
        /// Get the full meta-address struct
        fn get_full_meta_address(self: @ContractState, user: ContractAddress) -> StealthMetaAddress {
            self.meta_addresses.entry(user).read()
        }
        
        /// Get protocol version
        fn get_version(self: @ContractState) -> u8 {
            self.version.read()
        }
    }
}
