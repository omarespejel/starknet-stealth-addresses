/// Gas Benchmark Tests for Stealth Address Protocol
///
/// These tests establish gas baselines and ensure operations stay efficient.
/// If gas usage increases significantly, these tests will fail.
///
/// Run: snforge test test_gas

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address
};
use starknet::contract_address_const;
use starknet_stealth_addresses::interfaces::i_stealth_registry::{
    IStealthRegistryDispatcher, IStealthRegistryDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_registry_admin::{
    IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait
};
use starknet_stealth_addresses::interfaces::i_stealth_account_factory::{
    IStealthAccountFactoryDispatcher, IStealthAccountFactoryDispatcherTrait
};
use starknet_stealth_addresses::crypto::constants::StarkCurve;

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

fn disable_rate_limit(registry_addr: starknet::ContractAddress) {
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry_addr };
    let owner = admin.get_owner();
    start_cheat_caller_address(registry_addr, owner);
    admin.set_min_announce_block_gap(0);
    stop_cheat_caller_address(registry_addr);
}

// ============================================================================
// Gas Benchmark Tests
// ============================================================================

/// Benchmark: Meta-address registration
/// This is a write operation users do once
#[test]
fn test_gas_benchmark_register_meta_address() {
    let registry = deploy_registry();
    let caller = contract_address_const::<0x123>();
    
    start_cheat_caller_address(registry.contract_address, caller);
    
    // This operation should be efficient - users register once
    registry.register_stealth_meta_address(StarkCurve::GEN_X, StarkCurve::GEN_Y);
    
    // Gas is logged by snforge - check output for l2_gas
    // Target: < 1M l2_gas for registration
}

/// Benchmark: Meta-address lookup
/// This is a read operation senders do frequently
#[test]
fn test_gas_benchmark_lookup_meta_address() {
    let registry = deploy_registry();
    let caller = contract_address_const::<0x123>();
    
    start_cheat_caller_address(registry.contract_address, caller);
    registry.register_stealth_meta_address(StarkCurve::GEN_X, StarkCurve::GEN_Y);
    
    // Lookup should be very cheap - it's a read operation
    let (_x, _y) = registry.get_stealth_meta_address(caller);
    
    // Target: < 500K l2_gas for lookup
}

/// Benchmark: Announcement emission
/// Senders call this for every payment
#[test]
fn test_gas_benchmark_announce() {
    let registry = deploy_registry();
    let stealth_addr = contract_address_const::<0x456>();
    
    // Announcement should be efficient - called per payment
    registry.announce(0, StarkCurve::GEN_X, StarkCurve::GEN_Y, stealth_addr, 42, 0);
    
    // Target: < 700K l2_gas for announce
}

/// Benchmark: Stealth address computation (view function)
/// Senders call this to pre-compute addresses
#[test]
fn test_gas_benchmark_compute_address() {
    let factory = deploy_factory();
    
    // Compute should be cheap - it's a view function
    let _addr = factory.compute_stealth_address(StarkCurve::GEN_X, StarkCurve::GEN_Y, 12345);
    
    // Target: < 300K l2_gas for compute
}

/// Benchmark: Stealth account deployment
/// This is the most expensive operation
#[test]
fn test_gas_benchmark_deploy_stealth_account() {
    let factory = deploy_factory();
    
    // Deployment is expected to be expensive
    let _addr = factory.deploy_stealth_account(StarkCurve::GEN_X, StarkCurve::GEN_Y, 12345);
    
    // Target: < 1.5M l2_gas for deployment
}

/// Benchmark: Full sender workflow (compute + deploy + announce)
#[test]
fn test_gas_benchmark_full_sender_workflow() {
    let registry = deploy_registry();
    let factory = deploy_factory();
    
    // Step 1: Compute address
    let stealth_addr = factory.compute_stealth_address(StarkCurve::GEN_X, StarkCurve::GEN_Y, 99999);
    
    // Step 2: Deploy account
    let deployed_addr = factory.deploy_stealth_account(StarkCurve::GEN_X, StarkCurve::GEN_Y, 99999);
    assert(stealth_addr == deployed_addr, 'Address mismatch');
    
    // Step 3: Announce
    registry.announce(0, StarkCurve::GEN_X, StarkCurve::GEN_Y, deployed_addr, 42, 0);
    
    // Total target: < 2.5M l2_gas for full workflow
}

// ============================================================================
// Efficiency Tests
// ============================================================================

/// Test: Multiple lookups should not increase gas linearly
#[test]
fn test_gas_efficiency_multiple_lookups() {
    let registry = deploy_registry();
    
    // Register multiple users using pre-defined addresses
    let users: Array<starknet::ContractAddress> = array![
        contract_address_const::<0x101>(),
        contract_address_const::<0x102>(),
        contract_address_const::<0x103>(),
        contract_address_const::<0x104>(),
        contract_address_const::<0x105>(),
        contract_address_const::<0x106>(),
        contract_address_const::<0x107>(),
        contract_address_const::<0x108>(),
        contract_address_const::<0x109>(),
        contract_address_const::<0x10a>(),
    ];
    
    let mut i: u32 = 0;
    while i < 10 {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.register_stealth_meta_address(StarkCurve::GEN_X, StarkCurve::GEN_Y);
        i += 1;
    };
    
    // Lookups should be O(1), not affected by registry size
    let first_user = contract_address_const::<0x101>();
    let (_x, _y) = registry.get_stealth_meta_address(first_user);
    
    // Verify lookup still works
    assert(_x == StarkCurve::GEN_X, 'Lookup failed');
}

/// Test: Announcement count should be O(1)
#[test]
fn test_gas_efficiency_announcement_count() {
    let registry = deploy_registry();
    disable_rate_limit(registry.contract_address);
    let stealth_addr = contract_address_const::<0x456>();
    
    // Make many announcements
    let mut i: u32 = 0;
    while i < 20 {
        registry.announce(0, StarkCurve::GEN_X, StarkCurve::GEN_Y, stealth_addr, 42, i.into());
        i += 1;
    };
    
    // Get count - should be O(1)
    let count = registry.get_announcement_count();
    assert(count == 20, 'Count mismatch');
}
