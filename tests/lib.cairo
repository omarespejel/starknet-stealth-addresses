/// Stealth Address Protocol Test Suite (87 tests)
///
/// Test organization:
/// - test_unit_*       : Fast, isolated unit tests (22)
/// - test_security_*   : Security-focused tests (21)
/// - test_integration_*: Cross-component tests (5)
/// - test_e2e_*        : End-to-end workflow tests (3)
/// - test_fuzz         : Fuzz tests with random inputs (11)
/// - test_gas_*        : Gas benchmarks (8)
/// - test_stress_*     : High-load scenarios (8)
///
/// Run specific categories:
/// ```
/// snforge test --filter "unit_"        # Unit tests
/// snforge test --filter "security_"    # Security tests
/// snforge test --filter "fuzz_"        # Fuzz tests
/// snforge test --filter "stress_"      # Stress tests
/// snforge test --filter "gas_"         # Gas benchmarks
/// ```

mod test_unit_registry;
mod test_unit_account;
mod test_unit_factory;
mod test_unit_view_tag;

mod test_security_registry;
mod test_security_account;
mod test_security_factory;

mod test_integration_stealth_flow;

mod test_e2e_stealth_payment;

mod test_fuzz;
mod test_gas_benchmarks;
mod test_stress;

// Test fixtures and helpers
mod fixtures;
