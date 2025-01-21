module lemonjet::player;

use lemonjet::vault::Vault;
use sui::table::{Self, Table};
use sui::transfer::{transfer, share_object};

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

// public struct ReferrerNames has key, store {
//     id: UID,
//     value: Table<String, address>,
// }

// public fun setName(referrer_names: &mut ReferrerNames, name: String, ctx: &mut TxContext) {
//     referrer_names.value.add(name, ctx.sender());
// }

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

// public fun register_by_name(
//     player_registry: &mut PlayerRegistry,
//     referrer_names: &ReferrerNames,
//     referrer_name: String,
//     ctx: &mut TxContext,
// ) {
//     let referrer = referrer_names.value[referrer_name];
//     assert!(referrer != ctx.sender());
//     player_registry.has_registered_table.add(ctx.sender(), true);
//     transfer(
//         Player {
//             id: object::new(ctx),
//             referrer: option::some(referrer),
//         },
//         ctx.sender(),
//     );
// }

public fun referrer(self: &Player): &Option<address> {
    &self.referrer
}
