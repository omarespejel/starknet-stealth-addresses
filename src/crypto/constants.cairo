/// Cryptographic Constants for the Stealth Address Protocol
///
/// These constants define the STARK curve parameters used for
/// stealth address cryptography.

/// STARK Curve Parameters
/// The STARK curve is defined by: y² = x³ + α·x + β (mod p)
/// Note: The prime p itself cannot be represented as felt252 (it defines the field)
pub mod StarkCurve {
    /// Curve coefficient α = 1
    pub const ALPHA: felt252 = 1;
    
    /// Curve coefficient β
    pub const BETA: felt252 = 0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89;
    
    /// Generator point X coordinate
    pub const GEN_X: felt252 = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
    
    /// Generator point Y coordinate  
    pub const GEN_Y: felt252 = 0x5668060aa49730b7be4801df46ec62de53ecd11abe43a32873000c36e8dc1f;
    
    /// Curve order (number of points) - this fits in felt252
    pub const ORDER: felt252 = 0x800000000000010ffffffffffffffffb781126dcae7b2321e66a241adc64d2f;

    /// Half of the field prime (p - 1) / 2 for canonical Y enforcement
    /// p = 2^251 + 17 * 2^192 + 1
    pub const FIELD_HALF: u256 = 0x400000000000008800000000000000000000000000000000000000000000000;
}

/// On-curve validation toggle
///
/// When set to true, `is_valid_public_key` performs a full curve check
/// (y^2 == x^3 + alpha*x + beta). This adds gas cost to registry/factory
/// calls. Default is true for production safety.
pub const STRICT_CURVE_CHECK: bool = true;

/// Validates a public key point
/// 
/// ## Security Model
/// 
/// This function performs **canonical** validation (non-zero + canonical Y),
/// with an optional strict mode for full curve validation.
///
/// Full on-curve validation is recommended for production because:
/// 
/// 1. **Registry hygiene**: Rejects invalid points early and prevents pollution.
/// 2. **ECDH safety**: Off-chain ECDH assumes valid curve points.
/// 3. **Defense in depth**: Even though the ECDSA builtin validates at spend
///    time, early checks reduce DoS and operational risk.
/// 
/// ## What This Catches
/// 
/// - Zero coordinates (point at infinity)
/// - Obvious invalid inputs
/// 
/// ## What ECDSA Builtin Catches (at spend time)
/// 
/// - Points not on curve
/// - Invalid public key format
/// - Signature/key mismatch
/// 
/// # Arguments
/// * `x` - X coordinate
/// * `y` - Y coordinate
/// 
/// # Returns
/// true if valid, false otherwise
pub fn is_valid_public_key(x: felt252, y: felt252) -> bool {
    // Check non-zero (not point at infinity)
    if x == 0 || y == 0 {
        return false;
    }

    // Enforce canonical Y (unique point representation)
    let y_u256: u256 = y.into();
    if y_u256 > StarkCurve::FIELD_HALF {
        return false;
    }

    if STRICT_CURVE_CHECK {
        is_on_curve(x, y)
    } else {
        true
    }
}

/// Full on-curve validation (y^2 == x^3 + alpha*x + beta)
pub fn is_on_curve(x: felt252, y: felt252) -> bool {
    let y2 = y * y;
    let x2 = x * x;
    let x3 = x2 * x;
    let rhs = x3 + StarkCurve::ALPHA * x + StarkCurve::BETA;
    y2 == rhs
}

/// View Tag Configuration
pub mod ViewTag {
    /// Number of bits for view tag (8 bits = 1 byte)
    pub const BITS: u8 = 8;
    
    /// Mask for extracting view tag from hash
    pub const MASK: u256 = 0xFF;
    
    /// Expected false positive rate: 1/256 ≈ 0.39%
    pub const FALSE_POSITIVE_RATE_INVERSE: u32 = 256;
}

/// Contract Address Computation Constants
pub mod AddressComputation {
    /// Prefix for contract address calculation
    /// ASCII: "STARKNET_CONTRACT_ADDRESS"
    pub const CONTRACT_ADDRESS_PREFIX: felt252 = 'STARKNET_CONTRACT_ADDRESS';
}
