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
    use starknet::{ContractAddress, get_caller_address, get_block_number, get_execution_info};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, 
        StoragePathEntry, Map
    };
    use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistry;
    use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::IStealthRegistryAdmin;
    use starknet_stealth_addresses::types::meta_address::{StealthMetaAddress, StealthMetaAddressTrait};
    use starknet_stealth_addresses::errors::Errors;
    use starknet_stealth_addresses::crypto::constants::is_valid_public_key;

    // ========================================================================
    // STORAGE
    // ========================================================================

    #[storage]
    struct Storage {
        /// Owner for admin operations
        owner: ContractAddress,

        /// Maps user address to their stealth meta-address
        meta_addresses: Map<ContractAddress, StealthMetaAddress>,
        
        /// Total number of announcements (for indexing)
        announcement_count: u64,
        
        /// Minimum block gap between announcements per caller (0 = disabled)
        min_announce_block_gap: u64,

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
    }

    /// Emitted when a user registers their stealth meta-address
    #[derive(Drop, starknet::Event)]
    pub struct MetaAddressRegistered {
        #[key]
        pub user: ContractAddress,
        pub scheme_id: u8,
        pub spending_pubkey_x: felt252,
        pub spending_pubkey_y: felt252,
    }

    /// Emitted when a user updates their stealth meta-address
    #[derive(Drop, starknet::Event)]
    pub struct MetaAddressUpdated {
        #[key]
        pub user: ContractAddress,
        pub scheme_id: u8,
        pub spending_pubkey_x: felt252,
        pub spending_pubkey_y: felt252,
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

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    #[constructor]
    fn constructor(ref self: ContractState) {
        let exec_info = get_execution_info();
        let tx_info = exec_info.unbox().tx_info.unbox();
        self.owner.write(tx_info.account_contract_address);
        self.version.write(1);
        self.announcement_count.write(0);
        self.min_announce_block_gap.write(0);
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
            spending_pubkey_y: felt252
        ) {
            let caller = get_caller_address();
            
            // Check not already registered
            let existing = self.meta_addresses.entry(caller).read();
            assert(!existing.is_valid(), Errors::META_ADDRESS_ALREADY_REGISTERED);
            
            // Validate public key (non-zero; optional strict curve check)
            assert(
                is_valid_public_key(spending_pubkey_x, spending_pubkey_y), 
                Errors::INVALID_META_ADDRESS
            );
            
            // Store meta-address
            let meta_address = StealthMetaAddress {
                scheme_id: 0, // STARK curve ECDH
                spending_pubkey_x,
                spending_pubkey_y,
            };
            self.meta_addresses.entry(caller).write(meta_address);
            
            // Emit event
            self.emit(MetaAddressRegistered {
                user: caller,
                scheme_id: 0,
                spending_pubkey_x,
                spending_pubkey_y,
            });
        }

        /// Update an existing stealth meta-address
        fn update_stealth_meta_address(
            ref self: ContractState,
            spending_pubkey_x: felt252,
            spending_pubkey_y: felt252
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
            
            // Update meta-address
            let meta_address = StealthMetaAddress {
                scheme_id: 0,
                spending_pubkey_x,
                spending_pubkey_y,
            };
            self.meta_addresses.entry(caller).write(meta_address);
            
            // Emit event
            self.emit(MetaAddressUpdated {
                user: caller,
                scheme_id: 0,
                spending_pubkey_x,
                spending_pubkey_y,
            });
        }

        /// Get meta-address for a user
        fn get_stealth_meta_address(
            self: @ContractState,
            user: ContractAddress
        ) -> (felt252, felt252) {
            let meta = self.meta_addresses.entry(user).read();
            (meta.spending_pubkey_x, meta.spending_pubkey_y)
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
            // Only scheme 0 supported (STARK curve ECDH)
            assert(scheme_id == 0, Errors::INVALID_SCHEME_ID);

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

                if last != 0 {
                    assert(current_block >= last + min_gap, Errors::RATE_LIMITED);
                }

                self.last_announce_block.entry(caller).write(current_block);
            }
            
            // Get and increment announcement count
            let index = self.announcement_count.read();
            self.announcement_count.write(index + 1);
            
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

            let old_gap = self.min_announce_block_gap.read();
            self.min_announce_block_gap.write(min_gap);

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
