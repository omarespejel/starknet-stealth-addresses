use starknet::ContractAddress;

/// Stealth Registry Admin Interface
///
/// Optional administrative controls for rate limiting announcements.
#[starknet::interface]
pub trait IStealthRegistryAdmin<TContractState> {
    /// Set minimum block gap between announcements (0 = disabled)
    fn set_min_announce_block_gap(ref self: TContractState, min_gap: u64);

    /// Get minimum block gap between announcements
    fn get_min_announce_block_gap(self: @TContractState) -> u64;

    /// Get registry owner
    fn get_owner(self: @TContractState) -> ContractAddress;
}
