use starknet::{ContractAddress, ClassHash};

/// Stealth Account Factory Interface
///
/// Responsible for deploying and computing addresses of stealth accounts.
/// The factory enables:
/// 1. Deterministic address computation (senders can know address before deployment)
/// 2. Lazy deployment (deploy only when recipient wants to spend)
/// 3. Consistent class hash for all stealth accounts
///
/// ## Address Computation
/// The stealth address is computed as:
/// ```
/// address = pedersen(
///     "STARKNET_CONTRACT_ADDRESS",
///     deployer_address,
///     salt,
///     class_hash,
///     pedersen(constructor_calldata)
/// ) mod 2^251 + 17 * 2^192 + 1
/// ```
#[starknet::interface]
pub trait IStealthAccountFactory<TContractState> {
    // ========================================================================
    // DEPLOYMENT
    // ========================================================================
    
    /// Deploy a new stealth account
    ///
    /// # Arguments
    /// * `stealth_pubkey_x` - X coordinate of the stealth public key
    /// * `stealth_pubkey_y` - Y coordinate of the stealth public key
    /// * `salt` - Unique salt for address derivation
    ///
    /// # Returns
    /// The deployed contract address
    ///
    /// # Requirements
    /// - Public key must be valid (non-zero)
    /// - Salt should be derived from ephemeral key for determinism
    fn deploy_stealth_account(
        ref self: TContractState,
        stealth_pubkey_x: felt252,
        stealth_pubkey_y: felt252,
        salt: felt252
    ) -> ContractAddress;
    
    // ========================================================================
    // ADDRESS COMPUTATION
    // ========================================================================
    
    /// Compute the stealth address without deploying
    ///
    /// This allows senders to:
    /// 1. Know the recipient address before deployment
    /// 2. Send funds to the address
    /// 3. Let recipient deploy when they want to spend
    ///
    /// # Arguments
    /// * `stealth_pubkey_x` - X coordinate of the stealth public key
    /// * `stealth_pubkey_y` - Y coordinate of the stealth public key
    /// * `salt` - Unique salt for address derivation
    ///
    /// # Returns
    /// The computed contract address (same as deploy would return)
    fn compute_stealth_address(
        self: @TContractState,
        stealth_pubkey_x: felt252,
        stealth_pubkey_y: felt252,
        salt: felt252
    ) -> ContractAddress;
    
    // ========================================================================
    // CONFIGURATION
    // ========================================================================
    
    /// Get the class hash used for stealth accounts
    fn get_account_class_hash(self: @TContractState) -> ClassHash;
    
    /// Get the total number of accounts deployed through this factory
    fn get_deployment_count(self: @TContractState) -> u64;
}
