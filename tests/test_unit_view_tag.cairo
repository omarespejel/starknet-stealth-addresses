/// Unit Tests for View Tag Computation

use starknet_stealth_addresses::crypto::view_tag::{
    compute_view_tag, compute_view_tag_simple, view_tag_matches
};

#[test]
fn test_unit_view_tag_in_range() {
    let tag = compute_view_tag(12345, 67890);
    assert(tag <= 255, 'View tag must be <= 255');
}

#[test]
fn test_unit_view_tag_deterministic() {
    let tag1 = compute_view_tag(12345, 67890);
    let tag2 = compute_view_tag(12345, 67890);
    assert(tag1 == tag2, 'Tag should be deterministic');
}

#[test]
fn test_unit_view_tag_simple_deterministic() {
    let tag1 = compute_view_tag_simple(12345);
    let tag2 = compute_view_tag_simple(12345);
    assert(tag1 == tag2, 'Simple tag deterministic');
}

#[test]
fn test_unit_view_tag_matches_true() {
    assert(view_tag_matches(42, 42), 'Same tags should match');
}

#[test]
fn test_unit_view_tag_matches_false() {
    assert(!view_tag_matches(42, 43), 'Different tags should not match');
}

#[test]
fn test_unit_view_tag_zero() {
    let tag = compute_view_tag(0, 0);
    assert(tag <= 255, 'Zero input should produce valid');
}

#[test]
fn test_unit_view_tag_large_inputs() {
    // Large but valid felt252 values (< 2^251)
    let large_x: felt252 = 0x7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    let large_y: felt252 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;
    
    let tag = compute_view_tag(large_x, large_y);
    assert(tag <= 255, 'Large input should be valid');
}
