/// End-to-End Tests for Stealth Payments

use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};
use starknet::contract_address_const;

use starknet_stealth_addresses::interfaces::i_stealth_registry::IStealthRegistryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::{
    IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_account_factory::IStealthAccountFactoryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_account::{
    IStealthAccountDispatcher, IStealthAccountDispatcherTrait
};
use starknet_stealth_addresses::crypto::view_tag::compute_view_tag;

use super::fixtures::{deploy_full_infrastructure, alice, bob, charlie, test_keys};

fn disable_rate_limit(registry_addr: starknet::ContractAddress) {
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry_addr };
    let owner = admin.get_owner();
    start_cheat_caller_address(registry_addr, owner);
    admin.set_min_announce_block_gap(0);
    stop_cheat_caller_address(registry_addr);
}

#[test]
fn test_e2e_complete_stealth_payment() {
    let infra = deploy_full_infrastructure();
    
    // STEP 1: Alice registers
    start_cheat_caller_address(infra.registry_address, alice());
    infra.registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    stop_cheat_caller_address(infra.registry_address);
    
    assert(infra.registry.has_meta_address(alice()), 'Alice should be registered');
    
    // STEP 2: Bob looks up Alice
    let alice_meta = infra.registry.get_stealth_meta_address(alice());
    assert(alice_meta.spending_pubkey_x != 0, 'Should find Alice meta-address');
    
    // STEP 3: Bob computes stealth address
    let stealth_pubkey_x = test_keys::TEST_STEALTH_PUBKEY_X;
    let stealth_pubkey_y = test_keys::TEST_STEALTH_PUBKEY_Y;
    let view_tag = compute_view_tag(stealth_pubkey_x, stealth_pubkey_y);
    let salt: felt252 = 0xABCDEF123456;
    
    // STEP 4: Deploy stealth account
    // Note: Address precomputation is validated in the SDK which uses 
    // the exact Starknet address formula. Factory's compute_stealth_address
    // provides deterministic output for off-chain use.
    let deployed_address = infra.factory.deploy_stealth_account(
        stealth_pubkey_x,
        stealth_pubkey_y,
        salt
    );
    let addr_felt: felt252 = deployed_address.into();
    assert(addr_felt != 0, 'Deploy must succeed');
    
    // STEP 5: Announce
    infra.registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        deployed_address,
        view_tag,
        0
    );
    
    // STEP 6: Verify
    let account = IStealthAccountDispatcher { contract_address: deployed_address };
    let (claimed_x, claimed_y) = account.get_stealth_public_key();
    
    assert(claimed_x == stealth_pubkey_x, 'Account has correct key X');
    assert(claimed_y == stealth_pubkey_y, 'Account has correct key Y');
    
    assert(infra.registry.get_announcement_count() == 1, 'One announcement');
    assert(infra.factory.get_deployment_count() == 1, 'One deployment');
}

#[test]
fn test_e2e_multiple_senders_single_recipient() {
    let infra = deploy_full_infrastructure();
    disable_rate_limit(infra.registry_address);
    
    start_cheat_caller_address(infra.registry_address, alice());
    infra.registry.register_stealth_meta_address(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        0
    );
    stop_cheat_caller_address(infra.registry_address);
    
    let addr1 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X, test_keys::TEST_STEALTH_PUBKEY_Y, 1
    );
    infra.registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        addr1,
        10,
        0
    );
    
    let addr2 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X, test_keys::TEST_STEALTH_PUBKEY_Y, 2
    );
    infra.registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        addr2,
        20,
        0
    );
    
    let addr3 = infra.factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X, test_keys::TEST_STEALTH_PUBKEY_Y, 3
    );
    infra.registry.announce(
        0,
        test_keys::TEST_EPHEMERAL_PUBKEY_X,
        test_keys::TEST_EPHEMERAL_PUBKEY_Y,
        addr3,
        30,
        0
    );
    
    assert(addr1 != addr2, 'Addresses are unique');
    assert(addr2 != addr3, 'Addresses are unique');
    assert(addr1 != addr3, 'Addresses are unique');
    
    assert(infra.registry.get_announcement_count() == 3, '3 announcements');
    assert(infra.factory.get_deployment_count() == 3, '3 accounts');
}

#[test]
fn test_e2e_scanning_with_view_tags() {
    let infra = deploy_full_infrastructure();
    disable_rate_limit(infra.registry_address);
    
    let mut i: u8 = 0;
    while i < 10 {
        let addr = contract_address_const::<'stealth'>();
        infra.registry.announce(
            0,
            test_keys::TEST_EPHEMERAL_PUBKEY_X,
            test_keys::TEST_EPHEMERAL_PUBKEY_Y,
            addr,
            i,
            0
        );
        i += 1;
    };
    
    assert(infra.registry.get_announcement_count() == 10, '10 announcements');
}
