/// Security Tests for StealthRegistry Contract

use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::contract_address_const;

use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::{
    IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait
};

use super::fixtures::{deploy_registry, alice, bob, test_keys};

// ============================================================================
// INPUT VALIDATION SECURITY TESTS
// ============================================================================

#[test]
#[should_panic(expected: 'STEALTH: invalid meta address')]
fn test_security_registry_reject_zero_x() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    registry.register_stealth_meta_address(
        0,
        test_keys::Alice::PUBKEY_Y,
        0,
        test_keys::Alice::PUBKEY_Y,
        0
    );
}

#[test]
#[should_panic(expected: 'STEALTH: invalid meta address')]
fn test_security_registry_reject_zero_y() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        0,
        test_keys::Alice::PUBKEY_X,
        0,
        0
    );
}

#[test]
#[should_panic(expected: 'STEALTH: invalid ephemeral key')]
fn test_security_registry_announce_reject_zero_ephemeral_x() {
    let (_, registry) = deploy_registry();
    let stealth_addr = contract_address_const::<'stealth1'>();
    
    registry.announce(0, 0, test_keys::TEST_EPHEMERAL_PUBKEY_Y, stealth_addr, 42, 0);
}

#[test]
#[should_panic(expected: 'STEALTH: invalid ephemeral key')]
fn test_security_registry_announce_reject_zero_ephemeral_y() {
    let (_, registry) = deploy_registry();
    let stealth_addr = contract_address_const::<'stealth1'>();
    
    registry.announce(0, test_keys::TEST_EPHEMERAL_PUBKEY_X, 0, stealth_addr, 42, 0);
}

#[test]
#[should_panic(expected: 'STEALTH: invalid scheme id')]
fn test_security_registry_announce_reject_invalid_scheme() {
    let (_, registry) = deploy_registry();
    let stealth_addr = contract_address_const::<'stealth1'>();

    // Only scheme_id == 0 or 1 is supported
    registry.announce(2, test_keys::TEST_EPHEMERAL_PUBKEY_X, test_keys::TEST_EPHEMERAL_PUBKEY_Y, stealth_addr, 42, 0);
}

#[test]
#[should_panic(expected: 'STEALTH: unauthorized')]
fn test_security_registry_admin_only_owner() {
    let (_, registry) = deploy_registry();
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry.contract_address };

    start_cheat_caller_address(registry.contract_address, bob());
    admin.set_min_announce_block_gap(1);
}

#[test]
fn test_security_registry_admin_can_update_gap() {
    let (_, registry) = deploy_registry();
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry.contract_address };

    let owner = admin.get_owner();
    start_cheat_caller_address(registry.contract_address, owner);
    admin.set_min_announce_block_gap(1000);

    let gap = admin.get_min_announce_block_gap();
    assert(gap == 1000, 'Gap not updated');
}

#[test]
#[should_panic(expected: 'STEALTH: rate limited')]
fn test_security_registry_rate_limit_enforced() {
    let (_, registry) = deploy_registry();
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry.contract_address };

    let owner = admin.get_owner();
    start_cheat_caller_address(registry.contract_address, owner);
    admin.set_min_announce_block_gap(1000);

    let stealth_addr = contract_address_const::<'stealth1'>();
    registry.announce(0, test_keys::TEST_EPHEMERAL_PUBKEY_X, test_keys::TEST_EPHEMERAL_PUBKEY_Y, stealth_addr, 42, 0);

    // Second announce should be rate-limited (gap too large)
    registry.announce(0, test_keys::TEST_EPHEMERAL_PUBKEY_X, test_keys::TEST_EPHEMERAL_PUBKEY_Y, stealth_addr, 42, 0);
}

// ============================================================================
// STATE CONSISTENCY SECURITY TESTS
// ============================================================================

#[test]
#[should_panic(expected: 'STEALTH: already registered')]
fn test_security_registry_cannot_double_register() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    
    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    
    registry.register_stealth_meta_address(
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        0
    );
}

#[test]
#[should_panic(expected: 'STEALTH: meta addr not found')]
fn test_security_registry_cannot_update_unregistered() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    registry.update_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
}

#[test]
fn test_security_registry_user_isolation() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    stop_cheat_caller_address(registry.contract_address);
    
    start_cheat_caller_address(registry.contract_address, bob());
    assert(!registry.has_meta_address(bob()), 'Bob should not be registered');
    
    let meta = registry.get_stealth_meta_address(alice());
    assert(meta.spending_pubkey_x == test_keys::Alice::PUBKEY_X, 'Alice X unchanged');
    assert(meta.spending_pubkey_y == test_keys::Alice::PUBKEY_Y, 'Alice Y unchanged');
}
