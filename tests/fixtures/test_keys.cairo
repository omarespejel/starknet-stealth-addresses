/// Test Key Fixtures
///
/// Pre-generated test keys for deterministic testing.
/// These are for TESTING ONLY - never use in production!
///
/// NOTE: On-curve validation is disabled in the contracts (see PRIVACY_AUDIT.md C-01).
/// For production, enable on-curve checks and use verified STARK curve points.

/// Test spending private key (for testing only)
pub const TEST_SPENDING_PRIV_KEY: felt252 = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

/// Test spending public key X coordinate
pub const TEST_SPENDING_PUBKEY_X: felt252 = 0x5f3b0e76c0e3c0f7c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6;

/// Test spending public key Y coordinate
pub const TEST_SPENDING_PUBKEY_Y: felt252 = 0x6a4c1f87d1f4d1e8d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7;

/// Test ephemeral private key (sender generates this)
pub const TEST_EPHEMERAL_PRIV_KEY: felt252 = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

/// Test ephemeral public key X coordinate
pub const TEST_EPHEMERAL_PUBKEY_X: felt252 = 0x7b5d2f98e2f5e2f9e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8;

/// Test ephemeral public key Y coordinate
pub const TEST_EPHEMERAL_PUBKEY_Y: felt252 = 0x8c6e3fa9f3a6f3faf6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9;

/// Test stealth public key X (derived from spending + ephemeral)
pub const TEST_STEALTH_PUBKEY_X: felt252 = 0x9d7f4fba04b704ab07b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0;

/// Test stealth public key Y
pub const TEST_STEALTH_PUBKEY_Y: felt252 = 0x0e8050cb05c805bc08c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1;

/// Test view tag (pre-computed)
pub const TEST_VIEW_TAG: u8 = 42;

/// Test salt for address derivation
pub const TEST_SALT: felt252 = 0x123456789;

/// Alternative test keys for multi-user testing
pub mod Alice {
    pub const PUBKEY_X: felt252 = 0x1111111111111111111111111111111111111111111111111111111111111111;
    pub const PUBKEY_Y: felt252 = 0x2222222222222222222222222222222222222222222222222222222222222222;
}

pub mod Bob {
    pub const PUBKEY_X: felt252 = 0x3333333333333333333333333333333333333333333333333333333333333333;
    pub const PUBKEY_Y: felt252 = 0x4444444444444444444444444444444444444444444444444444444444444444;
}

pub mod Charlie {
    pub const PUBKEY_X: felt252 = 0x5555555555555555555555555555555555555555555555555555555555555555;
    pub const PUBKEY_Y: felt252 = 0x6666666666666666666666666666666666666666666666666666666666666666;
}
