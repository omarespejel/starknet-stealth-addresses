/// Unit Tests for StealthAccountFactory Contract

use starknet_stealth_addresses::interfaces::i_stealth_account_factory::IStealthAccountFactoryDispatcherTrait;
use starknet_stealth_addresses::interfaces::i_stealth_account::{
    IStealthAccountDispatcher, IStealthAccountDispatcherTrait
};
use starknet_stealth_addresses::crypto::constants::AddressComputation;

use super::fixtures::{deploy_factory, test_keys};

// ============================================================================
// DEPLOYMENT TESTS
// ============================================================================

#[test]
fn test_unit_factory_deploy_account() {
    let (_, factory, _) = deploy_factory();
    
    let stealth_address = factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    let account = IStealthAccountDispatcher { contract_address: stealth_address };
    let (x, y) = account.get_stealth_public_key();
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'Wrong pubkey X');
    assert(y == test_keys::TEST_STEALTH_PUBKEY_Y, 'Wrong pubkey Y');
}

#[test]
fn test_unit_factory_deployment_count() {
    let (_, factory, _) = deploy_factory();
    
    assert(factory.get_deployment_count() == 0, 'Initial count should be 0');
    
    factory.deploy_stealth_account(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y,
        1
    );
    assert(factory.get_deployment_count() == 1, 'Count should be 1');
    
    factory.deploy_stealth_account(
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y,
        2
    );
    assert(factory.get_deployment_count() == 2, 'Count should be 2');
}

#[test]
fn test_unit_factory_different_salts_different_addresses() {
    let (_, factory, _) = deploy_factory();
    
    let addr1 = factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        1
    );
    
    let addr2 = factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        2
    );
    
    assert(addr1 != addr2, 'Diff salts = diff addresses');
}

// Note: compute_stealth_address uses the Starknet contract address formula:
// h(h(h(h(PREFIX, deployer), salt), class_hash), calldata_hash)
// The deploy_syscall may use slightly different internals in test environment.
// This test verifies deployment works; address precomputation is validated in SDK.
#[test]
fn test_unit_factory_deploy_returns_valid_address() {
    let (_, factory, _) = deploy_factory();
    
    let deployed = factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    // Verify address is non-zero (valid deployment)
    let addr_felt: felt252 = deployed.into();
    assert(addr_felt != 0, 'Address must be non-zero');
    
    // Verify we can interact with the deployed account
    let account = IStealthAccountDispatcher { contract_address: deployed };
    let (x, y) = account.get_stealth_public_key();
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'Pubkey X mismatch');
    assert(y == test_keys::TEST_STEALTH_PUBKEY_Y, 'Pubkey Y mismatch');
}

#[test]
fn test_unit_factory_get_class_hash() {
    let (_, factory, expected_class_hash) = deploy_factory();
    
    let stored_class_hash = factory.get_account_class_hash();
    assert(stored_class_hash == expected_class_hash, 'Class hash mismatch');
}

#[test]
fn test_unit_factory_normalize_contract_address_hash() {
    let raw = AddressComputation::CONTRACT_ADDRESS_BOUND + 1;
    let normalized = AddressComputation::normalize_contract_address_hash(raw);
    assert(normalized == 1, 'Normalize wrap');
}

#[test]
fn test_unit_factory_normalize_contract_address_boundaries() {
    let bound = AddressComputation::CONTRACT_ADDRESS_BOUND;
    let last = bound - 1;
    let normalized_bound = AddressComputation::normalize_contract_address_hash(bound);
    let normalized_last = AddressComputation::normalize_contract_address_hash(last);
    assert(normalized_bound == 0, 'Normalize bound');
    assert(normalized_last == last, 'Normalize last');
}

#[test]
fn test_unit_factory_normalize_contract_address_idempotent() {
    let raw = AddressComputation::CONTRACT_ADDRESS_BOUND + 123;
    let normalized_once = AddressComputation::normalize_contract_address_hash(raw);
    let normalized_twice = AddressComputation::normalize_contract_address_hash(normalized_once);
    assert(normalized_once == normalized_twice, 'Normalize idempotent');
}

// ============================================================================
// CRITICAL: ADDRESS COMPUTATION MUST MATCH DEPLOYMENT
// ============================================================================

/// This is the most critical test for production safety.
/// compute_stealth_address MUST return the exact same address that
/// deploy_stealth_account will deploy to. If these don't match,
/// senders will send funds to addresses that recipients can't access.
#[test]
fn test_unit_factory_compute_matches_deploy_critical() {
    let (_, factory, _) = deploy_factory();
    
    // Test with multiple key/salt combinations
    let test_cases: Array<(felt252, felt252, felt252)> = array![
        (test_keys::TEST_STEALTH_PUBKEY_X, test_keys::TEST_STEALTH_PUBKEY_Y, test_keys::TEST_SALT),
        (test_keys::Alice::PUBKEY_X, test_keys::Alice::PUBKEY_Y, 12345),
        (test_keys::Bob::PUBKEY_X, test_keys::Bob::PUBKEY_Y, 99999),
        (test_keys::Charlie::PUBKEY_X, test_keys::Charlie::PUBKEY_Y, 1),
        // Edge case: large salt
        (test_keys::TEST_STEALTH_PUBKEY_X, test_keys::TEST_STEALTH_PUBKEY_Y, 0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff),
    ];
    
    let mut i: u32 = 0;
    loop {
        if i >= test_cases.len() {
            break;
        }
        
        let (pubkey_x, pubkey_y, salt) = *test_cases.at(i);
        
        // First compute the expected address
        let computed = factory.compute_stealth_address(pubkey_x, pubkey_y, salt);
        
        // Then deploy and get the actual address
        let deployed = factory.deploy_stealth_account(pubkey_x, pubkey_y, salt);
        
        // CRITICAL ASSERTION: These MUST be equal
        assert(computed == deployed, 'CRITICAL: compute != deploy');
        
        i += 1;
    };
}

/// Test that pre-computing address before deployment works correctly
/// This simulates the real-world sender workflow
#[test]
fn test_unit_factory_sender_workflow_precompute() {
    let (_, factory, _) = deploy_factory();
    
    // Sender pre-computes address (this happens off-chain in production)
    let precomputed = factory.compute_stealth_address(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    // Sender could send funds to precomputed address here
    // (funds would be locked until deployment)
    
    // Later, someone deploys the account
    let actual = factory.deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y,
        test_keys::TEST_SALT
    );
    
    // Recipient's account MUST be at the precomputed address
    assert(precomputed == actual, 'Precompute must match deploy');
    
    // Verify the account is functional
    let account = IStealthAccountDispatcher { contract_address: actual };
    let (x, _) = account.get_stealth_public_key();
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'Account not functional');
}
