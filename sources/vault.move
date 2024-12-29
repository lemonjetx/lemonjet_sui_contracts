module lemonjet::vault {

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use sui::package;
use sui::pay;
use sui::url::Url;

const BASIS_POINT_SCALE: u128 = 10000;
const EXIT_FEE_BP: u128 = 50;

public struct VAULT has drop {}

public struct DepositEvent has copy, drop {
    asset_amount_in: u64,
    shares_amount_out: u64,
}

public struct RedeemEvent has copy, drop {
    shares_amount_in: u64,
    asset_amount_out: u64,
}

public struct Vault<phantom T> has key, store {
    id: UID,
    asset_pool: Balance<T>,
    shares_treasury_cap: TreasuryCap<VAULT>,
    fees: Balance<T>,
}

public struct AdminCap has key {
    id: UID,
}

fun init(otw: VAULT, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::transfer(admin_cap, ctx.sender());
}

public fun initialize_vault<T>(
    _: &AdminCap,
    otw: VAULT,
    initial_pool: Coin<T>,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    icon_url: Option<Url>,
    ctx: &mut TxContext,
) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        otw,
        decimals,
        symbol,
        name,
        description,
        icon_url,
        ctx,
    );

    let vault = Vault<T> {
        id: object::new(ctx),
        asset_pool: initial_pool.into_balance(),
        shares_treasury_cap: treasury_cap,
        fees: balance::zero<T>(),
    };

    transfer::share_object(vault);
    transfer::public_freeze_object(coin_metadata);
}

fun total_assets<T>(self: &Vault<T>): u64 {
    self.asset_pool.value()
}

fun total_shares<T>(self: &Vault<T>): u64 {
    self.shares_treasury_cap.total_supply()
}

fun assets_to_shares<T>(self: &Vault<T>, assets: u64): u64 {
    let total_assets = self.total_assets() + 1;
    let total_shares = self.total_shares() + 1;

    let shares = (assets as u128) * (total_shares as u128)
         / (total_assets  as u128);

    shares as u64
}

fun shares_to_assets<T>(self: &Vault<T>, shares: u64): u64 {
    let total_assets = self.total_assets() + 1;
    let total_shares = self.total_shares() + 1;

    let assets = (shares as u128) * (total_assets as u128)
         / (total_shares as u128);

    assets as u64
}

public(package) fun payout<T>(self: &mut Vault<T>, amount: u64, ctx: &mut TxContext) {
    pay::keep(self.asset_pool.split(amount).into_coin(ctx), ctx)
}

public(package) fun top_up<T>(self: &mut Vault<T>, coin: Coin<T>) {
    coin::put(&mut self.asset_pool, coin);
}

public fun deposit<T>(vault: &mut Vault<T>, assets: Coin<T>, ctx: &mut TxContext): Coin<VAULT> {
    let deposit_amount = assets.value();
    let shares_amount = vault.assets_to_shares(deposit_amount);
    vault.asset_pool.join(assets.into_balance());
    let shares = vault.shares_treasury_cap.mint(shares_amount, ctx);
    event::emit(DepositEvent { asset_amount_in: deposit_amount, shares_amount_out: shares_amount });
    shares
}

public fun redeem<T>(vault: &mut Vault<T>, shares: Coin<VAULT>, ctx: &mut TxContext): Coin<T> {
    let shares_amount = shares.value();
    let assets_amount = vault.shares_to_assets(shares_amount);
    let fee = calc_exit_fee(assets_amount);
    let mut assets = vault.asset_pool.split(assets_amount);
    vault.fees.join(assets.split(fee));
    vault.shares_treasury_cap.burn(shares);
    event::emit(RedeemEvent {
        shares_amount_in: shares_amount,
        asset_amount_out: assets.value(),
    });
    assets.into_coin(ctx)
}

public fun withdraw_fee<T>(_: &AdminCap, vault: &mut Vault<T>, ctx: &mut TxContext) {
    pay::keep(vault.fees.withdraw_all().into_coin(ctx), ctx)
}

fun calc_exit_fee(assets: u64): u64 {
    ((assets as u128) * EXIT_FEE_BP  / BASIS_POINT_SCALE) as u64
}
}