/// Deployment Fixtures
///
/// Helper functions for deploying contracts in tests.

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

/// Deploy the StealthRegistry contract
pub fn deploy_registry() -> (ContractAddress, IStealthRegistryDispatcher) {
    let contract = declare("StealthRegistry").unwrap().contract_class();
    let owner = registry_owner();
    let (address, _) = contract.deploy(@array![owner.into()]).unwrap();
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

/// Test addresses
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

pub fn registry_owner() -> ContractAddress {
    contract_address_const::<'registry_owner'>()
}
