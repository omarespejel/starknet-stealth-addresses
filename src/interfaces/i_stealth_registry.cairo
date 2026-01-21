use starknet::ContractAddress;

/// Stealth Meta-Address Registry Interface
///
/// The registry serves two critical functions:
/// 1. Store stealth meta-addresses for users (spending public key)
/// 2. Emit announcements when stealth payments are made
///
/// ## Workflow
/// ```
/// 1. Recipient registers meta-address: register_stealth_meta_address()
/// 2. Sender looks up meta-address: get_stealth_meta_address()
/// 3. Sender derives stealth address off-chain
/// 4. Sender announces ephemeral key: announce()
/// 5. Recipient scans announcements to detect payments
/// ```
#[starknet::interface]
pub trait IStealthRegistry<TContractState> {
    // ========================================================================
    // META-ADDRESS MANAGEMENT
    // ========================================================================
    
    /// Register a stealth meta-address for the caller
    /// 
    /// # Arguments
    /// * `spending_pubkey_x` - X coordinate of the spending public key
    /// * `spending_pubkey_y` - Y coordinate of the spending public key
    ///
    /// # Requirements
    /// - Caller must not have already registered (call update_stealth_meta_address instead)
    /// - Public key must be valid (non-zero, on curve)
    ///
    /// # Emits
    /// - `MetaAddressRegistered` event
    fn register_stealth_meta_address(
        ref self: TContractState,
        spending_pubkey_x: felt252,
        spending_pubkey_y: felt252
    );
    
    /// Update an existing stealth meta-address
    ///
    /// # Arguments
    /// * `spending_pubkey_x` - New X coordinate
    /// * `spending_pubkey_y` - New Y coordinate
    ///
    /// # Requirements
    /// - Caller must have previously registered
    /// - New public key must be valid
    ///
    /// # Emits
    /// - `MetaAddressUpdated` event
    fn update_stealth_meta_address(
        ref self: TContractState,
        spending_pubkey_x: felt252,
        spending_pubkey_y: felt252
    );
    
    /// Get the stealth meta-address for a user
    ///
    /// # Arguments
    /// * `user` - The user's contract address
    ///
    /// # Returns
    /// Tuple of (spending_pubkey_x, spending_pubkey_y)
    /// Returns (0, 0) if not registered
    fn get_stealth_meta_address(
        self: @TContractState,
        user: ContractAddress
    ) -> (felt252, felt252);
    
    /// Check if a user has registered a meta-address
    fn has_meta_address(self: @TContractState, user: ContractAddress) -> bool;
    
    // ========================================================================
    // ANNOUNCEMENTS
    // ========================================================================
    
    /// Announce a stealth payment (called by sender)
    ///
    /// This publishes the ephemeral public key so the recipient can
    /// scan and detect payments addressed to them.
    ///
    /// # Arguments
    /// * `scheme_id` - Cryptographic scheme identifier (0 = STARK curve ECDH)
    /// * `ephemeral_pubkey_x` - X coordinate of sender's ephemeral public key
    /// * `ephemeral_pubkey_y` - Y coordinate of sender's ephemeral public key
    /// * `stealth_address` - The derived stealth address receiving funds
    /// * `view_tag` - 8-bit view tag for efficient scanning
    /// * `metadata` - Optional metadata (token type, amount hint, etc.)
    ///
    /// # Requirements
    /// - scheme_id MUST be 0 (single-key STARK curve ECDH)
    ///
    /// # Emits
    /// - `Announcement` event (indexed by scheme_id and view_tag)
    fn announce(
        ref self: TContractState,
        scheme_id: u8,
        ephemeral_pubkey_x: felt252,
        ephemeral_pubkey_y: felt252,
        stealth_address: ContractAddress,
        view_tag: u8,
        metadata: felt252
    );
    
    /// Get the total number of announcements
    fn get_announcement_count(self: @TContractState) -> u64;
}
