/// Stealth Account Factory Contract
///
/// Deploys stealth accounts with deterministic addresses, enabling:
/// 1. Senders to compute recipient address before deployment
/// 2. Recipients to deploy only when ready to spend
/// 3. Consistent account implementation across all stealth addresses
///
/// ## Address Determinism
/// The factory uses CREATE2-style address computation:
/// - Same (pubkey, salt) always produces same address
/// - Senders can pre-compute address without on-chain interaction
/// - Recipients can verify address matches before accepting funds

#[starknet::contract]
pub mod StealthAccountFactory {
    use starknet::{
        ContractAddress, ClassHash, get_contract_address,
        syscalls::deploy_syscall,
        storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map}
    };
    use core::pedersen::pedersen;
    use starknet_stealth_addresses::interfaces::i_stealth_account_factory::IStealthAccountFactory;
    use starknet_stealth_addresses::errors::Errors;
    use starknet_stealth_addresses::crypto::constants::{AddressComputation, is_valid_public_key};

    // ========================================================================
    // STORAGE
    // ========================================================================

    #[storage]
    struct Storage {
        /// Class hash of the StealthAccount contract
        stealth_account_class_hash: ClassHash,
        
        /// Number of accounts deployed through this factory
        deployment_count: u64,
        
        /// Mapping of deployed addresses (for verification)
        deployed_accounts: Map<ContractAddress, bool>,
    }

    // ========================================================================
    // EVENTS
    // ========================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StealthAccountDeployed: StealthAccountDeployed,
        ClassHashUpdated: ClassHashUpdated,
    }

    /// Emitted when a new stealth account is deployed
    #[derive(Drop, starknet::Event)]
    struct StealthAccountDeployed {
        #[key]
        stealth_address: ContractAddress,
        pubkey_x: felt252,
        salt: felt252,
        deployer: ContractAddress,
    }

    /// Emitted when the account class hash is updated
    #[derive(Drop, starknet::Event)]
    struct ClassHashUpdated {
        old_class_hash: ClassHash,
        new_class_hash: ClassHash,
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================

    #[constructor]
    fn constructor(ref self: ContractState, account_class_hash: ClassHash) {
        // Validate class hash
        assert(account_class_hash.into() != 0, Errors::INVALID_CLASS_HASH);
        
        self.stealth_account_class_hash.write(account_class_hash);
        self.deployment_count.write(0);
    }

    // ========================================================================
    // EXTERNAL FUNCTIONS
    // ========================================================================

    #[abi(embed_v0)]
    impl StealthAccountFactoryImpl of IStealthAccountFactory<ContractState> {
        /// Deploy a new stealth account
        fn deploy_stealth_account(
            ref self: ContractState,
            stealth_pubkey_x: felt252,
            stealth_pubkey_y: felt252,
            salt: felt252
        ) -> ContractAddress {
            // Validate public key (non-zero; optional strict curve check)
            assert(
                is_valid_public_key(stealth_pubkey_x, stealth_pubkey_y), 
                Errors::INVALID_PUBLIC_KEY
            );
            
            let class_hash = self.stealth_account_class_hash.read();
            
            // Prepare constructor calldata
            let constructor_calldata = array![stealth_pubkey_x, stealth_pubkey_y];
            
            // Deploy the account
            let (deployed_address, _) = deploy_syscall(
                class_hash,
                salt,
                constructor_calldata.span(),
                false // deploy_from_zero
            ).expect(Errors::DEPLOYMENT_FAILED);
            
            // Update state
            let count = self.deployment_count.read();
            self.deployment_count.write(count + 1);
            self.deployed_accounts.entry(deployed_address).write(true);
            
            // Emit event
            self.emit(StealthAccountDeployed {
                stealth_address: deployed_address,
                pubkey_x: stealth_pubkey_x,
                salt,
                deployer: starknet::get_caller_address(),
            });
            
            deployed_address
        }

        /// Compute stealth address without deploying
        /// 
        /// Uses Starknet's contract address formula with compute_hash_on_elements:
        /// calldata_hash = pedersen(pedersen(pedersen(0, x), y), len)  // len=2
        /// address_hash = pedersen(pedersen(...pedersen(0, PREFIX), deployer), ..., calldata_hash)
        /// address = pedersen(address_hash, 5)  // 5 elements
        fn compute_stealth_address(
            self: @ContractState,
            stealth_pubkey_x: felt252,
            stealth_pubkey_y: felt252,
            salt: felt252
        ) -> ContractAddress {
            let class_hash = self.stealth_account_class_hash.read();
            let deployer = get_contract_address();
            
            // Compute constructor calldata hash using compute_hash_on_elements formula:
            // h = pedersen(pedersen(pedersen(0, x), y), len)
            // For array [x, y], len = 2
            let h0 = pedersen(0, stealth_pubkey_x);
            let h1 = pedersen(h0, stealth_pubkey_y);
            let constructor_calldata_hash = pedersen(h1, 2);  // 2 = array length
            
            // Compute contract address using compute_hash_on_elements on:
            // [PREFIX, deployer, salt, class_hash, calldata_hash]
            let a0 = pedersen(0, AddressComputation::CONTRACT_ADDRESS_PREFIX);
            let a1 = pedersen(a0, deployer.into());
            let a2 = pedersen(a1, salt);
            let a3 = pedersen(a2, class_hash.into());
            let a4 = pedersen(a3, constructor_calldata_hash);
            let final_hash = pedersen(a4, 5);  // 5 = number of elements
            
            // Convert to address
            final_hash.try_into().expect(Errors::ADDRESS_MISMATCH)
        }

        /// Get the account class hash
        fn get_account_class_hash(self: @ContractState) -> ClassHash {
            self.stealth_account_class_hash.read()
        }

        /// Get deployment count
        fn get_deployment_count(self: @ContractState) -> u64 {
            self.deployment_count.read()
        }
    }

    // ========================================================================
    // VIEW FUNCTIONS
    // ========================================================================

    #[generate_trait]
    pub impl FactoryViewImpl of FactoryViewTrait {
        /// Check if an address was deployed by this factory
        fn is_deployed_by_factory(self: @ContractState, address: ContractAddress) -> bool {
            self.deployed_accounts.entry(address).read()
        }
        
        /// Verify that a computed address matches expected
        fn verify_address(
            self: @ContractState,
            expected: ContractAddress,
            stealth_pubkey_x: felt252,
            stealth_pubkey_y: felt252,
            salt: felt252
        ) -> bool {
            let computed = self.compute_stealth_address(stealth_pubkey_x, stealth_pubkey_y, salt);
            computed == expected
        }
    }
}
