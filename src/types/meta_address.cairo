
/// Stealth Meta-Address Structure
///
/// A meta-address contains the public information needed for senders
/// to derive one-time stealth addresses for the recipient.
///
/// ## SNIP-42/43 Compatibility
/// This structure is designed to be compatible with:
/// - SNIP-42: Bech32m encoding with `strkm` HRP for meta-addresses
/// - SNIP-43: Unified addresses and viewing keys
///
/// ## Cryptographic Details
/// The meta-address contains only the spending public key.
/// For the simplified single-key scheme:
/// - `spending_pubkey` = G * spending_private_key
/// 
/// For future dual-key schemes (view + spend separation):
/// - Add `viewing_pubkey_x` and `viewing_pubkey_y` fields
/// - Set scheme_id to indicate dual-key scheme
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct StealthMetaAddress {
    /// Cryptographic scheme version
    /// 0 = Single-key STARK curve ECDH
    /// 1 = Dual-key (view + spend) - future
    pub scheme_id: u8,
    
    /// X coordinate of spending public key on STARK curve
    pub spending_pubkey_x: felt252,
    
    /// Y coordinate of spending public key on STARK curve
    pub spending_pubkey_y: felt252,
}

impl StealthMetaAddressDefault of Default<StealthMetaAddress> {
    fn default() -> StealthMetaAddress {
        StealthMetaAddress {
            scheme_id: 0,
            spending_pubkey_x: 0,
            spending_pubkey_y: 0,
        }
    }
}

#[generate_trait]
pub impl StealthMetaAddressImpl of StealthMetaAddressTrait {
    /// Check if the meta-address is valid (non-zero)
    fn is_valid(self: @StealthMetaAddress) -> bool {
        *self.spending_pubkey_x != 0 && *self.spending_pubkey_y != 0
    }
    
    /// Check if the meta-address is empty/unregistered
    fn is_empty(self: @StealthMetaAddress) -> bool {
        *self.spending_pubkey_x == 0 && *self.spending_pubkey_y == 0
    }
    
    /// Create a new meta-address with scheme 0 (STARK curve ECDH)
    fn new(spending_pubkey_x: felt252, spending_pubkey_y: felt252) -> StealthMetaAddress {
        StealthMetaAddress {
            scheme_id: 0,
            spending_pubkey_x,
            spending_pubkey_y,
        }
    }
}
