/// Fuzz Tests for Stealth Address Protocol
///
/// These tests use random inputs to find edge cases and vulnerabilities.
/// snforge runs each test multiple times with different random values.

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address
};
use starknet::{ContractAddress, contract_address_const};
use starknet_stealth_addresses::interfaces::i_stealth_registry::{
    IStealthRegistryDispatcher, IStealthRegistryDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::{
    IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_account_factory::{
    IStealthAccountFactoryDispatcher, IStealthAccountFactoryDispatcherTrait
};
use starknet_stealth_addresses::crypto::constants::is_valid_public_key;
use starknet_stealth_addresses::crypto::view_tag::compute_view_tag;

// ============================================================================
// Test Fixtures
// ============================================================================

fn deploy_registry() -> IStealthRegistryDispatcher {
    let contract = declare("StealthRegistry").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    IStealthRegistryDispatcher { contract_address: address }
}

fn deploy_factory() -> IStealthAccountFactoryDispatcher {
    let account_class = declare("StealthAccount").unwrap().contract_class();
    let factory_class = declare("StealthAccountFactory").unwrap().contract_class();
    let (address, _) = factory_class.deploy(@array![(*account_class.class_hash).into()]).unwrap();
    IStealthAccountFactoryDispatcher { contract_address: address }
}

fn disable_rate_limit(registry_address: ContractAddress) {
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry_address };
    let owner = admin.get_owner();
    start_cheat_caller_address(registry_address, owner);
    admin.set_min_announce_block_gap(0);
    stop_cheat_caller_address(registry_address);
}

// ============================================================================
// Fuzz Tests - Registry
// ============================================================================

/// Fuzz test: Any valid public key should be registerable
#[test]
#[fuzzer(runs: 100, seed: 12345)]
fn test_fuzz_registry_accepts_nonzero_keys(x: felt252, y: felt252) {
    // Skip invalid values
    if !is_valid_public_key(x, y) {
        return;
    }
    
    let registry = deploy_registry();
    let caller = contract_address_const::<0x123>();
    
    start_cheat_caller_address(registry.contract_address, caller);
    
    // Should not panic for any non-zero values
    registry.register_stealth_meta_address(x, y, x, y, 0);
    
    // Verify it was stored
    let meta = registry.get_stealth_meta_address(caller);
    assert(meta.spending_pubkey_x == x, 'X mismatch');
    assert(meta.spending_pubkey_y == y, 'Y mismatch');
}

/// Fuzz test: Announcements with valid ephemeral keys should work
#[test]
#[fuzzer(runs: 100, seed: 67890)]
fn test_fuzz_registry_announce_accepts_valid_keys(
    eph_x: felt252, 
    eph_y: felt252, 
    view_tag: u8,
    metadata: felt252
) {
    // Skip invalid values
    if !is_valid_public_key(eph_x, eph_y) {
        return;
    }
    
    let registry = deploy_registry();
    let stealth_addr = contract_address_const::<0x456>();
    
    // Should not panic for any non-zero ephemeral key
    registry.announce(0, eph_x, eph_y, stealth_addr, view_tag, metadata);
    
    // Verify count increased
    assert(registry.get_announcement_count() == 1, 'Count should be 1');
}

/// Property test: spam pattern should increment announcement count when rate-limit disabled
#[test]
#[fuzzer(runs: 30, seed: 99999)]
fn test_fuzz_registry_spam_pattern(
    eph_x: felt252,
    eph_y: felt252,
    view_tag: u8,
    count: u8
) {
    if !is_valid_public_key(eph_x, eph_y) {
        return;
    }

    let registry = deploy_registry();
    disable_rate_limit(registry.contract_address);
    let stealth_addr = contract_address_const::<0xabc>();

    let n: u32 = (count % 20).into();
    if n == 0 {
        return;
    }

    let mut i: u32 = 0;
    while i < n {
        registry.announce(0, eph_x, eph_y, stealth_addr, view_tag, i.into());
        i += 1;
    };

    assert(registry.get_announcement_count() == n.into(), 'Spam count mismatch');
}

// ============================================================================
// Fuzz Tests - Factory
// ============================================================================

/// Fuzz test: compute_stealth_address should be deterministic
#[test]
#[fuzzer(runs: 50, seed: 11111)]
fn test_fuzz_factory_address_deterministic(x: felt252, y: felt252, salt: felt252) {
    // Skip zero values
    if x == 0 || y == 0 {
        return;
    }
    
    let factory = deploy_factory();
    
    // Compute twice - should get same result
    let addr1 = factory.compute_stealth_address(x, y, salt);
    let addr2 = factory.compute_stealth_address(x, y, salt);
    
    assert(addr1 == addr2, 'Address not deterministic');
}

/// Fuzz test: Different salts should produce different addresses
#[test]
#[fuzzer(runs: 50, seed: 22222)]
fn test_fuzz_factory_salt_uniqueness(x: felt252, y: felt252, salt1: felt252, salt2: felt252) {
    // Skip zero values and same salts
    if x == 0 || y == 0 || salt1 == salt2 {
        return;
    }
    
    let factory = deploy_factory();
    
    let addr1 = factory.compute_stealth_address(x, y, salt1);
    let addr2 = factory.compute_stealth_address(x, y, salt2);
    
    assert(addr1 != addr2, 'Same addr for diff salts');
}

/// Fuzz test: Different keys should produce different addresses
#[test]
#[fuzzer(runs: 50, seed: 33333)]
fn test_fuzz_factory_key_uniqueness(x1: felt252, y1: felt252, x2: felt252, y2: felt252, salt: felt252) {
    // Skip zero values and same keys
    if x1 == 0 || y1 == 0 || x2 == 0 || y2 == 0 {
        return;
    }
    if x1 == x2 && y1 == y2 {
        return;
    }
    
    let factory = deploy_factory();
    
    let addr1 = factory.compute_stealth_address(x1, y1, salt);
    let addr2 = factory.compute_stealth_address(x2, y2, salt);
    
    assert(addr1 != addr2, 'Same addr for diff keys');
}

// ============================================================================
// Fuzz Tests - View Tags
// ============================================================================

/// Fuzz test: View tag should always be in range [0, 255]
#[test]
#[fuzzer(runs: 100, seed: 44444)]
fn test_fuzz_view_tag_in_range(x: felt252, y: felt252) {
    let tag = compute_view_tag(x, y);
    
    // u8 is always in range, but let's verify the computation doesn't panic
    assert(tag <= 255, 'Tag out of range');
}

/// Fuzz test: View tag should be deterministic
#[test]
#[fuzzer(runs: 100, seed: 55555)]
fn test_fuzz_view_tag_deterministic(x: felt252, y: felt252) {
    let tag1 = compute_view_tag(x, y);
    let tag2 = compute_view_tag(x, y);
    
    assert(tag1 == tag2, 'Tag not deterministic');
}

// ============================================================================
// Invariant Tests - Properties that must ALWAYS hold
// ============================================================================

/// Invariant: A registered user must always be able to retrieve their meta-address
#[test]
#[fuzzer(runs: 50, seed: 66666)]
fn test_invariant_registered_user_can_lookup(x: felt252, y: felt252) {
    if !is_valid_public_key(x, y) {
        return;
    }
    
    let registry = deploy_registry();
    let caller = contract_address_const::<0x789>();
    
    start_cheat_caller_address(registry.contract_address, caller);
    registry.register_stealth_meta_address(x, y, x, y, 0);
    
    // INVARIANT: has_meta_address must return true after registration
    assert(registry.has_meta_address(caller), 'Invariant: has_meta violated');
    
    // INVARIANT: get_stealth_meta_address must return the registered values
    let meta = registry.get_stealth_meta_address(caller);
    assert(meta.spending_pubkey_x == x, 'Invariant: x mismatch');
    assert(meta.spending_pubkey_y == y, 'Invariant: y mismatch');
}

/// Invariant: Announcement count must always increase
#[test]
#[fuzzer(runs: 30, seed: 77777)]
fn test_invariant_announcement_count_increases(
    eph_x: felt252, 
    eph_y: felt252,
    num_announcements: u8
) {
    if !is_valid_public_key(eph_x, eph_y) {
        return;
    }
    
    // Limit to reasonable number
    let count: u32 = (num_announcements % 10).into();
    if count == 0 {
        return;
    }
    
    let registry = deploy_registry();
    disable_rate_limit(registry.contract_address);
    let stealth_addr = contract_address_const::<0xabc>();
    
    let initial_count = registry.get_announcement_count();
    
    let mut i: u32 = 0;
    while i < count {
        registry.announce(0, eph_x, eph_y, stealth_addr, 42, 0);
        i += 1;
    };
    
    let final_count = registry.get_announcement_count();
    
    // INVARIANT: count must increase by exactly the number of announcements
    assert(final_count == initial_count + count.into(), 'Invariant: count violated');
}

/// Invariant: compute_stealth_address must match deploy_stealth_account
#[test]
#[fuzzer(runs: 20, seed: 88888)]
fn test_invariant_compute_matches_deploy(x: felt252, y: felt252, salt: felt252) {
    if !is_valid_public_key(x, y) {
        return;
    }
    
    let factory = deploy_factory();
    
    // Compute address first
    let computed = factory.compute_stealth_address(x, y, salt);
    
    // Deploy and get actual address
    let deployed = factory.deploy_stealth_account(x, y, salt);
    
    // CRITICAL INVARIANT: computed address MUST equal deployed address
    assert(computed == deployed, 'CRITICAL: compute != deploy');
}
