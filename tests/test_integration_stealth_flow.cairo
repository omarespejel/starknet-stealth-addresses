/// Integration Tests for Stealth Address Flow

use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::contract_address_const;

use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_account_factory::IStealthAccountFactoryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_account::{
    IStealthAccountDispatcher, IStealthAccountDispatcherTrait
};

use super::fixtures::{deploy_full_infrastructure, alice, bob, charlie, test_keys};

#[test]
fn test_integration_register_and_lookup() {
    let infra = deploy_full_infrastructure();
    
    start_cheat_caller_address(infra.registry_address, alice());
    infra.registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y
    );
    stop_cheat_caller_address(infra.registry_address);
    
    let (x, y) = infra.registry.get_stealth_meta_address(alice());
    
    assert(x == test_keys::Alice::PUBKEY_X, 'Lookup X correct');
    assert(y == test_keys::Alice::PUBKEY_Y, 'Lookup Y correct');
}

#[test]
fn test_integration_deploy_stealth_account_via_factory() {
    let infra = deploy_full_infrastructure();
    
    let stealth_address = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    let account = IStealthAccountDispatcher { contract_address: stealth_address };
    let (x, y) = account.get_stealth_public_key();
    
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'Stealth pubkey X');
    assert(y == test_keys::TEST_STEALTH_PUBKEY_Y, 'Stealth pubkey Y');
}

#[test]
fn test_integration_announce_after_deploy() {
    let infra = deploy_full_infrastructure();
    
    let stealth_address = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    infra.registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        stealth_address,
        test_keys::TEST_VIEW_TAG,
        0
    );
    
    assert(infra.registry.get_announcement_count() == 1, 'Should have 1 announcement');
}

#[test]
fn test_integration_multiple_recipients() {
    let infra = deploy_full_infrastructure();
    
    start_cheat_caller_address(infra.registry_address, alice());
    infra.registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X, test_keys::Alice::PUBKEY_Y
    );
    stop_cheat_caller_address(infra.registry_address);
    
    start_cheat_caller_address(infra.registry_address, bob());
    infra.registry.register_stealth_meta_address(
        test_keys::Bob::PUBKEY_X, test_keys::Bob::PUBKEY_Y
    );
    stop_cheat_caller_address(infra.registry_address);
    
    start_cheat_caller_address(infra.registry_address, charlie());
    infra.registry.register_stealth_meta_address(
        test_keys::Charlie::PUBKEY_X, test_keys::Charlie::PUBKEY_Y
    );
    stop_cheat_caller_address(infra.registry_address);
    
    assert(infra.registry.has_meta_address(alice()), 'Alice registered');
    assert(infra.registry.has_meta_address(bob()), 'Bob registered');
    assert(infra.registry.has_meta_address(charlie()), 'Charlie registered');
}

#[test]
fn test_integration_multiple_payments_unlinkable() {
    let infra = deploy_full_infrastructure();
    
    let addr1 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        1
    );
    
    let addr2 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        2
    );
    
    let addr3 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        3
    );
    
    assert(addr1 != addr2, 'addr1 != addr2');
    assert(addr2 != addr3, 'addr2 != addr3');
    assert(addr1 != addr3, 'addr1 != addr3');
    
    infra.registry.announce(0, 1, 1, addr1, 10, 0);
    infra.registry.announce(0, 2, 2, addr2, 20, 0);
    infra.registry.announce(0, 3, 3, addr3, 30, 0);
    
    assert(infra.registry.get_announcement_count() == 3, 'Three announcements');
}
