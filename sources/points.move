module lemonjet::points;

use lemonjet::player::Player;
use sui::clock::Clock;
use sui::coin::{Self, TreasuryCap, Coin};
use sui::table::{Self, Table};

const EMismatchCycle: u64 = 1;
const ETotalVolumeMustBeCompleted: u64 = 2;

public struct POINTS has drop {}

public struct PointsData has key {
    id: UID,
    treasury: TreasuryCap<POINTS>,
}

public struct AdminCap has key {
    id: UID,
}

public struct Volume<phantom T> has key, store {
    id: UID,
    cycle: u64,
    value: u64,
}

public struct Config<phantom T> has key, store {
    id: UID,
    point_capacity: u64,
    interval_ms: u64,
}

public struct TotalVolume<phantom T> has key {
    id: UID,
    cycle: u64,
    value: u64,
    completion_time_ms: u64,
}

public struct RateRegistry<phantom T> has key {
    id: UID,
    // cycle -> rate
    value: Table<u64, Rate<T>>,
}

public struct VolumeRewardRegistry<phantom T> has key {
    id: UID,
    rewards: Table<address, Table<u64, u64>>,
}

public struct Rate<phantom T> has store {
    points: u64,
    volume: u64,
}

fun init(otw: POINTS, ctx: &mut TxContext) {
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        otw,
        9,
        b"POINT",
        b"LemonJet Point",
        b"LemonJet Point",
        option::none(),
        true,
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(deny_cap, ctx.sender());
    transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    transfer::share_object(PointsData {
        id: object::new(ctx),
        treasury: treasury_cap,
    });
}

public fun next_cycle<T>(
    clock: &Clock,
    config: &Config<T>,
    total_volume: &mut TotalVolume<T>,
    rate_registry: &mut RateRegistry<T>,
) {
    assert!(is_completed(total_volume, clock), ETotalVolumeMustBeCompleted);

    rate_registry
        .value
        .add(
            total_volume.cycle,
            Rate { points: config.point_capacity, volume: total_volume.value },
        );

    total_volume.cycle = total_volume.cycle + 1;
    total_volume.value = 0;
    total_volume.completion_time_ms = clock.timestamp_ms() + config.interval_ms;
}

public fun create_volume<T>(cycle: u64, ctx: &mut TxContext): Volume<T> {
    Volume<T> {
        id: object::new(ctx),
        cycle,
        value: 0,
    }
}

public fun new<T>(
    _: &AdminCap,
    clock: &Clock,
    point_capacity: u64,
    interval_ms: u64,
    ctx: &mut TxContext,
) {
    transfer::share_object(Config<T> {
        id: object::new(ctx),
        point_capacity,
        interval_ms,
    });

    transfer::share_object(TotalVolume<T> {
        id: object::new(ctx),
        cycle: 1,
        value: 0,
        completion_time_ms: clock.timestamp_ms() + interval_ms,
    });

    transfer::share_object(RateRegistry<T> {
        id: object::new(ctx),
        value: table::new(ctx),
    });

    transfer::share_object(VolumeRewardRegistry<T> {
        id: object::new(ctx),
        rewards: table::new(ctx),
    })
}

public fun is_completed<T>(total_volume: &TotalVolume<T>, clock: &Clock): bool {
    total_volume.completion_time_ms < clock.timestamp_ms()
}

public fun claim<T>(
    volumes: vector<Volume<T>>,
    rate_registry: &RateRegistry<T>,
    point_data: &mut PointsData,
    ctx: &mut TxContext,
): Coin<POINTS> {
    point_data.treasury.mint(volumes.fold!(0, |acc, Volume { id, cycle, value: player_volume }| {
            let rate = &rate_registry.value[cycle];
            let mint_value =
                ((player_volume as u128) * (rate.points as u128)  / ( rate.volume as u128)) as u64;

            object::delete(id);
            acc + mint_value
        }), ctx)
}

public fun claim_ref_volume<T>(
    cycles: vector<u64>,
    reward_registry: &mut VolumeRewardRegistry<T>,
    ctx: &mut TxContext,
): vector<Volume<T>> {
    let volume_table = &mut reward_registry.rewards[ctx.sender()];
    cycles.map!(|cycle| {
        let value = volume_table[cycle];
        volume_table.remove(cycle);
        Volume<T> {
            id: object::new(ctx),
            cycle,
            value,
        }
    })
}

public fun rewards<T>(self: &VolumeRewardRegistry<T>, owner: address): &Table<u64, u64> {
    &self.rewards[owner]
}

public fun mint(
    _: &AdminCap,
    point_data: &mut PointsData,
    value: u64,
    ctx: &mut TxContext,
): Coin<POINTS> {
    point_data.treasury.mint(value, ctx)
}

public(package) fun add<T>(
    stake: &Coin<T>,
    total_volume: &mut TotalVolume<T>,
    player_volume: &mut Volume<T>,
) {
    assert!(total_volume.cycle == player_volume.cycle, EMismatchCycle);
    total_volume.value = total_volume.value + stake.value();
    player_volume.value = player_volume.value + stake.value();
}

public(package) fun mint_and_deposit<T>(
    self: &mut VolumeRewardRegistry<T>,
    cycle: u64,
    value: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    if (!self.rewards.contains(recipient)) {
        let mut table = table::new(ctx);
        table.add(cycle, value);
        self.rewards.add(recipient, table)
    } else if (!self.rewards[recipient].contains(cycle)) {
        self.rewards[recipient].add(cycle, value);
    } else {
        let volume = self.rewards.borrow_mut(recipient).borrow_mut(cycle);
        *volume = *volume + value;
    }
}

public(package) fun add_ref<T>(
    stake: &Coin<T>,
    player: &Player,
    total_volume: &mut TotalVolume<T>,
    rewards_registry: &mut VolumeRewardRegistry<T>,
    ctx: &mut TxContext,
) {
    player.referrer().do_ref!(|referrer| {
        let reward = (stake.value() as u128 * 10 / 100) as u64;
        rewards_registry.mint_and_deposit(total_volume.cycle, reward, *referrer, ctx);
    })
}
