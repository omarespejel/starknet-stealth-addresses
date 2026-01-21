/// Stealth Account Interface
///
/// A SNIP-6 compliant account contract for stealth addresses.
/// Each stealth account is a one-time-use smart contract account
/// that can only be controlled by the derived spending key.
///
/// ## Key Features
/// - SNIP-6 (SRC-6) compliant for standard account interface
/// - Single public key (derived stealth public key)
/// - ECDSA signature verification on STARK curve
/// - Supports paymaster/gas abstraction
#[starknet::interface]
pub trait IStealthAccount<TContractState> {
    /// Get the stealth public key that controls this account
    ///
    /// # Returns
    /// Tuple of (pubkey_x, pubkey_y) - the stealth public key coordinates
    fn get_stealth_public_key(self: @TContractState) -> (felt252, felt252);
    
    /// Get just the X coordinate (for compatibility with existing tooling)
    fn get_public_key(self: @TContractState) -> felt252;
}

// Note: ISRC6_ID is imported from openzeppelin_account::interface
