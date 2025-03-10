module lemonjet::lemonjet;

use lemonjet::player::Player;
use lemonjet::points::{Self, Volume, TotalVolume};
use lemonjet::vault::Vault;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event::emit;
use sui::random::{new_generator, generate_u64_in_range, Random};

const HOUSE_EDGE: u64 = 1;
const THRESHOLD: u64 = 10_000_000 * (100 - HOUSE_EDGE) / 100;

const EInvalidAmount: u64 = 1;
const EInvalidCoef: u64 = 2;
const EPotentialWinExceeded: u64 = 3;
const ETotalVolumeMustNotBeCompleted: u64 = 2;

public struct Outcome has copy, drop {
    address: address,
    payout: u64,
    random_number: u64,
    x: u64,
}

entry fun play<T>(
    random: &Random,
    player: &Player,
    stake: Coin<T>,
    coef: u64,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): Outcome {
    let stake_value = stake.value();
    assert!(stake_value >= 1000, EInvalidAmount);
    assert!(coef >= 1_01 && coef <= 5000_00, EInvalidCoef);

    let potential_payout = calc_winner_payout(stake_value, coef);
    assert!(potential_payout <= vault.max_payout(), EPotentialWinExceeded);

    let fee = stake.value() / 100;
    vault.mint_and_deposit(fee * 20 / 100, @0x0); // admin shares

    player.referrer().do_ref!(|addr| vault.mint_and_deposit(fee * 30 / 100, *addr));

    vault.add(stake);

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

entry fun play_and_earn_points<T>(
    random: &Random,
    clock: &Clock,
    player: &Player,
    stake: Coin<T>,
    coef: u64,
    player_volume: &mut Volume<T>,
    total_volume: &mut TotalVolume<T>,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): Outcome {
    assert!(!points::is_completed(total_volume, clock), ETotalVolumeMustNotBeCompleted);
    points::add(&stake, total_volume, player_volume);
    play(random, player, stake, coef, vault, ctx)
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
