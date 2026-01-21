
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
/// The meta-address contains both spending and viewing public keys.
/// 
/// For the single-key scheme:
/// - `viewing_pubkey` == `spending_pubkey`
/// 
/// For the dual-key scheme:
/// - `viewing_pubkey` is distinct and used only for scanning
#[derive(Copy, Drop, Serde, starknet::Store, PartialEq, Debug)]
pub struct StealthMetaAddress {
    /// Cryptographic scheme version
    /// 0 = Single-key STARK curve ECDH
    /// 1 = Dual-key (view + spend)
    pub scheme_id: u8,
    
    /// X coordinate of spending public key on STARK curve
    pub spending_pubkey_x: felt252,
    
    /// Y coordinate of spending public key on STARK curve
    pub spending_pubkey_y: felt252,

    /// X coordinate of viewing public key on STARK curve
    pub viewing_pubkey_x: felt252,

    /// Y coordinate of viewing public key on STARK curve
    pub viewing_pubkey_y: felt252,
}

impl StealthMetaAddressDefault of Default<StealthMetaAddress> {
    fn default() -> StealthMetaAddress {
        StealthMetaAddress {
            scheme_id: 0,
            spending_pubkey_x: 0,
            spending_pubkey_y: 0,
            viewing_pubkey_x: 0,
            viewing_pubkey_y: 0,
        }
    }
}

#[generate_trait]
pub impl StealthMetaAddressImpl of StealthMetaAddressTrait {
    /// Check if the meta-address is valid (non-zero)
    fn is_valid(self: @StealthMetaAddress) -> bool {
        if *self.spending_pubkey_x == 0 || *self.spending_pubkey_y == 0 {
            return false;
        }
        if *self.viewing_pubkey_x == 0 || *self.viewing_pubkey_y == 0 {
            return false;
        }

        if *self.scheme_id == 0 {
            *self.spending_pubkey_x == *self.viewing_pubkey_x
                && *self.spending_pubkey_y == *self.viewing_pubkey_y
        } else if *self.scheme_id == 1 {
            true
        } else {
            false
        }
    }
    
    /// Check if the meta-address is empty/unregistered
    fn is_empty(self: @StealthMetaAddress) -> bool {
        *self.spending_pubkey_x == 0
            && *self.spending_pubkey_y == 0
            && *self.viewing_pubkey_x == 0
            && *self.viewing_pubkey_y == 0
    }
    
    /// Create a new meta-address with scheme 0 (STARK curve ECDH)
    fn new(spending_pubkey_x: felt252, spending_pubkey_y: felt252) -> StealthMetaAddress {
        StealthMetaAddress {
            scheme_id: 0,
            spending_pubkey_x,
            spending_pubkey_y,
            viewing_pubkey_x: spending_pubkey_x,
            viewing_pubkey_y: spending_pubkey_y,
        }
    }

    /// Create a new dual-key meta-address (scheme 1)
    fn new_dual(
        spending_pubkey_x: felt252,
        spending_pubkey_y: felt252,
        viewing_pubkey_x: felt252,
        viewing_pubkey_y: felt252
    ) -> StealthMetaAddress {
        StealthMetaAddress {
            scheme_id: 1,
            spending_pubkey_x,
            spending_pubkey_y,
            viewing_pubkey_x,
            viewing_pubkey_y,
        }
    }
}
