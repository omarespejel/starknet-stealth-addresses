/// Stealth Account Contract
///
/// A SNIP-6 compliant account contract for one-time stealth addresses.
/// Each stealth account is controlled by a derived spending key that only
/// the recipient can compute.
///
/// ## Security Properties
/// - Single owner: Only the stealth private key holder can sign transactions
/// - ECDSA verification: Uses STARK curve ECDSA (native builtin)
/// - Protocol-only execution: Only Starknet protocol can call __execute__
///
/// ## Integration with Paymasters
/// This account works with Starknet's native paymaster infrastructure,
/// solving the gas funding problem for stealth addresses.

#[starknet::contract(account)]
pub mod StealthAccount {
    use starknet::{get_caller_address, get_tx_info, get_contract_address, ContractAddress};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::account::Call;
    use starknet::syscalls::call_contract_syscall;
    use core::num::traits::Zero;
    use core::ecdsa::check_ecdsa_signature;
    use openzeppelin_account::interface::{ISRC6, ISRC6_ID};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet_stealth_addresses::interfaces::i_stealth_account::IStealthAccount;
    use starknet_stealth_addresses::errors::Errors;
    use starknet_stealth_addresses::crypto::constants::is_valid_public_key;

    // ========================================================================
    // COMPONENTS
    // ========================================================================

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    // ========================================================================
    // STORAGE
    // ========================================================================

    #[storage]
    struct Storage {
        /// X coordinate of the stealth public key
        stealth_pubkey_x: felt252,
        
        /// Y coordinate of the stealth public key  
        stealth_pubkey_y: felt252,
        
        /// Whether the account has been initialized
        initialized: bool,
        
        /// SRC5 component storage
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccountInitialized: AccountInitialized,
        TransactionExecuted: TransactionExecuted,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct AccountInitialized {
        #[key]
        account: ContractAddress,
        pubkey_x: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct TransactionExecuted {
        #[key]
        account: ContractAddress,
        tx_hash: felt252,
        num_calls: u32,
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    #[constructor]
    fn constructor(
        ref self: ContractState,
        pubkey_x: felt252,
        pubkey_y: felt252
    ) {
        // Validate public key (non-zero; optional strict curve check)
        assert(is_valid_public_key(pubkey_x, pubkey_y), Errors::INVALID_PUBLIC_KEY);
        
        // Store public key
        self.stealth_pubkey_x.write(pubkey_x);
        self.stealth_pubkey_y.write(pubkey_y);
        self.initialized.write(true);
        
        // Register supported interfaces
        self.src5.register_interface(ISRC6_ID);
        
        // Emit initialization event
        self.emit(AccountInitialized {
            account: get_contract_address(),
            pubkey_x,
        });
    }

    // ========================================================================
    // SRC-6 ACCOUNT INTERFACE
    // ========================================================================

    #[abi(embed_v0)]
    impl SRC6Impl of ISRC6<ContractState> {
        /// Execute a batch of calls
        /// 
        /// Only callable by the Starknet protocol (caller is zero address).
        /// Signature must have been validated by __validate__ first.
        fn __execute__(self: @ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            // Security: Only protocol can call execute
            assert(get_caller_address().is_zero(), Errors::INVALID_CALLER);
            
            let mut results: Array<Span<felt252>> = array![];
            
            // Execute each call
            for call in calls {
                let Call { to, selector, calldata } = call;
                let result = call_contract_syscall(to, selector, calldata)
                    .expect(Errors::CALL_FAILED);
                results.append(result);
            };
            
            results
        }

        /// Validate transaction signature
        ///
        /// Called by the protocol before __execute__ to verify
        /// the transaction was signed by the account owner.
        fn __validate__(self: @ContractState, calls: Array<Call>) -> felt252 {
            // Security: Only protocol can call validate
            assert(get_caller_address().is_zero(), Errors::INVALID_CALLER);
            
            // Validate signature
            self._validate_transaction_signature()
        }

        /// Check if a signature is valid for this account
        ///
        /// Used for off-chain signature verification (EIP-1271 style).
        fn is_valid_signature(
            self: @ContractState,
            hash: felt252,
            signature: Array<felt252>
        ) -> felt252 {
            if self._is_valid_signature(hash, signature.span()) {
                starknet::VALIDATED
            } else {
                0
            }
        }
    }

    // ========================================================================
    // STEALTH ACCOUNT INTERFACE
    // ========================================================================

    #[abi(embed_v0)]
    impl StealthAccountImpl of IStealthAccount<ContractState> {
        /// Get the full stealth public key
        fn get_stealth_public_key(self: @ContractState) -> (felt252, felt252) {
            (self.stealth_pubkey_x.read(), self.stealth_pubkey_y.read())
        }
        
        /// Get just X coordinate (compatibility)
        fn get_public_key(self: @ContractState) -> felt252 {
            self.stealth_pubkey_x.read()
        }
    }

    // ========================================================================
    // INTERNAL FUNCTIONS
    // ========================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Validate the transaction signature
        fn _validate_transaction_signature(self: @ContractState) -> felt252 {
            let tx_info = get_tx_info().unbox();
            
            if self._is_valid_signature(tx_info.transaction_hash, tx_info.signature) {
                starknet::VALIDATED
            } else {
                0
            }
        }

        /// Check if a signature is valid
        fn _is_valid_signature(
            self: @ContractState,
            hash: felt252,
            signature: Span<felt252>
        ) -> bool {
            // Signature must be exactly 2 elements: (r, s)
            if signature.len() != 2 {
                return false;
            }
            
            let r = *signature.at(0);
            let s = *signature.at(1);
            let pubkey_x = self.stealth_pubkey_x.read();
            
            // Use native ECDSA verification
            check_ecdsa_signature(hash, pubkey_x, r, s)
        }
    }
}
