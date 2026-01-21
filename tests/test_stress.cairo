/// Stress Tests for Stealth Address Protocol
///
/// These tests simulate high-load scenarios to ensure the protocol
/// handles many users, announcements, and deployments correctly.
///
/// Run: snforge test test_stress

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

fn disable_rate_limit(registry_addr: starknet::ContractAddress) {
    let admin = IStealthRegistryAdminDispatcher { contract_address: registry_addr };
    let owner = admin.get_owner();
    start_cheat_caller_address(registry_addr, owner);
    admin.set_min_announce_block_gap(0);
    stop_cheat_caller_address(registry_addr);
}

// Helper to get test addresses
fn get_test_addresses() -> Array<starknet::ContractAddress> {
    array![
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
        contract_address_const::<0x10b>(),
        contract_address_const::<0x10c>(),
        contract_address_const::<0x10d>(),
        contract_address_const::<0x10e>(),
        contract_address_const::<0x10f>(),
        contract_address_const::<0x110>(),
        contract_address_const::<0x111>(),
        contract_address_const::<0x112>(),
        contract_address_const::<0x113>(),
        contract_address_const::<0x114>(),
    ]
}

// ============================================================================
// Stress Tests - Many Users
// ============================================================================

/// Stress test: Many users registering meta-addresses
#[test]
fn test_stress_many_user_registrations() {
    let registry = deploy_registry();
    let users = get_test_addresses();
    let num_users: u32 = 20;
    
    let mut i: u32 = 0;
    while i < num_users {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.register_stealth_meta_address(
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            0
        );
        
        // Verify registration
        assert(registry.has_meta_address(caller), 'Registration failed');
        i += 1;
    };
    
    // Verify first and last users can be looked up
    let first_user = *users.at(0);
    let last_user = *users.at(19);
    
    assert(registry.has_meta_address(first_user), 'First user missing');
    assert(registry.has_meta_address(last_user), 'Last user missing');
}

/// Stress test: Many announcements
#[test]
fn test_stress_many_announcements() {
    let registry = deploy_registry();
    disable_rate_limit(registry.contract_address);
    let num_announcements: u64 = 50;
    
    let mut i: u64 = 0;
    while i < num_announcements {
        let stealth_addr = contract_address_const::<0x999>();
        let view_tag: u8 = (i % 256).try_into().unwrap();
        
        registry.announce(
            0, 
            StarkCurve::GEN_X, 
            StarkCurve::GEN_Y, 
            stealth_addr, 
            view_tag, 
            i.into()
        );
        
        i += 1;
    };
    
    // Verify count
    let count = registry.get_announcement_count();
    assert(count == num_announcements, 'Announcement count wrong');
}

/// Stress test: Many stealth account deployments
#[test]
fn test_stress_many_deployments() {
    let factory = deploy_factory();
    let num_deployments: u32 = 15;
    
    let mut deployed_addresses: Array<starknet::ContractAddress> = array![];
    
    let mut i: u32 = 1;
    while i <= num_deployments {
        let salt: felt252 = i.into();
        
        // Deploy with unique salt
        let addr = factory.deploy_stealth_account(StarkCurve::GEN_X, StarkCurve::GEN_Y, salt);
        
        // Verify address is valid (non-zero)
        assert(addr != contract_address_const::<0>(), 'Invalid address');
        
        // Store for uniqueness check
        deployed_addresses.append(addr);
        
        i += 1;
    };
    
    // Verify all addresses are unique (spot check first vs last)
    let first = *deployed_addresses.at(0);
    let last = *deployed_addresses.at(14);
    assert(first != last, 'Addresses not unique');
}

// ============================================================================
// Stress Tests - Mixed Operations
// ============================================================================

/// Stress test: Interleaved operations (realistic usage pattern)
#[test]
fn test_stress_interleaved_operations() {
    let registry = deploy_registry();
    let factory = deploy_factory();
    disable_rate_limit(registry.contract_address);
    let users = get_test_addresses();
    
    // Register 5 users
    let num_users: u32 = 5;
    
    let mut i: u32 = 0;
    while i < num_users {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.register_stealth_meta_address(
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            0
        );
        i += 1;
    };
    
    // Make 3 payments to each user (15 total)
    let payments_per_user: u32 = 3;
    let mut payment_id: u32 = 1;
    
    i = 0;
    while i < num_users {
        let mut j: u32 = 0;
        while j < payments_per_user {
            let salt: felt252 = payment_id.into();
            
            // Compute and deploy
            let computed = factory.compute_stealth_address(StarkCurve::GEN_X, StarkCurve::GEN_Y, salt);
            let deployed = factory.deploy_stealth_account(StarkCurve::GEN_X, StarkCurve::GEN_Y, salt);
            assert(computed == deployed, 'Address mismatch');
            
            // Announce
            registry.announce(0, StarkCurve::GEN_X, StarkCurve::GEN_Y, deployed, 42, salt);
            
            payment_id += 1;
            j += 1;
        };
        i += 1;
    };
    
    // Verify final state
    let expected: u64 = (num_users * payments_per_user).into();
    assert(registry.get_announcement_count() == expected, 'Wrong count');
}

/// Stress test: Rapid sequential registrations
#[test]
fn test_stress_rapid_registrations() {
    let registry = deploy_registry();
    let users = get_test_addresses();
    let num_users: u32 = 20;
    
    // Register all users rapidly
    let mut i: u32 = 0;
    while i < num_users {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.register_stealth_meta_address(
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            0
        );
        i += 1;
    };
    
    // Verify all registrations persisted
    i = 0;
    while i < num_users {
        let addr = *users.at(i);
        assert(registry.has_meta_address(addr), 'Registration lost');
        i += 1;
    };
}

// ============================================================================
// Stress Tests - Edge Cases Under Load
// ============================================================================

/// Stress test: Updates under load
#[test]
fn test_stress_updates_under_load() {
    let registry = deploy_registry();
    let users = get_test_addresses();
    let num_users: u32 = 10;
    
    // Register all users
    let mut i: u32 = 0;
    while i < num_users {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.register_stealth_meta_address(
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            0
        );
        i += 1;
    };
    
    // Now update all users (simulates key rotation)
    i = 0;
    while i < num_users {
        let caller = *users.at(i);
        start_cheat_caller_address(registry.contract_address, caller);
        registry.update_stealth_meta_address(
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            StarkCurve::GEN_X,
            StarkCurve::GEN_Y,
            0
        );
        
        // Verify update worked
        let meta = registry.get_stealth_meta_address(caller);
        assert(meta.spending_pubkey_x == StarkCurve::GEN_X, 'Update failed');
        i += 1;
    };
}

/// Stress test: View tag distribution
#[test]
fn test_stress_view_tag_distribution() {
    // Compute many view tags and verify they're all in range
    let mut i: u32 = 0;
    
    while i < 100 {
        let offset: felt252 = i.into();
        let tag = compute_view_tag(StarkCurve::GEN_X + offset, StarkCurve::GEN_Y);
        
        // View tag must always be in [0, 255]
        assert(tag <= 255, 'View tag out of range');
        
        i += 1;
    };
}

/// Stress test: Address computation consistency under load
#[test]
fn test_stress_compute_consistency() {
    let factory = deploy_factory();
    
    // Compute same address many times - must always match
    let mut i: u32 = 0;
    let first_addr = factory.compute_stealth_address(StarkCurve::GEN_X, StarkCurve::GEN_Y, 12345);
    
    while i < 50 {
        let addr = factory.compute_stealth_address(StarkCurve::GEN_X, StarkCurve::GEN_Y, 12345);
        assert(addr == first_addr, 'Inconsistent computation');
        i += 1;
    };
}
