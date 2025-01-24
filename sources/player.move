module lemonjet::player;

use lemonjet::vault::Vault;
use sui::table::{Self, Table};
use sui::transfer::{transfer, share_object};
use std::ascii::{String};

public struct Player has key {
    id: UID,
    referrer: Option<address>,
}

public struct PlayerRegistry has key {
    id: UID,
    has_registered: Table<address, bool>,
}

fun init(ctx: &mut TxContext) {
    share_object(PlayerRegistry {
        id: object::new(ctx),
        has_registered: table::new(ctx),
    });
}

public struct NameRegistry has key {
    id: UID,
    value: Table<String, address>,
}

public fun register_name(name_registry: &mut NameRegistry, name: String, ctx: &mut TxContext) {
    name_registry.value.add(name, ctx.sender());
}

public fun create<T>(
    player_registry: &mut PlayerRegistry,
    vault: &mut Vault<T>,
    referrer: Option<address>,
    ctx: &mut TxContext,
) {
    referrer.do!(|addr| {
        assert!(addr != ctx.sender());
        if (!vault.contains_reward_balance(addr)) {
            vault.init_reward_balance(addr)
        }
    });

    player_registry.has_registered.add(ctx.sender(), true);

    transfer(
        Player {
            id: object::new(ctx),
            referrer,
        },
        ctx.sender(),
    );
}

public fun create_by_name<T>(
    name_registry: &NameRegistry,
    player_registry: &mut PlayerRegistry,
    vault: &mut Vault<T>,
    referrer_name: String,
    ctx: &mut TxContext,
) {

    let referrer = name_registry.value[referrer_name];
    create(player_registry, vault, option::some(referrer), ctx)

}

public fun referrer(self: &Player): &Option<address> {
    &self.referrer
}

