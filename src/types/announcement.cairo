use starknet::ContractAddress;

/// Announcement Data Structure
///
/// When a sender transfers funds to a stealth address, they must
/// publish an announcement so the recipient can detect the payment.
///
/// ## Scanning Process
/// 1. Recipient fetches all Announcement events
/// 2. For each announcement, check if view_tag matches (fast filter)
/// 3. If view_tag matches, compute full ECDH shared secret
/// 4. Derive stealth address and check if it matches
/// 5. If match found, derive spending key to claim funds
///
/// ## View Tag Optimization
/// The view_tag provides 256x speedup in scanning:
/// - Without: O(n) full ECDH computations
/// - With: O(n) comparisons + O(n/256) ECDH computations
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct AnnouncementData {
    /// Cryptographic scheme identifier
    /// 0 = STARK curve ECDH (default)
    pub scheme_id: u8,
    
    /// X coordinate of sender's ephemeral public key
    pub ephemeral_pubkey_x: felt252,
    
    /// Y coordinate of sender's ephemeral public key
    pub ephemeral_pubkey_y: felt252,
    
    /// The stealth address receiving funds
    pub stealth_address: ContractAddress,
    
    /// 8-bit view tag for efficient scanning
    /// Computed as: truncate(poseidon(shared_secret), 8 bits)
    pub view_tag: u8,
    
    /// Optional metadata
    /// Can encode: token type, amount hint, memo, etc.
    pub metadata: felt252,
}

/// Scheme identifiers for different cryptographic protocols
pub mod SchemeId {
    /// Single-key STARK curve ECDH (this SNIP)
    pub const STARK_CURVE_ECDH: u8 = 0;
    
    /// Dual-key STARK curve (future: view + spend separation)
    pub const STARK_CURVE_DUAL_KEY: u8 = 1;
    
    /// Reserved for secp256k1 compatibility
    pub const SECP256K1_ECDH: u8 = 2;
    
    /// Reserved for post-quantum schemes
    pub const POST_QUANTUM: u8 = 255;
}

#[generate_trait]
pub impl AnnouncementDataImpl of AnnouncementDataTrait {
    /// Create a new announcement with scheme 0
    fn new(
        ephemeral_pubkey_x: felt252,
        ephemeral_pubkey_y: felt252,
        stealth_address: ContractAddress,
        view_tag: u8,
        metadata: felt252
    ) -> AnnouncementData {
        AnnouncementData {
            scheme_id: SchemeId::STARK_CURVE_ECDH,
            ephemeral_pubkey_x,
            ephemeral_pubkey_y,
            stealth_address,
            view_tag,
            metadata,
        }
    }
    
    /// Check if ephemeral key is valid
    fn has_valid_ephemeral_key(self: @AnnouncementData) -> bool {
        *self.ephemeral_pubkey_x != 0 && *self.ephemeral_pubkey_y != 0
    }
}
