module lemonjet::vault {

use sui::balance::{ Self, Balance, Supply };
use sui::coin::{ Coin };
use sui::event;
use sui::package;
use sui::pay;

const BASIS_POINT_SCALE: u128 = 10000;
const EXIT_FEE_BP: u128 = 60;

public struct VAULT has drop {}

public struct SharesType<phantom T> has drop {}

public struct Shares<phantom T> has key {
id: UID,
balance: Balance<SharesType<T>>
}

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
    shares_supply: Supply<SharesType<T>>,
    fee_pool: Balance<T>,
}


public struct AdminCap has key {
    id: UID,
}


fun mint<T>(self: &mut Vault<T>, value: u64, ctx: &mut TxContext ): Shares<T> {
    Shares { id: object::new(ctx), balance:self.shares_supply.increase_supply(value)}
}

fun burn<T>(self: &mut Vault<T>, shares: Shares<T>) {
    let Shares {id, balance} = shares;
    id.delete();
    self.shares_supply.decrease_supply(balance);
}


fun init(otw: VAULT, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx);

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::transfer(admin_cap, ctx.sender());
}

public fun initialize_vault<T>(
    ctx: &mut TxContext,
) {

    let vault = Vault<T> {
        id: object::new(ctx),
        asset_pool: balance::zero<T>(),
        shares_supply: balance::create_supply(SharesType<T> {}),
        fee_pool: balance::zero<T>(),
    };

    transfer::share_object(vault);
}

fun total_assets<T>(self: &Vault<T>): u64 {
    self.asset_pool.value()
}

fun total_shares<T>(self: &Vault<T>): u64 {
    self.shares_supply.supply_value()
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

public fun deposit<T>(vault: &mut Vault<T>, assets: Coin<T>, ctx: &mut TxContext): Shares<T> {
    let deposit_value = assets.value();
    let shares_value = vault.assets_to_shares(deposit_value);
    vault.asset_pool.join(assets.into_balance());
    let shares = vault.mint(shares_value, ctx);
    event::emit(DepositEvent { asset_amount_in: deposit_value, shares_amount_out: shares_value });
    shares
}

public fun redeem<T>(vault: &mut Vault<T>, shares: Shares<T>, ctx: &mut TxContext): Coin<T> {
    let shares_value = shares.balance.value();
    let assets_value = vault.shares_to_assets(shares_value);
    let (in_fee_pool, remains_in_asset_pool) = calc_exit_fee(assets_value);
    let mut assets = vault.asset_pool.split(assets_value - remains_in_asset_pool);
    vault.fee_pool.join(assets.split(in_fee_pool));
    vault.burn(shares);
    event::emit(RedeemEvent {
        shares_amount_in: shares_value,
        asset_amount_out: assets.value(),
    });
    assets.into_coin(ctx)
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