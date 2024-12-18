#[test_only]
module lemonjet_sui::lemonjet_sui_tests {
use lemonjet_sui::game;
use lemonjet_sui::house_data;
   use sui::balance::Balance;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use sui::random::Random;


const ENotImplemented: u64 = 0;

#[test]
fun test_lemonjet_play() {
    let mut ctx = tx_context::dummy();
}

#[test, expected_failure(abort_code = ::lemonjet_sui::lemonjet_sui_tests::ENotImplemented)]
fun test_lemonjet_sui_fail() {
    abort ENotImplemented
}
}