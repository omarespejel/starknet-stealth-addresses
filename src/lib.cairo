/// Starknet Stealth Addresses - SNIP-XX Reference Implementation
/// 
/// A production-grade stealth address protocol enabling non-interactive
/// generation of one-time recipient addresses for enhanced privacy.
///
/// ## Architecture
/// 
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                    STEALTH ADDRESS PROTOCOL                      │
/// ├─────────────────────────────────────────────────────────────────┤
/// │  StealthRegistry     - Meta-address storage + announcements     │
/// │  StealthAccount      - SNIP-6 compliant one-time account        │
/// │  StealthAccountFactory - Deterministic account deployment       │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Security Properties
/// - Recipient unlinkability: One-time addresses are cryptographically unlinkable
/// - Non-interactive: No recipient interaction required for address generation
/// - View tag optimization: 256x scanning speedup with 8-bit view tags
/// - Account abstraction: Native paymaster support for gas abstraction

// ============================================================================
// INTERFACES - Design by Contract
// ============================================================================

pub mod interfaces {
    pub mod i_stealth_registry;
    pub mod i_stealth_registry_admin;
    pub mod i_stealth_account;
    pub mod i_stealth_account_factory;
}

// ============================================================================
// CORE CONTRACTS
// ============================================================================

pub mod contracts {
    pub mod stealth_registry;
    pub mod stealth_account;
    pub mod stealth_account_factory;
}

// ============================================================================
// CRYPTOGRAPHIC UTILITIES
// ============================================================================

pub mod crypto {
    pub mod view_tag;
    pub mod constants;
}

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

pub mod types {
    pub mod meta_address;
    pub mod announcement;
}

// ============================================================================
// ERROR DEFINITIONS
// ============================================================================

pub mod errors;

// ============================================================================
// RE-EXPORTS for convenience
// ============================================================================

pub use interfaces::i_stealth_registry::{IStealthRegistry, IStealthRegistryDispatcher, IStealthRegistryDispatcherTrait};
pub use interfaces::i_stealth_registry_admin::{IStealthRegistryAdmin, IStealthRegistryAdminDispatcher, IStealthRegistryAdminDispatcherTrait};
pub use interfaces::i_stealth_account::{IStealthAccount, IStealthAccountDispatcher, IStealthAccountDispatcherTrait};
pub use interfaces::i_stealth_account_factory::{IStealthAccountFactory, IStealthAccountFactoryDispatcher, IStealthAccountFactoryDispatcherTrait};
pub use types::meta_address::StealthMetaAddress;
pub use types::announcement::AnnouncementData;
