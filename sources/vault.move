module lemonjet::vault;

use std::option::{Self, Option};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use sui::pay;
use sui::sui::SUI as CoinType;
use sui::table::{Self, Table};

const BASIS_POINT_SCALE: u128 = 10000;
const EXIT_FEE_BP: u128 = 50;
const ADMIN_SHARES_DIVIDENDS_BP: u128 = 10;
const GOLDEN_RATIO_PERCENTAGE: u128 = 1618;
const ADMIN_KEY: address = @0x0;

public struct VAULT has drop {}

public struct Vault<phantom T> has key, store {
    id: UID,
    assets_pool: Balance<T>,
    player_reward_shares: Table<address, Balance<VAULT>>,
    shares_treasury: TreasuryCap<VAULT>,
}

public struct AdminCap has key {
    id: UID,
}

public struct DepositEvent has copy, drop {
    assets_amount_in: u64,
    shares_amount_out: u64,
}

public struct RedeemEvent has copy, drop {
    shares_value_in: u64,
    asset_value_out: u64,
}

fun init(otw: VAULT, ctx: &mut TxContext) {
    // package::claim_and_keep(otw, ctx);
    let (treasury, metadata) = coin::create_currency(
        otw,
        9,
        b"SHARE_COIN",
        b"",
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    let mut player_reward_shares = table::new<address, Balance<VAULT>>(ctx);
    player_reward_shares.add(ADMIN_KEY, balance::zero());

    let vault = Vault<CoinType> {
        id: object::new(ctx),
        assets_pool: balance::zero(),
        player_reward_shares,
        shares_treasury: treasury,
    };

    transfer::share_object(vault);
    transfer::transfer(admin_cap, ctx.sender());
}

public fun deposit<T>(vault: &mut Vault<T>, assets: Coin<T>, ctx: &mut TxContext): Coin<VAULT> {
    let assets_amount_in = assets.value();
    let shares_amount_out = vault.assets_to_shares(assets_amount_in);
    vault.assets_pool.join(assets.into_balance());
    event::emit(DepositEvent { assets_amount_in, shares_amount_out });
    vault.shares_treasury.mint(shares_amount_out, ctx)
}

public fun redeem<T>(vault: &mut Vault<T>, mut shares: Coin<VAULT>, ctx: &mut TxContext): Coin<T> {
    let shares_value_in = shares.value();
    vault
        .player_reward_shares[ADMIN_KEY]
        .join(shares.balance_mut().split(calc_admin_shares_dividends(shares_value_in)));

    let assets_value = vault.shares_to_assets(shares.value());
    let mut assets = vault.assets_pool.split(assets_value - calc_exit_fee(assets_value));
    vault.shares_treasury.burn(shares);
    event::emit(RedeemEvent {
        shares_value_in,
        asset_value_out: assets.value(),
    });

    assets.into_coin(ctx)
}

public fun claim_shares<T>(vault: &mut Vault<T>, value: u64, ctx: &mut TxContext): Coin<VAULT> {
    vault.claim_shares_balance(ctx.sender(), option::some(value)).into_coin(ctx)
}

public fun claim_all_shares<T>(vault: &mut Vault<T>, ctx: &mut TxContext): Coin<VAULT> {
    vault.claim_shares_balance(ctx.sender(), option::none()).into_coin(ctx)
}

fun total_assets<T>(self: &Vault<T>): u64 {
    self.assets_pool.value()
}

fun total_shares<T>(self: &Vault<T>): u64 {
    self.shares_treasury.total_supply()
}

public fun admin_claim_shares<T>(
    _: &AdminCap,
    vault: &mut Vault<T>,
    value: u64,
    ctx: &mut TxContext,
): Coin<VAULT> {
    vault.claim_shares_balance(ADMIN_KEY, option::some(value)).into_coin(ctx)
}

public fun admin_claim_all_shares<T>(
    _: &AdminCap,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): Coin<VAULT> {
    vault.claim_shares_balance(ADMIN_KEY, option::none()).into_coin(ctx)
}

public(package) fun max_payout<T>(self: &Vault<T>): u64 {
    ((self.assets_pool.value() as u128) * GOLDEN_RATIO_PERCENTAGE / 100000) as u64
}

public(package) fun mint_reward_shares_and_deposit<T>(
    self: &mut Vault<T>,
    value: u64,
    recipient: address,
) {
    (&mut self.player_reward_shares[recipient]).join(self.shares_treasury.mint_balance(value));
}

public(package) fun payout<T>(self: &mut Vault<T>, value: u64, ctx: &mut TxContext) {
    pay::keep(self.assets_pool.split(value).into_coin(ctx), ctx)
}

public(package) fun add<T>(self: &mut Vault<T>, coin: Coin<T>) {
    self.assets_pool.join(coin.into_balance());
}

public(package) fun exists_reward_shares_balance<T>(self: &Vault<T>, key: address): bool {
    self.player_reward_shares.contains(key)
}

public(package) fun init_reward_shares_balance<T>(self: &mut Vault<T>, key: address) {
    self.player_reward_shares.add(key, balance::zero())
}

fun claim_shares_balance<T>(
    self: &mut Vault<T>,
    owner: address,
    value: Option<u64>,
): Balance<VAULT> {
    let balance = &mut self.player_reward_shares[owner];

    (if (value.is_some()) {
            balance.split(value.extract())
        } else {
            balance.withdraw_all()
        })
}

fun assets_to_shares<T>(self: &Vault<T>, assets: u64): u64 {
    let total_assets = self.total_assets() + 1;
    let total_shares = self.total_shares() + 1;

    let shares = (assets as u128) * (total_shares as u128)
            / (total_assets as u128);

    shares as u64
}

fun shares_to_assets<T>(self: &Vault<T>, shares: u64): u64 {
    let total_assets = self.total_assets() + 1;
    let total_shares = self.total_shares() + 1;

    let assets = (shares as u128) * (total_assets as u128)
            / (total_shares as u128);

    assets as u64
}

fun calc_exit_fee(assets: u64): u64 {
    ((assets as u128) * EXIT_FEE_BP / BASIS_POINT_SCALE) as u64
}

fun calc_admin_shares_dividends(shares: u64): u64 {
    ((shares as u128) * ADMIN_SHARES_DIVIDENDS_BP / BASIS_POINT_SCALE) as u64
}
