/// Error definitions for the Stealth Address Protocol
/// 
/// All errors follow the pattern: 'STEALTH: <description>'
/// This enables easy grep-ability and debugging.

pub mod Errors {
    // ========================================================================
    // Registry Errors
    // ========================================================================
    
    /// Meta-address already registered for this user
    pub const META_ADDRESS_ALREADY_REGISTERED: felt252 = 'STEALTH: already registered';
    
    /// Meta-address not found for user
    pub const META_ADDRESS_NOT_FOUND: felt252 = 'STEALTH: meta addr not found';
    
    /// Invalid meta-address (zero or malformed)
    pub const INVALID_META_ADDRESS: felt252 = 'STEALTH: invalid meta address';
    
    /// Invalid ephemeral public key
    pub const INVALID_EPHEMERAL_KEY: felt252 = 'STEALTH: invalid ephemeral key';
    
    /// Invalid view tag (must be 0-255)
    pub const INVALID_VIEW_TAG: felt252 = 'STEALTH: invalid view tag';

    /// Invalid scheme identifier
    pub const INVALID_SCHEME_ID: felt252 = 'STEALTH: invalid scheme id';

    /// Caller not authorized
    pub const UNAUTHORIZED: felt252 = 'STEALTH: unauthorized';

    /// Announce rate limited
    pub const RATE_LIMITED: felt252 = 'STEALTH: rate limited';

    /// Pending owner not set
    pub const NO_PENDING_OWNER: felt252 = 'STEALTH: no pending owner';

    /// Announcement count overflow
    pub const ANNOUNCEMENT_COUNT_OVERFLOW: felt252 = 'STEALTH: announcement overflow';
    
    // ========================================================================
    // Account Errors
    // ========================================================================
    
    /// Invalid signature length (must be 2 felts: r, s)
    pub const INVALID_SIGNATURE_LENGTH: felt252 = 'STEALTH: invalid sig length';
    
    /// Signature verification failed
    pub const INVALID_SIGNATURE: felt252 = 'STEALTH: invalid signature';
    
    /// Caller must be the Starknet protocol (zero address)
    pub const INVALID_CALLER: felt252 = 'STEALTH: invalid caller';
    
    /// Account already initialized
    pub const ALREADY_INITIALIZED: felt252 = 'STEALTH: already initialized';
    
    /// Invalid public key (zero or not on curve)
    pub const INVALID_PUBLIC_KEY: felt252 = 'STEALTH: invalid public key';
    
    /// Contract call execution failed
    pub const CALL_FAILED: felt252 = 'STEALTH: call failed';
    
    // ========================================================================
    // Factory Errors
    // ========================================================================
    
    /// Deployment failed
    pub const DEPLOYMENT_FAILED: felt252 = 'STEALTH: deployment failed';
    
    /// Invalid class hash
    pub const INVALID_CLASS_HASH: felt252 = 'STEALTH: invalid class hash';
    
    /// Address computation mismatch
    pub const ADDRESS_MISMATCH: felt252 = 'STEALTH: address mismatch';
    
    // ========================================================================
    // Cryptographic Errors
    // ========================================================================
    
    /// Point not on curve
    pub const POINT_NOT_ON_CURVE: felt252 = 'STEALTH: point not on curve';
    
    /// Invalid scalar (zero or >= curve order)
    pub const INVALID_SCALAR: felt252 = 'STEALTH: invalid scalar';
}
