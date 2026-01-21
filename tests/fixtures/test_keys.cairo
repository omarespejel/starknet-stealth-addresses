/// Test Key Fixtures
///
/// Pre-generated test keys for deterministic testing.
/// These are for TESTING ONLY - never use in production!
///
/// NOTE: On-curve validation is enabled in the contracts.
/// All keys below are valid STARK curve points.

/// Test spending private key (for testing only)
pub const TEST_SPENDING_PRIV_KEY: felt252 = 0x1;

/// Test spending public key X coordinate
pub const TEST_SPENDING_PUBKEY_X: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;

/// Test spending public key Y coordinate
pub const TEST_SPENDING_PUBKEY_Y: felt252 = 0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f;

/// Test ephemeral private key (sender generates this)
pub const TEST_EPHEMERAL_PRIV_KEY: felt252 = 0x2;

/// Test ephemeral public key X coordinate
pub const TEST_EPHEMERAL_PUBKEY_X: felt252 = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;

/// Test ephemeral public key Y coordinate
pub const TEST_EPHEMERAL_PUBKEY_Y: felt252 = 0x10adb5cbff189082a3fe5d7a6752d8d18baa55778874e606c4a9d28569b93c0;

/// Test stealth public key X (derived from spending + ephemeral)
pub const TEST_STEALTH_PUBKEY_X: felt252 = 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;

/// Test stealth public key Y
pub const TEST_STEALTH_PUBKEY_Y: felt252 = 0x1e4c1453f76dc3d3d90bf6ab6e6e0306b0c4090cfe12caac1dd2047fd0f97b;

/// Test view tag (pre-computed)
pub const TEST_VIEW_TAG: u8 = 42;

/// Test salt for address derivation
pub const TEST_SALT: felt252 = 0x123456789;

/// Alternative test keys for multi-user testing
pub mod Alice {
    pub const PUBKEY_X: felt252 = 0xa7da05a4d664859ccd6e567b935cdfbfe3018c7771cb980892ef38878ae9bc;
    pub const PUBKEY_Y: felt252 = 0x27b4f3d437cc5c47729d4c781f10797351d1555d770b3584cb37b4b935fce4b;
}

pub mod Bob {
    pub const PUBKEY_X: felt252 = 0x788435d61046d3eec54d77d25bd194525f4fa26ebe6575536bc6f656656b74c;
    pub const PUBKEY_Y: felt252 = 0x13926386b9e5e908c359519eaa68c44a2430f4b4ca5d0dbdcb4231f031eb18b;
}

pub mod Charlie {
    pub const PUBKEY_X: felt252 = 0x1efc3d7c9649900fcbd03f578a8248d095bc4b6a13b3c25f9886ef971ff96fa;
    pub const PUBKEY_Y: felt252 = 0x16b1b2316aec6c9c8309d3854f6b92a59b6bf08461a8c0bcdb3e293163b2670;
}
