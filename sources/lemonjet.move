module lemonjet::lemonjet {

use lemonjet::vault::Vault;
use sui::coin::Coin;
use sui::event::emit;
use sui::random::{new_generator, generate_u64_in_range, Random};

const HOUSE_EDGE: u64 = 1;
const THRESHOLD: u64 = 10_000_000 * (100 - HOUSE_EDGE) / 100;

const EInvalidAmount: u64 = 1;
const EInvalidCoef: u64 = 2;
const EPotentialWinExceeded: u64 = 3;

public struct Outcome has copy, drop {
    address: address,
    payout: u64,
    random_number: u64,
    x: u64,
}

entry fun play<T>(
    random: &Random,
    stake: Coin<T>,
    coef: u64,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): Outcome {
    let stake_value = stake.value();
    assert!(stake_value >= 1000, EInvalidAmount);
    assert!(coef >= 101 && coef <= 500000, EInvalidCoef);
    let potential_payout = calc_winner_payout(stake_value, coef);
    assert!(potential_payout <= vault.max_payout(), EPotentialWinExceeded);
    vault.top_up(stake);
    let threshold = calc_threshold(coef);
    let random_number = generate_random_number(random, ctx);
    let payout = if (is_player_won(random_number, threshold)) {
        let value = calc_winner_payout(stake_value, coef);
        vault.payout(value, ctx);
       value 
    } else { 0 };

    let outcome = Outcome {
        address: ctx.sender(),
        payout,
        random_number,
        x: calc_x(random_number),
    };

    emit(outcome);
    outcome
}

fun calc_threshold(coef: u64): u64 {
    THRESHOLD / coef
}

fun generate_random_number(random: &Random, ctx: &mut TxContext): u64 {
    let mut generator = new_generator(random, ctx);
    generate_u64_in_range(&mut generator, 1, 100_000)
}

fun calc_winner_payout(stake: u64, coef: u64): u64 {
    ((stake as u128) * (coef as u128) / 100) as u64
}

fun is_player_won(random_number: u64, threshold: u64): bool {
    random_number <= threshold
}

fun calc_x(random_number: u64): u64 {
    THRESHOLD / random_number
}
}