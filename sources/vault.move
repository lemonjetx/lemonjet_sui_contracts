module lemonjet::vault;

use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::event;
use sui::pay;
use sui::table::{Self, Table};

const BASIS_POINT_SCALE: u128 = 10000;
const EXIT_FEE_BP: u128 = 50;
const ADMIN_DIVIDENDS_BP: u128 = 10;
const GOLDEN_RATIO_PERCENTAGE: u128 = 1618;

public struct VaultShare<phantom T> has drop {}

public struct Vault<phantom T> has key, store {
    id: UID,
    liquidity: Balance<T>,
    rewards: Table<address, Balance<VaultShare<T>>>,
    shares_supply: Supply<VaultShare<T>>,
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

fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::transfer(admin_cap, ctx.sender());
}

public fun deposit<T>(
    vault: &mut Vault<T>,
    assets: Coin<T>,
    ctx: &mut TxContext,
): Coin<VaultShare<T>> {
    let assets_amount_in = assets.value();
    let shares_amount_out = vault.assets_to_shares(assets_amount_in);
    vault.liquidity.join(assets.into_balance());
    event::emit(DepositEvent { assets_amount_in, shares_amount_out });
    coin::from_balance(vault.shares_supply.increase_supply(shares_amount_out), ctx)
}

public fun redeem<T>(
    vault: &mut Vault<T>,
    mut shares: Coin<VaultShare<T>>,
    ctx: &mut TxContext,
): Coin<T> {
    let shares_value_in = shares.value();
    vault.rewards[@0x0].join(shares.balance_mut().split(calc_admin_dividends(shares_value_in)));

    let assets_value = vault.shares_to_assets(shares.value());
    let assets = vault.liquidity.split(assets_value - calc_exit_fee(assets_value));
    vault.shares_supply.decrease_supply(shares.into_balance());
    event::emit(RedeemEvent {
        shares_value_in,
        asset_value_out: assets.value(),
    });

    assets.into_coin(ctx)
}

public fun claim<T>(vault: &mut Vault<T>, value: u64, ctx: &mut TxContext): Coin<VaultShare<T>> {
    vault.claim_balance(ctx.sender(), option::some(value)).into_coin(ctx)
}

public fun claim_all<T>(vault: &mut Vault<T>, ctx: &mut TxContext): Coin<VaultShare<T>> {
    vault.claim_balance(ctx.sender(), option::none()).into_coin(ctx)
}

fun total_assets<T>(self: &Vault<T>): u64 {
    self.liquidity.value()
}

fun total_shares<T>(self: &Vault<T>): u64 {
    self.shares_supply.supply_value()
}

public fun create<T>(_: &AdminCap, ctx: &mut TxContext) {
    let mut rewards = table::new<address, Balance<VaultShare<T>>>(ctx);
    rewards.add(@0x0, balance::zero());

    transfer::share_object(Vault {
        id: object::new(ctx),
        liquidity: balance::zero(),
        rewards: rewards,
        shares_supply: balance::create_supply(VaultShare {}),
    });
}

public fun admin_claim<T>(
    _: &AdminCap,
    vault: &mut Vault<T>,
    value: u64,
    ctx: &mut TxContext,
): Coin<VaultShare<T>> {
    vault.claim_balance(@0x0, option::some(value)).into_coin(ctx)
}

public fun admin_claim_all<T>(
    _: &AdminCap,
    vault: &mut Vault<T>,
    ctx: &mut TxContext,
): Coin<VaultShare<T>> {
    vault.claim_balance(@0x0, option::none()).into_coin(ctx)
}

public(package) fun max_payout<T>(self: &Vault<T>): u64 {
    ((self.liquidity.value() as u128) * GOLDEN_RATIO_PERCENTAGE / 100000) as u64
}

public(package) fun mint_and_deposit<T>(self: &mut Vault<T>, value: u64, recipient: address) {
    if (!self.has_reward(recipient)) {
        self.init_reward(recipient);
    };
    (&mut self.rewards[recipient]).join(self.shares_supply.increase_supply(value));
}

public(package) fun payout<T>(self: &mut Vault<T>, value: u64, ctx: &mut TxContext) {
    pay::keep(self.liquidity.split(value).into_coin(ctx), ctx)
}

public(package) fun add<T>(self: &mut Vault<T>, coin: Coin<T>) {
    self.liquidity.join(coin.into_balance());
}

public(package) fun has_reward<T>(self: &Vault<T>, key: address): bool {
    self.rewards.contains(key)
}

public(package) fun init_reward<T>(self: &mut Vault<T>, key: address) {
    self.rewards.add(key, balance::zero())
}

fun claim_balance<T>(
    self: &mut Vault<T>,
    owner: address,
    mut value: Option<u64>,
): Balance<VaultShare<T>> {
    let balance = &mut self.rewards[owner];

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

fun calc_admin_dividends(shares: u64): u64 {
    ((shares as u128) * ADMIN_DIVIDENDS_BP / BASIS_POINT_SCALE) as u64
}
