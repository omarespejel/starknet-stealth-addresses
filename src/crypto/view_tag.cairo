use core::poseidon::poseidon_hash_span;

/// View Tag Computation Module
///
/// View tags provide efficient filtering during announcement scanning.
/// Instead of performing expensive ECDH for every announcement,
/// recipients can quickly filter by comparing 8-bit view tags.
///
/// ## Efficiency Analysis
/// - Full ECDH: ~1ms per operation
/// - View tag comparison: ~1μs per operation
/// - False positive rate: 1/256
/// 
/// For 10,000 announcements:
/// - Without view tags: 10,000 × 1ms = 10 seconds
/// - With view tags: 10,000 × 1μs + 39 × 1ms = 49ms (200x faster)

/// Compute an 8-bit view tag from shared secret coordinates
///
/// # Arguments
/// * `shared_secret_x` - X coordinate of ECDH shared secret
/// * `shared_secret_y` - Y coordinate of ECDH shared secret
///
/// # Returns
/// 8-bit view tag (0-255)
///
/// # Algorithm
/// view_tag = truncate(poseidon_hash(x, y), 8 bits)
pub fn compute_view_tag(shared_secret_x: felt252, shared_secret_y: felt252) -> u8 {
    let hash = poseidon_hash_span(array![shared_secret_x, shared_secret_y].span());
    
    // Extract lowest 8 bits
    // Safe because we're taking modulo 256
    let hash_u256: u256 = hash.into();
    let view_tag: u8 = (hash_u256 & 0xFF).try_into().unwrap();
    
    view_tag
}

/// Compute view tag from a single felt (for simpler cases)
///
/// # Arguments
/// * `shared_secret` - Single felt252 shared secret value
///
/// # Returns
/// 8-bit view tag (0-255)
pub fn compute_view_tag_simple(shared_secret: felt252) -> u8 {
    let hash = poseidon_hash_span(array![shared_secret].span());
    let hash_u256: u256 = hash.into();
    (hash_u256 & 0xFF).try_into().unwrap()
}

/// Check if a view tag matches (for scanning)
///
/// # Arguments
/// * `expected` - The view tag from the announcement
/// * `computed` - The view tag computed from shared secret
///
/// # Returns
/// true if tags match, false otherwise
pub fn view_tag_matches(expected: u8, computed: u8) -> bool {
    expected == computed
}

// Note: Tests for this module are in tests/test_unit_view_tag.cairo
// to use snforge_std assertions
