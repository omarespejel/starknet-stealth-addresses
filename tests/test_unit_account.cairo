/// Unit Tests for StealthAccount Contract

use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

use starknet_stealth_addresses::interfaces::i_stealth_account::IStealthAccountDispatcherTrait;
use openzeppelin_account::interface::ISRC6_ID;
use openzeppelin_introspection::interface::{ISRC5_ID, ISRC5DispatcherTrait};

use super::fixtures::{deploy_stealth_account, test_keys};

// ============================================================================
// CONSTRUCTOR AND INITIALIZATION TESTS
// ============================================================================

#[test]
fn test_unit_account_constructor_stores_pubkey() {
    let (_, account) = deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y
    );
    
    let (x, y) = account.get_stealth_public_key();
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'Wrong pubkey X');
    assert(y == test_keys::TEST_STEALTH_PUBKEY_Y, 'Wrong pubkey Y');
}

#[test]
fn test_unit_account_get_public_key_returns_x() {
    let (_, account) = deploy_stealth_account(
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y
    );
    
    let x = account.get_public_key();
    assert(x == test_keys::TEST_STEALTH_PUBKEY_X, 'get_public_key should return X');
}

// ============================================================================
// INTERFACE SUPPORT TESTS
// ============================================================================

#[test]
fn test_unit_account_supports_src6() {
    let contract = declare("StealthAccount").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y
    ]).unwrap();
    
    let src5_dispatcher = openzeppelin_introspection::interface::ISRC5Dispatcher { 
        contract_address: address 
    };
    
    assert(src5_dispatcher.supports_interface(ISRC6_ID), 'Should support SRC6');
}

#[test]
fn test_unit_account_supports_src5() {
    let contract = declare("StealthAccount").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![
        test_keys::TEST_STEALTH_PUBKEY_X,
        test_keys::TEST_STEALTH_PUBKEY_Y
    ]).unwrap();
    
    let src5_dispatcher = openzeppelin_introspection::interface::ISRC5Dispatcher { 
        contract_address: address 
    };
    
    assert(src5_dispatcher.supports_interface(ISRC5_ID), 'Should support SRC5');
}

#[test]
fn test_unit_account_various_keys() {
    let (_, alice_account) = deploy_stealth_account(
        test_keys::Alice::PUBKEY_X,
        test_keys::Alice::PUBKEY_Y
    );
    let (ax, ay) = alice_account.get_stealth_public_key();
    assert(ax == test_keys::Alice::PUBKEY_X, 'Alice X wrong');
    assert(ay == test_keys::Alice::PUBKEY_Y, 'Alice Y wrong');
    
    let (_, bob_account) = deploy_stealth_account(
        test_keys::Bob::PUBKEY_X,
        test_keys::Bob::PUBKEY_Y
    );
    let (bx, by) = bob_account.get_stealth_public_key();
    assert(bx == test_keys::Bob::PUBKEY_X, 'Bob X wrong');
    assert(by == test_keys::Bob::PUBKEY_Y, 'Bob Y wrong');
}
