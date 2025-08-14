module lemonjet::points;

use lemonjet::admin::AdminCap;
use lemonjet::player::Player;
use sui::clock::Clock;
use sui::coin::{Self, TreasuryCap, Coin};
use sui::linked_table::{Self, LinkedTable};
use sui::table::{Self, Table};

const EWrongVersion: u64 = 2;
const EMismatchCycle: u64 = 3;
const ETotalVolumeMustBeCompleted: u64 = 4;

const VERSION: u64 = 1;

public struct POINTS has drop {}

public struct PointsData has key {
    id: UID,
    version: u64,
    treasury: TreasuryCap<POINTS>,
}

public struct Volume<phantom T> has key, store {
    id: UID,
    cycle: u64,
    value: u64,
}

public struct Config<phantom T> has key, store {
    id: UID,
    version: u64,
    point_capacity: u64,
    interval_ms: u64,
}

public struct TotalVolume<phantom T> has key {
    id: UID,
    version: u64,
    cycle: u64,
    value: u64,
    completion_time_ms: u64,
}

public struct RateRegistry<phantom T> has key {
    id: UID,
    version: u64,
    // cycle -> rate
    value: Table<u64, Rate<T>>,
}

public struct VolumeRewardRegistry<phantom T> has key {
    id: UID,
    version: u64,
    rewards: Table<address, LinkedTable<u64, u64>>,
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
    transfer::share_object(PointsData {
        id: object::new(ctx),
        version: VERSION,
        treasury: treasury_cap,
    });
}

public fun next_cycle<T>(
    clock: &Clock,
    config: &Config<T>,
    total_volume: &mut TotalVolume<T>,
    rate_registry: &mut RateRegistry<T>,
) {
    assert!(config.version == VERSION, EWrongVersion);
    assert!(total_volume.version == VERSION, EWrongVersion);
    assert!(rate_registry.version == VERSION, EWrongVersion);
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
        version: VERSION,
        point_capacity,
        interval_ms,
    });

    transfer::share_object(TotalVolume<T> {
        id: object::new(ctx),
        version: VERSION,
        cycle: 1,
        value: 0,
        completion_time_ms: clock.timestamp_ms() + interval_ms,
    });

    transfer::share_object(RateRegistry<T> {
        id: object::new(ctx),
        version: VERSION,
        value: table::new(ctx),
    });

    transfer::share_object(VolumeRewardRegistry<T> {
        id: object::new(ctx),
        version: VERSION,
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
    assert!(rate_registry.version == VERSION, EWrongVersion);
    assert!(point_data.version == VERSION, EWrongVersion);
    point_data.treasury.mint(volumes.fold!(0, |acc, volume| {
            if (!rate_registry.value.contains(volume.cycle)) {
                transfer::transfer(volume, ctx.sender());
                return acc;
            };
            let Volume { id, cycle, value: player_volume } = volume;
            let rate = &rate_registry.value[cycle];
            let mint_value =
                ((player_volume as u128) * (rate.points as u128)  / ( rate.volume as u128)) as u64;

            object::delete(id);
            acc + mint_value
        }), ctx)
}

public fun claim_ref_volume<T>(
    reward_registry: &mut VolumeRewardRegistry<T>,
    ctx: &mut TxContext,
): vector<Volume<T>> {
    assert!(reward_registry.version == VERSION, EWrongVersion);
    let volume_table = &mut reward_registry.rewards[ctx.sender()];
    let mut volume_vec: vector<Volume<T>> = vector[];
    while (!volume_table.is_empty()) {
        let (cycle, value) = volume_table.pop_front();
        volume_vec.push_back(Volume<T> {
            id: object::new(ctx),
            cycle,
            value,
        });
    };
    volume_vec
}

public fun mint(
    _: &AdminCap,
    point_data: &mut PointsData,
    value: u64,
    ctx: &mut TxContext,
): Coin<POINTS> {
    assert!(point_data.version == VERSION, EWrongVersion);
    point_data.treasury.mint(value, ctx)
}

public(package) fun add<T>(
    stake: &Coin<T>,
    total_volume: &mut TotalVolume<T>,
    player_volume: &mut Volume<T>,
) {
    assert!(total_volume.version == VERSION, EWrongVersion);
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
    assert!(self.version == VERSION, EWrongVersion);
    if (!self.rewards.contains(recipient)) {
        let mut table = linked_table::new(ctx);
        table.push_back(cycle, value);
        self.rewards.add(recipient, table)
    } else if (!self.rewards[recipient].contains(cycle)) {
        let table = &mut self.rewards[recipient];
        table.push_back(cycle, value);
    } else {
        let volume = self.rewards.borrow_mut(recipient).borrow_mut(cycle);
        *volume = *volume + value;
    }
}

public(package) fun add_ref<T>(
    stake: &Coin<T>,
    player: &Player,
    total_volume: &TotalVolume<T>,
    rewards_registry: &mut VolumeRewardRegistry<T>,
    ctx: &mut TxContext,
) {
    assert!(total_volume.version == VERSION, EWrongVersion);
    assert!(rewards_registry.version == VERSION, EWrongVersion);
    player.referrer().do_ref!(|referrer| {
        let reward = (stake.value() as u128 * 10 / 100) as u64;
        rewards_registry.mint_and_deposit(total_volume.cycle, reward, *referrer, ctx);
    })
}

// entry fun migrate_points_data(data: &mut PointsData, _: &AdminCap) {
//     assert!(data.version < VERSION, EWrongVersion);
//     data.version = VERSION;
// }

// entry fun migrate_config<T>(config: &mut Config<T>, _: &AdminCap) {
//     assert!(config.version < VERSION, EWrongVersion);
//     config.version = VERSION;
// }

// entry fun migrate_total_volume<T>(volume: &mut TotalVolume<T>, _: &AdminCap) {
//     assert!(volume.version < VERSION, EWrongVersion);
//     volume.version = VERSION;
// }

// entry fun migrate_rate_registry<T>(registry: &mut RateRegistry<T>, _: &AdminCap) {
//     assert!(registry.version < VERSION, EWrongVersion);
//     registry.version = VERSION;
// }

// entry fun migrate_volume_reward_registry<T>(registry: &mut VolumeRewardRegistry<T>, _: &AdminCap) {
//     assert!(registry.version < VERSION, EWrongVersion);
//     registry.version = VERSION;
// }

#[test]
public fun test_claim_ref_volume() {
    use std::debug;
    let mut ctx = tx_context::dummy();
    let dummy_address = @0xCAFE;
    let sender = ctx.sender();

    let mut reward_registry = VolumeRewardRegistry<sui::sui::SUI> {
        id: object::new(&mut ctx),
        version: VERSION,
        rewards: sui::table::new(&mut ctx),
    };

    // reward_registry.mint_and_deposit(1, 5000, sender, &mut ctx);

    let volumes = claim_ref_volume(&mut reward_registry, &mut ctx);

    debug::print(&reward_registry.rewards[sender]);
    debug::print(&volumes);

    assert!(vector::length(&volumes) == 1);
    assert!(reward_registry.rewards[sender].is_empty());
    transfer::transfer(reward_registry, dummy_address);

    volumes.destroy!(|v| {
        transfer::transfer(v, dummy_address);
    })
}
