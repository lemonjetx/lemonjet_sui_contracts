module lemonjet::vault {

use sui::balance::{ Self, Balance };
use sui::coin::{Self,Coin, TreasuryCap};
use sui::sui::SUI as CoinType;
use sui::event;
use sui::pay;

const BASIS_POINT_SCALE: u128 = 10000;
const EXIT_FEE_BP: u128 = 60;
const GOLDEN_RATIO_PERCENTAGE: u128 = 1618;

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
    shares_treasury: TreasuryCap<VAULT>,
    fee_pool: Balance<T>,
}


public struct AdminCap has key {
    id: UID,
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


    let vault = Vault<CoinType> {
        id: object::new(ctx),
        asset_pool: balance::zero(),
        shares_treasury: treasury,
        fee_pool: balance::zero(),
    };

    transfer::share_object(vault);
    transfer::transfer(admin_cap, ctx.sender());
}


fun total_assets<T>(self: &Vault<T>): u64 {
    self.asset_pool.value()
}

fun total_shares<T>(self: &Vault<T>): u64 {
    self.shares_treasury.total_supply() 
}

public(package) fun max_payout<T>(self: &Vault<T>): u64 {
    ((self.asset_pool.value() as u128) * GOLDEN_RATIO_PERCENTAGE / 100000) as u64
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

public(package) fun payout<T>(self: &mut Vault<T>, value: u64, ctx: &mut TxContext) {
    pay::keep(self.asset_pool.split(value).into_coin(ctx), ctx)
}

public(package) fun top_up<T>(self: &mut Vault<T>, coin: Coin<T>) {
    let mut balance = coin.into_balance();
    let value = balance.value() as u128;
    self.fee_pool.join(balance.split((value * 20 / BASIS_POINT_SCALE) as u64));
    self.asset_pool.join(balance);
}

public fun deposit<T>(vault: &mut Vault<T>, assets: Coin<T>, ctx: &mut TxContext) {
    let deposit_value = assets.value();
    let shares_value = vault.assets_to_shares(deposit_value);
    vault.asset_pool.join(assets.into_balance());
    vault.shares_treasury.mint_and_transfer(shares_value, ctx.sender(), ctx);
    event::emit(DepositEvent { asset_amount_in: deposit_value, shares_amount_out: shares_value });
}

public fun redeem<T>(vault: &mut Vault<T>, shares: Coin<VAULT>, ctx: &mut TxContext) {
    let shares_value = shares.value();
    let assets_value = vault.shares_to_assets(shares_value);
    let (in_fee_pool, remains_in_asset_pool) = calc_exit_fee(assets_value);
    let mut assets = vault.asset_pool.split(assets_value - remains_in_asset_pool);
    vault.fee_pool.join(assets.split(in_fee_pool));
    vault.shares_treasury.burn(shares);
    event::emit(RedeemEvent {
        shares_amount_in: shares_value,
        asset_amount_out: assets.value(),
    });
    pay::keep(  assets.into_coin(ctx), ctx);
}

public fun withdraw_fee<T>(_: &AdminCap, vault: &mut Vault<T>, ctx: &mut TxContext) {
    pay::keep(vault.fee_pool.withdraw_all().into_coin(ctx), ctx)
}

fun calc_exit_fee(assets: u64): (u64, u64) {
    let total_fee = ((assets as u128) * EXIT_FEE_BP  / BASIS_POINT_SCALE);
    let in_fee_pool = (total_fee / 6);
    let remains_in_asset_pool = total_fee - in_fee_pool;
    (in_fee_pool as u64, remains_in_asset_pool as u64)
}
}