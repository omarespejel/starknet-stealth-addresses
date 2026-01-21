/// Unit Tests for StealthRegistry Contract

use snforge_std::{
    start_cheat_caller_address, stop_cheat_caller_address,
    spy_events, EventSpyAssertionsTrait,
};
use starknet::contract_address_const;

use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistryDispatcherTrait;
use starknet_stealth_addresses::contracts::stealth_registry::StealthRegistry;
use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::{
    IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait
};

use super::fixtures::{deploy_registry, alice, bob, test_keys};

fn disable_rate_limit(registry_addr: starknet::ContractAddress) {
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry_addr };
    let owner = admin.get_owner();
    start_cheat_caller_address(registry_addr, owner);
    admin.set_min_announce_block_gap(0);
    stop_cheat_caller_address(registry_addr);
}

// ============================================================================
// META-ADDRESS REGISTRATION TESTS
// ============================================================================

#[test]
fn test_unit_registry_register_meta_address() {
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
    
    let meta = registry.get_stealth_meta_address(alice());
    assert(meta.spending_pubkey_x == test_keys::Alice::PUBKEY_X, 'Wrong pubkey X');
    assert(meta.spending_pubkey_y == test_keys::Alice::PUBKEY_Y, 'Wrong pubkey Y');
}

#[test]
fn test_unit_registry_register_meta_address_dual_key() {
    let (_, registry) = deploy_registry();

    start_cheat_caller_address(registry.contract_address, alice());

    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        1
    );

    stop_cheat_caller_address(registry.contract_address);

    let meta = registry.get_stealth_meta_address(alice());
    assert(meta.scheme_id == 1, 'Scheme should be dual-key');
    assert(meta.spending_pubkey_x == test_keys::Alice::PUBKEY_X, 'Spending X mismatch');
    assert(meta.viewing_pubkey_x == test_keys::Bob::PUBKEY_X, 'Viewing X mismatch');
}

#[test]
fn test_unit_registry_has_meta_address() {
    let (_, registry) = deploy_registry();
    
    assert(!registry.has_meta_address(alice()), 'Should not have meta-address');
    
    start_cheat_caller_address(registry.contract_address, alice());
    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    stop_cheat_caller_address(registry.contract_address);
    
    assert(registry.has_meta_address(alice()), 'Should have meta-address');
}

#[test]
fn test_unit_registry_get_unregistered_returns_zero() {
    let (_, registry) = deploy_registry();
    
    let meta = registry.get_stealth_meta_address(alice());
    assert(meta.spending_pubkey_x == 0, 'Unregistered X should be 0');
    assert(meta.spending_pubkey_y == 0, 'Unregistered Y should be 0');
}

#[test]
fn test_unit_registry_update_meta_address() {
    let (_, registry) = deploy_registry();
    
    start_cheat_caller_address(registry.contract_address, alice());
    
    registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    
    registry.update_stealth_meta_address(
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        0
    );
    
    stop_cheat_caller_address(registry.contract_address);
    
    let meta = registry.get_stealth_meta_address(alice());
    assert(meta.spending_pubkey_x == test_keys::Bob::PUBKEY_X, 'Update failed - wrong X');
    assert(meta.spending_pubkey_y == test_keys::Bob::PUBKEY_Y, 'Update failed - wrong Y');
}

#[test]
fn test_unit_registry_multiple_users() {
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
    registry.register_stealth_meta_address(
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        0
    );
    stop_cheat_caller_address(registry.contract_address);
    
    let alice_meta = registry.get_stealth_meta_address(alice());
    let bob_meta = registry.get_stealth_meta_address(bob());
    
    assert(alice_meta.spending_pubkey_x == test_keys::Alice::PUBKEY_X, 'Alice X wrong');
    assert(alice_meta.spending_pubkey_y == test_keys::Alice::PUBKEY_Y, 'Alice Y wrong');
    assert(bob_meta.spending_pubkey_x == test_keys::Bob::PUBKEY_X, 'Bob X wrong');
    assert(bob_meta.spending_pubkey_y == test_keys::Bob::PUBKEY_Y, 'Bob Y wrong');
}

// ============================================================================
// ANNOUNCEMENT TESTS
// ============================================================================

#[test]
fn test_unit_registry_announce() {
    let (_, registry) = deploy_registry();
    
    assert(registry.get_announcement_count() == 0, 'Initial count should be 0');
    
    let stealth_addr = contract_address_const::<'stealth1'>();
    
    registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        stealth_addr,
        test_keys::TEST_VIEW_TAG,
        0
    );
    
    assert(registry.get_announcement_count() == 1, 'Count should be 1');
}

#[test]
fn test_unit_registry_multiple_announcements() {
    let (_, registry) = deploy_registry();
    disable_rate_limit(registry.contract_address);
    
    let stealth_addr = contract_address_const::<'stealth1'>();
    
    let mut i: u8 = 0;
    while i < 5 {
        registry.announce(
            0,
            test_keys::TEST_EPHEMERAL_PUBKEY_X,
            test_keys::TEST_EPHEMERAL_PUBKEY_Y,
            stealth_addr,
            i,
            0
        );
        i += 1;
    };
    
    assert(registry.get_announcement_count() == 5, 'Should have 5 announcements');
}

#[test]
fn test_unit_registry_announce_emits_event() {
    let (registry_addr, registry) = deploy_registry();
    
    let mut spy = spy_events();
    
    let stealth_addr = contract_address_const::<'stealth1'>();
    
    registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        stealth_addr,
        42,
        123
    );
    
    spy.assert_emitted(@array![
        (
            registry_addr,
            StealthRegistry::Event::Announcement(
                StealthRegistry::Announcement {
                    scheme_id: 0,
                    ephemeral_pubkey_x: test_keys::TEST_EPHEMERAL_PUBKEY_X,
                    ephemeral_pubkey_y: test_keys::TEST_EPHEMERAL_PUBKEY_Y,
                    stealth_address: stealth_addr,
                    view_tag: 42,
                    metadata: 123,
                    index: 0,
                }
            )
        )
    ]);
}
