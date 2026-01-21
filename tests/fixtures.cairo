/// Test Fixtures and Helpers
///
/// Shared test data and utility functions for the stealth address test suite.

use starknet::{ContractAddress, ClassHash, contract_address_const};
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

use starknet_stealth_addresses::interfaces::i_stealth_registry::{
    IStealthRegistryDispatcher, IStealthRegistryDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_account_factory::{
    IStealthAccountFactoryDispatcher, IStealthAccountFactoryDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_account::{
    IStealthAccountDispatcher, IStealthAccountDispatcherTrait
};

// ============================================================================
// TEST KEYS (for testing only - never use in production!)
// ============================================================================

pub mod test_keys {
    // Valid felt252 values (< 2^251)
    /// Test spending public key X coordinate
    pub const TEST_SPENDING_PUBKEY_X: felt252 = 0x5f3b0e76c0e3c0f7c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5;
    /// Test spending public key Y coordinate
    pub const TEST_SPENDING_PUBKEY_Y: felt252 = 0x6a4c1f87d1f4d1e8d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6;
    
    /// Test ephemeral public key X coordinate
    pub const TEST_EPHEMERAL_PUBKEY_X: felt252 = 0x7b5d2f98e2f5e2f9e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7;
    /// Test ephemeral public key Y coordinate
    pub const TEST_EPHEMERAL_PUBKEY_Y: felt252 = 0x1c6e3fa9f3a6f3faf6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8;
    
    /// Test stealth public key X
    pub const TEST_STEALTH_PUBKEY_X: felt252 = 0x2d7f4fba4b74aba7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0;
    /// Test stealth public key Y
    pub const TEST_STEALTH_PUBKEY_Y: felt252 = 0x3e8a5acb5c8b5bcb8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1;
    
    /// Test view tag
    pub const TEST_VIEW_TAG: u8 = 42;
    
    /// Test salt
    pub const TEST_SALT: felt252 = 0x123456789;
    
    pub mod Alice {
        pub const PUBKEY_X: felt252 = 0x111111111111111111111111111111111111111111111111111111111111;
        pub const PUBKEY_Y: felt252 = 0x222222222222222222222222222222222222222222222222222222222222;
    }
    
    pub mod Bob {
        pub const PUBKEY_X: felt252 = 0x333333333333333333333333333333333333333333333333333333333333;
        pub const PUBKEY_Y: felt252 = 0x444444444444444444444444444444444444444444444444444444444444;
    }
    
    pub mod Charlie {
        pub const PUBKEY_X: felt252 = 0x555555555555555555555555555555555555555555555555555555555555;
        pub const PUBKEY_Y: felt252 = 0x666666666666666666666666666666666666666666666666666666666666;
    }
}

// ============================================================================
// DEPLOYMENT HELPERS
// ============================================================================

/// Deploy the StealthRegistry contract
pub fn deploy_registry() -> (ContractAddress, IStealthRegistryDispatcher) {
    let contract = declare("StealthRegistry").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![]).unwrap();
    let dispatcher = IStealthRegistryDispatcher { contract_address: address };
    (address, dispatcher)
}

/// Deploy the StealthAccountFactory contract
pub fn deploy_factory() -> (ContractAddress, IStealthAccountFactoryDispatcher, ClassHash) {
    // First declare the StealthAccount class
    let account_class = declare("StealthAccount").unwrap().contract_class();
    let account_class_hash = *account_class.class_hash;
    
    // Then deploy the factory with the account class hash
    let factory_class = declare("StealthAccountFactory").unwrap().contract_class();
    let (factory_address, _) = factory_class.deploy(@array![account_class_hash.into()]).unwrap();
    
    let dispatcher = IStealthAccountFactoryDispatcher { contract_address: factory_address };
    (factory_address, dispatcher, account_class_hash)
}

/// Deploy a StealthAccount directly (for testing)
pub fn deploy_stealth_account(
    pubkey_x: felt252,
    pubkey_y: felt252
) -> (ContractAddress, IStealthAccountDispatcher) {
    let contract = declare("StealthAccount").unwrap().contract_class();
    let (address, _) = contract.deploy(@array![pubkey_x, pubkey_y]).unwrap();
    let dispatcher = IStealthAccountDispatcher { contract_address: address };
    (address, dispatcher)
}

/// Deploy full stealth infrastructure
pub struct StealthInfrastructure {
    pub registry_address: ContractAddress,
    pub registry: IStealthRegistryDispatcher,
    pub factory_address: ContractAddress,
    pub factory: IStealthAccountFactoryDispatcher,
    pub account_class_hash: ClassHash,
}

pub fn deploy_full_infrastructure() -> StealthInfrastructure {
    let (registry_address, registry) = deploy_registry();
    let (factory_address, factory, account_class_hash) = deploy_factory();
    
    StealthInfrastructure {
        registry_address,
        registry,
        factory_address,
        factory,
        account_class_hash,
    }
}

// ============================================================================
// TEST ADDRESSES
// ============================================================================

pub fn alice() -> ContractAddress {
    contract_address_const::<'alice'>()
}

pub fn bob() -> ContractAddress {
    contract_address_const::<'bob'>()
}

pub fn charlie() -> ContractAddress {
    contract_address_const::<'charlie'>()
}

pub fn attacker() -> ContractAddress {
    contract_address_const::<'attacker'>()
}
