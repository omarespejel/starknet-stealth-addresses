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

    /// Get pending owner (two-step transfer)
    fn get_pending_owner(self: @TContractState) -> ContractAddress;

    /// Begin ownership transfer (two-step)
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    /// Accept ownership transfer
    fn accept_ownership(ref self: TContractState);

    /// Cancel pending ownership transfer
    fn cancel_ownership_transfer(ref self: TContractState);
}
